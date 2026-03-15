require "../game/game_state"
require "../game/game_events"

class GameState
  def apply!(event : GameEvent) : Nil
    case event
    when GameStarted
      apply_game_started!(event)
    when SettlementPlaced
      apply_settlement_placed!(event)
    when RoadPlaced
      apply_road_placed!(event)
    when CityPlaced
      apply_city_placed!(event)
    when DiceRolled
      apply_dice_rolled!(event)
    when RobberMoved
      apply_robber_moved!(event)
    when TurnEnded
      apply_turn_ended!(event)
    else
      raise "Unhandled event type: #{event.class}"
    end

    refresh_derived_state!
    @version = event.version
  end

  private def apply_game_started!(event : GameStarted) : Nil
    @turn.phase = TurnPhase::Setup1Settlement
  end

  private def apply_settlement_placed!(event : SettlementPlaced) : Nil
    validate_settlement_placement!(event)
    player = player!(event.player_id)

    unless event.free
      player.hand.pay_settlement!
      @bank.deposit!(Resource::Wood)
      @bank.deposit!(Resource::Brick)
      @bank.deposit!(Resource::Sheep)
      @bank.deposit!(Resource::Wheat)
    end

    @board.buildings[event.vertex_id] = Building.new(event.player_id, BuildingKind::Settlement)
    player.settlements_left -= 1

    if @turn.phase == TurnPhase::Setup2Settlement
      grant_setup_resources!(player, event.vertex_id)
    end

    # setup phase progression example
    case @turn.phase
    when TurnPhase::Setup1Settlement
      @turn.phase = TurnPhase::Setup1Road
    when TurnPhase::Setup2Settlement
      @turn.phase = TurnPhase::Setup2Road
    end
  end

  private def apply_road_placed!(event : RoadPlaced) : Nil
    validate_road_placement!(event)
    player = player!(event.player_id)

    unless event.free
      player.hand.pay_road!
      @bank.deposit!(Resource::Wood)
      @bank.deposit!(Resource::Brick)
    end

    @board.roads[event.edge_id] = Road.new(event.player_id)
    player.roads_left -= 1

    case @turn.phase
    when TurnPhase::Setup1Road
      advance_setup_forward!
    when TurnPhase::Setup2Road
      advance_setup_reverse!
    end
  end

  private def apply_city_placed!(event : CityPlaced) : Nil
    validate_city_placement!(event)
    player = player!(event.player_id)

    player.hand.pay_city!
    @bank.deposit!(Resource::Wheat, 2)
    @bank.deposit!(Resource::Ore, 3)
    @board.buildings[event.vertex_id] = Building.new(event.player_id, BuildingKind::City)
    player.settlements_left += 1
    player.cities_left -= 1
  end

  private def apply_dice_rolled!(event : DiceRolled) : Nil
    validate_dice_roll!(event)
    distribute_resources!(event.total) unless event.total == 7
    @turn.phase = event.total == 7 ? TurnPhase::MoveRobber : TurnPhase::Main
  end

  private def apply_robber_moved!(event : RobberMoved) : Nil
    validate_robber_move!(event)
    @board.robber_tile_id = event.tile_id
    @turn.phase = TurnPhase::Main
  end

  private def apply_turn_ended!(event : TurnEnded) : Nil
    validate_turn_end!(event)

    idx = @player_order.index(@turn.current_player_id) || raise "current player missing"
    next_idx = (idx + 1) % @player_order.size

    @turn.current_player_id = @player_order[next_idx]
    @turn.number += 1 if next_idx == 0
    @turn.phase = TurnPhase::Roll
  end

  private def advance_setup_forward! : Nil
    idx = @player_order.index(@turn.current_player_id) || raise "current player missing"

    if idx == @player_order.size - 1
      @turn.phase = TurnPhase::Setup2Settlement
    else
      @turn.current_player_id = @player_order[idx + 1]
      @turn.phase = TurnPhase::Setup1Settlement
    end
  end

  private def advance_setup_reverse! : Nil
    idx = @player_order.index(@turn.current_player_id) || raise "current player missing"

    if idx == 0
      @turn.phase = TurnPhase::Roll
    else
      @turn.current_player_id = @player_order[idx - 1]
      @turn.phase = TurnPhase::Setup2Settlement
    end
  end

  private def distribute_resources!(total : Int32) : Nil
    demand_by_resource = Hash(Resource, Int32).new(0)
    grants = [] of Tuple(PlayerId, Resource, Int32)

    @board.tile_states.each do |tile_id, tile_state|
      next unless tile_state.token == total
      next if tile_id == @board.robber_tile_id
      next if tile_state.resource.desert?

      tile = @topology.tiles[tile_id]
      tile.vertex_ids.each do |vertex_id|
        next unless building = @board.building_at?(vertex_id)

        amount = building.kind.city? ? 2 : 1
        grants << {building.player_id, tile_state.resource, amount}
        demand_by_resource[tile_state.resource] += amount
      end
    end

    demand_by_resource.each do |resource, amount|
      next if amount.zero?
      next if @bank.resources.count(resource) < amount

      grants.each do |player_id, grant_resource, grant_amount|
        next unless grant_resource == resource
        grant_resource!(player!(player_id), resource, grant_amount)
      end
    end
  end

  private def grant_setup_resources!(player : PlayerState, vertex_id : VertexId) : Nil
    vertex = @topology.vertices[vertex_id]
    vertex.tile_ids.each do |tile_id|
      tile_state = @board.tile_states[tile_id]
      next if tile_state.resource.desert?

      grant_resource!(player, tile_state.resource)
    end
  end

  private def grant_resource!(player : PlayerState, resource : Resource, amount : Int32 = 1) : Nil
    @bank.withdraw!(resource, amount)
    player.hand.add(resource, amount)
  end

  private def refresh_derived_state! : Nil
    resolve_longest_road!
    resolve_largest_army!
    recalculate_victory_points!
    resolve_winner!
  end

  private def resolve_longest_road! : Nil
    road_lengths = Hash(PlayerId, Int32).new(0)
    @player_order.each do |player_id|
      road_lengths[player_id] = longest_road_for(player_id)
    end

    @longest_road_player_id = resolve_special_award_holder(road_lengths, @longest_road_player_id, 5)
    @longest_road_length = @longest_road_player_id ? road_lengths[@longest_road_player_id.not_nil!] : 0
  end

  private def resolve_largest_army! : Nil
    army_sizes = Hash(PlayerId, Int32).new(0)
    @player_order.each do |player_id|
      army_sizes[player_id] = player!(player_id).knights_played
    end

    @largest_army_player_id = resolve_special_award_holder(army_sizes, @largest_army_player_id, 3)
    @largest_army_size = @largest_army_player_id ? army_sizes[@largest_army_player_id.not_nil!] : 0
  end

  private def resolve_special_award_holder(values_by_player : Hash(PlayerId, Int32), current_holder : PlayerId?, threshold : Int32) : PlayerId?
    highest_value = values_by_player.values.max? || 0
    return nil if highest_value < threshold

    contenders = values_by_player.each_with_object([] of PlayerId) do |(player_id, value), memo|
      memo << player_id if value == highest_value
    end

    if current_holder && values_by_player[current_holder]? == highest_value
      return current_holder
    end

    contenders.size == 1 ? contenders.first : nil
  end

  private def recalculate_victory_points! : Nil
    points_by_player = Hash(PlayerId, Int32).new(0)

    @board.buildings.each_value do |building|
      points_by_player[building.player_id] += building.kind.city? ? 2 : 1
    end

    if player_id = @longest_road_player_id
      points_by_player[player_id] += 2
    end

    if player_id = @largest_army_player_id
      points_by_player[player_id] += 2
    end

    @player_order.each do |player_id|
      player!(player_id).victory_points = points_by_player[player_id]
    end
  end

  private def resolve_winner! : Nil
    return if @winner_player_id

    if current_player!.victory_points >= 10
      @winner_player_id = @turn.current_player_id
      @turn.phase = TurnPhase::GameOver
      return
    end

    winner = @player_order.find do |player_id|
      player!(player_id).victory_points >= 10
    end

    return unless winner

    @winner_player_id = winner
    @turn.phase = TurnPhase::GameOver
  end

  private def longest_road_for(player_id : PlayerId) : Int32
    @topology.vertices.keys.max_of? do |vertex_id|
      longest_road_from_vertex(vertex_id, player_id, [] of EdgeId)
    end || 0
  end

  private def longest_road_from_vertex(vertex_id : VertexId, player_id : PlayerId, used_edge_ids : Array(EdgeId)) : Int32
    longest = 0

    @topology.vertices[vertex_id].edge_ids.each do |edge_id|
      next if used_edge_ids.includes?(edge_id)
      road = @board.road_at?(edge_id)
      next unless road && road.player_id == player_id

      used_edge_ids << edge_id
      next_vertex_id = opposite_vertex_id(edge_id, vertex_id)
      continuation = opponent_building_blocks?(next_vertex_id, player_id) ? 0 : longest_road_from_vertex(next_vertex_id, player_id, used_edge_ids)
      candidate = 1 + continuation
      longest = Math.max(longest, candidate)
      used_edge_ids.pop
    end

    longest
  end

  private def opponent_building_blocks?(vertex_id : VertexId, player_id : PlayerId) : Bool
    if building = @board.building_at?(vertex_id)
      return building.player_id != player_id
    end

    false
  end

  private def opposite_vertex_id(edge_id : EdgeId, vertex_id : VertexId) : VertexId
    a, b = @topology.edges[edge_id].vertex_ids
    a == vertex_id ? b : a
  end

  private def validate_settlement_placement!(event : SettlementPlaced) : Nil
    raise "wrong player placed settlement" unless event.player_id == @turn.current_player_id
    raise "cannot place settlement during #{@turn.phase}" unless settlement_phase?(@turn.phase)
    raise "unknown vertex #{event.vertex_id.value}" unless @topology.vertices.has_key?(event.vertex_id)

    player = player!(event.player_id)
    raise "no settlements remaining" unless player.settlements_left > 0
    raise "vertex already occupied" if @board.occupied_vertex?(event.vertex_id)

    if @topology.neighboring_vertices(event.vertex_id).any? { |vertex_id| @board.occupied_vertex?(vertex_id) }
      raise "settlement must not be adjacent to another building"
    end

    if setup_settlement_phase?(@turn.phase)
      raise "setup settlements must be free" unless event.free
    else
      raise "free settlement placement is only allowed during setup" if event.free
      raise "settlement must connect to your road" unless connected_to_player_road?(event.vertex_id, event.player_id)
    end
  end

  private def validate_road_placement!(event : RoadPlaced) : Nil
    raise "wrong player placed road" unless event.player_id == @turn.current_player_id
    raise "cannot place road during #{@turn.phase}" unless road_phase?(@turn.phase)
    edge = @topology.edges[event.edge_id]? || raise "unknown edge #{event.edge_id.value}"

    player = player!(event.player_id)
    raise "no roads remaining" unless player.roads_left > 0
    raise "edge already occupied" if @board.occupied_edge?(event.edge_id)

    if setup_road_phase?(@turn.phase)
      raise "setup roads must be free" unless event.free

      settlement_vertex_id = pending_setup_settlement_vertex!(event.player_id)
      a, b = edge.vertex_ids
      raise "setup road must connect to the just-placed settlement" unless a == settlement_vertex_id || b == settlement_vertex_id
    else
      raise "free road placement is only allowed during setup" if event.free
      raise "road must connect to your network" unless road_connected_to_player_network?(event.edge_id, event.player_id)
    end
  end

  private def validate_city_placement!(event : CityPlaced) : Nil
    raise "wrong player placed city" unless event.player_id == @turn.current_player_id
    raise "can only place city during the main phase" unless @turn.phase.main?
    raise "unknown vertex #{event.vertex_id.value}" unless @topology.vertices.has_key?(event.vertex_id)

    player = player!(event.player_id)
    raise "no cities remaining" unless player.cities_left > 0

    building = @board.building_at?(event.vertex_id) || raise "city must upgrade an existing settlement"
    raise "city must upgrade your own settlement" unless building.player_id == event.player_id
    raise "city can only upgrade a settlement" unless building.kind.settlement?
  end

  private def validate_dice_roll!(event : DiceRolled) : Nil
    raise "can only roll dice during the roll phase" unless @turn.phase.roll?
    raise "dice total must be between 2 and 12" unless (2..12).includes?(event.total)
  end

  private def validate_robber_move!(event : RobberMoved) : Nil
    raise "wrong player moved robber" unless event.player_id == @turn.current_player_id
    raise "can only move robber after rolling a 7" unless @turn.phase.move_robber?
    raise "unknown tile #{event.tile_id.value}" unless @topology.tiles.has_key?(event.tile_id)
    raise "robber must move to a different tile" if event.tile_id == @board.robber_tile_id
  end

  private def validate_turn_end!(event : TurnEnded) : Nil
    raise "wrong player ended turn" unless event.player_id == @turn.current_player_id
    raise "can only end turn during the main phase" unless @turn.phase.main?
  end

  private def settlement_phase?(phase : TurnPhase) : Bool
    setup_settlement_phase?(phase) || phase.main?
  end

  private def setup_settlement_phase?(phase : TurnPhase) : Bool
    phase.setup1_settlement? || phase.setup2_settlement?
  end

  private def road_phase?(phase : TurnPhase) : Bool
    setup_road_phase?(phase) || phase.main?
  end

  private def setup_road_phase?(phase : TurnPhase) : Bool
    phase.setup1_road? || phase.setup2_road?
  end

  private def connected_to_player_road?(vertex_id : VertexId, player_id : PlayerId) : Bool
    player_road_ids_touching_vertex(vertex_id, player_id).any?
  end

  private def road_connected_to_player_network?(edge_id : EdgeId, player_id : PlayerId) : Bool
    edge = @topology.edges[edge_id]
    a, b = edge.vertex_ids

    vertex_connects_to_player_network?(a, player_id, edge_id) || vertex_connects_to_player_network?(b, player_id, edge_id)
  end

  private def vertex_connects_to_player_network?(vertex_id : VertexId, player_id : PlayerId, pending_edge_id : EdgeId) : Bool
    if building = @board.building_at?(vertex_id)
      return building.player_id == player_id
    end

    player_road_ids_touching_vertex(vertex_id, player_id, pending_edge_id).any?
  end

  private def pending_setup_settlement_vertex!(player_id : PlayerId) : VertexId
    candidate_vertices = @board.buildings.each_with_object([] of VertexId) do |(vertex_id, building), memo|
      next unless building.player_id == player_id
      next unless player_road_ids_touching_vertex(vertex_id, player_id).empty?
      memo << vertex_id
    end

    raise "missing setup settlement for road placement" unless candidate_vertices.size == 1
    candidate_vertices.first
  end

  private def player_road_ids_touching_vertex(vertex_id : VertexId, player_id : PlayerId, exclude_edge_id : EdgeId? = nil) : Array(EdgeId)
    @topology.vertices[vertex_id].edge_ids.select do |edge_id|
      next false if exclude_edge_id && edge_id == exclude_edge_id
      road = @board.road_at?(edge_id)
      !!road && road.player_id == player_id
    end
  end
end
