require "../../domain/game/lobby"
require "../../transport/websocket/client"
require "../../infrastructure/persistence/game_event_store"
require "json"
require "time"

module Katan::Engine::Application
  class LobbyManager
    DISCONNECT_GRACE_PERIOD = 60.seconds

    property lobbies = Hash(String, Domain::Lobby).new
    property clients = Hash(String, Array(Transport::WebSocket::Client)).new

    def initialize(@game_event_store : Infrastructure::Persistence::GameEventStore = Infrastructure::Persistence::NullGameEventStore.new)
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
      player.ready = false
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

      @lobbies.delete(lobby_id)
      @clients.delete(lobby_id)
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
  end
end
