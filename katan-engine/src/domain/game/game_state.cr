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
  Main
  MoveRobber
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
end

class PlayerState
  getter id : PlayerId
  property name : String
  getter hand : ResourceHand
  property roads_left : Int32
  property settlements_left : Int32
  property cities_left : Int32
  property victory_points : Int32

  def initialize(@id : PlayerId, @name : String)
    @hand = ResourceHand.new
    @roads_left = 15
    @settlements_left = 5
    @cities_left = 4
    @victory_points = 0
  end
end

class TurnState
  property current_player_id : PlayerId
  property number : Int32
  property phase : TurnPhase

  def initialize(@current_player_id : PlayerId, @number : Int32, @phase : TurnPhase)
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
  property version : Int32

  def initialize(
    @topology : BoardTopology,
    @players : Hash(PlayerId, PlayerState),
    @settings : Hash(String, JSON::Any)
  )
    @version = 0
    @bank = Bank.new
    rng = Random.new
    @player_order = @players.keys.shuffle(random: rng)
    board_setup = BoardSetupGenerator.generate(@topology, rng)
    @board = BoardState.new(
      tile_states: board_setup.tile_setups.map { |tile_setup| {tile_setup.tile_id, TileState.new(tile_setup.resource, tile_setup.token) } }.to_h,
      robber_tile_id: board_setup.robber_tile_id,
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
