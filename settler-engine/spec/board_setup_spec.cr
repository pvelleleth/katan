require "./spec_helper"

describe BoardSetupGenerator do
  it "never places 6 and 8 tokens on adjacent tiles" do
    [BoardTopology.standard, BoardTopology.five_six_extension].each do |topology|
      100.times do |seed|
        setup = BoardSetupGenerator.generate(topology, Random.new(seed))
        token_by_tile_id = setup.tile_setups.each_with_object({} of TileId => Int32) do |tile_setup, memo|
          memo[tile_setup.tile_id] = tile_setup.token.not_nil! if tile_setup.token
        end

        token_by_tile_id.each do |tile_id, token|
          next unless token == 6 || token == 8

          topology.neighboring_tiles(tile_id).each do |neighbor_tile_id|
            neighbor_token = token_by_tile_id[neighbor_tile_id]?
            next unless neighbor_token

            (neighbor_token == 6 || neighbor_token == 8).should be_false
          end
        end
      end
    end
  end

  it "uses the official extension tile, token, and harbor inventories" do
    topology = BoardTopology.five_six_extension
    setup = BoardSetupGenerator.generate(topology, Random.new(42))

    setup.tile_setups.size.should eq(30)
    setup.tile_setups.count(&.resource.desert?).should eq(2)
    setup.tile_setups.count(&.resource.wood?).should eq(6)
    setup.tile_setups.count(&.resource.brick?).should eq(5)
    setup.tile_setups.count(&.resource.sheep?).should eq(6)
    setup.tile_setups.count(&.resource.wheat?).should eq(6)
    setup.tile_setups.count(&.resource.ore?).should eq(5)
    setup.tile_setups.compact_map(&.token).size.should eq(28)
    setup.harbors.size.should eq(11)
    setup.harbors.count(&.kind.three_to_one?).should eq(5)
    setup.harbors.count(&.kind.sheep_two_to_one?).should eq(2)
  end
end
