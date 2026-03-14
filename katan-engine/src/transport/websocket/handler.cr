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
  end
end
