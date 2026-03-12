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
            @lobby_manager.remove_client(client)
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
            
            if player_id && name
              client.player_id = player_id
              
              lobby = @lobby_manager.get_or_create_lobby(lid)
              player = Domain::Player.new(player_id, name)
              lobby.add_player(player)
              
              @lobby_manager.add_client(lid, client)
              @lobby_manager.broadcast_lobby_state(lid)
            end
          end
        when "leave"
          @lobby_manager.remove_client(client)
          # We might want to close the socket from our end but that will also trigger `on_close`
          client.socket.close
        when "ready"
          # Example of an action to toggle readiness
          if payload = incoming.payload
            player_id = payload["player_id"]?.try(&.as_s?)
            ready_state = payload["ready"]?.try(&.as_bool?)
            
            if player_id && !ready_state.nil?
              lobby = @lobby_manager.get_or_create_lobby(lid)
              
              # Find and update player
              if player = lobby.players.find { |p| p.id == player_id }
                player.ready = ready_state
                @lobby_manager.broadcast_lobby_state(lid)
              end
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
