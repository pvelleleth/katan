require "json"
require "time"

module Settler::Engine::Infrastructure::Persistence
  record PersistedLobbyParticipant,
    player_id : String,
    player_name : String,
    ready : Bool

  record PersistedLobby,
    short_code : String,
    host_player_id : String,
    status : String,
    is_public : Bool,
    settings_json : String?,
    created_at : Time,
    participants : Array(PersistedLobbyParticipant)

  record PersistedGameSnapshot,
    snapshot_json : String,
    snapshot_version : Int32,
    settings_json : String?

  abstract class GameEventStore
    abstract def create_lobby(host_player_id : String, is_public : Bool, settings_json : String) : PersistedLobby
    abstract def load_waiting_lobby(lobby_code : String) : PersistedLobby?
    abstract def load_public_waiting_lobbies : Array(PersistedLobby)
    abstract def add_participant(lobby_code : String, player_id : String, ready : Bool = false) : Nil
    abstract def remove_participant(lobby_code : String, player_id : String) : Nil
    abstract def update_participant_ready(lobby_code : String, player_id : String, ready : Bool) : Nil
    abstract def update_lobby_visibility(lobby_code : String, is_public : Bool) : Nil
    abstract def update_game_settings(lobby_code : String, settings_json : String) : Nil
    abstract def mark_game_started(lobby_code : String) : Nil

    abstract def append(
      lobby_code : String,
      event_type : String,
      actor_player_id : String? = nil,
      turn_number : Int32? = nil,
      phase : String? = nil,
      payload_json : String = "{}",
      message : String? = nil,
    ) : Nil

    abstract def save_game_snapshot(lobby_code : String, snapshot_json : String, snapshot_version : Int32) : Nil

    abstract def load_game_snapshot(lobby_code : String) : PersistedGameSnapshot?
  end

  class NullGameEventStore < GameEventStore
    def create_lobby(host_player_id : String, is_public : Bool, settings_json : String) : PersistedLobby
      PersistedLobby.new(
        short_code: Random::Secure.urlsafe_base64(4)[0, 6].upcase,
        host_player_id: host_player_id,
        status: "waiting",
        is_public: is_public,
        settings_json: settings_json,
        created_at: Time.utc,
        participants: [PersistedLobbyParticipant.new(player_id: host_player_id, player_name: "Player", ready: false)]
      )
    end

    def load_waiting_lobby(lobby_code : String) : PersistedLobby?
      nil
    end

    def load_public_waiting_lobbies : Array(PersistedLobby)
      [] of PersistedLobby
    end

    def add_participant(lobby_code : String, player_id : String, ready : Bool = false) : Nil
    end

    def remove_participant(lobby_code : String, player_id : String) : Nil
    end

    def update_participant_ready(lobby_code : String, player_id : String, ready : Bool) : Nil
    end

    def update_lobby_visibility(lobby_code : String, is_public : Bool) : Nil
    end

    def update_game_settings(lobby_code : String, settings_json : String) : Nil
    end

    def mark_game_started(lobby_code : String) : Nil
    end

    def append(
      lobby_code : String,
      event_type : String,
      actor_player_id : String? = nil,
      turn_number : Int32? = nil,
      phase : String? = nil,
      payload_json : String = "{}",
      message : String? = nil,
    ) : Nil
    end

    def save_game_snapshot(lobby_code : String, snapshot_json : String, snapshot_version : Int32) : Nil
    end

    def load_game_snapshot(lobby_code : String) : PersistedGameSnapshot?
      nil
    end
  end
end
