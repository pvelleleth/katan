require "http/server"
require "http/web_socket"
require "json"
require "./client"
require "./message"
require "../../application/services/lobby_manager"

module Katan::Engine::Transport::WebSocket
  class Handler
    include HTTP::Handler

    def initialize(@lobby_manager : Application::LobbyManager)
    end

    def call(context)
      request = context.request

      if request.path.starts_with?("/ws/lobby/")
        # Extract the lobby ID from the path, e.g. /ws/lobby/123
        lobby_id = request.path.sub("/ws/lobby/", "")

        # Check if the path format was correct
        if lobby_id.empty?
          call_next(context)
          return
        end

        # Upgrade to WebSocket
        ws_handler = HTTP::WebSocketHandler.new do |ws, _ctx|
          client = Client.new(ws)
          client.lobby_id = lobby_id

          ws.on_message do |msg|
            handle_message(client, msg)
          end

          ws.on_close do
            @lobby_manager.disconnect_client(client)
          end
        end

        ws_handler.call(context)
      else
        call_next(context)
      end
    end

    private def handle_message(client : Client, msg : String)
      begin
        incoming = IncomingMessage.from_json(msg)
        lid = client.lobby_id
        return unless lid

        case incoming.action
        when "join"
          if payload = incoming.payload
            player_id = payload["player_id"]?.try(&.as_s?)
            name = payload["name"]?.try(&.as_s?)
            host_id = payload["host_id"]?.try(&.as_s?)

            if player_id && name
              @lobby_manager.handle_join(lid, player_id, name, client, host_id)
            end
          end
        when "leave"
          @lobby_manager.remove_client(client)
          client.socket.close
        when "kick"
          if payload = incoming.payload
            target_player_id = payload["target_player_id"]?.try(&.as_s?)

            if target_player_id
              lobby = @lobby_manager.get_or_create_lobby(lid)
              # Only the host is allowed to kick
              if lobby.host_id == client.player_id
                @lobby_manager.kick_player(lid, target_player_id)
              else
                puts "Kick rejected: #{client.player_id} is not the host of #{lid}"
              end
            end
          end
        when "settings_update"
          if payload = incoming.payload
            settings = payload["settings"]?.try(&.as_h?)
            if settings
              lobby = @lobby_manager.get_or_create_lobby(lid)
              if lobby.host_id == client.player_id
                @lobby_manager.update_settings(lid, settings)
              else
                puts "Settings update rejected: #{client.player_id} is not the host of #{lid}"
              end
            end
          end
        when "start_game", "place_settlement", "place_road", "place_city", "buy_development_card", "play_knight", "play_road_building", "play_monopoly", "play_year_of_plenty", "trade_with_player", "propose_player_trade", "accept_player_trade", "reject_player_trade", "cancel_player_trade", "finalize_player_trade", "trade_with_bank", "trade_with_harbor", "roll_dice", "discard_robber", "move_robber", "robber_steal", "end_turn", "game_action"
          handle_gameplay_action(client, lid, incoming)
        when "ready"
          if payload = incoming.payload
            player_id = payload["player_id"]?.try(&.as_s?)
            ready_state = payload["ready"]?.try(&.as_bool?)

            if player_id && !ready_state.nil?
              @lobby_manager.set_player_ready(lid, player_id, ready_state)
            end
          end
        else
          puts "Unknown action: #{incoming.action}"
        end
      rescue ex : JSON::ParseException
        puts "JSON parse error from WS client: #{ex.message}"
      rescue ex
        puts "Error handling ws message: #{ex.message}\n#{ex.backtrace.join("\n")}"
      end
    end

    private def handle_gameplay_action(client : Client, lobby_id : String, incoming : IncomingMessage)
      case incoming.action
      when "start_game"
        lobby = @lobby_manager.get_or_create_lobby(lobby_id)
        if lobby.host_id == client.player_id
          @lobby_manager.start_game(lobby_id)
        else
          puts "Start game rejected: #{client.player_id} is not the host of #{lobby_id}"
        end
      when "place_settlement"
        return unless payload = incoming.payload
        return unless player_id = client.player_id

        vertex_id = payload["vertex_id"]?.try(&.as_s?)
        free = payload["free"]?.try(&.as_bool?) || false
        @lobby_manager.place_settlement(lobby_id, player_id, vertex_id, free) if vertex_id
      when "place_road"
        return unless payload = incoming.payload
        return unless player_id = client.player_id

        edge_id = payload["edge_id"]?.try(&.as_s?)
        free = payload["free"]?.try(&.as_bool?) || false
        @lobby_manager.place_road(lobby_id, player_id, edge_id, free) if edge_id
      when "place_city"
        return unless payload = incoming.payload
        return unless player_id = client.player_id

        vertex_id = payload["vertex_id"]?.try(&.as_s?)
        @lobby_manager.place_city(lobby_id, player_id, vertex_id) if vertex_id
      when "buy_development_card"
        return unless player_id = client.player_id

        @lobby_manager.buy_development_card(lobby_id, player_id)
      when "play_knight"
        return unless payload = incoming.payload
        return unless player_id = client.player_id

        tile_id = payload["tile_id"]?.try(&.as_s?)
        @lobby_manager.play_knight(lobby_id, player_id, tile_id) if tile_id
      when "play_road_building"
        return unless payload = incoming.payload
        return unless player_id = client.player_id

        first_edge_id = payload["first_edge_id"]?.try(&.as_s?)
        second_edge_id = payload["second_edge_id"]?.try(&.as_s?)
        @lobby_manager.play_road_building(lobby_id, player_id, first_edge_id, second_edge_id) if first_edge_id
      when "play_monopoly"
        return unless payload = incoming.payload
        return unless player_id = client.player_id

        resource_name = payload["resource"]?.try(&.as_s?)
        resource = parse_resource(resource_name)
        @lobby_manager.play_monopoly(lobby_id, player_id, resource) if resource
      when "play_year_of_plenty"
        return unless payload = incoming.payload
        return unless player_id = client.player_id

        first_resource_name = payload["first_resource"]?.try(&.as_s?)
        second_resource_name = payload["second_resource"]?.try(&.as_s?)
        first_resource = parse_resource(first_resource_name)
        second_resource = parse_resource(second_resource_name)
        @lobby_manager.play_year_of_plenty(lobby_id, player_id, first_resource, second_resource) if first_resource && second_resource
      when "trade_with_player", "propose_player_trade"
        return unless payload = incoming.payload
        return unless player_id = client.player_id

        offered = parse_resource_pile(payload["offered"]?)
        requested = parse_resource_pile(payload["requested"]?)
        @lobby_manager.propose_player_trade(lobby_id, player_id, offered, requested) if offered && requested
      when "accept_player_trade"
        return unless player_id = client.player_id

        @lobby_manager.accept_player_trade(lobby_id, player_id)
      when "reject_player_trade"
        return unless player_id = client.player_id

        @lobby_manager.reject_player_trade(lobby_id, player_id)
      when "cancel_player_trade"
        return unless player_id = client.player_id

        @lobby_manager.cancel_player_trade(lobby_id, player_id)
      when "finalize_player_trade"
        return unless payload = incoming.payload
        return unless player_id = client.player_id

        partner_player_id = payload["partner_player_id"]?.try(&.as_s?)
        @lobby_manager.finalize_player_trade(lobby_id, player_id, partner_player_id) if partner_player_id
      when "trade_with_bank", "trade_with_harbor"
        return unless payload = incoming.payload
        return unless player_id = client.player_id

        offered_resource_name = payload["offered_resource"]?.try(&.as_s?)
        requested_resource_name = payload["requested_resource"]?.try(&.as_s?)
        offered_resource = parse_resource(offered_resource_name)
        requested_resource = parse_resource(requested_resource_name)
        @lobby_manager.trade_with_bank(lobby_id, player_id, offered_resource, requested_resource) if offered_resource && requested_resource
      when "roll_dice"
        return unless player_id = client.player_id

        @lobby_manager.roll_dice(lobby_id, player_id)
      when "discard_robber"
        return unless payload = incoming.payload
        return unless player_id = client.player_id

        discarded = parse_resource_pile(payload["discarded"]?)
        @lobby_manager.discard_robber(lobby_id, player_id, discarded) if discarded
      when "move_robber"
        return unless payload = incoming.payload
        return unless player_id = client.player_id

        tile_id = payload["tile_id"]?.try(&.as_s?)
        @lobby_manager.move_robber(lobby_id, player_id, tile_id) if tile_id
      when "robber_steal"
        return unless payload = incoming.payload
        return unless player_id = client.player_id

        victim_player_id = payload["victim_player_id"]?.try(&.as_s?)
        @lobby_manager.robber_steal(lobby_id, player_id, victim_player_id) if victim_player_id
      when "end_turn"
        return unless player_id = client.player_id

        @lobby_manager.end_turn(lobby_id, player_id)
      when "game_action"
        return unless payload = incoming.payload

        route_game_action(client, lobby_id, payload)
      end
    end

    private def route_game_action(client : Client, lobby_id : String, payload : JSON::Any)
      player_id = client.player_id
      return unless player_id

      action = payload["type"]?.try(&.as_s?)
      return unless action

      case action
      when "place_settlement"
        vertex_id = payload["vertex_id"]?.try(&.as_s?)
        free = payload["free"]?.try(&.as_bool?) || false
        @lobby_manager.place_settlement(lobby_id, player_id, vertex_id, free) if vertex_id
      when "place_road"
        edge_id = payload["edge_id"]?.try(&.as_s?)
        free = payload["free"]?.try(&.as_bool?) || false
        @lobby_manager.place_road(lobby_id, player_id, edge_id, free) if edge_id
      when "place_city"
        vertex_id = payload["vertex_id"]?.try(&.as_s?)
        @lobby_manager.place_city(lobby_id, player_id, vertex_id) if vertex_id
      when "buy_development_card"
        @lobby_manager.buy_development_card(lobby_id, player_id)
      when "play_knight"
        tile_id = payload["tile_id"]?.try(&.as_s?)
        @lobby_manager.play_knight(lobby_id, player_id, tile_id) if tile_id
      when "play_road_building"
        first_edge_id = payload["first_edge_id"]?.try(&.as_s?)
        second_edge_id = payload["second_edge_id"]?.try(&.as_s?)
        @lobby_manager.play_road_building(lobby_id, player_id, first_edge_id, second_edge_id) if first_edge_id
      when "play_monopoly"
        resource_name = payload["resource"]?.try(&.as_s?)
        resource = parse_resource(resource_name)
        @lobby_manager.play_monopoly(lobby_id, player_id, resource) if resource
      when "play_year_of_plenty"
        first_resource_name = payload["first_resource"]?.try(&.as_s?)
        second_resource_name = payload["second_resource"]?.try(&.as_s?)
        first_resource = parse_resource(first_resource_name)
        second_resource = parse_resource(second_resource_name)
        @lobby_manager.play_year_of_plenty(lobby_id, player_id, first_resource, second_resource) if first_resource && second_resource
      when "trade_with_player", "propose_player_trade"
        offered = parse_resource_pile(payload["offered"]?)
        requested = parse_resource_pile(payload["requested"]?)
        @lobby_manager.propose_player_trade(lobby_id, player_id, offered, requested) if offered && requested
      when "accept_player_trade"
        @lobby_manager.accept_player_trade(lobby_id, player_id)
      when "reject_player_trade"
        @lobby_manager.reject_player_trade(lobby_id, player_id)
      when "cancel_player_trade"
        @lobby_manager.cancel_player_trade(lobby_id, player_id)
      when "finalize_player_trade"
        partner_player_id = payload["partner_player_id"]?.try(&.as_s?)
        @lobby_manager.finalize_player_trade(lobby_id, player_id, partner_player_id) if partner_player_id
      when "trade_with_bank", "trade_with_harbor"
        offered_resource_name = payload["offered_resource"]?.try(&.as_s?)
        requested_resource_name = payload["requested_resource"]?.try(&.as_s?)
        offered_resource = parse_resource(offered_resource_name)
        requested_resource = parse_resource(requested_resource_name)
        @lobby_manager.trade_with_bank(lobby_id, player_id, offered_resource, requested_resource) if offered_resource && requested_resource
      when "roll_dice"
        @lobby_manager.roll_dice(lobby_id, player_id)
      when "discard_robber"
        discarded = parse_resource_pile(payload["discarded"]?)
        @lobby_manager.discard_robber(lobby_id, player_id, discarded) if discarded
      when "move_robber"
        tile_id = payload["tile_id"]?.try(&.as_s?)
        @lobby_manager.move_robber(lobby_id, player_id, tile_id) if tile_id
      when "robber_steal"
        victim_player_id = payload["victim_player_id"]?.try(&.as_s?)
        @lobby_manager.robber_steal(lobby_id, player_id, victim_player_id) if victim_player_id
      when "end_turn"
        @lobby_manager.end_turn(lobby_id, player_id)
      else
        puts "Unknown game action: #{action}"
      end
    end

    private def parse_resource(name : String?) : Resource?
      return nil unless name

      case name.downcase
      when "wood"   then Resource::Wood
      when "brick"  then Resource::Brick
      when "sheep"  then Resource::Sheep
      when "wheat"  then Resource::Wheat
      when "ore"    then Resource::Ore
      when "desert" then Resource::Desert
      else
        nil
      end
    end

    private def parse_resource_pile(value : JSON::Any?) : ResourcePile?
      return nil unless hash = value.try(&.as_h?)

      wood = resource_pile_count(hash, "wood")
      brick = resource_pile_count(hash, "brick")
      sheep = resource_pile_count(hash, "sheep")
      wheat = resource_pile_count(hash, "wheat")
      ore = resource_pile_count(hash, "ore")

      return nil if wood < 0 || brick < 0 || sheep < 0 || wheat < 0 || ore < 0

      ResourcePile.new(wood, brick, sheep, wheat, ore)
    end

    private def resource_pile_count(hash : Hash(String, JSON::Any), key : String) : Int32
      value = hash[key]?
      return 0 unless value

      value.as_i.to_i32
    rescue
      0
    end
  end
end
