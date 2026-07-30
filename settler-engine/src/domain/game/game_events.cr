require "./topology"

abstract class GameEvent
  getter version : Int32

  def initialize(@version : Int32)
  end
end

class GameStarted < GameEvent
end

class SettlementPlaced < GameEvent
  getter player_id : PlayerId
  getter vertex_id : VertexId
  getter free : Bool

  def initialize(@version : Int32, @player_id : PlayerId, @vertex_id : VertexId, @free : Bool = false)
    super(@version)
  end
end

class RoadPlaced < GameEvent
  getter player_id : PlayerId
  getter edge_id : EdgeId
  getter free : Bool

  def initialize(@version : Int32, @player_id : PlayerId, @edge_id : EdgeId, @free : Bool = false)
    super(@version)
  end
end

class CityPlaced < GameEvent
  getter player_id : PlayerId
  getter vertex_id : VertexId

  def initialize(@version : Int32, @player_id : PlayerId, @vertex_id : VertexId)
    super(@version)
  end
end

class DevelopmentCardPurchased < GameEvent
  getter player_id : PlayerId
  getter card : DevCard

  def initialize(@version : Int32, @player_id : PlayerId, @card : DevCard)
    super(@version)
  end
end

class KnightPlayed < GameEvent
  getter player_id : PlayerId
  getter tile_id : TileId

  def initialize(@version : Int32, @player_id : PlayerId, @tile_id : TileId)
    super(@version)
  end
end

class RoadBuildingPlayed < GameEvent
  getter player_id : PlayerId
  getter first_edge_id : EdgeId
  getter second_edge_id : EdgeId?

  def initialize(@version : Int32, @player_id : PlayerId, @first_edge_id : EdgeId, @second_edge_id : EdgeId? = nil)
    super(@version)
  end
end

class MonopolyPlayed < GameEvent
  getter player_id : PlayerId
  getter resource : Resource

  def initialize(@version : Int32, @player_id : PlayerId, @resource : Resource)
    super(@version)
  end
end

class YearOfPlentyPlayed < GameEvent
  getter player_id : PlayerId
  getter first_resource : Resource
  getter second_resource : Resource

  def initialize(@version : Int32, @player_id : PlayerId, @first_resource : Resource, @second_resource : Resource)
    super(@version)
  end
end

class PlayerTradeProposed < GameEvent
  getter trade_id : Int32
  getter player_id : PlayerId
  getter offered : ResourcePile
  getter requested : ResourcePile

  def initialize(@version : Int32, @trade_id : Int32, @player_id : PlayerId, @offered : ResourcePile, @requested : ResourcePile)
    super(@version)
  end
end

class PlayerTradeAccepted < GameEvent
  getter trade_id : Int32
  getter player_id : PlayerId
  getter partner_player_id : PlayerId

  def initialize(@version : Int32, @trade_id : Int32, @player_id : PlayerId, @partner_player_id : PlayerId)
    super(@version)
  end
end

class PlayerTradeRejected < GameEvent
  getter trade_id : Int32
  getter player_id : PlayerId
  getter partner_player_id : PlayerId

  def initialize(@version : Int32, @trade_id : Int32, @player_id : PlayerId, @partner_player_id : PlayerId)
    super(@version)
  end
end

class PlayerTradeCancelled < GameEvent
  getter trade_id : Int32
  getter player_id : PlayerId

  def initialize(@version : Int32, @trade_id : Int32, @player_id : PlayerId)
    super(@version)
  end
end

class PlayerTradeCompleted < GameEvent
  getter trade_id : Int32
  getter player_id : PlayerId
  getter partner_player_id : PlayerId
  getter offered : ResourcePile
  getter requested : ResourcePile

  def initialize(@version : Int32, @trade_id : Int32, @player_id : PlayerId, @partner_player_id : PlayerId, @offered : ResourcePile, @requested : ResourcePile)
    super(@version)
  end
end

class BankTradeCompleted < GameEvent
  getter player_id : PlayerId
  getter offered_resource : Resource
  getter requested_resource : Resource

  def initialize(@version : Int32, @player_id : PlayerId, @offered_resource : Resource, @requested_resource : Resource)
    super(@version)
  end
end

class DiceRolled < GameEvent
  getter die_one : Int32
  getter die_two : Int32
  getter total : Int32
  getter resources_granted : Hash(String, Hash(String, Int32))

  def initialize(@version : Int32, @die_one : Int32, @die_two : Int32, @resources_granted : Hash(String, Hash(String, Int32)) = Hash(String, Hash(String, Int32)).new)
    super(@version)
    @total = @die_one + @die_two
  end
end

class RobberDiscarded < GameEvent
  getter player_id : PlayerId
  getter discarded : ResourcePile

  def initialize(@version : Int32, @player_id : PlayerId, @discarded : ResourcePile)
    super(@version)
  end
end

class RobberMoved < GameEvent
  getter player_id : PlayerId
  getter tile_id : TileId

  def initialize(@version : Int32, @player_id : PlayerId, @tile_id : TileId)
    super(@version)
  end
end

class RobberStolen < GameEvent
  getter player_id : PlayerId
  getter victim_player_id : PlayerId
  getter resource : Resource

  def initialize(@version : Int32, @player_id : PlayerId, @victim_player_id : PlayerId, @resource : Resource)
    super(@version)
  end
end

class TurnEnded < GameEvent
  getter player_id : PlayerId

  def initialize(@version : Int32, @player_id : PlayerId)
    super(@version)
  end
end
