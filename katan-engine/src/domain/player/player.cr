require "json"
require "time"

module Katan::Engine::Domain
  class Player
    include JSON::Serializable

    getter id : String
    property name : String
    property ready : Bool = false
    property connected : Bool = true
    property disconnected_at : Time?
    @[JSON::Field(ignore: true)]
    property disconnect_version : Int32 = 0

    def initialize(@id : String, @name : String)
    end

    def mark_connected
      @connected = true
      @disconnected_at = nil
      @disconnect_version += 1
    end

    def mark_disconnected
      @connected = false
      @disconnected_at = Time.utc
      @disconnect_version += 1
    end
  end
end
