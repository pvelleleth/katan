require "json"

module Katan::Engine::Infrastructure::Persistence
  abstract class GameEventStore
    abstract def update_game_settings(lobby_code : String, settings_json : String) : Nil

    abstract def append(
      lobby_code : String,
      event_type : String,
      actor_player_id : String? = nil,
      turn_number : Int32? = nil,
      phase : String? = nil,
      payload_json : String = "{}",
      message : String? = nil
    ) : Nil
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
      message : String? = nil
    ) : Nil
    end
  end
end
