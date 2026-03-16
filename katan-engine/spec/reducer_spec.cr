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

private def set_bank_resource!(game_state : GameState, resource : Resource, amount : Int32) : Nil
  case resource
  when .wood?  then game_state.bank.resources.wood = amount
  when .brick? then game_state.bank.resources.brick = amount
  when .sheep? then game_state.bank.resources.sheep = amount
  when .wheat? then game_state.bank.resources.wheat = amount
  when .ore?   then game_state.bank.resources.ore = amount
  else
    raise "cannot set desert bank supply"
  end
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

private def robber_target_with_victim(game_state : GameState) : NamedTuple(tile_id: TileId, vertex_id: VertexId)
  game_state.topology.tiles.keys.sort_by(&.value).each do |tile_id|
    next if tile_id == game_state.board.robber_tile_id

    vertex_id = game_state.topology.tiles[tile_id].vertex_ids.first
    return {tile_id: tile_id, vertex_id: vertex_id}
  end

  raise "no robber target tile available"
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
    token = tile_state.token.not_nil!
    die_one = token > 6 ? 6 : 1
    die_two = token - die_one
    game_state.apply!(DiceRolled.new(2, die_one, die_two))

    player = game_state.current_player!
    player.hand.count(tile_state.resource).should eq(1)
    game_state.bank.resources.count(tile_state.resource).should eq(18)
    game_state.turn.phase.should eq(TurnPhase::Main)
    game_state.last_roll.not_nil!.die_one.should eq(die_one)
    game_state.last_roll.not_nil!.die_two.should eq(die_two)
    game_state.last_roll.not_nil!.total.should eq(token)
  end

  it "grants the remaining bank supply when only one player receives a scarce resource" do
    game_state = build_game_state(1)
    tile_id, tile_state = game_state.board.tile_states.find { |_, state| state.token && !state.resource.desert? }.not_nil!
    vertex_ids = game_state.topology.tiles[tile_id].vertex_ids
    player = game_state.current_player!

    game_state.turn.phase = TurnPhase::Roll
    game_state.board.buildings[vertex_ids[0]] = Building.new(player.id, BuildingKind::City)
    game_state.board.buildings[vertex_ids[1]] = Building.new(player.id, BuildingKind::Settlement)
    set_bank_resource!(game_state, tile_state.resource, 2)

    token = tile_state.token.not_nil!
    die_one = token > 6 ? 6 : 1
    die_two = token - die_one
    game_state.apply!(DiceRolled.new(2, die_one, die_two))

    player.hand.count(tile_state.resource).should eq(2)
    game_state.bank.resources.count(tile_state.resource).should eq(0)
  end

  it "does not distribute a scarce resource when multiple players would receive it" do
    game_state = build_game_state(2)
    tile_id, tile_state = game_state.board.tile_states.find { |_, state| state.token && !state.resource.desert? }.not_nil!
    vertex_ids = game_state.topology.tiles[tile_id].vertex_ids
    current_player = game_state.current_player!
    other_player_id = (game_state.player_order - [current_player.id]).first

    game_state.turn.phase = TurnPhase::Roll
    game_state.board.buildings[vertex_ids[0]] = Building.new(current_player.id, BuildingKind::Settlement)
    game_state.board.buildings[vertex_ids[1]] = Building.new(other_player_id, BuildingKind::Settlement)
    set_bank_resource!(game_state, tile_state.resource, 1)

    token = tile_state.token.not_nil!
    die_one = token > 6 ? 6 : 1
    die_two = token - die_one
    game_state.apply!(DiceRolled.new(2, die_one, die_two))

    current_player.hand.count(tile_state.resource).should eq(0)
    game_state.player!(other_player_id).hand.count(tile_state.resource).should eq(0)
    game_state.bank.resources.count(tile_state.resource).should eq(1)
  end

  it "requires robber discards before allowing the robber to move" do
    game_state = build_game_state(3)
    current_player = game_state.turn.current_player_id
    discarding_player = (game_state.player_order - [current_player]).first
    discarding_hand = game_state.player!(discarding_player).hand
    discarding_hand.wood = 4
    discarding_hand.brick = 2
    discarding_hand.sheep = 2
    game_state.turn.phase = TurnPhase::Roll

    game_state.apply!(DiceRolled.new(1, 3, 4))

    game_state.turn.phase.should eq(TurnPhase::DiscardResources)
    game_state.pending_robber_discards[discarding_player].should eq(4)

    expect_raises(Exception, "can only move robber after rolling a 7") do
      target_tile_id = game_state.topology.tiles.keys.find { |tile_id| tile_id != game_state.board.robber_tile_id }.not_nil!
      game_state.apply!(RobberMoved.new(2, current_player, target_tile_id))
    end

    game_state.apply!(RobberDiscarded.new(2, discarding_player, ResourcePile.new(4, 0, 0, 0, 0)))

    discarding_hand.total.should eq(4)
    game_state.pending_robber_discards.empty?.should be_true
    game_state.turn.phase.should eq(TurnPhase::MoveRobber)
  end

  it "moves the robber, exposes eligible victims, and steals a random card" do
    game_state = build_game_state
    current_player = game_state.turn.current_player_id
    victim_player = (game_state.player_order - [current_player]).first
    target = robber_target_with_victim(game_state)
    victim = game_state.player!(victim_player)

    game_state.board.buildings[target[:vertex_id]] = Building.new(victim_player, BuildingKind::Settlement)
    victim.hand.brick = 3
    game_state.turn.phase = TurnPhase::Roll

    game_state.apply!(DiceRolled.new(1, 3, 4))
    game_state.apply!(RobberMoved.new(2, current_player, target[:tile_id]))

    game_state.board.robber_tile_id.should eq(target[:tile_id])
    game_state.turn.phase.should eq(TurnPhase::StealResource)
    game_state.robber_eligible_victim_ids.should eq([victim_player])

    game_state.apply!(RobberStolen.new(3, current_player, victim_player, Resource::Brick))

    game_state.player!(current_player).hand.brick.should eq(1)
    victim.hand.brick.should eq(2)
    game_state.robber_eligible_victim_ids.should be_empty
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
    token = tile_state.token.not_nil!
    die_one = token > 6 ? 6 : 1
    die_two = token - die_one
    game_state.apply!(DiceRolled.new(2, die_one, die_two))
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
    game_state.apply!(DiceRolled.new(game_state.version + 1, 1, 1))

    game_state.largest_army_player_id.should eq(player_one)
    game_state.largest_army_size.should eq(3)
    game_state.player!(player_one).victory_points.should eq(4)

    game_state.player!(player_two).knights_played = 3
    game_state.turn.current_player_id = player_two
    game_state.turn.phase = TurnPhase::Roll
    game_state.apply!(DiceRolled.new(game_state.version + 1, 1, 2))

    game_state.largest_army_player_id.should eq(player_one)

    game_state.player!(player_two).knights_played = 4
    game_state.turn.current_player_id = player_two
    game_state.turn.phase = TurnPhase::Roll
    game_state.apply!(DiceRolled.new(game_state.version + 1, 1, 3))

    game_state.largest_army_player_id.should eq(player_two)
    game_state.largest_army_size.should eq(4)
    game_state.player!(player_one).victory_points.should eq(2)
    game_state.player!(player_two).victory_points.should eq(4)
  end

  it "buys a development card, keeps it unplayable until end of turn, and decrements bank supply" do
    game_state = build_game_state(1)
    player = game_state.current_player!
    target_tile_id = game_state.topology.tiles.keys.find { |tile_id| tile_id != game_state.board.robber_tile_id }.not_nil!

    player.hand.sheep = 1
    player.hand.wheat = 1
    player.hand.ore = 1
    game_state.turn.phase = TurnPhase::Main

    game_state.apply!(DevelopmentCardPurchased.new(1, player.id, DevCard::Knight))

    player.hand.sheep.should eq(0)
    player.hand.wheat.should eq(0)
    player.hand.ore.should eq(0)
    game_state.bank.resources.sheep.should eq(20)
    game_state.bank.resources.wheat.should eq(20)
    game_state.bank.resources.ore.should eq(20)
    game_state.bank.knight.should eq(13)
    player.dev_cards.knight.should eq(0)
    player.newly_purchased_dev_cards.knight.should eq(1)

    expect_raises(Exception, "player does not have Knight") do
      game_state.apply!(KnightPlayed.new(2, player.id, target_tile_id))
    end

    game_state.apply!(TurnEnded.new(2, player.id))
    player.dev_cards.knight.should eq(1)
    player.newly_purchased_dev_cards.knight.should eq(0)
  end

  it "counts purchased victory point cards toward score immediately" do
    game_state = build_game_state(1)
    player = game_state.current_player!

    player.hand.sheep = 1
    player.hand.wheat = 1
    player.hand.ore = 1
    game_state.turn.phase = TurnPhase::Main

    game_state.apply!(DevelopmentCardPurchased.new(1, player.id, DevCard::VictoryPoint))

    player.victory_points.should eq(1)
    player.newly_purchased_dev_cards.victory_point.should eq(1)
  end

  it "plays a knight to move the robber and enforces one development card play per turn" do
    game_state = build_game_state(2)
    player = game_state.current_player!
    opponent_player_id = (game_state.player_order - [player.id]).first
    target_tile_id = game_state.topology.tiles.keys.find { |tile_id| tile_id != game_state.board.robber_tile_id }.not_nil!

    opponent_vertex_id = game_state.topology.tiles[target_tile_id].vertex_ids.first
    game_state.board.buildings[opponent_vertex_id] = Building.new(opponent_player_id, BuildingKind::Settlement)
    game_state.player!(opponent_player_id).hand.sheep = 1
    player.dev_cards.knight = 1
    player.dev_cards.monopoly = 1
    game_state.turn.phase = TurnPhase::Main

    game_state.apply!(KnightPlayed.new(1, player.id, target_tile_id))

    game_state.board.robber_tile_id.should eq(target_tile_id)
    player.dev_cards.knight.should eq(0)
    player.knights_played.should eq(1)
    game_state.turn.phase.should eq(TurnPhase::StealResource)

    game_state.apply!(RobberStolen.new(2, player.id, opponent_player_id, Resource::Sheep))

    expect_raises(Exception, "can only play one development card per turn") do
      game_state.apply!(MonopolyPlayed.new(3, player.id, Resource::Wood))
    end
  end

  it "allows playing a knight before rolling and returns to the roll phase after robber resolution" do
    game_state = build_game_state(2)
    player = game_state.current_player!
    opponent_player_id = (game_state.player_order - [player.id]).first
    target_tile_id = game_state.topology.tiles.keys.find { |tile_id| tile_id != game_state.board.robber_tile_id }.not_nil!

    opponent_vertex_id = game_state.topology.tiles[target_tile_id].vertex_ids.first
    game_state.board.buildings[opponent_vertex_id] = Building.new(opponent_player_id, BuildingKind::Settlement)
    game_state.player!(opponent_player_id).hand.sheep = 1
    player.dev_cards.knight = 1
    game_state.turn.phase = TurnPhase::Roll

    game_state.apply!(KnightPlayed.new(1, player.id, target_tile_id))

    game_state.turn.phase.should eq(TurnPhase::StealResource)

    game_state.apply!(RobberStolen.new(2, player.id, opponent_player_id, Resource::Sheep))

    game_state.turn.phase.should eq(TurnPhase::Roll)
    game_state.player!(player.id).hand.sheep.should eq(1)
  end

  it "plays road building to place two free roads" do
    game_state = build_game_state(1)
    player = game_state.current_player!
    path = find_simple_road_path(game_state.topology, 2)

    game_state.board.buildings[path[:start_vertex_id]] = Building.new(player.id, BuildingKind::Settlement)
    player.settlements_left = 4
    player.dev_cards.road_building = 1
    game_state.turn.phase = TurnPhase::Main

    game_state.apply!(RoadBuildingPlayed.new(1, player.id, path[:edge_ids][0], path[:edge_ids][1]))

    game_state.board.road_at?(path[:edge_ids][0]).not_nil!.player_id.should eq(player.id)
    game_state.board.road_at?(path[:edge_ids][1]).not_nil!.player_id.should eq(player.id)
    player.dev_cards.road_building.should eq(0)
    player.roads_left.should eq(13)
    player.victory_points.should eq(1)
  end

  it "rejects road building with one road when a second placement is available" do
    game_state = build_game_state(1)
    player = game_state.current_player!
    path = find_simple_road_path(game_state.topology, 2)

    game_state.board.buildings[path[:start_vertex_id]] = Building.new(player.id, BuildingKind::Settlement)
    player.settlements_left = 4
    player.dev_cards.road_building = 1
    game_state.turn.phase = TurnPhase::Main

    expect_raises(Exception, "road building must place a second road when possible") do
      game_state.apply!(RoadBuildingPlayed.new(1, player.id, path[:edge_ids][0]))
    end

    game_state.board.road_at?(path[:edge_ids][0]).should be_nil
    game_state.board.road_at?(path[:edge_ids][1]).should be_nil
    player.dev_cards.road_building.should eq(1)
    player.roads_left.should eq(15)
  end

  it "plays monopoly to collect one resource type from all opponents" do
    game_state = build_game_state
    player_one = game_state.player_order[0]
    player_two = game_state.player_order[1]
    current_player = game_state.player!(player_one)
    other_player = game_state.player!(player_two)

    current_player.dev_cards.monopoly = 1
    other_player.hand.wheat = 3
    game_state.turn.current_player_id = player_one
    game_state.turn.phase = TurnPhase::Main

    game_state.apply!(MonopolyPlayed.new(1, player_one, Resource::Wheat))

    current_player.hand.wheat.should eq(3)
    other_player.hand.wheat.should eq(0)
    current_player.dev_cards.monopoly.should eq(0)
  end

  it "plays year of plenty to take two resources from the bank" do
    game_state = build_game_state(1)
    player = game_state.current_player!

    player.dev_cards.year_of_plenty = 1
    game_state.turn.phase = TurnPhase::Main

    game_state.apply!(YearOfPlentyPlayed.new(1, player.id, Resource::Ore, Resource::Ore))

    player.hand.ore.should eq(2)
    game_state.bank.resources.ore.should eq(17)
    player.dev_cards.year_of_plenty.should eq(0)
  end

  it "stores broadcast player trade responses until the proposer finalizes" do
    game_state = build_game_state(3)
    player_one = game_state.player_order[0]
    player_two = game_state.player_order[1]
    player_three = game_state.player_order[2]
    current_player = game_state.player!(player_one)
    second_player = game_state.player!(player_two)
    third_player = game_state.player!(player_three)

    current_player.hand.wood = 2
    current_player.hand.brick = 1
    second_player.hand.sheep = 1
    second_player.hand.wheat = 2
    third_player.hand.sheep = 1
    third_player.hand.wheat = 2
    game_state.turn.current_player_id = player_one
    game_state.turn.phase = TurnPhase::Main

    game_state.apply!(
      PlayerTradeProposed.new(
        1,
        player_one,
        ResourcePile.new(2, 1, 0, 0, 0),
        ResourcePile.new(0, 0, 1, 2, 0)
      )
    )
    game_state.apply!(PlayerTradeAccepted.new(2, player_two, player_one))
    game_state.apply!(PlayerTradeRejected.new(3, player_three, player_one))

    pending_trade = game_state.pending_player_trade.not_nil!
    pending_trade.player_id.should eq(player_one)
    pending_trade.offered.should eq(ResourcePile.new(2, 1, 0, 0, 0))
    pending_trade.requested.should eq(ResourcePile.new(0, 0, 1, 2, 0))
    pending_trade.accepted_player_ids.should eq([player_two])
    pending_trade.rejected_player_ids.should eq([player_three])
    current_player.hand.wood.should eq(2)
    second_player.hand.wheat.should eq(2)
  end

  it "completes a player trade only after the proposer chooses an accepter" do
    game_state = build_game_state(3)
    player_one = game_state.player_order[0]
    player_two = game_state.player_order[1]
    player_three = game_state.player_order[2]
    current_player = game_state.player!(player_one)
    second_player = game_state.player!(player_two)
    third_player = game_state.player!(player_three)

    current_player.hand.wood = 2
    current_player.hand.brick = 1
    second_player.hand.sheep = 1
    second_player.hand.wheat = 2
    third_player.hand.sheep = 1
    third_player.hand.wheat = 2
    game_state.turn.current_player_id = player_one
    game_state.turn.phase = TurnPhase::Main

    game_state.apply!(
      PlayerTradeProposed.new(
        1,
        player_one,
        ResourcePile.new(2, 1, 0, 0, 0),
        ResourcePile.new(0, 0, 1, 2, 0)
      )
    )
    game_state.apply!(PlayerTradeAccepted.new(2, player_two, player_one))
    game_state.apply!(PlayerTradeAccepted.new(3, player_three, player_one))
    game_state.apply!(
      PlayerTradeCompleted.new(
        4,
        player_one,
        player_three,
        ResourcePile.new(2, 1, 0, 0, 0),
        ResourcePile.new(0, 0, 1, 2, 0)
      )
    )

    current_player.hand.wood.should eq(0)
    current_player.hand.brick.should eq(0)
    current_player.hand.sheep.should eq(1)
    current_player.hand.wheat.should eq(2)
    second_player.hand.wood.should eq(0)
    second_player.hand.brick.should eq(0)
    second_player.hand.sheep.should eq(1)
    second_player.hand.wheat.should eq(2)
    third_player.hand.wood.should eq(2)
    third_player.hand.brick.should eq(1)
    third_player.hand.sheep.should eq(0)
    third_player.hand.wheat.should eq(0)
    game_state.pending_player_trade.should be_nil
  end

  it "rejects trade completion before any player accepts" do
    game_state = build_game_state(3)
    player_one = game_state.player_order[0]
    player_two = game_state.player_order[1]

    game_state.player!(player_one).hand.wood = 1
    game_state.player!(player_two).hand.brick = 1
    game_state.turn.current_player_id = player_one
    game_state.turn.phase = TurnPhase::Main

    game_state.apply!(
      PlayerTradeProposed.new(
        1,
        player_one,
        ResourcePile.new(1, 0, 0, 0, 0),
        ResourcePile.new(0, 1, 0, 0, 0)
      )
    )

    expect_raises(Exception, "accepted before completion") do
      game_state.apply!(
        PlayerTradeCompleted.new(
          2,
          player_one,
          player_two,
          ResourcePile.new(1, 0, 0, 0, 0),
          ResourcePile.new(0, 1, 0, 0, 0)
        )
      )
    end
  end

  it "rejects player-to-player trades with negative offered resources" do
    game_state = build_game_state
    player_one = game_state.player_order[0]
    current_player = game_state.player!(player_one)

    current_player.hand.wood = 2
    current_player.hand.brick = 1
    game_state.turn.current_player_id = player_one
    game_state.turn.phase = TurnPhase::Main

    expect_raises(Exception, "negative") do
      game_state.apply!(
        PlayerTradeProposed.new(
          1,
          player_one,
          ResourcePile.new(-1, 1, 0, 0, 0),
          ResourcePile.new(0, 0, 1, 2, 0)
        )
      )
    end
  end

  it "rejects player-to-player trades with negative requested resources" do
    game_state = build_game_state
    player_one = game_state.player_order[0]
    current_player = game_state.player!(player_one)

    current_player.hand.wood = 2
    current_player.hand.brick = 1
    game_state.turn.current_player_id = player_one
    game_state.turn.phase = TurnPhase::Main

    expect_raises(Exception, "negative") do
      game_state.apply!(
        PlayerTradeProposed.new(
          1,
          player_one,
          ResourcePile.new(2, 1, 0, 0, 0),
          ResourcePile.new(0, 0, -1, 2, 0)
        )
      )
    end
  end

  it "allows any non-proposer player to accept a broadcast trade" do
    game_state = build_game_state(3)
    player_one = game_state.player_order[0]
    player_three = game_state.player_order[2]

    game_state.player!(player_one).hand.wood = 1
    game_state.player!(player_three).hand.brick = 1
    game_state.turn.current_player_id = player_one
    game_state.turn.phase = TurnPhase::Main

    game_state.apply!(
      PlayerTradeProposed.new(
        1,
        player_one,
        ResourcePile.new(1, 0, 0, 0, 0),
        ResourcePile.new(0, 1, 0, 0, 0)
      )
    )
    game_state.apply!(PlayerTradeAccepted.new(2, player_three, player_one))

    game_state.pending_player_trade.not_nil!.accepted_player_ids.should eq([player_three])
  end

  it "keeps a pending trade when a player rejects the offer" do
    game_state = build_game_state
    player_one = game_state.player_order[0]
    player_two = game_state.player_order[1]

    game_state.player!(player_one).hand.wood = 1
    game_state.player!(player_two).hand.brick = 1
    game_state.turn.current_player_id = player_one
    game_state.turn.phase = TurnPhase::Main

    game_state.apply!(
      PlayerTradeProposed.new(
        1,
        player_one,
        ResourcePile.new(1, 0, 0, 0, 0),
        ResourcePile.new(0, 1, 0, 0, 0)
      )
    )
    game_state.apply!(PlayerTradeRejected.new(2, player_two, player_one))

    game_state.pending_player_trade.should_not be_nil
    game_state.pending_player_trade.not_nil!.rejected_player_ids.should eq([player_two])
    game_state.player!(player_one).hand.wood.should eq(1)
    game_state.player!(player_two).hand.brick.should eq(1)
  end

  it "clears a pending trade when the proposer cancels it" do
    game_state = build_game_state
    player_one = game_state.player_order[0]

    game_state.player!(player_one).hand.wood = 1
    game_state.turn.current_player_id = player_one
    game_state.turn.phase = TurnPhase::Main

    game_state.apply!(
      PlayerTradeProposed.new(
        1,
        player_one,
        ResourcePile.new(1, 0, 0, 0, 0),
        ResourcePile.new(0, 1, 0, 0, 0)
      )
    )
    game_state.apply!(PlayerTradeCancelled.new(2, player_one))

    game_state.pending_player_trade.should be_nil
  end

  it "clears a pending trade when the turn ends" do
    game_state = build_game_state
    player_one = game_state.player_order[0]

    game_state.player!(player_one).hand.wood = 1
    game_state.turn.current_player_id = player_one
    game_state.turn.phase = TurnPhase::Main

    game_state.apply!(
      PlayerTradeProposed.new(
        1,
        player_one,
        ResourcePile.new(1, 0, 0, 0, 0),
        ResourcePile.new(0, 1, 0, 0, 0)
      )
    )
    game_state.apply!(TurnEnded.new(2, player_one))

    game_state.pending_player_trade.should be_nil
  end

  it "trades 4 to 1 with the bank when the player has no harbor" do
    game_state = build_game_state(1)
    player = game_state.current_player!

    game_state.board.harbors.clear
    player.hand.wood = 4
    game_state.turn.phase = TurnPhase::Main

    game_state.apply!(BankTradeCompleted.new(1, player.id, Resource::Wood, Resource::Ore))

    player.hand.wood.should eq(0)
    player.hand.ore.should eq(1)
    game_state.bank.resources.wood.should eq(23)
    game_state.bank.resources.ore.should eq(18)
  end

  it "uses a matching harbor to trade 2 to 1 with the bank" do
    game_state = build_game_state(1)
    player = game_state.current_player!
    harbor_slot = game_state.topology.harbor_slots.values.sort_by(&.id.value).first

    game_state.board.harbors = [
      HarborAssignment.new(HarborSlotId.new("h-test"), harbor_slot.vertex_ids, HarborKind::WoodTwoToOne),
    ]
    game_state.board.buildings[harbor_slot.vertex_ids[0]] = Building.new(player.id, BuildingKind::Settlement)
    player.settlements_left = 4
    player.hand.wood = 2
    game_state.turn.phase = TurnPhase::Main

    game_state.apply!(BankTradeCompleted.new(1, player.id, Resource::Wood, Resource::Ore))

    player.hand.wood.should eq(0)
    player.hand.ore.should eq(1)
    game_state.bank.resources.wood.should eq(21)
    game_state.bank.resources.ore.should eq(18)
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
