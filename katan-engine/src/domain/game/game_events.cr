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

class DiceRolled < GameEvent
  getter total : Int32

  def initialize(@version : Int32, @total : Int32)
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

class TurnEnded < GameEvent
  getter player_id : PlayerId

  def initialize(@version : Int32, @player_id : PlayerId)
    super(@version)
  end
end
