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
    when DevelopmentCardPurchased
      apply_development_card_purchased!(event)
    when KnightPlayed
      apply_knight_played!(event)
    when RoadBuildingPlayed
      apply_road_building_played!(event)
    when MonopolyPlayed
      apply_monopoly_played!(event)
    when YearOfPlentyPlayed
      apply_year_of_plenty_played!(event)
    when PlayerTradeProposed
      apply_player_trade_proposed!(event)
    when PlayerTradeAccepted
      apply_player_trade_accepted!(event)
    when PlayerTradeRejected
      apply_player_trade_rejected!(event)
    when PlayerTradeCompleted
      apply_player_trade_completed!(event)
    when BankTradeCompleted
      apply_bank_trade_completed!(event)
    when DiceRolled
      apply_dice_rolled!(event)
    when RobberDiscarded
      apply_robber_discarded!(event)
    when RobberMoved
      apply_robber_moved!(event)
    when RobberStolen
      apply_robber_stolen!(event)
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

  private def apply_development_card_purchased!(event : DevelopmentCardPurchased) : Nil
    validate_development_card_purchase!(event)
    player = player!(event.player_id)

    player.hand.pay_development_card!
    @bank.deposit!(Resource::Sheep)
    @bank.deposit!(Resource::Wheat)
    @bank.deposit!(Resource::Ore)
    @bank.withdraw_dev_card!(event.card)
    player.newly_purchased_dev_cards.add(event.card)
  end

  private def apply_knight_played!(event : KnightPlayed) : Nil
    validate_knight_play!(event)
    player = player!(event.player_id)

    player.dev_cards.remove(DevCard::Knight)
    player.knights_played += 1
    @board.robber_tile_id = event.tile_id
    @turn.dev_card_played_this_turn = true
    advance_robber_after_move!(event.player_id, event.tile_id)
  end

  private def apply_road_building_played!(event : RoadBuildingPlayed) : Nil
    validate_road_building_play!(event)
    player = player!(event.player_id)

    player.dev_cards.remove(DevCard::RoadBuilding)
    place_road_from_dev_card!(player, event.first_edge_id)
    place_road_from_dev_card!(player, event.second_edge_id.not_nil!) if event.second_edge_id
    @turn.dev_card_played_this_turn = true
  end

  private def apply_monopoly_played!(event : MonopolyPlayed) : Nil
    validate_monopoly_play!(event)
    player = player!(event.player_id)
    total_taken = 0

    @player_order.each do |other_player_id|
      next if other_player_id == event.player_id

      other_player = player!(other_player_id)
      amount = other_player.hand.count(event.resource)
      next if amount.zero?

      other_player.hand.remove(event.resource, amount)
      total_taken += amount
    end

    player.dev_cards.remove(DevCard::Monopoly)
    player.hand.add(event.resource, total_taken)
    @turn.dev_card_played_this_turn = true
  end

  private def apply_year_of_plenty_played!(event : YearOfPlentyPlayed) : Nil
    validate_year_of_plenty_play!(event)
    player = player!(event.player_id)

    player.dev_cards.remove(DevCard::YearOfPlenty)
    grant_resource!(player, event.first_resource)
    grant_resource!(player, event.second_resource)
    @turn.dev_card_played_this_turn = true
  end

  private def apply_player_trade_proposed!(event : PlayerTradeProposed) : Nil
    validate_player_trade_proposed!(event)
    @pending_player_trade = PendingPlayerTrade.new(event.player_id, event.partner_player_id, event.offered, event.requested)
  end

  private def apply_player_trade_accepted!(event : PlayerTradeAccepted) : Nil
    validate_player_trade_accepted!(event)
    @pending_player_trade.not_nil!.accepted = true
  end

  private def apply_player_trade_rejected!(event : PlayerTradeRejected) : Nil
    validate_player_trade_rejected!(event)
    @pending_player_trade = nil
  end

  private def apply_player_trade_completed!(event : PlayerTradeCompleted) : Nil
    validate_player_trade_completed!(event)

    player = player!(event.player_id)
    partner = player!(event.partner_player_id)

    player.hand.transfer_to!(partner.hand, event.offered)
    partner.hand.transfer_to!(player.hand, event.requested)
    @pending_player_trade = nil
  end

  private def apply_bank_trade_completed!(event : BankTradeCompleted) : Nil
    validate_bank_trade_completed!(event)

    player = player!(event.player_id)
    offered_amount = bank_trade_rate_for(event.player_id, event.offered_resource)

    player.hand.remove(event.offered_resource, offered_amount)
    @bank.deposit!(event.offered_resource, offered_amount)
    grant_resource!(player, event.requested_resource)
  end

  private def apply_dice_rolled!(event : DiceRolled) : Nil
    validate_dice_roll!(event)
    @last_roll = DiceRoll.new(event.die_one, event.die_two)
    if event.total == 7
      @pending_robber_discards = players_requiring_robber_discard
      @robber_eligible_victim_ids.clear
      @turn.phase = @pending_robber_discards.empty? ? TurnPhase::MoveRobber : TurnPhase::DiscardResources
    else
      distribute_resources!(event.total)
      @turn.phase = TurnPhase::Main
    end
  end

  private def apply_robber_discarded!(event : RobberDiscarded) : Nil
    validate_robber_discard!(event)
    player = player!(event.player_id)

    player.hand.remove(event.discarded)
    event.discarded.each_nonzero do |resource, amount|
      @bank.deposit!(resource, amount)
    end

    @pending_robber_discards.delete(event.player_id)
    @turn.phase = TurnPhase::MoveRobber if @pending_robber_discards.empty?
  end

  private def apply_robber_moved!(event : RobberMoved) : Nil
    validate_robber_move!(event)
    @board.robber_tile_id = event.tile_id
    advance_robber_after_move!(event.player_id, event.tile_id)
  end

  private def apply_robber_stolen!(event : RobberStolen) : Nil
    validate_robber_stolen!(event)
    player = player!(event.player_id)
    victim = player!(event.victim_player_id)

    victim.hand.remove(event.resource)
    player.hand.add(event.resource)
    @robber_eligible_victim_ids.clear
    @turn.phase = TurnPhase::Main
  end

  private def apply_turn_ended!(event : TurnEnded) : Nil
    validate_turn_end!(event)
    player!(event.player_id).finalize_turn!
    @turn.dev_card_played_this_turn = false
    @pending_robber_discards.clear
    @robber_eligible_victim_ids.clear
    @pending_player_trade = nil

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
      points_by_player[player_id] += player!(player_id).revealed_victory_point_cards
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
    raise "dice values must be between 1 and 6" unless (1..6).includes?(event.die_one) && (1..6).includes?(event.die_two)
    raise "dice total must be between 2 and 12" unless (2..12).includes?(event.total)
  end

  private def validate_robber_discard!(event : RobberDiscarded) : Nil
    raise "can only discard during the robber discard phase" unless @turn.phase.discard_resources?
    expected = @pending_robber_discards[event.player_id]? || raise "player does not need to discard"
    raise "wrong discard count" unless event.discarded.total == expected
    raise "player does not have discarded resources" unless player!(event.player_id).hand.can_cover?(event.discarded)
  end

  private def validate_robber_move!(event : RobberMoved) : Nil
    raise "wrong player moved robber" unless event.player_id == @turn.current_player_id
    raise "can only move robber after rolling a 7" unless @turn.phase.move_robber?
    raise "unknown tile #{event.tile_id.value}" unless @topology.tiles.has_key?(event.tile_id)
    raise "robber must move to a different tile" if event.tile_id == @board.robber_tile_id
  end

  private def validate_robber_stolen!(event : RobberStolen) : Nil
    raise "wrong player stole with robber" unless event.player_id == @turn.current_player_id
    raise "can only steal after moving the robber" unless @turn.phase.steal_resource?
    raise "player is not an eligible robbery victim" unless @robber_eligible_victim_ids.includes?(event.victim_player_id)

    victim = player!(event.victim_player_id)
    raise "victim has no resources to steal" if victim.hand.total.zero?
    raise "stolen resource not in victim hand" unless victim.hand.count(event.resource) > 0
  end

  private def validate_turn_end!(event : TurnEnded) : Nil
    raise "wrong player ended turn" unless event.player_id == @turn.current_player_id
    raise "can only end turn during the main phase" unless @turn.phase.main?
  end

  private def validate_development_card_purchase!(event : DevelopmentCardPurchased) : Nil
    raise "wrong player bought development card" unless event.player_id == @turn.current_player_id
    raise "can only buy development cards during the main phase" unless @turn.phase.main?
    raise "no development cards remaining" if @bank.dev_cards_remaining.zero?
    raise "purchased development card does not match bank supply" unless @bank.count(event.card) > 0
  end

  private def validate_knight_play!(event : KnightPlayed) : Nil
    validate_dev_card_play!(event.player_id, DevCard::Knight)
    raise "unknown tile #{event.tile_id.value}" unless @topology.tiles.has_key?(event.tile_id)
    raise "robber must move to a different tile" if event.tile_id == @board.robber_tile_id
  end

  private def validate_road_building_play!(event : RoadBuildingPlayed) : Nil
    validate_dev_card_play!(event.player_id, DevCard::RoadBuilding)
    edge_ids = [event.first_edge_id] of EdgeId
    edge_ids << event.second_edge_id.not_nil! if event.second_edge_id
    raise "road building cannot place the same road twice" unless edge_ids.uniq.size == edge_ids.size

    player = player!(event.player_id)
    raise "not enough roads remaining" unless player.roads_left >= edge_ids.size

    planned_edge_ids = [] of EdgeId
    edge_ids.each do |edge_id|
      raise "unknown edge #{edge_id.value}" unless @topology.edges.has_key?(edge_id)
      raise "edge already occupied" if @board.occupied_edge?(edge_id)
      raise "road must connect to your network" unless road_connected_to_player_network_with_pending?(edge_id, event.player_id, planned_edge_ids)
      planned_edge_ids << edge_id
    end

    if event.second_edge_id.nil? && player.roads_left > planned_edge_ids.size && road_building_follow_up_available?(event.player_id, planned_edge_ids)
      raise "road building must place a second road when possible"
    end
  end

  private def validate_monopoly_play!(event : MonopolyPlayed) : Nil
    validate_dev_card_play!(event.player_id, DevCard::Monopoly)
    raise "cannot choose desert for monopoly" if event.resource.desert?
  end

  private def validate_year_of_plenty_play!(event : YearOfPlentyPlayed) : Nil
    validate_dev_card_play!(event.player_id, DevCard::YearOfPlenty)
    raise "cannot choose desert for year of plenty" if event.first_resource.desert? || event.second_resource.desert?

    if event.first_resource == event.second_resource
      raise "insufficient #{event.first_resource} in bank" unless @bank.resources.count(event.first_resource) >= 2
    else
      raise "insufficient #{event.first_resource} in bank" unless @bank.resources.count(event.first_resource) >= 1
      raise "insufficient #{event.second_resource} in bank" unless @bank.resources.count(event.second_resource) >= 1
    end
  end

  private def validate_player_trade_proposed!(event : PlayerTradeProposed) : Nil
    validate_player_trade_payload!(event.player_id, event.partner_player_id, event.offered, event.requested)
    raise "trade already pending" if @pending_player_trade
  end

  private def validate_player_trade_accepted!(event : PlayerTradeAccepted) : Nil
    pending_trade = pending_player_trade! 
    raise "trade acceptor must match proposed partner" unless event.player_id == pending_trade.partner_player_id
    raise "trade proposer mismatch" unless event.partner_player_id == pending_trade.player_id
    raise "can only accept trades during the main phase" unless @turn.phase.main?
    raise "trade already accepted" if pending_trade.accepted

    player = player!(pending_trade.player_id)
    partner = player!(pending_trade.partner_player_id)

    raise "player does not have offered resources" unless player.hand.can_cover?(pending_trade.offered)
    raise "trading partner does not have requested resources" unless partner.hand.can_cover?(pending_trade.requested)
  end

  private def validate_player_trade_rejected!(event : PlayerTradeRejected) : Nil
    pending_trade = pending_player_trade!
    raise "trade rejector must be part of the trade" unless [pending_trade.player_id, pending_trade.partner_player_id].includes?(event.player_id)
    raise "trade partner mismatch" unless [pending_trade.player_id, pending_trade.partner_player_id].includes?(event.partner_player_id)
    raise "can only reject trades during the main phase" unless @turn.phase.main?
  end

  private def validate_player_trade_completed!(event : PlayerTradeCompleted) : Nil
    pending_trade = pending_player_trade!
    validate_player_trade_payload!(event.player_id, event.partner_player_id, event.offered, event.requested)
    raise "trade must be accepted before completion" unless pending_trade.accepted
    raise "trade completion does not match pending trade" unless event.player_id == pending_trade.player_id &&
      event.partner_player_id == pending_trade.partner_player_id &&
      event.offered == pending_trade.offered &&
      event.requested == pending_trade.requested
  end

  private def validate_bank_trade_completed!(event : BankTradeCompleted) : Nil
    raise "wrong player completed bank trade" unless event.player_id == @turn.current_player_id
    raise "can only trade during the main phase" unless @turn.phase.main?
    raise "cannot trade desert with the bank" if event.offered_resource.desert? || event.requested_resource.desert?
    raise "bank trade must change resources" if event.offered_resource == event.requested_resource

    player = player!(event.player_id)
    offered_amount = bank_trade_rate_for(event.player_id, event.offered_resource)

    raise "player does not have enough #{event.offered_resource} to trade" unless player.hand.count(event.offered_resource) >= offered_amount
    raise "insufficient #{event.requested_resource} in bank" unless @bank.resources.count(event.requested_resource) >= 1
  end

  private def has_negative_resources?(pile : ResourcePile) : Bool
    pile.wood < 0 || pile.brick < 0 || pile.sheep < 0 || pile.wheat < 0 || pile.ore < 0
  end

  private def validate_player_trade_payload!(player_id : PlayerId, partner_player_id : PlayerId, offered : ResourcePile, requested : ResourcePile) : Nil
    raise "wrong player completed trade" unless player_id == @turn.current_player_id
    raise "can only trade during the main phase" unless @turn.phase.main?
    raise "cannot trade with yourself" if partner_player_id == player_id
    raise "unknown trading partner #{partner_player_id.value}" unless @players.has_key?(partner_player_id)
    raise "trade offer cannot contain negative resource counts" if has_negative_resources?(offered)
    raise "trade request cannot contain negative resource counts" if has_negative_resources?(requested)
    raise "trade offer cannot be empty" if offered.empty?
    raise "trade request cannot be empty" if requested.empty?

    player = player!(player_id)
    partner = player!(partner_player_id)

    raise "player does not have offered resources" unless player.hand.can_cover?(offered)
    raise "trading partner does not have requested resources" unless partner.hand.can_cover?(requested)
  end

  private def pending_player_trade! : PendingPlayerTrade
    @pending_player_trade || raise "no pending player trade"
  end

  private def players_requiring_robber_discard : Hash(PlayerId, Int32)
    @player_order.each_with_object({} of PlayerId => Int32) do |player_id, memo|
      total = player!(player_id).hand.total
      memo[player_id] = total // 2 if total > 7
    end
  end

  private def advance_robber_after_move!(player_id : PlayerId, tile_id : TileId) : Nil
    @robber_eligible_victim_ids = robber_eligible_victims(player_id, tile_id)
    @turn.phase = @robber_eligible_victim_ids.empty? ? TurnPhase::Main : TurnPhase::StealResource
  end

  private def robber_eligible_victims(player_id : PlayerId, tile_id : TileId) : Array(PlayerId)
    @topology.tiles[tile_id].vertex_ids.each_with_object([] of PlayerId) do |vertex_id, memo|
      next unless building = @board.building_at?(vertex_id)
      next if building.player_id == player_id
      next if player!(building.player_id).hand.total.zero?
      memo << building.player_id unless memo.includes?(building.player_id)
    end
  end

  private def validate_dev_card_play!(player_id : PlayerId, card : DevCard) : Nil
    raise "wrong player played development card" unless player_id == @turn.current_player_id
    raise "can only play development cards during the main phase" unless @turn.phase.main?
    raise "can only play one development card per turn" if @turn.dev_card_played_this_turn

    player = player!(player_id)
    raise "player does not have #{card}" unless player.available_dev_cards(card) > 0
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

  private def road_connected_to_player_network_with_pending?(edge_id : EdgeId, player_id : PlayerId, pending_edge_ids : Array(EdgeId)) : Bool
    edge = @topology.edges[edge_id]
    a, b = edge.vertex_ids

    vertex_connects_to_player_network_with_pending?(a, player_id, edge_id, pending_edge_ids) || vertex_connects_to_player_network_with_pending?(b, player_id, edge_id, pending_edge_ids)
  end

  private def vertex_connects_to_player_network?(vertex_id : VertexId, player_id : PlayerId, pending_edge_id : EdgeId) : Bool
    if building = @board.building_at?(vertex_id)
      return building.player_id == player_id
    end

    player_road_ids_touching_vertex(vertex_id, player_id, pending_edge_id).any?
  end

  private def vertex_connects_to_player_network_with_pending?(vertex_id : VertexId, player_id : PlayerId, pending_edge_id : EdgeId, pending_edge_ids : Array(EdgeId)) : Bool
    if building = @board.building_at?(vertex_id)
      return building.player_id == player_id
    end

    player_road_ids_touching_vertex_with_pending(vertex_id, player_id, pending_edge_id, pending_edge_ids).any?
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

  private def player_road_ids_touching_vertex_with_pending(vertex_id : VertexId, player_id : PlayerId, exclude_edge_id : EdgeId? = nil, pending_edge_ids : Array(EdgeId) = [] of EdgeId) : Array(EdgeId)
    @topology.vertices[vertex_id].edge_ids.select do |edge_id|
      next false if exclude_edge_id && edge_id == exclude_edge_id
      next true if pending_edge_ids.includes?(edge_id)

      road = @board.road_at?(edge_id)
      !!road && road.player_id == player_id
    end
  end

  private def road_building_follow_up_available?(player_id : PlayerId, pending_edge_ids : Array(EdgeId)) : Bool
    @topology.edges.each_key.any? do |edge_id|
      next false if pending_edge_ids.includes?(edge_id)
      next false if @board.occupied_edge?(edge_id)

      road_connected_to_player_network_with_pending?(edge_id, player_id, pending_edge_ids)
    end
  end

  private def place_road_from_dev_card!(player : PlayerState, edge_id : EdgeId) : Nil
    @board.roads[edge_id] = Road.new(player.id)
    player.roads_left -= 1
  end

  private def bank_trade_rate_for(player_id : PlayerId, resource : Resource) : Int32
    return 4 if resource.desert?

    best_rate = 4

    @board.harbors.each do |harbor|
      next unless player_controls_harbor?(player_id, harbor)

      rate = harbor_trade_rate(harbor.kind, resource)
      best_rate = Math.min(best_rate, rate) if rate
    end

    best_rate
  end

  private def player_controls_harbor?(player_id : PlayerId, harbor : HarborAssignment) : Bool
    harbor.vertex_ids.any? do |vertex_id|
      if building = @board.building_at?(vertex_id)
        building.player_id == player_id
      else
        false
      end
    end
  end

  private def harbor_trade_rate(kind : HarborKind, resource : Resource) : Int32?
    case kind
    when .three_to_one?
      3
    when .wood_two_to_one?
      resource.wood? ? 2 : nil
    when .brick_two_to_one?
      resource.brick? ? 2 : nil
    when .sheep_two_to_one?
      resource.sheep? ? 2 : nil
    when .wheat_two_to_one?
      resource.wheat? ? 2 : nil
    when .ore_two_to_one?
      resource.ore? ? 2 : nil
    end
  end
end
