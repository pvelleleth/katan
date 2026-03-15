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
        when "start_game", "place_settlement", "place_road", "place_city", "roll_dice", "move_robber", "end_turn", "game_action"
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
      when "roll_dice"
        return unless payload = incoming.payload
        return unless player_id = client.player_id

        total = payload["total"]?.try(&.as_i?)
        @lobby_manager.roll_dice(lobby_id, player_id, total.to_i32) if total
      when "move_robber"
        return unless payload = incoming.payload
        return unless player_id = client.player_id

        tile_id = payload["tile_id"]?.try(&.as_s?)
        @lobby_manager.move_robber(lobby_id, player_id, tile_id) if tile_id
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
      when "roll_dice"
        total = payload["total"]?.try(&.as_i?)
        @lobby_manager.roll_dice(lobby_id, player_id, total.to_i32) if total
      when "move_robber"
        tile_id = payload["tile_id"]?.try(&.as_s?)
        @lobby_manager.move_robber(lobby_id, player_id, tile_id) if tile_id
      when "end_turn"
        @lobby_manager.end_turn(lobby_id, player_id)
      else
        puts "Unknown game action: #{action}"
      end
    end
  end
end
