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

  def initialize(@current_player_id : PlayerId, @number : Int32, @phase : TurnPhase, @dev_card_played_this_turn = false)
  end
end

class PendingPlayerTrade
  getter player_id : PlayerId
  getter partner_player_id : PlayerId
  getter offered : ResourcePile
  getter requested : ResourcePile
  property accepted : Bool

  def initialize(@player_id : PlayerId, @partner_player_id : PlayerId, @offered : ResourcePile, @requested : ResourcePile, @accepted : Bool = false)
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
  property pending_player_trade : PendingPlayerTrade?
  property version : Int32

  def initialize(
    @topology : BoardTopology,
    @players : Hash(PlayerId, PlayerState),
    @settings : Hash(String, JSON::Any),
    @rng : Random = Random.new
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
    @pending_player_trade = nil
    @bank = Bank.new
    @player_order = @players.keys.shuffle(random: @rng)
    board_setup = BoardSetupGenerator.generate(@topology, @rng)
    @board = BoardState.new(
      tile_states: board_setup.tile_setups.map { |tile_setup| {tile_setup.tile_id, TileState.new(tile_setup.resource, tile_setup.token) } }.to_h,
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

  def player!(id : PlayerId) : PlayerState
    @players[id]? || raise "unknown player #{id.value}"
  end

  def current_player! : PlayerState
    player!(@turn.current_player_id)
  end
end
