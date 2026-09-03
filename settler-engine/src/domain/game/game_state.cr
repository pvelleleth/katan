require "./topology"
require "./bank"
require "../board/board_state"

enum TurnPhase
  Lobby
  Setup1Settlement
  Setup1Road
  Setup2Settlement
  Setup2Road
  Roll
  DiscardResources
  Main
  MoveRobber
  StealResource
  GameOver
end

enum TurnRole
  Regular
  PairedSecondary
  SpecialBuild
end

class ResourceHand
  property wood : Int32
  property brick : Int32
  property sheep : Int32
  property wheat : Int32
  property ore : Int32

  def initialize(@wood = 0, @brick = 0, @sheep = 0, @wheat = 0, @ore = 0)
  end

  def pay_road!
    raise "cannot afford road" unless @wood >= 1 && @brick >= 1
    @wood -= 1
    @brick -= 1
  end

  def pay_settlement!
    raise "cannot afford settlement" unless @wood >= 1 && @brick >= 1 && @sheep >= 1 && @wheat >= 1
    @wood -= 1
    @brick -= 1
    @sheep -= 1
    @wheat -= 1
  end

  def pay_city!
    raise "cannot afford city" unless @wheat >= 2 && @ore >= 3
    @wheat -= 2
    @ore -= 3
  end

  def can_afford_development_card? : Bool
    @sheep >= 1 && @wheat >= 1 && @ore >= 1
  end

  def pay_development_card!
    raise "cannot afford development card" unless can_afford_development_card?
    @sheep -= 1
    @wheat -= 1
    @ore -= 1
  end

  def add(resource : Resource, amount : Int32 = 1)
    case resource
    when .wood?  then @wood += amount
    when .brick? then @brick += amount
    when .sheep? then @sheep += amount
    when .wheat? then @wheat += amount
    when .ore?   then @ore += amount
    else
      # desert ignored
    end
  end

  def count(resource : Resource) : Int32
    case resource
    when .wood?  then @wood
    when .brick? then @brick
    when .sheep? then @sheep
    when .wheat? then @wheat
    when .ore?   then @ore
    else
      0
    end
  end

  def remove(resource : Resource, amount : Int32 = 1) : Nil
    raise "insufficient #{resource} in hand" unless count(resource) >= amount
    add(resource, -amount)
  end

  def can_cover?(pile : ResourcePile) : Bool
    count(Resource::Wood) >= pile.wood &&
      count(Resource::Brick) >= pile.brick &&
      count(Resource::Sheep) >= pile.sheep &&
      count(Resource::Wheat) >= pile.wheat &&
      count(Resource::Ore) >= pile.ore
  end

  def total : Int32
    @wood + @brick + @sheep + @wheat + @ore
  end

  def add(pile : ResourcePile) : Nil
    pile.each_nonzero do |resource, amount|
      add(resource, amount)
    end
  end

  def remove(pile : ResourcePile) : Nil
    raise "insufficient resources in hand" unless can_cover?(pile)

    pile.each_nonzero do |resource, amount|
      remove(resource, amount)
    end
  end

  def transfer_to!(other : ResourceHand, pile : ResourcePile) : Nil
    remove(pile)
    other.add(pile)
  end
end

class PlayerState
  getter id : PlayerId
  property name : String
  getter hand : ResourceHand
  property roads_left : Int32
  property settlements_left : Int32
  property cities_left : Int32
  property knights_played : Int32
  property victory_points : Int32
  getter dev_cards : DevCardHand
  getter newly_purchased_dev_cards : DevCardHand

  def initialize(@id : PlayerId, @name : String)
    @hand = ResourceHand.new
    @roads_left = 15
    @settlements_left = 5
    @cities_left = 4
    @knights_played = 0
    @victory_points = 0
    @dev_cards = DevCardHand.new
    @newly_purchased_dev_cards = DevCardHand.new
  end

  def total_dev_cards : Int32
    @dev_cards.total + @newly_purchased_dev_cards.total
  end

  def available_dev_cards(card : DevCard) : Int32
    @dev_cards.count(card)
  end

  def revealed_victory_point_cards : Int32
    @dev_cards.victory_point + @newly_purchased_dev_cards.victory_point
  end

  def finalize_turn! : Nil
    @dev_cards.merge!(@newly_purchased_dev_cards)
  end
end

class TurnState
  property current_player_id : PlayerId
  property number : Int32
  property phase : TurnPhase
  property dev_card_played_this_turn : Bool
  property timer_started_at : Time?
  property timer_expires_at : Time?
  property timer_duration_seconds : Int32?
  property role : TurnRole
  property primary_player_id : PlayerId
  property special_build_remaining_player_ids : Array(PlayerId)

  def initialize(
    @current_player_id : PlayerId,
    @number : Int32,
    @phase : TurnPhase,
    @dev_card_played_this_turn = false,
    @timer_started_at : Time? = nil,
    @timer_expires_at : Time? = nil,
    @timer_duration_seconds : Int32? = nil,
    @role : TurnRole = TurnRole::Regular,
    primary_player_id : PlayerId? = nil,
    @special_build_remaining_player_ids : Array(PlayerId) = [] of PlayerId,
  )
    @primary_player_id = primary_player_id || @current_player_id
  end
end

enum PlayerTradeResponseStatus
  Accepted
  Rejected
end

class PendingPlayerTrade
  getter id : Int32
  getter player_id : PlayerId
  getter offered : ResourcePile
  getter requested : ResourcePile
  getter responses : Hash(PlayerId, PlayerTradeResponseStatus)

  def initialize(
    @id : Int32,
    @player_id : PlayerId,
    @offered : ResourcePile,
    @requested : ResourcePile,
    @responses = {} of PlayerId => PlayerTradeResponseStatus,
  )
  end

  def set_response!(player_id : PlayerId, status : PlayerTradeResponseStatus) : Nil
    @responses[player_id] = status
  end

  def clear_response!(player_id : PlayerId) : Nil
    @responses.delete(player_id)
  end

  def response_for(player_id : PlayerId) : PlayerTradeResponseStatus?
    @responses[player_id]?
  end

  def accepted_by?(player_id : PlayerId) : Bool
    response_for(player_id).try(&.accepted?) || false
  end

  def accepted_player_ids : Array(PlayerId)
    @responses.compact_map do |target_player_id, status|
      status.accepted? ? target_player_id : nil
    end
  end

  def rejected_player_ids : Array(PlayerId)
    @responses.compact_map do |target_player_id, status|
      status.rejected? ? target_player_id : nil
    end
  end
end

struct DiceRoll
  getter die_one : Int32
  getter die_two : Int32
  getter total : Int32

  def initialize(@die_one : Int32, @die_two : Int32)
    @total = @die_one + @die_two
  end
end

class GameState
  getter topology : BoardTopology
  getter board : BoardState
  getter bank : Bank
  getter players : Hash(PlayerId, PlayerState)
  getter player_order : Array(PlayerId)
  getter turn : TurnState
  getter settings : Hash(String, JSON::Any)
  property last_roll : DiceRoll?
  property longest_road_player_id : PlayerId?
  property longest_road_length : Int32
  property largest_army_player_id : PlayerId?
  property largest_army_size : Int32
  property winner_player_id : PlayerId?
  property pending_robber_discards : Hash(PlayerId, Int32)
  property robber_eligible_victim_ids : Array(PlayerId)
  property robber_return_phase : TurnPhase?
  property pending_player_trades : Array(PendingPlayerTrade)
  property next_player_trade_id : Int32
  property version : Int32

  def initialize(
    @topology : BoardTopology,
    @players : Hash(PlayerId, PlayerState),
    @settings : Hash(String, JSON::Any),
    @rng : Random = Random.new,
  )
    @version = 0
    @last_roll = nil
    @longest_road_player_id = nil
    @longest_road_length = 0
    @largest_army_player_id = nil
    @largest_army_size = 0
    @winner_player_id = nil
    @pending_robber_discards = {} of PlayerId => Int32
    @robber_eligible_victim_ids = [] of PlayerId
    @robber_return_phase = nil
    @pending_player_trades = [] of PendingPlayerTrade
    @next_player_trade_id = 1
    @bank = five_six_extension? ? Bank.five_six_extension : Bank.new
    @player_order = @players.keys.shuffle(random: @rng)
    board_setup = BoardSetupGenerator.generate(@topology, @rng)
    @board = BoardState.new(
      tile_states: board_setup.tile_setups.map { |tile_setup| {tile_setup.tile_id, TileState.new(tile_setup.resource, tile_setup.token)} }.to_h,
      robber_tile_id: board_setup.robber_tile_id,
      harbors: board_setup.harbors,
      buildings: {} of VertexId => Building,
      roads: {} of EdgeId => Road
    )
    @turn = TurnState.new(
      current_player_id: @player_order[0],
      number: 1,
      phase: TurnPhase::Setup1Settlement
    )
  end

  def initialize(
    @topology : BoardTopology,
    @players : Hash(PlayerId, PlayerState),
    @settings : Hash(String, JSON::Any),
    @board : BoardState,
    @bank : Bank,
    @player_order : Array(PlayerId),
    @turn : TurnState,
    @version : Int32,
    @rng : Random = Random.new,
    @last_roll : DiceRoll? = nil,
    @longest_road_player_id : PlayerId? = nil,
    @longest_road_length : Int32 = 0,
    @largest_army_player_id : PlayerId? = nil,
    @largest_army_size : Int32 = 0,
    @winner_player_id : PlayerId? = nil,
    @pending_robber_discards : Hash(PlayerId, Int32) = {} of PlayerId => Int32,
    @robber_eligible_victim_ids : Array(PlayerId) = [] of PlayerId,
    @robber_return_phase : TurnPhase? = nil,
    @pending_player_trades : Array(PendingPlayerTrade) = [] of PendingPlayerTrade,
    @next_player_trade_id : Int32 = 1,
  )
  end

  def pending_player_trade(trade_id : Int32) : PendingPlayerTrade?
    @pending_player_trades.find { |trade| trade.id == trade_id }
  end

  def allocate_next_player_trade_id! : Int32
    id = @next_player_trade_id
    @next_player_trade_id += 1
    id
  end

  def player!(id : PlayerId) : PlayerState
    @players[id]? || raise "unknown player #{id.value}"
  end

  def current_player! : PlayerState
    player!(@turn.current_player_id)
  end

  def five_six_extension? : Bool
    @settings["gameMode"]?.try(&.as_s) == "fiveSixExtension"
  end

  def five_six_turn_rule : String
    @settings["fiveSixTurnRule"]?.try(&.as_s) || "paired"
  end

  def paired_turns? : Bool
    five_six_extension? && five_six_turn_rule == "paired"
  end

  def special_build_turns? : Bool
    five_six_extension? && five_six_turn_rule == "specialBuild"
  end

  def victory_point_target : Int32
    @settings["victoryPoints"]?.try(&.as_i.to_i32) || 10
  end

  def turn_timer_enabled? : Bool
    @settings["turnTimerEnabled"]?.try(&.as_bool) != false
  end

  def configured_turn_time_seconds : Int32
    @settings["turnTimeSeconds"]?.try(&.as_i.to_i32) || 120
  end

  def timer_duration_for_phase(phase : TurnPhase = @turn.phase) : Int32?
    case phase
    when .setup1_settlement?, .setup2_settlement?
      configured_turn_time_seconds * 2
    when .setup1_road?, .setup2_road?
      configured_turn_time_seconds // 2
    when .roll?
      7
    when .discard_resources?, .main?, .move_robber?, .steal_resource?
      configured_turn_time_seconds
    when .lobby?, .game_over?
      nil
    else
      @turn.timer_duration_seconds || configured_turn_time_seconds
    end
  end

  def clear_turn_timer! : Nil
    @turn.timer_started_at = nil
    @turn.timer_expires_at = nil
    @turn.timer_duration_seconds = nil
  end

  def start_turn_timer!(duration_seconds : Int32, now : Time = Time.utc) : Nil
    @turn.timer_started_at = now
    @turn.timer_duration_seconds = duration_seconds
    @turn.timer_expires_at = now + duration_seconds.seconds
  end

  def extend_turn_timer!(seconds : Int32, now : Time = Time.utc) : Nil
    return unless turn_timer_enabled?
    return unless expires_at = @turn.timer_expires_at

    base_time = expires_at < now ? now : expires_at
    started_at = @turn.timer_started_at || now
    duration_seconds = @turn.timer_duration_seconds || seconds
    extension = base_time + seconds.seconds

    @turn.timer_started_at = started_at
    @turn.timer_expires_at = extension
    @turn.timer_duration_seconds = (extension - started_at).total_seconds.to_i32
  end
end
