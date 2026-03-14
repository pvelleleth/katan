require "json"

module Katan::Engine::Infrastructure::Persistence
  abstract class GameEventStore
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
