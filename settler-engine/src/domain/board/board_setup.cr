require "../game/topology"

enum HarborKind
  ThreeToOne
  WoodTwoToOne
  BrickTwoToOne
  SheepTwoToOne
  WheatTwoToOne
  OreTwoToOne
end

struct HarborAssignment
  getter id : HarborSlotId
  getter vertex_ids : Tuple(VertexId, VertexId)
  getter kind : HarborKind

  def initialize(@id : HarborSlotId, @vertex_ids : Tuple(VertexId, VertexId), @kind : HarborKind)
  end
end

struct TileSetup
  getter tile_id : TileId
  getter resource : Resource
  getter token : Int32?

  def initialize(@tile_id : TileId, @resource : Resource, @token : Int32?)
  end
end

class GeneratedBoardSetup
  getter tile_setups : Array(TileSetup)
  getter robber_tile_id : TileId
  getter harbors : Array(HarborAssignment)

  def initialize(
    @tile_setups : Array(TileSetup),
    @robber_tile_id : TileId,
    @harbors : Array(HarborAssignment),
  )
  end
end

class BoardSetupGenerator
  RESOURCES = [
    Resource::Wood, Resource::Wood, Resource::Wood, Resource::Wood,
    Resource::Brick, Resource::Brick, Resource::Brick,
    Resource::Sheep, Resource::Sheep, Resource::Sheep, Resource::Sheep,
    Resource::Wheat, Resource::Wheat, Resource::Wheat, Resource::Wheat,
    Resource::Ore, Resource::Ore, Resource::Ore,
    Resource::Desert,
  ]

  TOKENS = [2, 3, 3, 4, 4, 5, 5, 6, 6, 8, 8, 9, 9, 10, 10, 11, 11, 12]

  def self.generate(topology : BoardTopology, rng : Random) : GeneratedBoardSetup
    tile_ids = topology.tiles.keys.to_a
    shuffled_resources = RESOURCES.shuffle(random: rng)

    desert_index = shuffled_resources.index!(Resource::Desert)
    non_desert_tile_ids = tile_ids.each_with_index.each_with_object([] of TileId) do |(tile_id, index), memo|
      memo << tile_id unless shuffled_resources[index].desert?
    end
    non_desert_tokens = generate_non_adjacent_high_probability_tokens(topology, non_desert_tile_ids, rng)

    tile_setups = [] of TileSetup
    token_idx = 0
    robber_tile_id = tile_ids[desert_index]

    tile_ids.each_with_index do |tile_id, i|
      resource = shuffled_resources[i]

      if resource.desert?
        tile_setups << TileSetup.new(tile_id, resource, nil)
      else
        tile_setups << TileSetup.new(tile_id, resource, non_desert_tokens[token_idx])
        token_idx += 1
      end
    end

    harbors = generate_harbors(topology, rng)

    GeneratedBoardSetup.new(tile_setups, robber_tile_id, harbors)
  end

  private def self.generate_non_adjacent_high_probability_tokens(
    topology : BoardTopology,
    tile_ids : Array(TileId),
    rng : Random,
  ) : Array(Int32)
    loop do
      tokens = TOKENS.shuffle(random: rng)
      token_by_tile_id = tile_ids.zip(tokens).to_h

      return tokens if high_probability_tokens_separated?(topology, token_by_tile_id)
    end
  end

  private def self.high_probability_tokens_separated?(
    topology : BoardTopology,
    token_by_tile_id : Hash(TileId, Int32),
  ) : Bool
    token_by_tile_id.each do |tile_id, token|
      next unless token == 6 || token == 8

      return false if topology.neighboring_tiles(tile_id).any? do |neighbor_tile_id|
        neighbor_token = token_by_tile_id[neighbor_tile_id]?
        neighbor_token == 6 || neighbor_token == 8
      end
    end

    true
  end

  def self.generate_harbors(topology : BoardTopology, rng : Random) : Array(HarborAssignment)
    harbor_kinds = [
      HarborKind::ThreeToOne,
      HarborKind::ThreeToOne,
      HarborKind::ThreeToOne,
      HarborKind::ThreeToOne,
      HarborKind::WoodTwoToOne,
      HarborKind::BrickTwoToOne,
      HarborKind::SheepTwoToOne,
      HarborKind::WheatTwoToOne,
      HarborKind::OreTwoToOne,
    ].shuffle(random: rng)

    harbor_slots = topology.harbor_slots.values.sort_by(&.id.value)

    harbor_slots.zip(harbor_kinds).map do |slot, kind|
      HarborAssignment.new(slot.id, slot.vertex_ids, kind)
    end
  end
end
