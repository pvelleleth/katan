require "./spec_helper"

describe BoardTopology do
  it "builds the standard catan board graph" do
    topology = BoardTopology.standard

    topology.tiles.size.should eq(19)
    topology.vertices.size.should eq(54)
    topology.edges.size.should eq(72)
    topology.harbor_slots.size.should eq(9)

    topology.tiles.each_value do |tile|
      tile.vertex_ids.size.should eq(6)
      tile.edge_ids.size.should eq(6)
    end
    topology.tiles.values.map { |tile| {tile.x, tile.y} }.uniq.size.should eq(19)

    topology.vertices.each_value do |vertex|
      vertex.tile_ids.size.should be >= 1
      vertex.tile_ids.size.should be <= 3
      vertex.edge_ids.size.should be >= 2
      vertex.edge_ids.size.should be <= 3
      topology.neighboring_vertices(vertex.id).size.should eq(vertex.edge_ids.size)
    end
    topology.vertices.values.map { |vertex| {vertex.x, vertex.y} }.uniq.size.should eq(54)

    topology.edges.each_value do |edge|
      edge.tile_ids.size.should be >= 1
      edge.tile_ids.size.should be <= 2
      edge.vertex_ids[0].should_not eq(edge.vertex_ids[1])
    end

    edge_vertex_pairs = topology.edges.values.map do |edge|
      a, b = edge.vertex_ids
      [a.value, b.value].sort
    end

    topology.harbor_slots.each_value do |harbor_slot|
      a, b = harbor_slot.vertex_ids
      edge_vertex_pairs.includes?([a.value, b.value].sort).should be_true
    end
  end

  it "exposes neighboring tiles through shared edges" do
    topology = BoardTopology.standard

    center_tile = topology.tiles.keys.find! { |tile_id| topology.tiles[tile_id].x == 0 && topology.tiles[tile_id].y == 0 }
    corner_tile = topology.tiles.keys.find! { |tile_id| topology.tiles[tile_id].x == -2 && topology.tiles[tile_id].y == -6 }

    topology.neighboring_tiles(center_tile).size.should eq(6)
    topology.neighboring_tiles(corner_tile).size.should eq(3)

    topology.neighboring_tiles(center_tile).each do |neighbor_tile_id|
      topology.neighboring_tiles(neighbor_tile_id).includes?(center_tile).should be_true
    end
  end

  it "builds the 5-6 player extension board graph" do
    topology = BoardTopology.five_six_extension

    topology.tiles.size.should eq(30)
    topology.vertices.size.should eq(80)
    topology.edges.size.should eq(109)
    topology.harbor_slots.size.should eq(11)

    topology.harbor_slots.each_value do |harbor_slot|
      edge = topology.edges.values.find do |candidate|
        candidate.vertex_ids == harbor_slot.vertex_ids || candidate.vertex_ids.reverse == harbor_slot.vertex_ids
      end
      edge.should_not be_nil
      edge.not_nil!.tile_ids.size.should eq(1)
    end
  end
end
