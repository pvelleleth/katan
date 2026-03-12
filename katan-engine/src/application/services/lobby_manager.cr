require "../../domain/game/lobby"
require "../../transport/websocket/client"
require "json"

module Katan::Engine::Application
  class LobbyManager
    property lobbies = Hash(String, Domain::Lobby).new
    property clients = Hash(String, Array(Transport::WebSocket::Client)).new

    def get_or_create_lobby(id : String) : Domain::Lobby
      @lobbies[id] ||= Domain::Lobby.new(id)
    end

    def add_client(lobby_id : String, client : Transport::WebSocket::Client)
      clients_list = (@clients[lobby_id] ||= [] of Transport::WebSocket::Client)
      clients_list << client unless clients_list.includes?(client)
    end

    def remove_client(client : Transport::WebSocket::Client)
      if lid = client.lobby_id
        if list = @clients[lid]?
          list.delete(client)
        end
        if pid = client.player_id
          if lobby = @lobbies[lid]?
            lobby.remove_player(pid)

            # Clean up empty lobbies
            if lobby.players.empty?
              @lobbies.delete(lid)
              @clients.delete(lid)
            end
          end
        end
        # Broadcast removal to everyone else in the lobby if the lobby still exists
        broadcast_lobby_state(lid) if @lobbies[lid]?
      end
    end

    def kick_player(lobby_id : String, target_player_id : String)
      if list = @clients[lobby_id]?
        target_client = list.find { |c| c.player_id == target_player_id }
        if target_client
          target_client.send_json({type: "kicked", message: "You were removed from the lobby by the host."}.to_json)
          remove_client(target_client)
          target_client.socket.close
        end
      end
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
  end
end
