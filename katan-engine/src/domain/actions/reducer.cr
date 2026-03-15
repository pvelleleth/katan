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
    when DiceRolled
      apply_dice_rolled!(event)
    when RobberMoved
      apply_robber_moved!(event)
    when TurnEnded
      apply_turn_ended!(event)
    else
      raise "Unhandled event type: #{event.class}"
    end

    @version = event.version
  end

  private def apply_game_started!(event : GameStarted) : Nil
    @turn.phase = TurnPhase::Setup1Settlement
  end

  private def apply_settlement_placed!(event : SettlementPlaced) : Nil
    player = player!(event.player_id)

    @board.buildings[event.vertex_id] = Building.new(event.player_id, BuildingKind::Settlement)
    player.settlements_left -= 1
    player.victory_points += 1

    unless event.free
      player.hand.pay_settlement!
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
    player = player!(event.player_id)

    @board.roads[event.edge_id] = Road.new(event.player_id)
    player.roads_left -= 1

    unless event.free
      player.hand.pay_road!
    end

    case @turn.phase
    when TurnPhase::Setup1Road
      advance_setup_forward!
    when TurnPhase::Setup2Road
      advance_setup_reverse!
    end
  end

  private def apply_dice_rolled!(event : DiceRolled) : Nil
    distribute_resources!(event.total) unless event.total == 7
    @turn.phase = event.total == 7 ? TurnPhase::MoveRobber : TurnPhase::Main
  end

  private def apply_robber_moved!(event : RobberMoved) : Nil
    @board.robber_tile_id = event.tile_id
    @turn.phase = TurnPhase::Main
  end

  private def apply_turn_ended!(event : TurnEnded) : Nil
    raise "wrong player ended turn" unless event.player_id == @turn.current_player_id

    idx = @player_order.index(@turn.current_player_id) || raise "current player missing"
    next_idx = (idx + 1) % @player_order.size

    @turn.current_player_id = @player_order[next_idx]
    @turn.number += 1 if next_idx == 0
    @turn.phase = TurnPhase::Roll
  end
end
