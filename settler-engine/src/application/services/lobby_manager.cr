require "../../domain/game/lobby"
require "../../transport/websocket/client"
require "../../infrastructure/persistence/game_event_store"
require "json"
require "time"

module Settler::Engine::Application
  record PublicLobbySummary,
    short_code : String,
    host_player_id : String,
    host_display_name : String,
    participant_count : Int32,
    max_players : Int32,
    created_at : String,
    is_public : Bool,
    game_mode : String,
    five_six_turn_rule : String

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
    TIMER_BONUS_SECONDS     =  10
    CHAT_MESSAGE_MAX_LENGTH = 500

    property lobbies = Hash(String, Domain::Lobby).new
    property clients = Hash(String, Array(Transport::WebSocket::Client)).new
    property games = Hash(String, GameState).new
    property public_clients = [] of Transport::WebSocket::Client

    def initialize(
      @game_event_store : Infrastructure::Persistence::GameEventStore = Infrastructure::Persistence::NullGameEventStore.new,
      @dice_roller : DiceRoller = RandomDiceRoller.new,
    )
      @timer_versions = Hash(String, Int32).new(0)
      hydrate_public_lobbies_from_store
    end

    def get_or_create_lobby(id : String) : Domain::Lobby
      restore_lobby_from_store(id) unless @lobbies.has_key?(id)
      @lobbies[id] ||= Domain::Lobby.new(id)
    end

    def add_client(lobby_id : String, client : Transport::WebSocket::Client)
      clients_list = (@clients[lobby_id] ||= [] of Transport::WebSocket::Client)
      clients_list << client unless clients_list.includes?(client)
    end

    def add_public_client(client : Transport::WebSocket::Client)
      @public_clients << client unless @public_clients.includes?(client)
      client.public_subscriber = true
    end

    def remove_public_client(client : Transport::WebSocket::Client)
      @public_clients.delete(client)
      client.public_subscriber = false
    end

    def public_lobby_summaries : Array(PublicLobbySummary)
      @lobbies.each_value.compact_map do |lobby|
        public_lobby_summary(lobby)
      end.to_a.sort_by { |summary| summary.created_at }.reverse
    end

    def subscribe_public_lobbies(client : Transport::WebSocket::Client)
      add_public_client(client)
      client.send_json(
        {
          type:    "public_lobbies_snapshot",
          lobbies: public_lobby_summaries.map { |summary| serialize_public_lobby(summary) },
        }.to_json
      )
    end

    def create_lobby(player_id : String, player_name : String, is_public : Bool = false) : Domain::Lobby
      default_settings = default_settings_json
      persisted = @game_event_store.create_lobby(player_id, is_public, default_settings.to_json)
      lobby = hydrate_waiting_lobby(persisted)

      if player = lobby.find_player(player_id)
        player.name = player_name
        player.ready = false
        player.connected = false
        player.disconnected_at = Time.utc
        # Host is not connected yet (they navigate to the lobby page next).
        # Evict the lobby if they never show up.
        schedule_disconnect_cleanup(lobby.id, player_id, player.disconnect_version)
      end

      @lobbies[lobby.id] = lobby
      broadcast_public_lobby_change(lobby.id, nil)
      lobby
    end

    def handle_join(lobby_id : String, player_id : String, name : String, client : Transport::WebSocket::Client)
      previous_summary = current_public_lobby_summary_for(lobby_id)
      lobby = get_or_create_lobby(lobby_id)

      if lobby_full_for_new_player?(lobby, player_id)
        client.send_json({type: "error", code: "lobby_full", message: "This lobby is full."}.to_json)
        return
      end

      @game_event_store.add_participant(lobby_id, player_id, false) unless lobby.find_player(player_id)

      player = lobby.find_player(player_id) || Domain::Player.new(player_id, name)
      player.name = name
      player.mark_connected
      lobby.add_player(player)

      client.player_id = player_id
      remove_existing_clients(lobby_id, player_id, client)
      add_client(lobby_id, client)

      broadcast_lobby_state(lobby_id)
      broadcast_public_lobby_change(lobby_id, previous_summary)

      if game_state = @games[lobby_id]?
        client.send_json(
          {
            type:       "game_update",
            game_state: serialize_game_state(game_state, client.player_id),
          }.to_json
        )
      end
    end

    def disconnect_client(client : Transport::WebSocket::Client)
      remove_public_client(client) if client.public_subscriber

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
      remove_public_client(client) if client.public_subscriber
    end

    def remove_player(lobby_id : String?, player_id : String?, event_type : String? = nil, message_suffix : String? = nil) : Bool
      return false unless lobby_id && player_id
      previous_summary = current_public_lobby_summary_for(lobby_id)

      if list = @clients[lobby_id]?
        list.reject! { |client| client.player_id == player_id }
      end

      removed = false
      if lobby = @lobbies[lobby_id]?
        if player = lobby.find_player(player_id)
          player.disconnect_version += 1
          lobby.remove_player(player_id)
          @game_event_store.remove_participant(lobby_id, player_id) unless @games[lobby_id]?
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
      broadcast_public_lobby_change(lobby_id, previous_summary)
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
      @game_event_store.update_participant_ready(lobby_id, player_id, ready_state)
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

    def update_settings(lobby_id : String, settings : Hash(String, JSON::Any)) : Bool
      previous_summary = current_public_lobby_summary_for(lobby_id)
      lobby = get_or_create_lobby(lobby_id)
      normalized_settings = normalized_settings(settings)
      validate_lobby_settings!(lobby, normalized_settings)
      if @games[lobby_id]?
        structural_keys = ["gameMode", "fiveSixTurnRule", "maxPlayers"]
        if structural_keys.any? { |key| lobby.settings[key]? != normalized_settings[key]? }
          raise "Cannot change game mode, extension rules, or seats after the game has started"
        end
      end

      structural_changed = ["gameMode", "fiveSixTurnRule", "maxPlayers"].any? do |key|
        lobby.settings[key]? != normalized_settings[key]?
      end
      lobby.settings = normalized_settings
      if structural_changed
        lobby.players.each do |player|
          next unless player.ready
          player.ready = false
          @game_event_store.update_participant_ready(lobby_id, player.id, false)
        end
      end
      if game_state = @games[lobby_id]?
        game_state.settings.clear
        normalized_settings.each { |key, value| game_state.settings[key] = value }
        initialize_turn_timer!(lobby_id, game_state)
      end
      @game_event_store.update_game_settings(lobby_id, normalized_settings.to_json)
      broadcast_lobby_state(lobby_id)
      broadcast_public_lobby_change(lobby_id, previous_summary)
      true
    rescue ex
      puts "Failed to persist game settings for #{lobby_id}: #{ex.message}"
      false
    end

    def update_visibility(lobby_id : String, is_public : Bool)
      previous_summary = current_public_lobby_summary_for(lobby_id)
      lobby = get_or_create_lobby(lobby_id)

      if @games[lobby_id]?
        raise "Cannot change visibility after the game has started"
      end

      lobby.is_public = is_public
      @game_event_store.update_lobby_visibility(lobby_id, is_public)
      broadcast_lobby_state(lobby_id)
      broadcast_public_lobby_change(lobby_id, previous_summary)
    end

    def send_chat_message(lobby_id : String, player_id : String, message : String) : Bool
      lobby = get_or_create_lobby(lobby_id)
      player = lobby.find_player(player_id)
      return false unless player
      return false unless player.connected

      normalized_message = message.strip
      return false if normalized_message.empty?
      return false if normalized_message.size > CHAT_MESSAGE_MAX_LENGTH

      created_at = Time.utc
      payload_json = {
        player_id:   player_id,
        player_name: player.name,
        message:     normalized_message,
        created_at:  created_at.to_rfc3339,
      }.to_json

      log_event(lobby_id, "chat_message", player_id, payload_json, normalized_message)
      broadcast_chat_message(lobby_id, player_id, player.name, normalized_message, created_at)
      true
    rescue ex
      puts "Failed to send chat message for #{lobby_id}: #{ex.message}"
      false
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

    def start_game(lobby_id : String, validate_lobby : Bool = false) : Bool
      previous_summary = current_public_lobby_summary_for(lobby_id)
      lobby = get_or_create_lobby(lobby_id)
      validate_game_start!(lobby) if validate_lobby
      game_state = build_game_state(lobby)
      @games[lobby_id] = game_state

      game_started = GameStarted.new(next_version(game_state))
      game_state.apply!(game_started)
      initialize_turn_timer!(lobby_id, game_state)
      @game_event_store.mark_game_started(lobby_id)

      @game_event_store.append(
        lobby_code: lobby_id,
        event_type: "game_started",
        turn_number: game_state.turn.number,
        phase: game_state.turn.phase.to_s,
        payload_json: serialize_game_state(game_state, include_all_hands: true).to_json,
        message: "Game started."
      )

      if list = @clients[lobby_id]?
        event_json = {
          type:       "game_log",
          message:    "Game started.",
          event_type: "game_started",
        }.to_json
        list.each do |client|
          client.send_json(event_json)
        end
      end

      broadcast_game_state(lobby_id, "game_started")
      broadcast_lobby_state(lobby_id)
      broadcast_public_lobby_change(lobby_id, previous_summary)
      true
    rescue ex
      puts "Failed to start game for #{lobby_id}: #{ex.message}"
      false
    end

    def place_settlement(lobby_id : String, player_id : String, vertex_id : String, free : Bool = false, grant_timer_bonus : Bool = true)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      previous_player_id = game_state.turn.current_player_id
      previous_phase = game_state.turn.phase
      event = SettlementPlaced.new(next_version(game_state), PlayerId.new(player_id), VertexId.new(vertex_id), free)

      game_state.apply!(event)
      sync_turn_timer_after_action!(lobby_id, game_state, previous_player_id, previous_phase, grant_timer_bonus && !setup_phase?(previous_phase))

      message = "#{game_state.player!(event.player_id).name} placed a settlement."
      if free && game_state.turn.phase == TurnPhase::Setup2Road
        # They just placed their second settlement and got resources
        # We don't have the exact list returned, but we can just say they got starting resources
        message += " They received their starting resources."
      end

      persist_game_event(lobby_id, game_state, "settlement_placed", player_id, serialize_event_payload(event).to_json, message)
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to place settlement for #{lobby_id}: #{ex.message}"
    end

    def place_road(lobby_id : String, player_id : String, edge_id : String, free : Bool = false, grant_timer_bonus : Bool = true)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      previous_player_id = game_state.turn.current_player_id
      previous_phase = game_state.turn.phase
      event = RoadPlaced.new(next_version(game_state), PlayerId.new(player_id), EdgeId.new(edge_id), free)

      game_state.apply!(event)
      sync_turn_timer_after_action!(lobby_id, game_state, previous_player_id, previous_phase, grant_timer_bonus && !setup_phase?(previous_phase))
      persist_game_event(lobby_id, game_state, "road_placed", player_id, serialize_event_payload(event).to_json, "#{game_state.player!(event.player_id).name} placed a road.")
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to place road for #{lobby_id}: #{ex.message}"
    end

    def place_city(lobby_id : String, player_id : String, vertex_id : String)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      previous_player_id = game_state.turn.current_player_id
      previous_phase = game_state.turn.phase
      event = CityPlaced.new(next_version(game_state), PlayerId.new(player_id), VertexId.new(vertex_id))

      game_state.apply!(event)
      sync_turn_timer_after_action!(lobby_id, game_state, previous_player_id, previous_phase, true)
      persist_game_event(lobby_id, game_state, "city_placed", player_id, serialize_event_payload(event).to_json, "#{game_state.player!(event.player_id).name} upgraded a settlement to a city.")
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to place city for #{lobby_id}: #{ex.message}"
    end

    def buy_development_card(lobby_id : String, player_id : String)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      actor = PlayerId.new(player_id)
      previous_player_id = game_state.turn.current_player_id
      previous_phase = game_state.turn.phase

      # Validate purchase before sampling to avoid RNG contamination from rejected attempts
      validate_development_card_purchase!(game_state, actor)

      card = game_state.bank.sample_dev_card(Random::DEFAULT)
      event = DevelopmentCardPurchased.new(next_version(game_state), actor, card)

      game_state.apply!(event)
      sync_turn_timer_after_action!(lobby_id, game_state, previous_player_id, previous_phase, true)
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

    def play_knight(lobby_id : String, player_id : String, tile_id : String, grant_timer_bonus : Bool = true)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      previous_player_id = game_state.turn.current_player_id
      previous_phase = game_state.turn.phase
      event = KnightPlayed.new(next_version(game_state), PlayerId.new(player_id), TileId.new(tile_id))

      game_state.apply!(event)
      sync_turn_timer_after_action!(lobby_id, game_state, previous_player_id, previous_phase, grant_timer_bonus)
      persist_game_event(lobby_id, game_state, "knight_played", player_id, serialize_event_payload(event).to_json, "#{game_state.player!(event.player_id).name} played a knight.")
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to play knight for #{lobby_id}: #{ex.message}"
    end

    def play_road_building(lobby_id : String, player_id : String, first_edge_id : String, second_edge_id : String? = nil, grant_timer_bonus : Bool = true)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      previous_player_id = game_state.turn.current_player_id
      previous_phase = game_state.turn.phase
      event = RoadBuildingPlayed.new(next_version(game_state), PlayerId.new(player_id), EdgeId.new(first_edge_id), second_edge_id ? EdgeId.new(second_edge_id) : nil)

      game_state.apply!(event)
      sync_turn_timer_after_action!(lobby_id, game_state, previous_player_id, previous_phase, grant_timer_bonus)
      persist_game_event(lobby_id, game_state, "road_building_played", player_id, serialize_event_payload(event).to_json, "#{game_state.player!(event.player_id).name} played road building.")
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to play road building for #{lobby_id}: #{ex.message}"
    end

    def play_monopoly(lobby_id : String, player_id : String, resource : Resource, grant_timer_bonus : Bool = true)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      previous_player_id = game_state.turn.current_player_id
      previous_phase = game_state.turn.phase
      event = MonopolyPlayed.new(next_version(game_state), PlayerId.new(player_id), resource)

      game_state.apply!(event)
      sync_turn_timer_after_action!(lobby_id, game_state, previous_player_id, previous_phase, grant_timer_bonus)
      persist_game_event(lobby_id, game_state, "monopoly_played", player_id, serialize_event_payload(event).to_json, "#{game_state.player!(event.player_id).name} played monopoly.")
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to play monopoly for #{lobby_id}: #{ex.message}"
    end

    def play_year_of_plenty(lobby_id : String, player_id : String, first_resource : Resource, second_resource : Resource, grant_timer_bonus : Bool = true)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      previous_player_id = game_state.turn.current_player_id
      previous_phase = game_state.turn.phase
      event = YearOfPlentyPlayed.new(next_version(game_state), PlayerId.new(player_id), first_resource, second_resource)

      game_state.apply!(event)
      sync_turn_timer_after_action!(lobby_id, game_state, previous_player_id, previous_phase, grant_timer_bonus)
      persist_game_event(lobby_id, game_state, "year_of_plenty_played", player_id, serialize_event_payload(event).to_json, "#{game_state.player!(event.player_id).name} played year of plenty.")
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to play year of plenty for #{lobby_id}: #{ex.message}"
    end

    def propose_player_trade(lobby_id : String, player_id : String, offered : ResourcePile, requested : ResourcePile, grant_timer_bonus : Bool = false)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      previous_player_id = game_state.turn.current_player_id
      previous_phase = game_state.turn.phase
      trade_id = game_state.allocate_next_player_trade_id!
      event = PlayerTradeProposed.new(next_version(game_state), trade_id, PlayerId.new(player_id), offered, requested)

      game_state.apply!(event)
      sync_turn_timer_after_action!(lobby_id, game_state, previous_player_id, previous_phase, grant_timer_bonus)
      actor_name = game_state.player!(event.player_id).name
      persist_game_event(
        lobby_id,
        game_state,
        "player_trade_proposed",
        player_id,
        serialize_event_payload(event).to_json,
        "#{actor_name} proposed a trade."
      )
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to propose player trade for #{lobby_id}: #{ex.message}"
    end

    def accept_player_trade(lobby_id : String, player_id : String, trade_id : Int32)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      pending_trade = game_state.pending_player_trade(trade_id) || raise "no pending player trade"
      previous_player_id = game_state.turn.current_player_id
      previous_phase = game_state.turn.phase

      accepted_event = PlayerTradeAccepted.new(next_version(game_state), trade_id, PlayerId.new(player_id), pending_trade.player_id)
      game_state.apply!(accepted_event)
      sync_turn_timer_after_action!(lobby_id, game_state, previous_player_id, previous_phase, false)
      actor_name = game_state.player!(accepted_event.player_id).name
      partner_name = game_state.player!(accepted_event.partner_player_id).name
      persist_game_event(
        lobby_id,
        game_state,
        "player_trade_accepted",
        player_id,
        serialize_event_payload(accepted_event).to_json,
        "#{actor_name} accepted #{partner_name}'s trade."
      )
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to accept player trade for #{lobby_id}: #{ex.message}"
    end

    def reject_player_trade(lobby_id : String, player_id : String, trade_id : Int32)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      pending_trade = game_state.pending_player_trade(trade_id) || raise "no pending player trade"
      previous_player_id = game_state.turn.current_player_id
      previous_phase = game_state.turn.phase
      event = PlayerTradeRejected.new(next_version(game_state), trade_id, PlayerId.new(player_id), pending_trade.player_id)

      game_state.apply!(event)
      sync_turn_timer_after_action!(lobby_id, game_state, previous_player_id, previous_phase, false)
      actor_name = game_state.player!(event.player_id).name
      partner_name = game_state.player!(event.partner_player_id).name
      persist_game_event(
        lobby_id,
        game_state,
        "player_trade_rejected",
        player_id,
        serialize_event_payload(event).to_json,
        "#{actor_name} passed on #{partner_name}'s trade."
      )
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to reject player trade for #{lobby_id}: #{ex.message}"
    end

    def cancel_player_trade(lobby_id : String, player_id : String, trade_id : Int32, grant_timer_bonus : Bool = false)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      previous_player_id = game_state.turn.current_player_id
      previous_phase = game_state.turn.phase
      event = PlayerTradeCancelled.new(next_version(game_state), trade_id, PlayerId.new(player_id))

      game_state.apply!(event)
      sync_turn_timer_after_action!(lobby_id, game_state, previous_player_id, previous_phase, grant_timer_bonus)
      actor_name = game_state.player!(event.player_id).name
      persist_game_event(
        lobby_id,
        game_state,
        "player_trade_cancelled",
        player_id,
        serialize_event_payload(event).to_json,
        "#{actor_name} canceled the trade."
      )
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to cancel player trade for #{lobby_id}: #{ex.message}"
    end

    def finalize_player_trade(lobby_id : String, player_id : String, trade_id : Int32, partner_player_id : String, grant_timer_bonus : Bool = true)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      pending_trade = game_state.pending_player_trade(trade_id) || raise "no pending player trade"
      previous_player_id = game_state.turn.current_player_id
      previous_phase = game_state.turn.phase
      event = PlayerTradeCompleted.new(next_version(game_state), trade_id, PlayerId.new(player_id), PlayerId.new(partner_player_id), pending_trade.offered, pending_trade.requested)

      game_state.apply!(event)
      sync_turn_timer_after_action!(lobby_id, game_state, previous_player_id, previous_phase, grant_timer_bonus)
      actor_name = game_state.player!(event.player_id).name
      partner_name = game_state.player!(event.partner_player_id).name
      offered_str = format_resource_pile(event.offered)
      requested_str = format_resource_pile(event.requested)
      persist_game_event(
        lobby_id,
        game_state,
        "player_trade_completed",
        player_id,
        serialize_event_payload(event).to_json,
        "#{actor_name} traded #{offered_str} for #{requested_str} with #{partner_name}."
      )
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to finalize player trade for #{lobby_id}: #{ex.message}"
    end

    def trade_with_bank(lobby_id : String, player_id : String, offered_resource : Resource, requested_resource : Resource, grant_timer_bonus : Bool = true)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      previous_player_id = game_state.turn.current_player_id
      previous_phase = game_state.turn.phase
      event = BankTradeCompleted.new(next_version(game_state), PlayerId.new(player_id), offered_resource, requested_resource)

      game_state.apply!(event)
      sync_turn_timer_after_action!(lobby_id, game_state, previous_player_id, previous_phase, grant_timer_bonus)
      actor_name = game_state.player!(event.player_id).name
      offered_amount = bank_trade_rate_for(game_state, event.player_id, event.offered_resource)
      persist_game_event(
        lobby_id,
        game_state,
        "bank_trade_completed",
        player_id,
        serialize_event_payload(event).to_json,
        "#{actor_name} traded #{offered_amount} #{event.offered_resource} with the bank for #{event.requested_resource}."
      )
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to trade with bank for #{lobby_id}: #{ex.message}"
    end

    def roll_dice(lobby_id : String, player_id : String, grant_timer_bonus : Bool = true)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      actor = PlayerId.new(player_id)
      previous_player_id = game_state.turn.current_player_id
      previous_phase = game_state.turn.phase
      raise "wrong player rolled dice" unless game_state.turn.current_player_id == actor

      roll = @dice_roller.roll
      event = DiceRolled.new(next_version(game_state), roll.die_one, roll.die_two)

      granted_log = game_state.apply!(event)
      sync_turn_timer_after_action!(lobby_id, game_state, previous_player_id, previous_phase, false)

      message = "#{game_state.player!(actor).name} rolled #{event.total}."

      if granted_log && !granted_log.empty?
        parts = [] of String
        granted_log.each do |pid, resources|
          next if resources.empty?
          pname = game_state.player!(PlayerId.new(pid)).name
          res_strs = resources.map { |r, amt| "#{amt} #{r}" }
          parts << "#{pname} got #{res_strs.join(", ")}"
        end
        message += " " + parts.join("; ") unless parts.empty?
      end

      persist_game_event(lobby_id, game_state, "dice_rolled", player_id, serialize_event_payload(event).to_json, message)
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to roll dice for #{lobby_id}: #{ex.message}"
    end

    def discard_robber(lobby_id : String, player_id : String, discarded : ResourcePile)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      previous_player_id = game_state.turn.current_player_id
      previous_phase = game_state.turn.phase
      event = RobberDiscarded.new(next_version(game_state), PlayerId.new(player_id), discarded)

      game_state.apply!(event)
      sync_turn_timer_after_action!(lobby_id, game_state, previous_player_id, previous_phase, false)
      actor_name = game_state.player!(event.player_id).name
      persist_game_event(
        lobby_id,
        game_state,
        "robber_discarded",
        player_id,
        serialize_event_payload(event).to_json,
        "#{actor_name} discarded #{event.discarded.total} cards for the robber."
      )
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to discard for robber for #{lobby_id}: #{ex.message}"
    end

    def move_robber(lobby_id : String, player_id : String, tile_id : String, grant_timer_bonus : Bool = true)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      previous_player_id = game_state.turn.current_player_id
      previous_phase = game_state.turn.phase
      event = RobberMoved.new(next_version(game_state), PlayerId.new(player_id), TileId.new(tile_id))

      game_state.apply!(event)
      sync_turn_timer_after_action!(lobby_id, game_state, previous_player_id, previous_phase, grant_timer_bonus)
      persist_game_event(lobby_id, game_state, "robber_moved", player_id, serialize_event_payload(event).to_json, "#{game_state.player!(event.player_id).name} moved the robber.")
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to move robber for #{lobby_id}: #{ex.message}"
    end

    def robber_steal(lobby_id : String, player_id : String, victim_player_id : String, grant_timer_bonus : Bool = true)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      player = PlayerId.new(player_id)
      victim = PlayerId.new(victim_player_id)
      previous_player_id = game_state.turn.current_player_id
      previous_phase = game_state.turn.phase
      stolen_resource = random_resource_from_hand(game_state.player!(victim).hand)
      event = RobberStolen.new(next_version(game_state), player, victim, stolen_resource)

      game_state.apply!(event)
      sync_turn_timer_after_action!(lobby_id, game_state, previous_player_id, previous_phase, grant_timer_bonus)
      actor_name = game_state.player!(event.player_id).name
      victim_name = game_state.player!(event.victim_player_id).name
      persist_game_event(
        lobby_id,
        game_state,
        "robber_stolen",
        player_id,
        serialize_event_payload(event).to_json,
        "#{actor_name} stole a random card from #{victim_name}."
      )
      broadcast_game_state(lobby_id)
    rescue ex
      puts "Failed to steal with robber for #{lobby_id}: #{ex.message}"
    end

    def end_turn(lobby_id : String, player_id : String, grant_timer_bonus : Bool = false)
      game_state = @games[lobby_id]? || raise "no active game for lobby #{lobby_id}"
      previous_player_id = game_state.turn.current_player_id
      previous_phase = game_state.turn.phase
      event = TurnEnded.new(next_version(game_state), PlayerId.new(player_id))
      actor_name = game_state.player!(event.player_id).name

      game_state.apply!(event)
      sync_turn_timer_after_action!(lobby_id, game_state, previous_player_id, previous_phase, grant_timer_bonus)
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
      previous_summary = current_public_lobby_summary_for(lobby_id)

      lobby.remove_player(player_id)
      @game_event_store.remove_participant(lobby_id, player_id) unless @games[lobby_id]?
      log_event(
        lobby_id,
        "player_disconnected",
        player_id,
        {name: player.name}.to_json,
        "#{player.name} disconnected."
      )
      cleanup_lobby(lobby_id, lobby)
      broadcast_lobby_state(lobby_id) if @lobbies[lobby_id]?
      broadcast_public_lobby_change(lobby_id, previous_summary)
    end

    private def cleanup_lobby(lobby_id : String, lobby : Domain::Lobby)
      return unless lobby.players.empty?

      # Persist abandonment so empty public lobbies do not reappear after restarts.
      @game_event_store.abandon_waiting_lobby(lobby_id) unless @games[lobby_id]?

      @games.delete(lobby_id)
      @lobbies.delete(lobby_id)
      @clients.delete(lobby_id)
    end

    private def restore_lobby_from_store(lobby_id : String) : Nil
      return if @lobbies.has_key?(lobby_id)

      if persisted_lobby = @game_event_store.load_waiting_lobby(lobby_id)
        if persisted_lobby.participants.empty?
          @game_event_store.abandon_waiting_lobby(lobby_id)
          return
        end

        lobby = hydrate_waiting_lobby(persisted_lobby)
        @lobbies[lobby_id] = lobby
        schedule_cleanup_for_disconnected_players(lobby)
        return
      end

      persisted_snapshot = @game_event_store.load_game_snapshot(lobby_id)
      return unless persisted_snapshot

      snapshot = JSON.parse(persisted_snapshot.snapshot_json)
      settings = normalized_settings(snapshot["settings"]?.try(&.as_h) || parse_json_hash(persisted_snapshot.settings_json))
      game_state = hydrate_game_state(snapshot, settings)
      lobby = hydrate_lobby(lobby_id, game_state, settings)

      @games[lobby_id] = game_state
      @lobbies[lobby_id] = lobby
      schedule_turn_timer(lobby_id, game_state)
    rescue ex
      puts "Failed to restore persisted lobby for #{lobby_id}: #{ex.message}"
    end

    private def hydrate_waiting_lobby(persisted_lobby : Infrastructure::Persistence::PersistedLobby) : Domain::Lobby
      lobby = Domain::Lobby.new(persisted_lobby.short_code)
      lobby.host_id = persisted_lobby.host_player_id
      lobby.is_public = persisted_lobby.is_public
      lobby.created_at = persisted_lobby.created_at
      lobby.settings = normalized_settings(
        if persisted_lobby.settings_json
          parse_json_hash(persisted_lobby.settings_json)
        else
          default_settings_json
        end
      )

      persisted_lobby.participants.each do |participant|
        player = Domain::Player.new(participant.player_id, participant.player_name)
        player.ready = participant.ready
        player.connected = false
        player.disconnected_at = Time.utc
        lobby.add_player(player)
      end

      lobby
    end

    private def schedule_cleanup_for_disconnected_players(lobby : Domain::Lobby) : Nil
      lobby.players.each do |player|
        next if player.connected
        schedule_disconnect_cleanup(lobby.id, player.id, player.disconnect_version)
      end
    end

    private def hydrate_public_lobbies_from_store : Nil
      @game_event_store.load_public_waiting_lobbies.each do |persisted_lobby|
        if persisted_lobby.participants.empty?
          @game_event_store.abandon_waiting_lobby(persisted_lobby.short_code)
          next
        end

        lobby = hydrate_waiting_lobby(persisted_lobby)
        @lobbies[lobby.id] = lobby
        schedule_cleanup_for_disconnected_players(lobby)
      end
    rescue ex
      puts "Failed to restore public lobbies from store: #{ex.message}"
    end

    private def hydrate_lobby(lobby_id : String, game_state : GameState, settings : Hash(String, JSON::Any)) : Domain::Lobby
      lobby = Domain::Lobby.new(lobby_id)
      lobby.settings = normalized_settings(settings)
      game_state.player_order.each do |player_id|
        player_state = game_state.player!(player_id)
        player = Domain::Player.new(player_state.id.value, player_state.name)
        player.connected = false
        player.disconnected_at = Time.utc
        player.ready = false
        lobby.add_player(player)
      end
      lobby
    end

    private def hydrate_game_state(snapshot : JSON::Any, settings : Hash(String, JSON::Any)) : GameState
      settings = normalized_settings(settings)
      topology = extension_mode?(settings) ? BoardTopology.five_six_extension : BoardTopology.standard
      players = hydrate_players(snapshot["players"].as_a)
      board = hydrate_board(snapshot["board"], topology)
      bank = hydrate_bank(snapshot["bank"])
      player_order = snapshot["player_order"].as_a.map { |player_id| PlayerId.new(player_id.as_s) }
      turn = hydrate_turn(snapshot["turn"])

      GameState.new(
        topology: topology,
        players: players,
        settings: settings,
        board: board,
        bank: bank,
        player_order: player_order,
        turn: turn,
        version: snapshot["version"].as_i.to_i32,
        last_roll: hydrate_last_roll(snapshot["last_roll"]?),
        longest_road_player_id: snapshot.dig?("awards", "longest_road", "player_id").try { |value| PlayerId.new(value.as_s) },
        longest_road_length: snapshot.dig?("awards", "longest_road", "length").try(&.as_i.to_i32) || 0,
        largest_army_player_id: snapshot.dig?("awards", "largest_army", "player_id").try { |value| PlayerId.new(value.as_s) },
        largest_army_size: snapshot.dig?("awards", "largest_army", "size").try(&.as_i.to_i32) || 0,
        winner_player_id: snapshot["winner_player_id"]?.try { |value| value.raw.nil? ? nil : PlayerId.new(value.as_s) },
        pending_robber_discards: hydrate_pending_discards(turn: snapshot["turn"]),
        robber_eligible_victim_ids: snapshot["turn"]["robber_eligible_victim_ids"].as_a.map { |player_id| PlayerId.new(player_id.as_s) },
        robber_return_phase: hydrate_turn_phase(snapshot["turn"]["robber_return_phase"]?),
        pending_player_trades: hydrate_pending_trades(snapshot["turn"]),
        next_player_trade_id: hydrate_next_player_trade_id(snapshot["turn"])
      )
    end

    private def hydrate_players(players_json : Array(JSON::Any)) : Hash(PlayerId, PlayerState)
      players_json.each_with_object({} of PlayerId => PlayerState) do |player_json, players|
        player_id = PlayerId.new(player_json["id"].as_s)
        player = PlayerState.new(player_id, player_json["name"].as_s)
        hand_json = player_json["hand"]?.try(&.as_h)
        development_cards_json = player_json["development_cards"]?.try(&.as_h)

        if hand_json
          player.hand.wood = hand_json["wood"].as_i.to_i32
          player.hand.brick = hand_json["brick"].as_i.to_i32
          player.hand.sheep = hand_json["sheep"].as_i.to_i32
          player.hand.wheat = hand_json["wheat"].as_i.to_i32
          player.hand.ore = hand_json["ore"].as_i.to_i32
        end

        if development_cards_json
          hydrate_dev_card_hand(player.dev_cards, development_cards_json["playable"].as_h)
          hydrate_dev_card_hand(player.newly_purchased_dev_cards, development_cards_json["newly_purchased"].as_h)
        end

        player.victory_points = player_json["victory_points"].as_i.to_i32
        player.roads_left = player_json["roads_left"].as_i.to_i32
        player.settlements_left = player_json["settlements_left"].as_i.to_i32
        player.cities_left = player_json["cities_left"].as_i.to_i32
        player.knights_played = player_json["knights_played"].as_i.to_i32
        players[player_id] = player
      end
    end

    private def hydrate_dev_card_hand(hand : DevCardHand, cards_json : Hash(String, JSON::Any)) : Nil
      hand.knight = cards_json["knight"].as_i.to_i32
      hand.victory_point = cards_json["victory_point"].as_i.to_i32
      hand.road_building = cards_json["road_building"].as_i.to_i32
      hand.year_of_plenty = cards_json["year_of_plenty"].as_i.to_i32
      hand.monopoly = cards_json["monopoly"].as_i.to_i32
    end

    private def hydrate_board(board_json : JSON::Any, topology : BoardTopology) : BoardState
      tile_states = board_json["tiles"].as_a.each_with_object({} of TileId => TileState) do |tile_json, tile_map|
        tile_id = TileId.new(tile_json["id"].as_s)
        tile_map[tile_id] = TileState.new(
          parse_enum(Resource, tile_json["resource"].as_s),
          tile_json["token"]?.try { |value| value.raw.nil? ? nil : value.as_i.to_i32 }
        )
      end

      robber_tile = board_json["tiles"].as_a.find { |tile_json| tile_json["has_robber"].as_bool } || raise "snapshot missing robber tile"

      buildings = board_json["vertices"].as_a.each_with_object({} of VertexId => Building) do |vertex_json, building_map|
        next unless building_json = vertex_json["building"]?
        next if building_json.raw.nil?

        building_map[VertexId.new(vertex_json["id"].as_s)] = Building.new(
          PlayerId.new(building_json["player_id"].as_s),
          parse_enum(BuildingKind, building_json["kind"].as_s)
        )
      end

      roads = board_json["edges"].as_a.each_with_object({} of EdgeId => Road) do |edge_json, road_map|
        next unless road_json = edge_json["road"]?
        next if road_json.raw.nil?

        road_map[EdgeId.new(edge_json["id"].as_s)] = Road.new(PlayerId.new(road_json["player_id"].as_s))
      end

      harbors = board_json["harbors"].as_a.map do |harbor_json|
        HarborAssignment.new(
          HarborSlotId.new(harbor_json["id"].as_s),
          {
            VertexId.new(harbor_json["vertex_ids"].as_a[0].as_s),
            VertexId.new(harbor_json["vertex_ids"].as_a[1].as_s),
          },
          parse_enum(HarborKind, harbor_json["kind"].as_s)
        )
      end

      BoardState.new(
        tile_states: tile_states,
        robber_tile_id: TileId.new(robber_tile["id"].as_s),
        harbors: harbors,
        buildings: buildings,
        roads: roads
      )
    end

    private def hydrate_bank(bank_json : JSON::Any) : Bank
      resources_json = bank_json["resources"]
      dev_cards_json = bank_json["dev_cards"]

      Bank.new(
        resources: ResourcePile.new(
          resources_json["wood"].as_i.to_i32,
          resources_json["brick"].as_i.to_i32,
          resources_json["sheep"].as_i.to_i32,
          resources_json["wheat"].as_i.to_i32,
          resources_json["ore"].as_i.to_i32
        ),
        knight: dev_cards_json["knight"].as_i.to_i32,
        victory_point: dev_cards_json["victory_point"].as_i.to_i32,
        road_building: dev_cards_json["road_building"].as_i.to_i32,
        year_of_plenty: dev_cards_json["year_of_plenty"].as_i.to_i32,
        monopoly: dev_cards_json["monopoly"].as_i.to_i32
      )
    end

    private def hydrate_turn(turn_json : JSON::Any) : TurnState
      current_player_id = PlayerId.new(turn_json["current_player_id"].as_s)
      TurnState.new(
        current_player_id: current_player_id,
        number: turn_json["number"].as_i.to_i32,
        phase: parse_enum(TurnPhase, turn_json["phase"].as_s),
        dev_card_played_this_turn: turn_json["dev_card_played_this_turn"].as_bool,
        timer_started_at: hydrate_time(turn_json["timer_started_at"]?),
        timer_expires_at: hydrate_time(turn_json["timer_expires_at"]?),
        timer_duration_seconds: turn_json["timer_duration_seconds"]?.try { |value| value.raw.nil? ? nil : value.as_i.to_i32 },
        role: turn_json["role"]?.try { |value| parse_enum(TurnRole, value.as_s) } || TurnRole::Regular,
        primary_player_id: turn_json["primary_player_id"]?.try { |value| PlayerId.new(value.as_s) } || current_player_id,
        special_build_remaining_player_ids: turn_json["special_build_remaining_player_ids"]?.try(&.as_a.map { |value| PlayerId.new(value.as_s) }) || [] of PlayerId
      )
    end

    private def hydrate_turn_phase(turn_phase_json : JSON::Any?) : TurnPhase?
      return nil unless turn_phase_json
      return nil if turn_phase_json.raw.nil?

      parse_enum(TurnPhase, turn_phase_json.as_s)
    end

    private def hydrate_last_roll(last_roll_json : JSON::Any?) : DiceRoll?
      return nil unless last_roll_json
      return nil if last_roll_json.raw.nil?

      DiceRoll.new(
        last_roll_json["die_one"].as_i.to_i32,
        last_roll_json["die_two"].as_i.to_i32
      )
    end

    private def hydrate_time(time_json : JSON::Any?) : Time?
      return nil unless time_json
      return nil if time_json.raw.nil?

      Time.parse_rfc3339(time_json.as_s)
    end

    private def hydrate_pending_discards(turn : JSON::Any) : Hash(PlayerId, Int32)
      turn["pending_robber_discards"].as_a.each_with_object({} of PlayerId => Int32) do |discard_json, discards|
        discards[PlayerId.new(discard_json["player_id"].as_s)] = discard_json["count"].as_i.to_i32
      end
    end

    private def hydrate_pending_trades(turn : JSON::Any) : Array(PendingPlayerTrade)
      if trades_json = turn["pending_player_trades"]?
        return [] of PendingPlayerTrade if trades_json.raw.nil?

        return trades_json.as_a.compact_map { |trade_json| hydrate_pending_trade(trade_json) }
      end

      # Backward-compatible hydration for snapshots that stored a single trade.
      single = hydrate_pending_trade(turn["pending_player_trade"]?)
      single ? [single] : [] of PendingPlayerTrade
    end

    private def hydrate_next_player_trade_id(turn : JSON::Any) : Int32
      if next_id = turn["next_player_trade_id"]?.try(&.as_i?)
        return next_id.to_i32
      end

      trades = hydrate_pending_trades(turn)
      return 1 if trades.empty?

      trades.map(&.id).max + 1
    end

    private def hydrate_pending_trade(pending_trade_json : JSON::Any?) : PendingPlayerTrade?
      return nil unless pending_trade_json
      return nil if pending_trade_json.raw.nil?

      responses = pending_trade_json["responses"].as_a.each_with_object({} of PlayerId => PlayerTradeResponseStatus) do |response_json, result|
        result[PlayerId.new(response_json["player_id"].as_s)] = parse_enum(PlayerTradeResponseStatus, response_json["status"].as_s)
      end

      trade_id = pending_trade_json["id"]?.try(&.as_i?).try(&.to_i32) || 1

      PendingPlayerTrade.new(
        trade_id,
        PlayerId.new(pending_trade_json["player_id"].as_s),
        hydrate_resource_pile(pending_trade_json["offered"]),
        hydrate_resource_pile(pending_trade_json["requested"]),
        responses
      )
    end

    private def hydrate_resource_pile(pile_json : JSON::Any) : ResourcePile
      ResourcePile.new(
        pile_json["wood"].as_i.to_i32,
        pile_json["brick"].as_i.to_i32,
        pile_json["sheep"].as_i.to_i32,
        pile_json["wheat"].as_i.to_i32,
        pile_json["ore"].as_i.to_i32
      )
    end

    private def lobby_full_for_new_player?(lobby : Domain::Lobby, player_id : String) : Bool
      return false if lobby.find_player(player_id)
      lobby.players.size >= max_players_for(lobby)
    end

    private def current_public_lobby_summary_for(lobby_id : String) : PublicLobbySummary?
      @lobbies[lobby_id]?.try do |lobby|
        public_lobby_summary(lobby)
      end
    end

    private def public_lobby_summary(lobby : Domain::Lobby) : PublicLobbySummary?
      return nil unless lobby.is_public
      return nil if @games[lobby.id]?
      return nil if lobby.players.empty?
      return nil if lobby.players.size >= max_players_for(lobby)
      return nil unless host_id = lobby.host_id

      host_player = lobby.find_player(host_id)
      host_name = host_player.try(&.name) || "Player"

      PublicLobbySummary.new(
        short_code: lobby.id,
        host_player_id: host_id,
        host_display_name: host_name,
        participant_count: lobby.players.size.to_i32,
        max_players: max_players_for(lobby),
        created_at: lobby.created_at.to_rfc3339,
        is_public: lobby.is_public,
        game_mode: lobby.settings["gameMode"]?.try(&.as_s) || "base",
        five_six_turn_rule: lobby.settings["fiveSixTurnRule"]?.try(&.as_s) || "paired"
      )
    end

    private def broadcast_public_lobby_change(lobby_id : String, previous_summary : PublicLobbySummary?) : Nil
      current_summary = current_public_lobby_summary_for(lobby_id)

      if previous_summary.nil? && current_summary.nil?
        return
      elsif previous_summary.nil?
        broadcast_public_event("public_lobby_created", current_summary)
      elsif current_summary.nil?
        broadcast_public_event("public_lobby_removed", previous_summary)
      else
        broadcast_public_event("public_lobby_updated", current_summary)
      end
    end

    private def broadcast_public_event(event_type : String, summary : PublicLobbySummary?) : Nil
      return if @public_clients.empty?
      return unless summary

      payload =
        if event_type == "public_lobby_removed"
          {type: event_type, short_code: summary.short_code}
        else
          {type: event_type, lobby: serialize_public_lobby(summary)}
        end

      json = payload.to_json
      @public_clients.each do |client|
        client.send_json(json)
      end
    end

    private def serialize_public_lobby(summary : PublicLobbySummary)
      {
        shortCode:        summary.short_code,
        hostPlayerId:     summary.host_player_id,
        hostDisplayName:  summary.host_display_name,
        participantCount: summary.participant_count,
        maxPlayers:       summary.max_players,
        createdAt:        summary.created_at,
        isPublic:         summary.is_public,
        gameMode:         summary.game_mode,
        fiveSixTurnRule:  summary.five_six_turn_rule,
      }
    end

    private def max_players_for(lobby : Domain::Lobby) : Int32
      extension_mode?(lobby.settings) ? 6 : 4
    end

    private def default_settings_json : Hash(String, JSON::Any)
      parse_json_hash(
        {
          turnTimerEnabled: true,
          turnTimeSeconds:  120,
          maxPlayers:       4,
          victoryPoints:    10,
          gameMode:         "base",
          fiveSixTurnRule:  "paired",
          useSeafarers:     false,
          useTraders:       false,
          useExplorers:     false,
        }.to_json
      )
    end

    private def parse_json_hash(json : String?) : Hash(String, JSON::Any)
      return Hash(String, JSON::Any).new unless json

      JSON.parse(json).as_h.transform_values { |value| value }
    end

    private def normalized_settings(settings : Hash(String, JSON::Any)) : Hash(String, JSON::Any)
      normalized = default_settings_json.merge(settings)
      normalized["maxPlayers"] = JSON::Any.new(extension_mode?(normalized) ? 6_i64 : 4_i64)
      normalized
    end

    private def extension_mode?(settings : Hash(String, JSON::Any)) : Bool
      settings["gameMode"]?.try(&.as_s) == "fiveSixExtension"
    end

    private def validate_lobby_settings!(lobby : Domain::Lobby, settings : Hash(String, JSON::Any)) : Nil
      mode = settings["gameMode"].as_s
      raise "Unknown game mode" unless mode == "base" || mode == "fiveSixExtension"
      turn_rule = settings["fiveSixTurnRule"].as_s
      raise "Unknown 5-6 player turn rule" unless turn_rule == "paired" || turn_rule == "specialBuild"
      max_players = settings["maxPlayers"].as_i.to_i32
      expected_seats = extension_mode?(settings) ? 6 : 4
      raise "Invalid seat count for selected game mode" unless max_players == expected_seats
      raise "The selected game mode has fewer seats than the current lobby" if lobby.players.size > max_players
    end

    private def validate_game_start!(lobby : Domain::Lobby) : Nil
      settings = normalized_settings(lobby.settings)
      validate_lobby_settings!(lobby, settings)
      allowed = extension_mode?(settings) ? (5..6) : (3..4)
      raise "Incorrect player count for selected game mode" unless allowed.includes?(lobby.players.size)
      raise "All players must be connected and ready" unless lobby.players.all? { |player| player.connected && player.ready }
    end

    private def parse_enum(enum_type : T.class, value : String) : T forall T
      enum_type.parse(value)
    end

    private def build_game_state(lobby : Domain::Lobby) : GameState
      settings = normalized_settings(lobby.settings)
      GameState.new(
        topology: extension_mode?(settings) ? BoardTopology.five_six_extension : BoardTopology.standard,
        players: lobby.players.map { |player|
          player_id = PlayerId.new(player.id)
          {player_id, PlayerState.new(player_id, player.name)}
        }.to_h,
        settings: settings
      )
    end

    private def broadcast_game_state(lobby_id : String, message_type : String = "game_update")
      return unless game_state = @games[lobby_id]?
      return unless list = @clients[lobby_id]?

      list.each do |client|
        client.send_json(
          {
            type:       message_type,
            game_state: serialize_game_state(game_state, client.player_id),
          }.to_json
        )
      end

      save_game_snapshot(lobby_id, game_state)
    end

    private def serialize_game_state(game_state : GameState, viewer_player_id : String? = nil, include_all_hands : Bool = false)
      {
        version:      game_state.version,
        player_order: game_state.player_order.map(&.value),
        turn:         {
          current_player_id:                  game_state.turn.current_player_id.value,
          primary_player_id:                  game_state.turn.primary_player_id.value,
          role:                               game_state.turn.role.to_s,
          special_build_remaining_player_ids: game_state.turn.special_build_remaining_player_ids.map(&.value),
          number:                             game_state.turn.number,
          phase:                              game_state.turn.phase.to_s,
          dev_card_played_this_turn:          game_state.turn.dev_card_played_this_turn,
          timer_enabled:                      game_state.turn_timer_enabled?,
          timer_started_at:                   game_state.turn.timer_started_at.try(&.to_rfc3339),
          timer_expires_at:                   game_state.turn.timer_expires_at.try(&.to_rfc3339),
          timer_duration_seconds:             game_state.turn.timer_duration_seconds,
          robber_return_phase:                game_state.robber_return_phase.try(&.to_s),
          pending_player_trades:              game_state.pending_player_trades.map { |trade|
            serialize_pending_player_trade(trade, viewer_player_id)
          },
          next_player_trade_id:    game_state.next_player_trade_id,
          pending_robber_discards: game_state.pending_robber_discards.map { |target_player_id, count|
            {
              player_id: target_player_id.value,
              count:     count,
            }
          },
          robber_eligible_victim_ids: game_state.robber_eligible_victim_ids.map(&.value),
        },
        last_roll: game_state.last_roll ? {
          die_one: game_state.last_roll.not_nil!.die_one,
          die_two: game_state.last_roll.not_nil!.die_two,
          total:   game_state.last_roll.not_nil!.total,
        } : nil,
        players: game_state.player_order.map { |player_id|
          player = game_state.player!(player_id)
          {
            id:                     player.id.value,
            name:                   player.name,
            victory_points:         player.victory_points,
            victory_point_cards:    include_all_hands || player.id.value == viewer_player_id || game_state.turn.phase == TurnPhase::GameOver ? player.revealed_victory_point_cards : 0,
            roads_left:             player.roads_left,
            settlements_left:       player.settlements_left,
            cities_left:            player.cities_left,
            knights_played:         player.knights_played,
            has_longest_road:       game_state.longest_road_player_id == player.id,
            has_largest_army:       game_state.largest_army_player_id == player.id,
            resource_count:         total_resources(player.hand),
            development_card_count: player.total_dev_cards,
            hand:                   include_all_hands || player.id.value == viewer_player_id ? {
              wood:  player.hand.wood,
              brick: player.hand.brick,
              sheep: player.hand.sheep,
              wheat: player.hand.wheat,
              ore:   player.hand.ore,
            } : nil,
            development_cards: include_all_hands || player.id.value == viewer_player_id ? {
              playable:        player.dev_cards.to_json_payload,
              newly_purchased: player.newly_purchased_dev_cards.to_json_payload,
            } : nil,
          }
        },
        bank:  game_state.bank.to_json_payload,
        board: {
          tiles: game_state.topology.tiles.values.sort_by(&.id.value).map { |tile|
            tile_state = game_state.board.tile_states[tile.id]
            {
              id:         tile.id.value,
              x:          tile.x,
              y:          tile.y,
              resource:   tile_state.resource.to_s,
              token:      tile_state.token,
              has_robber: game_state.board.robber_tile_id == tile.id,
            }
          },
          vertices: game_state.topology.vertices.values.sort_by(&.id.value).map { |vertex|
            building = game_state.board.building_at?(vertex.id)
            {
              id:       vertex.id.value,
              x:        vertex.x,
              y:        vertex.y,
              building: building ? {
                player_id: building.player_id.value,
                kind:      building.kind.to_s,
              } : nil,
            }
          },
          edges: game_state.topology.edges.values.sort_by(&.id.value).map { |edge|
            road = game_state.board.road_at?(edge.id)
            {
              id:   edge.id.value,
              v1:   edge.vertex_ids[0].value,
              v2:   edge.vertex_ids[1].value,
              road: road ? {
                player_id: road.player_id.value,
              } : nil,
            }
          },
          harbors: game_state.board.harbors.sort_by(&.id.value).map { |harbor|
            {
              id:         harbor.id.value,
              vertex_ids: [harbor.vertex_ids[0].value, harbor.vertex_ids[1].value],
              kind:       harbor.kind.to_s,
            }
          },
        },
        awards: {
          longest_road: game_state.longest_road_player_id ? {
            player_id: game_state.longest_road_player_id.not_nil!.value,
            length:    game_state.longest_road_length,
          } : nil,
          largest_army: game_state.largest_army_player_id ? {
            player_id: game_state.largest_army_player_id.not_nil!.value,
            size:      game_state.largest_army_size,
          } : nil,
        },
        winner_player_id: game_state.winner_player_id.try(&.value),
        settings:         game_state.settings,
      }
    end

    private def serialize_event_payload(event : GameEvent)
      case event
      when SettlementPlaced
        {
          version:   event.version,
          player_id: event.player_id.value,
          vertex_id: event.vertex_id.value,
          free:      event.free,
        }
      when RoadPlaced
        {
          version:   event.version,
          player_id: event.player_id.value,
          edge_id:   event.edge_id.value,
          free:      event.free,
        }
      when CityPlaced
        {
          version:   event.version,
          player_id: event.player_id.value,
          vertex_id: event.vertex_id.value,
        }
      when DevelopmentCardPurchased
        {
          version:   event.version,
          player_id: event.player_id.value,
          card:      event.card.to_s,
        }
      when KnightPlayed
        {
          version:   event.version,
          player_id: event.player_id.value,
          tile_id:   event.tile_id.value,
        }
      when RoadBuildingPlayed
        {
          version:        event.version,
          player_id:      event.player_id.value,
          first_edge_id:  event.first_edge_id.value,
          second_edge_id: event.second_edge_id.try(&.value),
        }
      when MonopolyPlayed
        {
          version:   event.version,
          player_id: event.player_id.value,
          resource:  event.resource.to_s,
        }
      when YearOfPlentyPlayed
        {
          version:         event.version,
          player_id:       event.player_id.value,
          first_resource:  event.first_resource.to_s,
          second_resource: event.second_resource.to_s,
        }
      when PlayerTradeProposed
        {
          version:   event.version,
          trade_id:  event.trade_id,
          player_id: event.player_id.value,
          offered:   event.offered.to_json_payload,
          requested: event.requested.to_json_payload,
        }
      when PlayerTradeAccepted
        {
          version:           event.version,
          trade_id:          event.trade_id,
          player_id:         event.player_id.value,
          partner_player_id: event.partner_player_id.value,
        }
      when PlayerTradeRejected
        {
          version:           event.version,
          trade_id:          event.trade_id,
          player_id:         event.player_id.value,
          partner_player_id: event.partner_player_id.value,
        }
      when PlayerTradeCancelled
        {
          version:   event.version,
          trade_id:  event.trade_id,
          player_id: event.player_id.value,
        }
      when PlayerTradeCompleted
        {
          version:           event.version,
          trade_id:          event.trade_id,
          player_id:         event.player_id.value,
          partner_player_id: event.partner_player_id.value,
          offered:           event.offered.to_json_payload,
          requested:         event.requested.to_json_payload,
        }
      when BankTradeCompleted
        {
          version:            event.version,
          player_id:          event.player_id.value,
          offered_resource:   event.offered_resource.to_s,
          requested_resource: event.requested_resource.to_s,
        }
      when DiceRolled
        {
          version: event.version,
          die_one: event.die_one,
          die_two: event.die_two,
          total:   event.total,
        }
      when RobberDiscarded
        {
          version:   event.version,
          player_id: event.player_id.value,
          discarded: event.discarded.to_json_payload,
        }
      when RobberMoved
        {
          version:   event.version,
          player_id: event.player_id.value,
          tile_id:   event.tile_id.value,
        }
      when RobberStolen
        {
          version:          event.version,
          player_id:        event.player_id.value,
          victim_player_id: event.victim_player_id.value,
          resource:         event.resource.to_s,
        }
      when TurnEnded
        {
          version:   event.version,
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

      if list = @clients[lobby_id]?
        event_json = {
          type:       "game_log",
          message:    message,
          event_type: event_type,
          payload:    JSON.parse(payload_json),
        }.to_json
        list.each do |client|
          client.send_json(event_json)
        end
      end
    end

    private def broadcast_chat_message(lobby_id : String, player_id : String, player_name : String, message : String, created_at : Time)
      if list = @clients[lobby_id]?
        event_json = {
          type:        "chat_message",
          player_id:   player_id,
          player_name: player_name,
          message:     message,
          created_at:  created_at.to_rfc3339,
        }.to_json
        list.each do |client|
          client.send_json(event_json)
        end
      end
    end

    private def serialize_pending_player_trade(pending_trade : PendingPlayerTrade, viewer_player_id : String?)
      viewer_response = viewer_player_id ? pending_trade.response_for(PlayerId.new(viewer_player_id)).try(&.to_s) : nil

      {
        id:        pending_trade.id,
        player_id: pending_trade.player_id.value,
        offered:   pending_trade.offered.to_json_payload,
        requested: pending_trade.requested.to_json_payload,
        responses: pending_trade.responses.keys.sort_by(&.value).map { |player_id|
          {
            player_id: player_id.value,
            status:    pending_trade.responses[player_id].to_s,
          }
        },
        accepted_player_ids: pending_trade.accepted_player_ids.map(&.value),
        rejected_player_ids: pending_trade.rejected_player_ids.map(&.value),
        viewer_response:     viewer_response,
        can_respond:         viewer_player_id ? viewer_player_id != pending_trade.player_id.value : false,
        can_finalize:        viewer_player_id == pending_trade.player_id.value && !pending_trade.accepted_player_ids.empty?,
      }
    end

    private def initialize_turn_timer!(lobby_id : String, game_state : GameState, now : Time = Time.utc) : Nil
      if !game_state.turn_timer_enabled? || game_state.turn.phase.lobby? || game_state.turn.phase.game_over?
        game_state.clear_turn_timer!
      elsif duration = game_state.timer_duration_for_phase(game_state.turn.phase)
        game_state.start_turn_timer!(duration, now)
      else
        game_state.clear_turn_timer!
      end

      schedule_turn_timer(lobby_id, game_state)
    end

    private def sync_turn_timer_after_action!(
      lobby_id : String,
      game_state : GameState,
      previous_player_id : PlayerId,
      previous_phase : TurnPhase,
      grant_bonus : Bool,
      now : Time = Time.utc,
    ) : Nil
      if !game_state.turn_timer_enabled? || game_state.turn.phase.lobby? || game_state.turn.phase.game_over?
        game_state.clear_turn_timer!
        schedule_turn_timer(lobby_id, game_state)
        return
      end

      if should_reset_turn_timer?(game_state, previous_player_id, previous_phase) || game_state.turn.timer_expires_at.nil?
        if duration = game_state.timer_duration_for_phase(game_state.turn.phase)
          game_state.start_turn_timer!(duration, now)
        else
          game_state.clear_turn_timer!
        end
      end

      if grant_bonus && game_state.turn.current_player_id == previous_player_id
        game_state.extend_turn_timer!(TIMER_BONUS_SECONDS, now)
      end

      schedule_turn_timer(lobby_id, game_state)
    end

    private def should_reset_turn_timer?(game_state : GameState, previous_player_id : PlayerId, previous_phase : TurnPhase) : Bool
      return true if game_state.turn.current_player_id != previous_player_id

      current_phase = game_state.turn.phase
      return false if current_phase == previous_phase

      case current_phase
      when .setup1_settlement?, .setup1_road?, .setup2_settlement?, .setup2_road?, .roll?, .discard_resources?
        true
      when .main?
        previous_phase.roll?
      when .move_robber?
        previous_phase.roll? || previous_phase.discard_resources?
      else
        false
      end
    end

    private def setup_phase?(phase : TurnPhase) : Bool
      phase.setup1_settlement? || phase.setup1_road? || phase.setup2_settlement? || phase.setup2_road?
    end

    private def schedule_turn_timer(lobby_id : String, game_state : GameState) : Nil
      version = (@timer_versions[lobby_id] += 1)
      expires_at = game_state.turn.timer_expires_at
      return unless game_state.turn_timer_enabled?
      return unless expires_at

      spawn do
        remaining = expires_at - Time.utc
        sleep remaining if remaining > 0.seconds
        handle_turn_timeout(lobby_id, version)
      end
    end

    private def handle_turn_timeout(lobby_id : String, version : Int32) : Nil
      return unless @timer_versions[lobby_id]? == version
      return unless game_state = @games[lobby_id]?
      return unless game_state.turn_timer_enabled?
      return unless expires_at = game_state.turn.timer_expires_at
      return if expires_at > Time.utc

      resolve_turn_timeout(lobby_id, game_state)
    rescue ex
      puts "Failed to resolve turn timeout for #{lobby_id}: #{ex.message}"
    end

    private def resolve_turn_timeout(lobby_id : String, game_state : GameState) : Nil
      player_id = game_state.turn.current_player_id.value
      player_name = game_state.player!(game_state.turn.current_player_id).name

      case game_state.turn.phase
      when .roll?
        log_timeout_event(lobby_id, player_id, "#{player_name} timed out; the dice were rolled automatically.")
        roll_dice(lobby_id, player_id, false)
      when .main?
        log_timeout_event(lobby_id, player_id, "#{player_name} timed out; their turn ended automatically.")
        end_turn(lobby_id, player_id, false)
      when .discard_resources?
        log_timeout_event(lobby_id, player_id, "#{player_name} timed out; pending robber discards were resolved randomly.")
        auto_discard_pending_robber!(lobby_id, game_state)
      when .move_robber?
        tile_id = random_legal_robber_tile_id(game_state).value
        log_timeout_event(lobby_id, player_id, "#{player_name} timed out; the robber was moved automatically.")
        move_robber(lobby_id, player_id, tile_id, false)
      when .steal_resource?
        victim_player_id = game_state.robber_eligible_victim_ids.sample(random: Random::DEFAULT).not_nil!.value
        log_timeout_event(lobby_id, player_id, "#{player_name} timed out; a robber steal target was chosen automatically.")
        robber_steal(lobby_id, player_id, victim_player_id, false)
      when .setup1_settlement?, .setup2_settlement?
        vertex_id = random_legal_setup_vertex_id(game_state).value
        log_timeout_event(lobby_id, player_id, "#{player_name} timed out; a setup settlement was placed automatically.")
        place_settlement(lobby_id, player_id, vertex_id, true, false)
      when .setup1_road?, .setup2_road?
        edge_id = random_legal_setup_road_id(game_state).value
        log_timeout_event(lobby_id, player_id, "#{player_name} timed out; a setup road was placed automatically.")
        place_road(lobby_id, player_id, edge_id, true, false)
      end
    end

    private def log_timeout_event(lobby_id : String, player_id : String, message : String) : Nil
      log_event(lobby_id, "turn_timeout", player_id, ({message: message}).to_json, message)
    end

    private def random_legal_setup_vertex_id(game_state : GameState) : VertexId
      candidates = game_state.topology.vertices.keys.select do |vertex_id|
        next false if game_state.board.occupied_vertex?(vertex_id)

        game_state.topology.neighboring_vertices(vertex_id).none? do |neighbor_id|
          game_state.board.occupied_vertex?(neighbor_id)
        end
      end

      candidates.sample(random: Random::DEFAULT) || raise "no legal setup settlement available"
    end

    private def random_legal_setup_road_id(game_state : GameState) : EdgeId
      player_id = game_state.turn.current_player_id
      settlement_vertex_id = pending_setup_settlement_vertex(game_state, player_id)
      candidates = game_state.topology.vertices[settlement_vertex_id].edge_ids.reject do |edge_id|
        game_state.board.occupied_edge?(edge_id)
      end

      candidates.sample(random: Random::DEFAULT) || raise "no legal setup road available"
    end

    private def pending_setup_settlement_vertex(game_state : GameState, player_id : PlayerId) : VertexId
      candidates = game_state.board.buildings.each_with_object([] of VertexId) do |(vertex_id, building), memo|
        next unless building.player_id == player_id
        next unless player_road_ids_touching_vertex(game_state, vertex_id, player_id).empty?
        memo << vertex_id
      end

      raise "missing setup settlement for timed road placement" unless candidates.size == 1
      candidates.first
    end

    private def player_road_ids_touching_vertex(game_state : GameState, vertex_id : VertexId, player_id : PlayerId) : Array(EdgeId)
      game_state.topology.vertices[vertex_id].edge_ids.select do |edge_id|
        road = game_state.board.road_at?(edge_id)
        !!road && road.player_id == player_id
      end
    end

    private def random_legal_robber_tile_id(game_state : GameState) : TileId
      candidates = game_state.topology.tiles.keys.reject { |tile_id| tile_id == game_state.board.robber_tile_id }
      candidates.sample(random: Random::DEFAULT) || raise "no legal robber tile available"
    end

    private def auto_discard_pending_robber!(lobby_id : String, game_state : GameState) : Nil
      game_state.pending_robber_discards.keys.each do |discarding_player_id|
        count = game_state.pending_robber_discards[discarding_player_id]? || next
        discarded = random_discard_pile(game_state.player!(discarding_player_id).hand, count)
        discard_robber(lobby_id, discarding_player_id.value, discarded)
      end
    end

    private def random_discard_pile(hand : ResourceHand, count : Int32) : ResourcePile
      remaining_hand = ResourceHand.new(hand.wood, hand.brick, hand.sheep, hand.wheat, hand.ore)
      discarded = ResourcePile.new

      count.times do
        resource = random_resource_from_hand(remaining_hand)
        remaining_hand.remove(resource)
        discarded.add(resource)
      end

      discarded
    end

    private def next_version(game_state : GameState) : Int32
      game_state.version + 1
    end

    private def format_resource_pile(pile : ResourcePile) : String
      parts = [] of String
      pile.each_nonzero { |resource, amount| parts << "#{amount} #{resource.to_s.downcase}" }
      parts.empty? ? "nothing" : parts.join(", ")
    end

    private def total_resources(hand : ResourceHand) : Int32
      hand.total
    end

    private def random_resource_from_hand(hand : ResourceHand) : Resource
      total = hand.total
      raise "cannot steal from empty hand" if total.zero?

      target = Random.rand(total)
      running_total = 0

      [Resource::Wood, Resource::Brick, Resource::Sheep, Resource::Wheat, Resource::Ore].each do |resource|
        running_total += hand.count(resource)
        return resource if target < running_total
      end

      raise "failed to choose a random resource"
    end

    private def bank_trade_rate_for(game_state : GameState, player_id : PlayerId, resource : Resource) : Int32
      return 4 if resource.desert?

      best_rate = 4

      game_state.board.harbors.each do |harbor|
        next unless harbor_claimed_by?(game_state, harbor, player_id)

        rate = case harbor.kind
               when .three_to_one?
                 3
               when .wood_two_to_one?
                 resource.wood? ? 2 : nil
               when .brick_two_to_one?
                 resource.brick? ? 2 : nil
               when .sheep_two_to_one?
                 resource.sheep? ? 2 : nil
               when .wheat_two_to_one?
                 resource.wheat? ? 2 : nil
               when .ore_two_to_one?
                 resource.ore? ? 2 : nil
               end

        best_rate = Math.min(best_rate, rate) if rate
      end

      best_rate
    end

    private def harbor_claimed_by?(game_state : GameState, harbor : HarborAssignment, player_id : PlayerId) : Bool
      harbor.vertex_ids.any? do |vertex_id|
        if building = game_state.board.building_at?(vertex_id)
          building.player_id == player_id
        else
          false
        end
      end
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
