require "./types"

alias GraphPoint = Tuple(Int32, Int32)
alias GraphEdgeKey = Tuple(GraphPoint, GraphPoint)

struct TileId
  getter value : String

  def initialize(@value : String); end

  def_equals_and_hash @value

  def to_s(io : IO) : Nil
    io << @value
  end
end

struct VertexId
  getter value : String

  def initialize(@value : String); end

  def_equals_and_hash @value

  def to_s(io : IO) : Nil
    io << @value
  end
end

struct EdgeId
  getter value : String

  def initialize(@value : String); end

  def_equals_and_hash @value

  def to_s(io : IO) : Nil
    io << @value
  end
end

struct TileTopology
  getter id : TileId
  getter vertex_ids : Array(VertexId)
  getter edge_ids : Array(EdgeId)
  getter x : Int32
  getter y : Int32

  def initialize(@id : TileId, @vertex_ids : Array(VertexId), @edge_ids : Array(EdgeId), @x : Int32, @y : Int32)
  end
end

struct VertexTopology
  getter id : VertexId
  getter tile_ids : Array(TileId)
  getter edge_ids : Array(EdgeId)
  getter x : Int32
  getter y : Int32

  def initialize(@id : VertexId, @tile_ids : Array(TileId), @edge_ids : Array(EdgeId), @x : Int32, @y : Int32)
  end
end

struct EdgeTopology
  getter id : EdgeId
  getter vertex_ids : Tuple(VertexId, VertexId)
  getter tile_ids : Array(TileId)

  def initialize(@id : EdgeId, @vertex_ids : Tuple(VertexId, VertexId), @tile_ids : Array(TileId))
  end
end

struct HarborSlotId
  getter value : String

  def initialize(@value : String); end

  def_equals_and_hash @value

  def to_s(io : IO) : Nil
    io << @value
  end
end

struct HarborSlotTopology
  getter id : HarborSlotId
  getter vertex_ids : Tuple(VertexId, VertexId)

  def initialize(@id : HarborSlotId, @vertex_ids : Tuple(VertexId, VertexId))
  end
end

class BoardTopology
  CORNER_OFFSETS = [
    {0, 2},
    {1, 1},
    {1, -1},
    {0, -2},
    {-1, -1},
    {-1, 1},
  ]

  HARBOR_SLOT_EDGE_POINTS = [
    { {-5, -1}, {-5, 1} },
    { {-4, 4}, {-3, 5} },
    { {-1, 7}, {0, 8} },
    { {2, 8}, {3, 7} },
    { {4, 2}, {4, 4} },
    { {4, -4}, {4, -2} },
    { {2, -8}, {3, -7} },
    { {-1, -7}, {0, -8} },
    { {-4, -4}, {-3, -5} },
  ]

  getter tiles : Hash(TileId, TileTopology)
  getter vertices : Hash(VertexId, VertexTopology)
  getter edges : Hash(EdgeId, EdgeTopology)
  getter harbor_slots : Hash(HarborSlotId, HarborSlotTopology)

  def self.standard : self
    tile_points = standard_tile_points
    tile_ids_by_point = Hash(GraphPoint, TileId).new
    tile_vertex_points = Hash(TileId, Array(GraphPoint)).new
    tile_edge_keys = Hash(TileId, Array(GraphEdgeKey)).new
    vertex_tile_ids = Hash(GraphPoint, Array(TileId)).new { |hash, key| hash[key] = [] of TileId }
    vertex_edge_keys = Hash(GraphPoint, Array(GraphEdgeKey)).new { |hash, key| hash[key] = [] of GraphEdgeKey }
    edge_tile_ids = Hash(GraphEdgeKey, Array(TileId)).new { |hash, key| hash[key] = [] of TileId }

    tile_points.each_with_index do |point, index|
      tile_id = TileId.new("t#{(index + 1).to_s.rjust(2, '0')}")
      tile_ids_by_point[point] = tile_id

      vertex_points = corner_points(point)
      edge_keys = [] of GraphEdgeKey

      vertex_points.each do |vertex_point|
        vertex_tile_ids[vertex_point] << tile_id
      end

      vertex_points.size.times do |offset|
        edge_key = canonical_edge(vertex_points[offset], vertex_points[(offset + 1) % vertex_points.size])
        edge_keys << edge_key
        edge_tile_ids[edge_key] << tile_id
        vertex_edge_keys[vertex_points[offset]] << edge_key
        vertex_edge_keys[vertex_points[(offset + 1) % vertex_points.size]] << edge_key
      end

      tile_vertex_points[tile_id] = vertex_points
      tile_edge_keys[tile_id] = edge_keys
    end

    sorted_vertex_points = vertex_tile_ids.keys.sort_by { |point| {point[1], point[0]} }
    vertex_ids_by_point = Hash(GraphPoint, VertexId).new
    sorted_vertex_points.each_with_index do |point, index|
      vertex_ids_by_point[point] = VertexId.new("v#{(index + 1).to_s.rjust(2, '0')}")
    end

    sorted_edge_keys = edge_tile_ids.keys.sort_by do |edge_key|
      a, b = edge_key
      {a[1] + b[1], a[0] + b[0], a[1], a[0], b[1], b[0]}
    end
    edge_ids_by_key = Hash(GraphEdgeKey, EdgeId).new
    sorted_edge_keys.each_with_index do |edge_key, index|
      edge_ids_by_key[edge_key] = EdgeId.new("e#{(index + 1).to_s.rjust(2, '0')}")
    end

    tiles = tile_points.each_with_object({} of TileId => TileTopology) do |point, hash|
      tile_id = tile_ids_by_point[point]
      hash[tile_id] = TileTopology.new(
        tile_id,
        tile_vertex_points[tile_id].map { |vertex_point| vertex_ids_by_point[vertex_point] },
        tile_edge_keys[tile_id].map { |edge_key| edge_ids_by_key[edge_key] },
        point[0],
        point[1]
      )
    end

    vertices = sorted_vertex_points.each_with_object({} of VertexId => VertexTopology) do |point, hash|
      vertex_id = vertex_ids_by_point[point]
      edge_keys = vertex_edge_keys[point].uniq.sort_by do |edge_key|
        edge_id = edge_ids_by_key[edge_key]
        edge_id.value
      end
      hash[vertex_id] = VertexTopology.new(
        vertex_id,
        vertex_tile_ids[point].sort_by(&.value),
        edge_keys.map { |edge_key| edge_ids_by_key[edge_key] },
        point[0],
        point[1]
      )
    end

    edges = sorted_edge_keys.each_with_object({} of EdgeId => EdgeTopology) do |edge_key, hash|
      edge_id = edge_ids_by_key[edge_key]
      a, b = edge_key
      hash[edge_id] = EdgeTopology.new(
        edge_id,
        {vertex_ids_by_point[a], vertex_ids_by_point[b]},
        edge_tile_ids[edge_key].uniq.sort_by(&.value)
      )
    end

    harbor_slots = build_harbor_slots(edge_tile_ids, vertex_ids_by_point)

    new(
      tiles: tiles,
      vertices: vertices,
      edges: edges,
      harbor_slots: harbor_slots
    )
  end

  def initialize(
    @tiles : Hash(TileId, TileTopology),
    @vertices : Hash(VertexId, VertexTopology),
    @edges : Hash(EdgeId, EdgeTopology),
    @harbor_slots : Hash(HarborSlotId, HarborSlotTopology) = {} of HarborSlotId => HarborSlotTopology,
  )
  end

  def neighboring_vertices(vertex_id : VertexId) : Array(VertexId)
    vertex = @vertices[vertex_id]
    vertex.edge_ids.map do |edge_id|
      edge = @edges[edge_id]
      a, b = edge.vertex_ids
      a == vertex_id ? b : a
    end
  end

  private def self.standard_tile_points : Array(GraphPoint)
    points = [] of GraphPoint

    (-2..2).each do |r|
      q_min = Math.max(-2, -r - 2)
      q_max = Math.min(2, -r + 2)

      (q_min..q_max).each do |q|
        points << axial_to_point(q, r)
      end
    end

    points
  end

  private def self.axial_to_point(q : Int32, r : Int32) : GraphPoint
    {2 * q + r, 3 * r}
  end

  private def self.corner_points(center : GraphPoint) : Array(GraphPoint)
    cx, cy = center
    CORNER_OFFSETS.map do |dx, dy|
      {cx + dx, cy + dy}
    end
  end

  private def self.canonical_edge(a : GraphPoint, b : GraphPoint) : GraphEdgeKey
    a <= b ? {a, b} : {b, a}
  end

  private def self.build_harbor_slots(
    edge_tile_ids : Hash(GraphEdgeKey, Array(TileId)),
    vertex_ids_by_point : Hash(GraphPoint, VertexId),
  ) : Hash(HarborSlotId, HarborSlotTopology)
    HARBOR_SLOT_EDGE_POINTS.each_with_index.each_with_object({} of HarborSlotId => HarborSlotTopology) do |(edge_points, harbor_index), hash|
      edge_key = canonical_edge(edge_points[0], edge_points[1])
      tile_ids = edge_tile_ids[edge_key]? || raise "unknown harbor edge #{edge_key}"
      raise "harbor edge #{edge_key} is not coastal" unless tile_ids.size == 1

      a, b = edge_key
      harbor_id = HarborSlotId.new("h#{(harbor_index + 1).to_s.rjust(2, '0')}")
      hash[harbor_id] = HarborSlotTopology.new(harbor_id, {vertex_ids_by_point[a], vertex_ids_by_point[b]})
    end
  end
end
