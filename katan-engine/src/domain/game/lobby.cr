require "json"
require "../player/player"

module Katan::Engine::Domain
  class Lobby
    include JSON::Serializable
    
    getter id : String
    getter players : Array(Player) = [] of Player
    
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
    
    def remove_player(player_id : String)
      @players.reject! { |p| p.id == player_id }
    end
  end
end
