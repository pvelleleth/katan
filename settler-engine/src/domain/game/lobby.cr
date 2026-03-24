require "json"
require "time"
require "../player/player"

module Settler::Engine::Domain
  class Lobby
    include JSON::Serializable

    getter id : String
    getter players : Array(Player) = [] of Player
    property host_id : String? = nil
    property is_public : Bool = false
    property settings : Hash(String, JSON::Any) = Hash(String, JSON::Any).new
    property created_at : Time = Time.utc

    def initialize(@id : String)
    end

    def add_player(player : Player)
      # Update or add
      if existing_index = @players.index { |p| p.id == player.id }
        @players[existing_index] = player
      else
        @players << player
      end
    end

    def find_player(player_id : String) : Player?
      @players.find { |p| p.id == player_id }
    end

    def remove_player(player_id : String)
      @players.reject! { |p| p.id == player_id }
    end
  end
end
