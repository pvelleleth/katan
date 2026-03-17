require "json"

module Settler::Engine::Infrastructure::Persistence
  record PersistedGameSnapshot,
    snapshot_json : String,
    snapshot_version : Int32,
    settings_json : String?

  abstract class GameEventStore
    abstract def update_game_settings(lobby_code : String, settings_json : String) : Nil

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
    def update_game_settings(lobby_code : String, settings_json : String) : Nil
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
