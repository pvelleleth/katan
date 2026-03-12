require "json"

module Katan::Engine::Domain
  class Player
    include JSON::Serializable

    getter id : String
    getter name : String
    property ready : Bool = false

    def initialize(@id : String, @name : String)
    end
  end
end
