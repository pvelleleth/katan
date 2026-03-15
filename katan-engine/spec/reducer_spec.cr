require "./spec_helper"

private def build_game_state(player_count : Int32 = 2) : GameState
  players = (1..player_count).map do |index|
    player_id = PlayerId.new("player-#{index}")
    {player_id, PlayerState.new(player_id, "Player #{index}")}
  end.to_h

  GameState.new(
    topology: BoardTopology.standard,
    players: players,
    settings: {} of String => JSON::Any
  )
end

private def resource_tally_for_vertex(game_state : GameState, vertex_id : VertexId) : Hash(Resource, Int32)
  tally = Hash(Resource, Int32).new(0)

  game_state.topology.vertices[vertex_id].tile_ids.each do |tile_id|
    resource = game_state.board.tile_states[tile_id].resource
    next if resource.desert?

    tally[resource] += 1
  end

  tally
end

private def place_roads_in_main!(game_state : GameState, player_id : PlayerId, edge_ids : Array(EdgeId)) : Nil
  player = game_state.player!(player_id)
  player.hand.wood += edge_ids.size
  player.hand.brick += edge_ids.size
  game_state.turn.current_player_id = player_id
  game_state.turn.phase = TurnPhase::Main

  edge_ids.each do |edge_id|
    game_state.apply!(RoadPlaced.new(game_state.version + 1, player_id, edge_id, false))
  end
end

describe GameState do
  it "advances through the snake-order setup flow" do
    game_state = build_game_state
    player_order = game_state.player_order

    first_player = player_order[0]
    second_player = player_order[1]

    first_vertex = legal_setup_vertex_for_current_player(game_state)
    game_state.apply!(SettlementPlaced.new(1, first_player, first_vertex, true))
    game_state.turn.phase.should eq(TurnPhase::Setup1Road)
    game_state.turn.current_player_id.should eq(first_player)

    first_edge = legal_setup_road_for_current_player(game_state)
    game_state.apply!(RoadPlaced.new(2, first_player, first_edge, true))
    game_state.turn.phase.should eq(TurnPhase::Setup1Settlement)
    game_state.turn.current_player_id.should eq(second_player)

    second_vertex = legal_setup_vertex_for_current_player(game_state)
    game_state.apply!(SettlementPlaced.new(3, second_player, second_vertex, true))
    game_state.turn.phase.should eq(TurnPhase::Setup1Road)
    game_state.turn.current_player_id.should eq(second_player)

    second_edge = legal_setup_road_for_current_player(game_state)
    game_state.apply!(RoadPlaced.new(4, second_player, second_edge, true))
    game_state.turn.phase.should eq(TurnPhase::Setup2Settlement)
    game_state.turn.current_player_id.should eq(second_player)

    third_vertex = legal_setup_vertex_for_current_player(game_state)
    game_state.apply!(SettlementPlaced.new(5, second_player, third_vertex, true))
    game_state.turn.phase.should eq(TurnPhase::Setup2Road)
    game_state.turn.current_player_id.should eq(second_player)

    third_edge = legal_setup_road_for_current_player(game_state)
    game_state.apply!(RoadPlaced.new(6, second_player, third_edge, true))
    game_state.turn.phase.should eq(TurnPhase::Setup2Settlement)
    game_state.turn.current_player_id.should eq(first_player)

    fourth_vertex = legal_setup_vertex_for_current_player(game_state)
    game_state.apply!(SettlementPlaced.new(7, first_player, fourth_vertex, true))
    game_state.turn.phase.should eq(TurnPhase::Setup2Road)
    game_state.turn.current_player_id.should eq(first_player)

    fourth_edge = legal_setup_road_for_current_player(game_state)
    game_state.apply!(RoadPlaced.new(8, first_player, fourth_edge, true))
    game_state.turn.phase.should eq(TurnPhase::Roll)
    game_state.turn.current_player_id.should eq(first_player)
  end

  it "grants starting resources for the second setup settlement" do
    game_state = build_game_state
    player_order = game_state.player_order

    first_player = player_order[0]
    second_player = player_order[1]

    game_state.apply!(SettlementPlaced.new(1, first_player, legal_setup_vertex_for_current_player(game_state), true))
    game_state.apply!(RoadPlaced.new(2, first_player, legal_setup_road_for_current_player(game_state), true))
    game_state.apply!(SettlementPlaced.new(3, second_player, legal_setup_vertex_for_current_player(game_state), true))
    game_state.apply!(RoadPlaced.new(4, second_player, legal_setup_road_for_current_player(game_state), true))

    second_setup_vertex = legal_setup_vertex_for_current_player(game_state)
    expected_resources = resource_tally_for_vertex(game_state, second_setup_vertex)

    game_state.apply!(SettlementPlaced.new(5, second_player, second_setup_vertex, true))

    player = game_state.player!(second_player)
    [Resource::Wood, Resource::Brick, Resource::Sheep, Resource::Wheat, Resource::Ore].each do |resource|
      player.hand.count(resource).should eq(expected_resources[resource])
      game_state.bank.resources.count(resource).should eq(19 - expected_resources[resource])
    end
  end

  it "distributes resources for a dice roll when a producing tile is not blocked" do
    game_state = build_game_state(1)
    tile_id, tile_state = game_state.board.tile_states.find { |_, state| state.token && !state.resource.desert? }.not_nil!
    vertex_id = game_state.topology.tiles[tile_id].vertex_ids.first

    game_state.turn.phase = TurnPhase::Roll
    game_state.board.buildings[vertex_id] = Building.new(game_state.turn.current_player_id, BuildingKind::Settlement)
    game_state.apply!(DiceRolled.new(2, tile_state.token.not_nil!))

    player = game_state.current_player!
    player.hand.count(tile_state.resource).should eq(1)
    game_state.bank.resources.count(tile_state.resource).should eq(18)
    game_state.turn.phase.should eq(TurnPhase::Main)
  end

  it "upgrades a settlement to a city and doubles future production" do
    game_state = build_game_state(1)
    player = game_state.current_player!
    tile_id, tile_state = game_state.board.tile_states.find { |_, state| state.token && !state.resource.desert? }.not_nil!
    vertex_id = game_state.topology.tiles[tile_id].vertex_ids.first

    game_state.board.buildings[vertex_id] = Building.new(player.id, BuildingKind::Settlement)
    player.settlements_left = 4
    player.hand.wheat = 2
    player.hand.ore = 3
    game_state.turn.phase = TurnPhase::Main

    game_state.apply!(CityPlaced.new(1, player.id, vertex_id))

    game_state.board.buildings[vertex_id].kind.should eq(BuildingKind::City)
    player.settlements_left.should eq(5)
    player.cities_left.should eq(3)
    player.victory_points.should eq(2)

    before_roll = player.hand.count(tile_state.resource)
    game_state.turn.phase = TurnPhase::Roll
    game_state.apply!(DiceRolled.new(2, tile_state.token.not_nil!))
    player.hand.count(tile_state.resource).should eq(before_roll + 2)
  end

  it "does not mutate game state when a city upgrade is unaffordable" do
    game_state = build_game_state(1)
    player = game_state.current_player!
    vertex_id = game_state.topology.vertices.keys.sort_by(&.value).first

    game_state.board.buildings[vertex_id] = Building.new(player.id, BuildingKind::Settlement)
    player.settlements_left = 4
    player.cities_left = 4
    player.hand.wheat = 1
    player.hand.ore = 2
    game_state.turn.phase = TurnPhase::Main

    expect_raises(Exception, "cannot afford city") do
      game_state.apply!(CityPlaced.new(1, player.id, vertex_id))
    end

    game_state.board.buildings[vertex_id].kind.should eq(BuildingKind::Settlement)
    player.settlements_left.should eq(4)
    player.cities_left.should eq(4)
    player.hand.wheat.should eq(1)
    player.hand.ore.should eq(2)
    game_state.bank.resources.wheat.should eq(19)
    game_state.bank.resources.ore.should eq(19)
    player.victory_points.should eq(0)
  end

  it "does not mutate game state when a settlement placement is unaffordable" do
    game_state = build_game_state(1)
    player = game_state.current_player!
    vertex_id = game_state.topology.vertices.keys.sort_by(&.value).first
    neighbor_vertex_id = game_state.topology.neighboring_vertices(vertex_id).first
    edge_id = game_state.topology.vertices[vertex_id].edge_ids.find do |candidate_edge_id|
      edge = game_state.topology.edges[candidate_edge_id]
      edge.vertex_ids.includes?(neighbor_vertex_id)
    end.not_nil!

    game_state.board.roads[edge_id] = Road.new(player.id)
    player.roads_left = 14
    player.hand.wood = 0
    player.hand.brick = 0
    player.hand.sheep = 0
    player.hand.wheat = 0
    game_state.turn.phase = TurnPhase::Main

    expect_raises(Exception, "cannot afford settlement") do
      game_state.apply!(SettlementPlaced.new(1, player.id, vertex_id, false))
    end

    game_state.board.building_at?(vertex_id).should be_nil
    player.settlements_left.should eq(5)
    player.hand.wood.should eq(0)
    player.hand.brick.should eq(0)
    player.hand.sheep.should eq(0)
    player.hand.wheat.should eq(0)
    game_state.bank.resources.wood.should eq(19)
    game_state.bank.resources.brick.should eq(19)
    game_state.bank.resources.sheep.should eq(19)
    game_state.bank.resources.wheat.should eq(19)
    player.victory_points.should eq(0)
  end

  it "does not mutate game state when a road placement is unaffordable" do
    game_state = build_game_state(1)
    player = game_state.current_player!
    vertex_id = game_state.topology.vertices.keys.sort_by(&.value).first
    edge_id = game_state.topology.vertices[vertex_id].edge_ids.first

    game_state.board.buildings[vertex_id] = Building.new(player.id, BuildingKind::Settlement)
    player.settlements_left = 4
    player.hand.wood = 0
    player.hand.brick = 0
    game_state.turn.phase = TurnPhase::Main

    expect_raises(Exception, "cannot afford road") do
      game_state.apply!(RoadPlaced.new(1, player.id, edge_id, false))
    end

    game_state.board.road_at?(edge_id).should be_nil
    player.roads_left.should eq(15)
    player.hand.wood.should eq(0)
    player.hand.brick.should eq(0)
    game_state.bank.resources.wood.should eq(19)
    game_state.bank.resources.brick.should eq(19)
    player.victory_points.should eq(0)
  end

  it "awards longest road at five, keeps it on ties, and transfers on a longer road" do
    game_state = build_game_state
    player_one = game_state.player_order[0]
    player_two = game_state.player_order[1]

    player_one_path = find_simple_road_path(game_state.topology, 5)
    player_one_vertices = vertices_for_road_path(game_state.topology, player_one_path[:start_vertex_id], player_one_path[:edge_ids])
    player_two_path = find_simple_road_path(game_state.topology, 6, player_one_path[:edge_ids], player_one_vertices)

    game_state.board.buildings[player_one_path[:start_vertex_id]] = Building.new(player_one, BuildingKind::Settlement)
    game_state.player!(player_one).settlements_left = 4
    game_state.board.buildings[player_two_path[:start_vertex_id]] = Building.new(player_two, BuildingKind::Settlement)
    game_state.player!(player_two).settlements_left = 4

    place_roads_in_main!(game_state, player_one, player_one_path[:edge_ids])
    game_state.longest_road_player_id.should eq(player_one)
    game_state.longest_road_length.should eq(5)
    game_state.player!(player_one).victory_points.should eq(3)

    place_roads_in_main!(game_state, player_two, player_two_path[:edge_ids][0, 5])
    game_state.longest_road_player_id.should eq(player_one)
    game_state.player!(player_one).victory_points.should eq(3)
    game_state.player!(player_two).victory_points.should eq(1)

    place_roads_in_main!(game_state, player_two, [player_two_path[:edge_ids][5]])
    game_state.longest_road_player_id.should eq(player_two)
    game_state.longest_road_length.should eq(6)
    game_state.player!(player_one).victory_points.should eq(1)
    game_state.player!(player_two).victory_points.should eq(3)
  end

  it "awards largest army once a player reaches three knights and preserves ties for the holder" do
    game_state = build_game_state
    complete_setup!(game_state)
    player_one = game_state.player_order[0]
    player_two = game_state.player_order[1]

    game_state.player!(player_one).knights_played = 3
    game_state.turn.current_player_id = player_one
    game_state.turn.phase = TurnPhase::Roll
    game_state.apply!(DiceRolled.new(game_state.version + 1, 2))

    game_state.largest_army_player_id.should eq(player_one)
    game_state.largest_army_size.should eq(3)
    game_state.player!(player_one).victory_points.should eq(4)

    game_state.player!(player_two).knights_played = 3
    game_state.turn.current_player_id = player_two
    game_state.turn.phase = TurnPhase::Roll
    game_state.apply!(DiceRolled.new(game_state.version + 1, 3))

    game_state.largest_army_player_id.should eq(player_one)

    game_state.player!(player_two).knights_played = 4
    game_state.turn.current_player_id = player_two
    game_state.turn.phase = TurnPhase::Roll
    game_state.apply!(DiceRolled.new(game_state.version + 1, 4))

    game_state.largest_army_player_id.should eq(player_two)
    game_state.largest_army_size.should eq(4)
    game_state.player!(player_one).victory_points.should eq(2)
    game_state.player!(player_two).victory_points.should eq(4)
  end

  it "transitions to game over when the current player reaches ten points" do
    game_state = build_game_state(1)
    player = game_state.current_player!
    city_vertices = game_state.topology.vertices.keys.sort_by(&.value)

    city_vertices[0, 3].each do |vertex_id|
      game_state.board.buildings[vertex_id] = Building.new(player.id, BuildingKind::City)
    end

    city_vertices[3, 3].each do |vertex_id|
      game_state.board.buildings[vertex_id] = Building.new(player.id, BuildingKind::Settlement)
    end

    player.settlements_left = 2
    player.cities_left = 1
    player.hand.wheat = 2
    player.hand.ore = 3
    game_state.turn.phase = TurnPhase::Main

    game_state.apply!(CityPlaced.new(1, player.id, city_vertices[3]))

    game_state.player!(player.id).victory_points.should eq(10)
    game_state.turn.phase.should eq(TurnPhase::GameOver)
    game_state.winner_player_id.should eq(player.id)
  end

  it "rejects a settlement next to an existing building" do
    game_state = build_game_state
    player = game_state.turn.current_player_id
    first_vertex = legal_setup_vertex_for_current_player(game_state)

    game_state.apply!(SettlementPlaced.new(1, player, first_vertex, true))
    game_state.turn.phase = TurnPhase::Setup1Settlement

    adjacent_vertex = game_state.topology.neighboring_vertices(first_vertex).first
    expect_raises(Exception, "settlement must not be adjacent to another building") do
      game_state.apply!(SettlementPlaced.new(2, player, adjacent_vertex, true))
    end
  end

  it "rejects a road that does not connect to the current player's network" do
    game_state = build_game_state
    complete_setup!(game_state)

    current_player = game_state.turn.current_player_id
    disconnected_edge = game_state.topology.edges.keys.sort_by(&.value).find do |edge_id|
      next false if game_state.board.occupied_edge?(edge_id)

      edge = game_state.topology.edges[edge_id]
      edge.vertex_ids.all? do |vertex_id|
        building = game_state.board.building_at?(vertex_id)
        next false if building && building.player_id == current_player

        player_road_ids_touching_vertex(game_state, vertex_id, current_player).empty?
      end
    end.not_nil!

    game_state.turn.phase = TurnPhase::Main
    expect_raises(Exception, "road must connect to your network") do
      game_state.apply!(RoadPlaced.new(game_state.version + 1, current_player, disconnected_edge, false))
    end
  end
end
