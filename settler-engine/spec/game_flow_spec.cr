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
  getter latest_snapshots = Hash(String, Settler::Engine::Infrastructure::Persistence::PersistedGameSnapshot).new
  getter waiting_lobbies = Hash(String, Settler::Engine::Infrastructure::Persistence::PersistedLobby).new

  def create_lobby(host_player_id : String, is_public : Bool, settings_json : String) : Settler::Engine::Infrastructure::Persistence::PersistedLobby
    lobby = Settler::Engine::Infrastructure::Persistence::PersistedLobby.new(
      short_code: "REC001",
      host_player_id: host_player_id,
      status: "waiting",
      is_public: is_public,
      settings_json: settings_json,
      created_at: Time.utc,
      participants: [] of Settler::Engine::Infrastructure::Persistence::PersistedLobbyParticipant
    )
    @waiting_lobbies[lobby.short_code] = lobby
    lobby
  end

  def load_waiting_lobby(lobby_code : String) : Settler::Engine::Infrastructure::Persistence::PersistedLobby?
    @waiting_lobbies[lobby_code]?
  end

  def load_public_waiting_lobbies : Array(Settler::Engine::Infrastructure::Persistence::PersistedLobby)
    @waiting_lobbies.values.select(&.is_public)
  end

  def add_participant(lobby_code : String, player_id : String, ready : Bool = false) : Nil
  end

  def remove_participant(lobby_code : String, player_id : String) : Nil
  end

  def update_participant_ready(lobby_code : String, player_id : String, ready : Bool) : Nil
  end

  def update_lobby_visibility(lobby_code : String, is_public : Bool) : Nil
  end

  def update_game_settings(lobby_code : String, settings_json : String) : Nil
    @settings_updates << {lobby_code: lobby_code, settings_json: settings_json}
  end

  def mark_game_started(lobby_code : String) : Nil
  end

  def abandon_waiting_lobby(lobby_code : String) : Nil
    @waiting_lobbies.delete(lobby_code)
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
    settings_json = @settings_updates.reverse_each.find(&.[:lobby_code].==(lobby_code)).try(&.[:settings_json])
    @latest_snapshots[lobby_code] = Settler::Engine::Infrastructure::Persistence::PersistedGameSnapshot.new(
      snapshot_json: snapshot_json,
      snapshot_version: snapshot_version,
      settings_json: settings_json
    )
  end

  def load_game_snapshot(lobby_code : String) : Settler::Engine::Infrastructure::Persistence::PersistedGameSnapshot?
    @latest_snapshots[lobby_code]?
  end
end

describe Settler::Engine::Application::LobbyManager do
  it "starts a validated 5-player extension lobby with the expanded board" do
    manager = Settler::Engine::Application::LobbyManager.new(RecordingGameEventStore.new)
    manager.handle_join("EXT501", "player-1", "Player 1", Settler::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new)).tap { |client| client.lobby_id = "EXT501" })
    manager.update_settings(
      "EXT501",
      JSON.parse(
        {
          gameMode:         "fiveSixExtension",
          fiveSixTurnRule:  "paired",
          maxPlayers:       6,
          turnTimerEnabled: false,
          turnTimeSeconds:  120,
          victoryPoints:    10,
          useSeafarers:     false,
          useTraders:       false,
          useExplorers:     false,
        }.to_json
      ).as_h
    ).should be_true

    (2..5).each do |index|
      client = Settler::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
      client.lobby_id = "EXT501"
      manager.handle_join("EXT501", "player-#{index}", "Player #{index}", client)
    end
    manager.get_or_create_lobby("EXT501").players.each do |player|
      manager.set_player_ready("EXT501", player.id, true).should be_true
    end

    manager.start_game("EXT501", true).should be_true
    game_state = manager.games["EXT501"]
    game_state.topology.tiles.size.should eq(30)
    game_state.players.size.should eq(5)
    game_state.paired_turns?.should be_true
  end
  it "persists and broadcasts lobby chat messages" do
    store = RecordingGameEventStore.new
    manager = Settler::Engine::Application::LobbyManager.new(store)
    first_client = Settler::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
    first_client.lobby_id = "CHAT01"
    second_client = Settler::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
    second_client.lobby_id = "CHAT01"

    manager.handle_join("CHAT01", "player-1", "Alice", first_client)
    manager.handle_join("CHAT01", "player-2", "Bob", second_client)

    manager.send_chat_message("CHAT01", "player-1", "  hello table  ").should be_true

    store.events.last[:event_type].should eq("chat_message")
    store.events.last[:actor_player_id].should eq("player-1")
    store.events.last[:message].should eq("hello table")

    payload = JSON.parse(store.events.last[:payload_json])
    payload["player_id"].as_s.should eq("player-1")
    payload["player_name"].as_s.should eq("Alice")
    payload["message"].as_s.should eq("hello table")
    payload["created_at"].as_s.should_not be_empty
  end

  it "rejects empty, oversized, and unauthenticated chat messages" do
    store = RecordingGameEventStore.new
    manager = Settler::Engine::Application::LobbyManager.new(store)
    client = Settler::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
    client.lobby_id = "CHAT02"

    manager.handle_join("CHAT02", "player-1", "Alice", client)

    manager.send_chat_message("CHAT02", "player-1", "   ").should be_false
    manager.send_chat_message("CHAT02", "player-1", "a" * 501).should be_false
    manager.send_chat_message("CHAT02", "ghost", "hello").should be_false

    store.events.should be_empty
  end

  it "allows chat before and after the game starts" do
    store = RecordingGameEventStore.new
    manager = Settler::Engine::Application::LobbyManager.new(store)
    first_client = Settler::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
    first_client.lobby_id = "CHAT03"
    second_client = Settler::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
    second_client.lobby_id = "CHAT03"

    manager.handle_join("CHAT03", "player-1", "Alice", first_client)
    manager.handle_join("CHAT03", "player-2", "Bob", second_client)

    manager.send_chat_message("CHAT03", "player-1", "pregame").should be_true
    manager.start_game("CHAT03")
    manager.send_chat_message("CHAT03", "player-2", "ingame").should be_true

    chat_events = store.events.select { |event| event[:event_type] == "chat_message" }
    chat_events.map(&.[:message]).should eq(["pregame", "ingame"])
  end

  it "serializes turn timer metadata and resets durations by phase" do
    store = RecordingGameEventStore.new
    manager = Settler::Engine::Application::LobbyManager.new(store, FixedDiceRoller.new([DiceRoll.new(1, 1)]))
    first_client = Settler::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
    first_client.lobby_id = "TIME01"
    second_client = Settler::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
    second_client.lobby_id = "TIME01"

    manager.handle_join("TIME01", "player-1", "Alice", first_client)
    manager.handle_join("TIME01", "player-2", "Bob", second_client)

    lobby = manager.get_or_create_lobby("TIME01")
    lobby.settings = {
      "turnTimeSeconds"  => JSON::Any.new(30),
      "turnTimerEnabled" => JSON::Any.new(true),
    }

    manager.start_game("TIME01")

    game_state = manager.games["TIME01"]
    game_state.turn.timer_duration_seconds.should eq(60)
    game_state.turn.timer_expires_at.should_not be_nil

    current_player_id = game_state.turn.current_player_id.value
    manager.place_settlement("TIME01", current_player_id, legal_setup_vertex_for_current_player(game_state).value, true)
    game_state.turn.phase.should eq(TurnPhase::Setup1Road)
    game_state.turn.timer_duration_seconds.should eq(15)

    complete_setup_through_manager!(manager, "TIME01")
    game_state.turn.phase.should eq(TurnPhase::Roll)
    game_state.turn.timer_duration_seconds.should eq(7)

    manager.roll_dice("TIME01", game_state.turn.current_player_id.value)
    game_state.turn.phase.should eq(TurnPhase::Main)
    game_state.turn.timer_duration_seconds.should eq(30)

    snapshot_json = JSON.parse(store.snapshots.last[:snapshot_json])
    snapshot_json["turn"]["timer_enabled"].as_bool.should be_true
    snapshot_json["turn"]["timer_started_at"].as_s.should_not be_empty
    snapshot_json["turn"]["timer_expires_at"].as_s.should_not be_empty
    snapshot_json["turn"]["timer_duration_seconds"].as_i.should eq(30)
  end

  it "does not extend the active timer for trade proposal, responses, or cancellation" do
    store = RecordingGameEventStore.new
    manager = Settler::Engine::Application::LobbyManager.new(store, FixedDiceRoller.new([] of DiceRoll))
    first_client = Settler::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
    first_client.lobby_id = "TIME02"
    second_client = Settler::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
    second_client.lobby_id = "TIME02"
    third_client = Settler::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
    third_client.lobby_id = "TIME02"

    manager.handle_join("TIME02", "player-1", "Alice", first_client)
    manager.handle_join("TIME02", "player-2", "Bob", second_client)
    manager.handle_join("TIME02", "player-3", "Cara", third_client)
    manager.get_or_create_lobby("TIME02").settings = {
      "turnTimeSeconds"  => JSON::Any.new(30),
      "turnTimerEnabled" => JSON::Any.new(true),
    }

    manager.start_game("TIME02")
    complete_setup_through_manager!(manager, "TIME02")

    game_state = manager.games["TIME02"]
    current_player_id = game_state.turn.current_player_id.value
    proposer = game_state.player!(PlayerId.new(current_player_id))
    proposer.hand.wood = 2
    other_player_id = (game_state.player_order.map(&.value) - [current_player_id]).first
    game_state.player!(PlayerId.new(other_player_id)).hand.brick = 1
    game_state.turn.phase = TurnPhase::Main
    game_state.start_turn_timer!(30)
    initial_expires_at = game_state.turn.timer_expires_at
    initial_duration = game_state.turn.timer_duration_seconds

    manager.propose_player_trade("TIME02", current_player_id, ResourcePile.new(1, 0, 0, 0, 0), ResourcePile.new(0, 1, 0, 0, 0))
    trade_id = game_state.pending_player_trades.first.id
    game_state.turn.timer_expires_at.should eq(initial_expires_at)
    game_state.turn.timer_duration_seconds.should eq(initial_duration)

    manager.accept_player_trade("TIME02", other_player_id, trade_id)
    game_state.turn.timer_expires_at.should eq(initial_expires_at)
    game_state.turn.timer_duration_seconds.should eq(initial_duration)

    manager.cancel_player_trade("TIME02", current_player_id, trade_id)
    game_state.turn.timer_expires_at.should eq(initial_expires_at)
    game_state.turn.timer_duration_seconds.should eq(initial_duration)
  end

  it "resets and extends the timer correctly across the robber flow after rolling a 7" do
    store = RecordingGameEventStore.new
    manager = Settler::Engine::Application::LobbyManager.new(store, FixedDiceRoller.new([DiceRoll.new(3, 4)]))
    first_client = Settler::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
    first_client.lobby_id = "TIME07"
    second_client = Settler::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
    second_client.lobby_id = "TIME07"

    manager.handle_join("TIME07", "player-1", "Alice", first_client)
    manager.handle_join("TIME07", "player-2", "Bob", second_client)
    manager.get_or_create_lobby("TIME07").settings = {
      "turnTimeSeconds"  => JSON::Any.new(30),
      "turnTimerEnabled" => JSON::Any.new(true),
    }

    manager.start_game("TIME07")
    complete_setup_through_manager!(manager, "TIME07")

    game_state = manager.games["TIME07"]
    current_player_id = game_state.turn.current_player_id.value
    other_player_id = (game_state.player_order.map(&.value) - [current_player_id]).first

    discarding_hand = game_state.player!(PlayerId.new(other_player_id)).hand
    discarding_hand.wood = 4
    discarding_hand.brick = 2
    discarding_hand.sheep = 2
    discarding_hand.wheat = 2
    discarding_hand.ore = 0

    robber_target = game_state.topology.tiles.keys.sort_by(&.value).find do |tile_id|
      tile_id != game_state.board.robber_tile_id
    end.not_nil!
    robber_vertex_id = game_state.topology.tiles[robber_target].vertex_ids.first
    game_state.board.buildings[robber_vertex_id] = Building.new(PlayerId.new(other_player_id), BuildingKind::Settlement)

    manager.roll_dice("TIME07", current_player_id)
    game_state.turn.phase.should eq(TurnPhase::DiscardResources)
    game_state.turn.timer_duration_seconds.should eq(30)

    manager.discard_robber("TIME07", other_player_id, ResourcePile.new(2, 1, 1, 1, 0))
    game_state.turn.phase.should eq(TurnPhase::MoveRobber)
    game_state.turn.timer_duration_seconds.should eq(30)

    manager.move_robber("TIME07", current_player_id, robber_target.value)
    game_state.turn.phase.should eq(TurnPhase::StealResource)
    game_state.turn.timer_duration_seconds.should eq(40)

    manager.robber_steal("TIME07", current_player_id, other_player_id)
    game_state.turn.phase.should eq(TurnPhase::Main)
    game_state.turn.timer_duration_seconds.should eq(50)
  end

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

    manager.handle_join("DEF456", "player-1", "Alice", first_client)
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

    manager.handle_join("GHI789", "player-1", "Alice", first_client)
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

    manager.handle_join("TRADE123", "player-1", "Alice", first_client)
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
    trade_id = game_state.pending_player_trades.first.id
    manager.accept_player_trade("TRADE123", accepting_player_id, trade_id)
    manager.reject_player_trade("TRADE123", rejecting_player_id, trade_id)

    pending_snapshot = JSON.parse(store.snapshots.last[:snapshot_json])["turn"]["pending_player_trades"].as_a.first
    pending_snapshot["id"].as_i.should eq(trade_id)
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

    manager.finalize_player_trade("TRADE123", proposer_id, trade_id, accepting_player_id)

    store.events.last(4).map(&.[:event_type]).should eq([
      "player_trade_proposed",
      "player_trade_accepted",
      "player_trade_rejected",
      "player_trade_completed",
    ])

    game_state.pending_player_trades.should be_empty
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
