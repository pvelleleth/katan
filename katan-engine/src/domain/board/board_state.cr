require "../game/topology"
require "./board_setup"

struct TileState
  property resource : Resource
  property token : Int32?

  def initialize(@resource : Resource, @token : Int32? = nil)
  end
end

struct Building
  getter player_id : PlayerId
  getter kind : BuildingKind

  def initialize(@player_id : PlayerId, @kind : BuildingKind)
  end
end

struct Road
  getter player_id : PlayerId

  def initialize(@player_id : PlayerId)
  end
end

class BoardState
  getter tile_states : Hash(TileId, TileState)
  getter buildings : Hash(VertexId, Building)
  getter roads : Hash(EdgeId, Road)
  property harbors : Array(HarborAssignment)
  property robber_tile_id : TileId

  def initialize(
    @tile_states : Hash(TileId, TileState),
    @robber_tile_id : TileId,
    @harbors : Array(HarborAssignment) = [] of HarborAssignment,
    @buildings : Hash(VertexId, Building) = {} of VertexId => Building,
    @roads : Hash(EdgeId, Road) = {} of EdgeId => Road
  )
  end

  def building_at?(vertex_id : VertexId) : Building?
    @buildings[vertex_id]?
  end

  def road_at?(edge_id : EdgeId) : Road?
    @roads[edge_id]?
  end

  def occupied_vertex?(vertex_id : VertexId) : Bool
    @buildings.has_key?(vertex_id)
  end

  def occupied_edge?(edge_id : EdgeId) : Bool
    @roads.has_key?(edge_id)
  end
end
