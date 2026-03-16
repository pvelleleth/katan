require "./spec_helper"

class FixedDiceRoller < Settler::Engine::Application::DiceRoller
  getter rolls : Array(DiceRoll)

  def initialize(@rolls : Array(DiceRoll))
  end

  def roll : DiceRoll
    @rolls.shift? || raise "no fixed dice rolls remaining"
  end
end

class RecordingGameEventStore < Settler::Engine::Infrastructure::Persistence::GameEventStore
  getter settings_updates = [] of NamedTuple(lobby_code: String, settings_json: String)
  getter events = [] of NamedTuple(
    lobby_code: String,
    event_type: String,
    actor_player_id: String?,
    turn_number: Int32?,
    phase: String?,
    payload_json: String,
    message: String?)
  getter snapshots = [] of NamedTuple(lobby_code: String, snapshot_json: String, snapshot_version: Int32)

  def update_game_settings(lobby_code : String, settings_json : String) : Nil
    @settings_updates << {lobby_code: lobby_code, settings_json: settings_json}
  end

  def append(
    lobby_code : String,
    event_type : String,
    actor_player_id : String? = nil,
    turn_number : Int32? = nil,
    phase : String? = nil,
    payload_json : String = "{}",
    message : String? = nil,
  ) : Nil
    @events << {
      lobby_code:      lobby_code,
      event_type:      event_type,
      actor_player_id: actor_player_id,
      turn_number:     turn_number,
      phase:           phase,
      payload_json:    payload_json,
      message:         message,
    }
  end

  def save_game_snapshot(lobby_code : String, snapshot_json : String, snapshot_version : Int32) : Nil
    @snapshots << {lobby_code: lobby_code, snapshot_json: snapshot_json, snapshot_version: snapshot_version}
  end
end

describe Settler::Engine::Application::LobbyManager do
  it "appends and applies every current gameplay action path" do
    store = RecordingGameEventStore.new
    manager = Settler::Engine::Application::LobbyManager.new(store, FixedDiceRoller.new([DiceRoll.new(3, 4)]))
    lobby = manager.get_or_create_lobby("ABC123")
    lobby.host_id = "player-1"
    lobby.add_player(Settler::Engine::Domain::Player.new("player-1", "Alice"))
    lobby.add_player(Settler::Engine::Domain::Player.new("player-2", "Bob"))

    manager.start_game("ABC123")

    game_state = manager.games["ABC123"]
    first_player = game_state.turn.current_player_id.value
    second_player = (game_state.player_order - [game_state.turn.current_player_id]).first.value

    complete_setup_through_manager!(manager, "ABC123")
    city_vertex = game_state.board.buildings.find do |_, building|
      building.player_id.value == first_player && building.kind.settlement?
    end.not_nil![0].value

    game_state.player!(PlayerId.new(first_player)).hand.wheat = 2
    game_state.player!(PlayerId.new(first_player)).hand.ore = 3
    game_state.turn.phase = TurnPhase::Main
    manager.place_city("ABC123", first_player, city_vertex)
    game_state.turn.phase = TurnPhase::Roll

    robber_target = game_state.topology.tiles.keys.sort_by(&.value).find do |tile_id|
      tile_id != game_state.board.robber_tile_id
    end.not_nil!.value
    robber_vertex_id = game_state.topology.tiles[TileId.new(robber_target)].vertex_ids.first
    game_state.board.buildings[robber_vertex_id] = Building.new(PlayerId.new(second_player), BuildingKind::Settlement)
    victim_hand = game_state.player!(PlayerId.new(second_player)).hand
    victim_hand.wood = 1
    victim_hand.brick = 0
    victim_hand.sheep = 0
    victim_hand.wheat = 0
    victim_hand.ore = 0

    manager.roll_dice("ABC123", first_player)
    manager.move_robber("ABC123", first_player, robber_target)
    manager.robber_steal("ABC123", first_player, second_player)
    manager.end_turn("ABC123", first_player)

    store.events.map(&.[:event_type]).should eq([
      "game_started",
      "settlement_placed",
      "road_placed",
      "settlement_placed",
      "road_placed",
      "settlement_placed",
      "road_placed",
      "settlement_placed",
      "road_placed",
      "city_placed",
      "dice_rolled",
      "robber_moved",
      "robber_stolen",
      "turn_ended",
    ])

    final_state = manager.games["ABC123"]
    final_state.version.should eq(14)
    final_state.turn.current_player_id.value.should eq(second_player)
    final_state.turn.phase.should eq(TurnPhase::Roll)
    final_state.last_roll.not_nil!.die_one.should eq(3)
    final_state.last_roll.not_nil!.die_two.should eq(4)
    final_state.last_roll.not_nil!.total.should eq(7)
    final_state.player!(PlayerId.new(second_player)).hand.wood.should eq(0)
  end

  it "persists full hands in game_started payloads and saved snapshots" do
    store = RecordingGameEventStore.new
    dice_roller = FixedDiceRoller.new([] of DiceRoll)
    manager = Settler::Engine::Application::LobbyManager.new(store, dice_roller)
    first_client = Settler::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
    first_client.lobby_id = "DEF456"
    second_client = Settler::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
    second_client.lobby_id = "DEF456"

    manager.handle_join("DEF456", "player-1", "Alice", first_client, "player-1")
    manager.handle_join("DEF456", "player-2", "Bob", second_client)

    manager.start_game("DEF456")

    started_payload = JSON.parse(store.events.first[:payload_json])
    started_players = started_payload["players"].as_a
    started_players.each do |player_json|
      hand = player_json["hand"]?
      hand.should_not be_nil
      hand = hand.not_nil!
      hand["wood"].as_i.should eq(0)
      hand["brick"].as_i.should eq(0)
      hand["sheep"].as_i.should eq(0)
      hand["wheat"].as_i.should eq(0)
      hand["ore"].as_i.should eq(0)
    end

    game_state = manager.games["DEF456"]
    complete_setup_through_manager!(manager, "DEF456")

    producer_tile_id, producer_tile_state = game_state.board.tile_states.find do |tile_id, state|
      next false unless state.token && !state.resource.desert?

      game_state.topology.tiles[tile_id].vertex_ids.any? do |vertex_id|
        building = game_state.board.building_at?(vertex_id)
        building && building.player_id == game_state.turn.current_player_id
      end
    end.not_nil!
    target_total = producer_tile_state.token.not_nil!
    die_one = target_total > 6 ? 6 : 1
    die_two = target_total - die_one
    dice_roller.rolls << DiceRoll.new(die_one, die_two)
    producer_vertex_id = game_state.topology.tiles[producer_tile_id].vertex_ids.find do |vertex_id|
      building = game_state.board.building_at?(vertex_id)
      building && building.player_id == game_state.turn.current_player_id
    end.not_nil!

    game_state.board.buildings[producer_vertex_id] = Building.new(game_state.turn.current_player_id, BuildingKind::City)
    game_state.turn.phase = TurnPhase::Roll
    manager.roll_dice("DEF456", game_state.turn.current_player_id.value)

    snapshot_json = JSON.parse(store.snapshots.last[:snapshot_json])
    snapshot_json["last_roll"]["die_one"].as_i.should eq(die_one)
    snapshot_json["last_roll"]["die_two"].as_i.should eq(die_two)
    snapshot_json["last_roll"]["total"].as_i.should eq(target_total)
    snapshot_players = snapshot_json["players"].as_a
    snapshot_players.each do |player_json|
      player_json["hand"]?.should_not be_nil
    end

    snapshot_players.each do |player_json|
      player = game_state.player!(PlayerId.new(player_json["id"].as_s))
      snapshot_hand = player_json["hand"]
      snapshot_hand["wood"].as_i.should eq(player.hand.wood)
      snapshot_hand["brick"].as_i.should eq(player.hand.brick)
      snapshot_hand["sheep"].as_i.should eq(player.hand.sheep)
      snapshot_hand["wheat"].as_i.should eq(player.hand.wheat)
      snapshot_hand["ore"].as_i.should eq(player.hand.ore)
    end
  end

  it "persists robber discards and exposes pending discard state" do
    store = RecordingGameEventStore.new
    manager = Settler::Engine::Application::LobbyManager.new(store, FixedDiceRoller.new([DiceRoll.new(3, 4)]))
    first_client = Settler::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
    first_client.lobby_id = "GHI789"
    second_client = Settler::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
    second_client.lobby_id = "GHI789"

    manager.handle_join("GHI789", "player-1", "Alice", first_client, "player-1")
    manager.handle_join("GHI789", "player-2", "Bob", second_client)

    manager.start_game("GHI789")
    complete_setup_through_manager!(manager, "GHI789")

    game_state = manager.games["GHI789"]
    current_player_id = game_state.turn.current_player_id.value
    other_player_id = (game_state.player_order - [game_state.turn.current_player_id]).first.value
    other_hand = game_state.player!(PlayerId.new(other_player_id)).hand
    other_hand.wood = 4
    other_hand.brick = 2
    other_hand.sheep = 2
    other_hand.wheat = 0
    other_hand.ore = 0

    manager.roll_dice("GHI789", current_player_id)

    rolled_snapshot = JSON.parse(store.snapshots.last[:snapshot_json])
    pending_discards = rolled_snapshot["turn"]["pending_robber_discards"].as_a
    pending_discards.size.should eq(1)
    pending_discards.first["player_id"].as_s.should eq(other_player_id)
    pending_discards.first["count"].as_i.should eq(4)

    manager.discard_robber("GHI789", other_player_id, ResourcePile.new(4, 0, 0, 0, 0))

    store.events.map(&.[:event_type]).last.should eq("robber_discarded")
    game_state.turn.phase.should eq(TurnPhase::MoveRobber)
    game_state.player!(PlayerId.new(other_player_id)).hand.total.should eq(4)
  end

  it "persists broadcast trade responses and finalizes the chosen trade partner" do
    store = RecordingGameEventStore.new
    manager = Settler::Engine::Application::LobbyManager.new(store, FixedDiceRoller.new([] of DiceRoll))
    first_client = Settler::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
    first_client.lobby_id = "TRADE123"
    second_client = Settler::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
    second_client.lobby_id = "TRADE123"
    third_client = Settler::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
    third_client.lobby_id = "TRADE123"

    manager.handle_join("TRADE123", "player-1", "Alice", first_client, "player-1")
    manager.handle_join("TRADE123", "player-2", "Bob", second_client)
    manager.handle_join("TRADE123", "player-3", "Cara", third_client)

    manager.start_game("TRADE123")
    complete_setup_through_manager!(manager, "TRADE123")

    game_state = manager.games["TRADE123"]
    proposer_id = game_state.turn.current_player_id.value
    responder_ids = (game_state.player_order - [game_state.turn.current_player_id]).map(&.value)
    accepting_player_id = responder_ids[0]
    rejecting_player_id = responder_ids[1]

    game_state.player!(PlayerId.new(proposer_id)).hand.wood = 2
    game_state.player!(PlayerId.new(proposer_id)).hand.brick = 1
    game_state.player!(PlayerId.new(accepting_player_id)).hand.sheep = 1
    game_state.player!(PlayerId.new(accepting_player_id)).hand.wheat = 2
    game_state.player!(PlayerId.new(rejecting_player_id)).hand.sheep = 1
    game_state.player!(PlayerId.new(rejecting_player_id)).hand.wheat = 2
    game_state.turn.phase = TurnPhase::Main

    offered = ResourcePile.new(2, 1, 0, 0, 0)
    requested = ResourcePile.new(0, 0, 1, 2, 0)

    manager.propose_player_trade("TRADE123", proposer_id, offered, requested)
    manager.accept_player_trade("TRADE123", accepting_player_id)
    manager.reject_player_trade("TRADE123", rejecting_player_id)

    pending_snapshot = JSON.parse(store.snapshots.last[:snapshot_json])["turn"]["pending_player_trade"]
    pending_snapshot["accepted_player_ids"].as_a.map(&.as_s).should eq([accepting_player_id])
    pending_snapshot["rejected_player_ids"].as_a.map(&.as_s).should eq([rejecting_player_id])

    proposer = game_state.player!(PlayerId.new(proposer_id))
    accepting_player = game_state.player!(PlayerId.new(accepting_player_id))
    rejecting_player = game_state.player!(PlayerId.new(rejecting_player_id))
    proposer_before = {
      wood:  proposer.hand.wood,
      brick: proposer.hand.brick,
      sheep: proposer.hand.sheep,
      wheat: proposer.hand.wheat,
    }
    accepting_before = {
      wood:  accepting_player.hand.wood,
      brick: accepting_player.hand.brick,
      sheep: accepting_player.hand.sheep,
      wheat: accepting_player.hand.wheat,
    }
    rejecting_before = {
      sheep: rejecting_player.hand.sheep,
      wheat: rejecting_player.hand.wheat,
    }

    manager.finalize_player_trade("TRADE123", proposer_id, accepting_player_id)

    store.events.last(4).map(&.[:event_type]).should eq([
      "player_trade_proposed",
      "player_trade_accepted",
      "player_trade_rejected",
      "player_trade_completed",
    ])

    game_state.pending_player_trade.should be_nil
    proposer.hand.wood.should eq(proposer_before[:wood] - 2)
    proposer.hand.brick.should eq(proposer_before[:brick] - 1)
    proposer.hand.sheep.should eq(proposer_before[:sheep] + 1)
    proposer.hand.wheat.should eq(proposer_before[:wheat] + 2)
    accepting_player.hand.wood.should eq(accepting_before[:wood] + 2)
    accepting_player.hand.brick.should eq(accepting_before[:brick] + 1)
    accepting_player.hand.sheep.should eq(accepting_before[:sheep] - 1)
    accepting_player.hand.wheat.should eq(accepting_before[:wheat] - 2)
    rejecting_player.hand.sheep.should eq(rejecting_before[:sheep])
    rejecting_player.hand.wheat.should eq(rejecting_before[:wheat])
  end
end
