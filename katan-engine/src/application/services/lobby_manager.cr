require "../../domain/game/lobby"
require "../../transport/websocket/client"
require "../../infrastructure/persistence/game_event_store"
require "json"
require "time"

module Katan::Engine::Application
  abstract class DiceRoller
    abstract def roll : DiceRoll
  end

  class RandomDiceRoller < DiceRoller
    def roll : DiceRoll
      DiceRoll.new(Random.rand(1..6).to_i32, Random.rand(1..6).to_i32)
    end
  end

  class LobbyManager
    DISCONNECT_GRACE_PERIOD = 60.seconds

    property lobbies = Hash(String, Domain::Lobby).new
    property clients = Hash(String, Array(Transport::WebSocket::Client)).new
    property games = Hash(String, GameState).new

    def initialize(
      @game_event_store : Infrastructure::Persistence::GameEventStore = Infrastructure::Persistence::NullGameEventStore.new,
      @dice_roller : DiceRoller = RandomDiceRoller.new
    )
    end

    def get_or_create_lobby(id : String) : Domain::Lobby
      @lobbies[id] ||= Domain::Lobby.new(id)
    end

    def add_client(lobby_id : String, client : Transport::WebSocket::Client)
      clients_list = (@clients[lobby_id] ||= [] of Transport::WebSocket::Client)
      clients_list << client unless clients_list.includes?(client)
    end

    def handle_join(lobby_id : String, player_id : String, name : String, client : Transport::WebSocket::Client, host_id : String? = nil)
      lobby = get_or_create_lobby(lobby_id)
      lobby.host_id = host_id if host_id

      player = lobby.find_player(player_id) || Domain::Player.new(player_id, name)
      player.name = name
      player.mark_connected
      lobby.add_player(player)

      client.player_id = player_id
      remove_existing_clients(lobby_id, player_id, client)
      add_client(lobby_id, client)
      
      broadcast_lobby_state(lobby_id)
    end

    def disconnect_client(client : Transport::WebSocket::Client)
      if lid = client.lobby_id
        if list = @clients[lid]?
          list.delete(client)
        end

        if pid = client.player_id
          if lobby = @lobbies[lid]?
            if player = lobby.find_player(pid)
              player.mark_disconnected
              schedule_disconnect_cleanup(lid, pid, player.disconnect_version)
            end
          end
        end

        broadcast_lobby_state(lid) if @lobbies[lid]?
      end
    end

    def remove_client(client : Transport::WebSocket::Client)
      remove_player(client.lobby_id, client.player_id, "player_left", "left the lobby")
      client.player_id = nil
      client.lobby_id = nil
    end

    def remove_player(lobby_id : String?, player_id : String?, event_type : String? = nil, message_suffix : String? = nil) : Bool
      return false unless lobby_id && player_id

      if list = @clients[lobby_id]?
        list.reject! { |client| client.player_id == player_id }
      end

      removed = false
      if lobby = @lobbies[lobby_id]?
        if player = lobby.find_player(player_id)
          player.disconnect_version += 1
          lobby.remove_player(player_id)
          if event_type
            log_event(
              lobby_id,
              event_type,
              player_id,
              {name: player.name}.to_json,
              "#{player.name} #{message_suffix}."
            )
          end
          removed = true
        end

        cleanup_lobby(lobby_id, lobby)
      end

      broadcast_lobby_state(lobby_id) if @lobbies[lobby_id]?
      removed
    end

    def kick_player(lobby_id : String, target_player_id : String)
      target_client = @clients[lobby_id]?.try(&.find { |client| client.player_id == target_player_id })

      if target_client
        target_client.send_json({type: "kicked", message: "You were removed from the lobby by the host."}.to_json)
        remove_player(lobby_id, target_player_id, "player_kicked", "was removed from the lobby")
        target_client.player_id = nil
        target_client.lobby_id = nil
        target_client.socket.close
      else
        remove_player(lobby_id, target_player_id, "player_kicked", "was removed from the lobby")
      end
    end

    def set_player_ready(lobby_id : String, player_id : String, ready_state : Bool) : Bool
      lobby = get_or_create_lobby(lobby_id)
      return false unless player = lobby.find_player(player_id)
      return false unless player.connected

      player.ready = ready_state
      log_event(
        lobby_id,
        "player_ready_changed",
        player_id,
        {name: player.name, ready: ready_state}.to_json,
        "#{player.name} is #{ready_state ? "ready" : "not ready"}."
      )
      broadcast_lobby_state(lobby_id)
      true
    end

    def update_settings(lobby_id : String, settings : Hash(String, JSON::Any))
      lobby = get_or_create_lobby(lobby_id)
      lobby.settings = settings
      @game_event_store.update_game_settings(lobby_id, settings.to_json)
      broadcast_lobby_state(lobby_id)
    rescue ex
      puts "Failed to persist game settings for #{lobby_id}: #{ex.message}"
    end

    def broadcast_lobby_state(lobby_id : String)
      if lobby = @lobbies[lobby_id]?
        if list = @clients[lobby_id]?
          state_json = {
            type:  "lobby_update",
            lobby: lobby,
          }.to_json
          list.each do |client|
            client.send_json(state_json)
          end
        end
      end
    end

    def start_game(lobby_id : String)
      lobby = get_or_create_lobby(lobby_id)
      game_state = build_game_state(lobby)
      @games[lobby_id] = game_state

      game_started = GameStarted.new(next_version(game_state))
      game_state.apply!(game_started)

      @game_event_store.append(
        lobby_code: lobby_id,
        event_type: "game_started",
        turn_number: game_state.turn.number,
        phase: game_state.turn.phase.to_s,
        payload_json: serialize_game_state(game_state, include_all_hands: true).to_json,
        message: "Game started."
      )

      broadcast_game_state(lobby_id, "game_started")
      broadcast_lobby_state(lobby_id)
    rescue ex
      puts "Failed to start game for #{lobby_id}: #{ex.message}"
    end

    def place_settlement(lobby_id : String, player_id : String, vertex_id : String, free : Bool = false)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      event = SettlementPlaced.new(next_version(game_state), PlayerId.new(player_id), VertexId.new(vertex_id), free)

      game_state.apply!(event)
      persist_game_event(lobby_id, game_state, "settlement_placed", player_id, serialize_event_payload(event).to_json, "#{game_state.player!(event.player_id).name} placed a settlement.")
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to place settlement for #{lobby_id}: #{ex.message}"
    end

    def place_road(lobby_id : String, player_id : String, edge_id : String, free : Bool = false)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      event = RoadPlaced.new(next_version(game_state), PlayerId.new(player_id), EdgeId.new(edge_id), free)

      game_state.apply!(event)
      persist_game_event(lobby_id, game_state, "road_placed", player_id, serialize_event_payload(event).to_json, "#{game_state.player!(event.player_id).name} placed a road.")
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to place road for #{lobby_id}: #{ex.message}"
    end

    def place_city(lobby_id : String, player_id : String, vertex_id : String)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      event = CityPlaced.new(next_version(game_state), PlayerId.new(player_id), VertexId.new(vertex_id))

      game_state.apply!(event)
      persist_game_event(lobby_id, game_state, "city_placed", player_id, serialize_event_payload(event).to_json, "#{game_state.player!(event.player_id).name} upgraded a settlement to a city.")
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to place city for #{lobby_id}: #{ex.message}"
    end

    def buy_development_card(lobby_id : String, player_id : String)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      actor = PlayerId.new(player_id)
      
      # Validate purchase before sampling to avoid RNG contamination from rejected attempts
      validate_development_card_purchase!(game_state, actor)
      
      card = game_state.bank.sample_dev_card(Random::DEFAULT)
      event = DevelopmentCardPurchased.new(next_version(game_state), actor, card)

      game_state.apply!(event)
      persist_game_event(lobby_id, game_state, "development_card_purchased", player_id, serialize_event_payload(event).to_json, "#{game_state.player!(event.player_id).name} bought a development card.")
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to buy development card for #{lobby_id}: #{ex.message}"
    end
    
    private def validate_development_card_purchase!(game_state : GameState, player_id : PlayerId) : Nil
      raise "wrong player bought development card" unless player_id == game_state.turn.current_player_id
      raise "can only buy development cards during the main phase" unless game_state.turn.phase.main?
      raise "no development cards remaining" if game_state.bank.dev_cards_remaining.zero?
      raise "player does not have enough resources" unless game_state.player!(player_id).hand.can_afford_development_card?
    end

    def play_knight(lobby_id : String, player_id : String, tile_id : String)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      event = KnightPlayed.new(next_version(game_state), PlayerId.new(player_id), TileId.new(tile_id))

      game_state.apply!(event)
      persist_game_event(lobby_id, game_state, "knight_played", player_id, serialize_event_payload(event).to_json, "#{game_state.player!(event.player_id).name} played a knight.")
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to play knight for #{lobby_id}: #{ex.message}"
    end

    def play_road_building(lobby_id : String, player_id : String, first_edge_id : String, second_edge_id : String? = nil)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      event = RoadBuildingPlayed.new(next_version(game_state), PlayerId.new(player_id), EdgeId.new(first_edge_id), second_edge_id ? EdgeId.new(second_edge_id) : nil)

      game_state.apply!(event)
      persist_game_event(lobby_id, game_state, "road_building_played", player_id, serialize_event_payload(event).to_json, "#{game_state.player!(event.player_id).name} played road building.")
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to play road building for #{lobby_id}: #{ex.message}"
    end

    def play_monopoly(lobby_id : String, player_id : String, resource : Resource)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      event = MonopolyPlayed.new(next_version(game_state), PlayerId.new(player_id), resource)

      game_state.apply!(event)
      persist_game_event(lobby_id, game_state, "monopoly_played", player_id, serialize_event_payload(event).to_json, "#{game_state.player!(event.player_id).name} played monopoly.")
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to play monopoly for #{lobby_id}: #{ex.message}"
    end

    def play_year_of_plenty(lobby_id : String, player_id : String, first_resource : Resource, second_resource : Resource)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      event = YearOfPlentyPlayed.new(next_version(game_state), PlayerId.new(player_id), first_resource, second_resource)

      game_state.apply!(event)
      persist_game_event(lobby_id, game_state, "year_of_plenty_played", player_id, serialize_event_payload(event).to_json, "#{game_state.player!(event.player_id).name} played year of plenty.")
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to play year of plenty for #{lobby_id}: #{ex.message}"
    end

    def roll_dice(lobby_id : String, player_id : String)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      actor = PlayerId.new(player_id)
      raise "wrong player rolled dice" unless game_state.turn.current_player_id == actor

      roll = @dice_roller.roll
      event = DiceRolled.new(next_version(game_state), roll.die_one, roll.die_two)

      game_state.apply!(event)
      persist_game_event(lobby_id, game_state, "dice_rolled", player_id, serialize_event_payload(event).to_json, "#{game_state.player!(actor).name} rolled #{event.total}.")
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to roll dice for #{lobby_id}: #{ex.message}"
    end

    def move_robber(lobby_id : String, player_id : String, tile_id : String)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      event = RobberMoved.new(next_version(game_state), PlayerId.new(player_id), TileId.new(tile_id))

      game_state.apply!(event)
      persist_game_event(lobby_id, game_state, "robber_moved", player_id, serialize_event_payload(event).to_json, "#{game_state.player!(event.player_id).name} moved the robber.")
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to move robber for #{lobby_id}: #{ex.message}"
    end

    def end_turn(lobby_id : String, player_id : String)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      event = TurnEnded.new(next_version(game_state), PlayerId.new(player_id))
      actor_name = game_state.player!(event.player_id).name

      game_state.apply!(event)
      persist_game_event(lobby_id, game_state, "turn_ended", player_id, serialize_event_payload(event).to_json, "#{actor_name} ended their turn.")
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to end turn for #{lobby_id}: #{ex.message}"
    end

    private def remove_existing_clients(lobby_id : String, player_id : String, current_client : Transport::WebSocket::Client)
      return unless list = @clients[lobby_id]?

      stale_clients = list.select { |client| client.player_id == player_id && client != current_client }
      stale_clients.each do |client|
        list.delete(client)
        client.player_id = nil
        client.lobby_id = nil
        client.socket.close unless client.socket.closed?
      end
    end

    private def schedule_disconnect_cleanup(lobby_id : String, player_id : String, disconnect_version : Int32)
      spawn do
        sleep DISCONNECT_GRACE_PERIOD
        evict_if_still_disconnected(lobby_id, player_id, disconnect_version)
      end
    end

    private def evict_if_still_disconnected(lobby_id : String, player_id : String, disconnect_version : Int32)
      return unless lobby = @lobbies[lobby_id]?
      return unless player = lobby.find_player(player_id)
      return unless !player.connected && player.disconnect_version == disconnect_version

      lobby.remove_player(player_id)
      log_event(
        lobby_id,
        "player_disconnected",
        player_id,
        {name: player.name}.to_json,
        "#{player.name} disconnected."
      )
      cleanup_lobby(lobby_id, lobby)
      broadcast_lobby_state(lobby_id) if @lobbies[lobby_id]?
    end

    private def cleanup_lobby(lobby_id : String, lobby : Domain::Lobby)
      return unless lobby.players.empty?

      @games.delete(lobby_id)
      @lobbies.delete(lobby_id)
      @clients.delete(lobby_id)
    end

    private def build_game_state(lobby : Domain::Lobby) : GameState
      GameState.new(
        topology: BoardTopology.standard,
        players: lobby.players.map { |player|
          player_id = PlayerId.new(player.id)
          {player_id, PlayerState.new(player_id, player.name)}
        }.to_h,
        settings: lobby.settings
      )
    end

    private def broadcast_game_state(lobby_id : String, message_type : String = "game_update")
      return unless game_state = @games[lobby_id]?
      return unless list = @clients[lobby_id]?

      list.each do |client|
        client.send_json(
          {
            type: message_type,
            game_state: serialize_game_state(game_state, client.player_id)
          }.to_json
        )
      end

      save_game_snapshot(lobby_id, game_state)
    end

    private def serialize_game_state(game_state : GameState, viewer_player_id : String? = nil, include_all_hands : Bool = false)
      {
        version: game_state.version,
        player_order: game_state.player_order.map(&.value),
        turn: {
          current_player_id: game_state.turn.current_player_id.value,
          number: game_state.turn.number,
          phase: game_state.turn.phase.to_s,
        },
        last_roll: game_state.last_roll ? {
          die_one: game_state.last_roll.not_nil!.die_one,
          die_two: game_state.last_roll.not_nil!.die_two,
          total: game_state.last_roll.not_nil!.total,
        } : nil,
        players: game_state.player_order.map { |player_id|
          player = game_state.player!(player_id)
          {
            id: player.id.value,
            name: player.name,
            victory_points: player.victory_points,
            roads_left: player.roads_left,
            settlements_left: player.settlements_left,
            cities_left: player.cities_left,
            knights_played: player.knights_played,
            has_longest_road: game_state.longest_road_player_id == player.id,
            has_largest_army: game_state.largest_army_player_id == player.id,
            resource_count: total_resources(player.hand),
            development_card_count: player.total_dev_cards,
            hand: include_all_hands || player.id.value == viewer_player_id ? {
              wood: player.hand.wood,
              brick: player.hand.brick,
              sheep: player.hand.sheep,
              wheat: player.hand.wheat,
              ore: player.hand.ore,
            } : nil,
            development_cards: include_all_hands || player.id.value == viewer_player_id ? {
              playable: player.dev_cards.to_json_payload,
              newly_purchased: player.newly_purchased_dev_cards.to_json_payload,
            } : nil,
          }
        },
        bank: game_state.bank.to_json_payload,
        board: {
          tiles: game_state.topology.tiles.values.sort_by(&.id.value).map { |tile|
            tile_state = game_state.board.tile_states[tile.id]
            {
              id: tile.id.value,
              x: tile.x,
              y: tile.y,
              resource: tile_state.resource.to_s,
              token: tile_state.token,
              has_robber: game_state.board.robber_tile_id == tile.id
            }
          },
          vertices: game_state.topology.vertices.values.sort_by(&.id.value).map { |vertex|
            building = game_state.board.building_at?(vertex.id)
            {
              id: vertex.id.value,
              x: vertex.x,
              y: vertex.y,
              building: building ? {
                player_id: building.player_id.value,
                kind: building.kind.to_s
              } : nil
            }
          },
          edges: game_state.topology.edges.values.sort_by(&.id.value).map { |edge|
            road = game_state.board.road_at?(edge.id)
            {
              id: edge.id.value,
              v1: edge.vertex_ids[0].value,
              v2: edge.vertex_ids[1].value,
              road: road ? {
                player_id: road.player_id.value
              } : nil
            }
          }
        },
        awards: {
          longest_road: game_state.longest_road_player_id ? {
            player_id: game_state.longest_road_player_id.not_nil!.value,
            length: game_state.longest_road_length,
          } : nil,
          largest_army: game_state.largest_army_player_id ? {
            player_id: game_state.largest_army_player_id.not_nil!.value,
            size: game_state.largest_army_size,
          } : nil,
        },
        winner_player_id: game_state.winner_player_id.try(&.value),
        settings: game_state.settings,
      }
    end

    private def serialize_event_payload(event : GameEvent)
      case event
      when SettlementPlaced
        {
          version: event.version,
          player_id: event.player_id.value,
          vertex_id: event.vertex_id.value,
          free: event.free,
        }
      when RoadPlaced
        {
          version: event.version,
          player_id: event.player_id.value,
          edge_id: event.edge_id.value,
          free: event.free,
        }
      when CityPlaced
        {
          version: event.version,
          player_id: event.player_id.value,
          vertex_id: event.vertex_id.value,
        }
      when DevelopmentCardPurchased
        {
          version: event.version,
          player_id: event.player_id.value,
          card: event.card.to_s,
        }
      when KnightPlayed
        {
          version: event.version,
          player_id: event.player_id.value,
          tile_id: event.tile_id.value,
        }
      when RoadBuildingPlayed
        {
          version: event.version,
          player_id: event.player_id.value,
          first_edge_id: event.first_edge_id.value,
          second_edge_id: event.second_edge_id.try(&.value),
        }
      when MonopolyPlayed
        {
          version: event.version,
          player_id: event.player_id.value,
          resource: event.resource.to_s,
        }
      when YearOfPlentyPlayed
        {
          version: event.version,
          player_id: event.player_id.value,
          first_resource: event.first_resource.to_s,
          second_resource: event.second_resource.to_s,
        }
      when DiceRolled
        {
          version: event.version,
          die_one: event.die_one,
          die_two: event.die_two,
          total: event.total,
        }
      when RobberMoved
        {
          version: event.version,
          player_id: event.player_id.value,
          tile_id: event.tile_id.value,
        }
      when TurnEnded
        {
          version: event.version,
          player_id: event.player_id.value,
        }
      when GameStarted
        {
          version: event.version,
        }
      else
        raise "unknown game event #{event.class}"
      end
    end

    private def persist_game_event(lobby_id : String, game_state : GameState, event_type : String, actor_player_id : String?, payload_json : String, message : String)
      @game_event_store.append(
        lobby_code: lobby_id,
        event_type: event_type,
        actor_player_id: actor_player_id,
        turn_number: game_state.turn.number,
        phase: game_state.turn.phase.to_s,
        payload_json: payload_json,
        message: message
      )
    end

    private def next_version(game_state : GameState) : Int32
      game_state.version + 1
    end

    private def total_resources(hand : ResourceHand) : Int32
      hand.wood + hand.brick + hand.sheep + hand.wheat + hand.ore
    end

    private def log_event(lobby_id : String, event_type : String, actor_player_id : String?, payload_json : String, message : String)
      @game_event_store.append(
        lobby_code: lobby_id,
        event_type: event_type,
        actor_player_id: actor_player_id,
        payload_json: payload_json,
        message: message
      )
    rescue ex
      puts "Failed to persist game event #{event_type} for #{lobby_id}: #{ex.message}"
    end

    private def save_game_snapshot(lobby_id : String, game_state : GameState)
      snapshot = serialize_game_state(game_state, include_all_hands: true)
      @game_event_store.save_game_snapshot(lobby_id, snapshot.to_json, game_state.version)
    rescue ex
      puts "Failed to save game snapshot for #{lobby_id}: #{ex.message}"
    end
  end
end
