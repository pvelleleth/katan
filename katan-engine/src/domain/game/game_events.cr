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

class DiceRolled < GameEvent
  getter die_one : Int32
  getter die_two : Int32
  getter total : Int32

  def initialize(@version : Int32, @die_one : Int32, @die_two : Int32)
    super(@version)
    @total = @die_one + @die_two
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
