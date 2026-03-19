require "./spec_helper"

describe BoardSetupGenerator do
  it "never places 6 and 8 tokens on adjacent tiles" do
    topology = BoardTopology.standard

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
