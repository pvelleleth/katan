require "./spec_helper"
require "base64"
require "openssl/hmac"

class FixedDiceRoller < Settler::Engine::Application::DiceRoller
  getter rolls : Array(DiceRoll)

  def initialize(@rolls : Array(DiceRoll))
  end

  def roll : DiceRoll
    @rolls.shift? || raise "no fixed dice rolls remaining"
  end
end

class SnapshotStore < Settler::Engine::Infrastructure::Persistence::GameEventStore
  getter snapshots = Hash(String, Settler::Engine::Infrastructure::Persistence::PersistedGameSnapshot).new
  getter waiting_lobbies = Hash(String, Settler::Engine::Infrastructure::Persistence::PersistedLobby).new

  @next_lobby_number = 1

  def create_lobby(host_player_id : String, is_public : Bool, settings_json : String) : Settler::Engine::Infrastructure::Persistence::PersistedLobby
    short_code = "L#{@next_lobby_number.to_s.rjust(5, '0')}"
    @next_lobby_number += 1

    lobby = Settler::Engine::Infrastructure::Persistence::PersistedLobby.new(
      short_code: short_code,
      host_player_id: host_player_id,
      status: "waiting",
      is_public: is_public,
      settings_json: settings_json,
      created_at: Time.utc,
      participants: [
        Settler::Engine::Infrastructure::Persistence::PersistedLobbyParticipant.new(
          player_id: host_player_id,
          player_name: "Player",
          ready: false
        ),
      ]
    )

    @waiting_lobbies[short_code] = lobby
    lobby
  end

  def load_waiting_lobby(lobby_code : String) : Settler::Engine::Infrastructure::Persistence::PersistedLobby?
    @waiting_lobbies[lobby_code]?
  end

  def load_public_waiting_lobbies : Array(Settler::Engine::Infrastructure::Persistence::PersistedLobby)
    @waiting_lobbies.values.select(&.is_public)
  end

  def add_participant(lobby_code : String, player_id : String, ready : Bool = false) : Nil
    return unless lobby = @waiting_lobbies[lobby_code]?
    return if lobby.participants.any? { |participant| participant.player_id == player_id }

    participants = lobby.participants + [
      Settler::Engine::Infrastructure::Persistence::PersistedLobbyParticipant.new(
        player_id: player_id,
        player_name: "Player",
        ready: ready
      ),
    ]
    @waiting_lobbies[lobby_code] = lobby.copy_with(participants: participants)
  end

  def remove_participant(lobby_code : String, player_id : String) : Nil
    return unless lobby = @waiting_lobbies[lobby_code]?

    participants = lobby.participants.reject { |participant| participant.player_id == player_id }
    @waiting_lobbies[lobby_code] = lobby.copy_with(participants: participants)
  end

  def update_participant_ready(lobby_code : String, player_id : String, ready : Bool) : Nil
    return unless lobby = @waiting_lobbies[lobby_code]?

    participants = lobby.participants.map do |participant|
      if participant.player_id == player_id
        participant.copy_with(ready: ready)
      else
        participant
      end
    end

    @waiting_lobbies[lobby_code] = lobby.copy_with(participants: participants)
  end

  def update_lobby_visibility(lobby_code : String, is_public : Bool) : Nil
    return unless lobby = @waiting_lobbies[lobby_code]?

    @waiting_lobbies[lobby_code] = lobby.copy_with(is_public: is_public)
  end

  def update_game_settings(lobby_code : String, settings_json : String) : Nil
    if snapshot = @snapshots[lobby_code]?
      @snapshots[lobby_code] = snapshot.copy_with(settings_json: settings_json)
    end

    if lobby = @waiting_lobbies[lobby_code]?
      @waiting_lobbies[lobby_code] = lobby.copy_with(settings_json: settings_json)
    end
  end

  def mark_game_started(lobby_code : String) : Nil
    @waiting_lobbies.delete(lobby_code)
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
  end

  def save_game_snapshot(lobby_code : String, snapshot_json : String, snapshot_version : Int32) : Nil
    settings_json = JSON.parse(snapshot_json)["settings"].to_json
    @snapshots[lobby_code] = Settler::Engine::Infrastructure::Persistence::PersistedGameSnapshot.new(
      snapshot_json: snapshot_json,
      snapshot_version: snapshot_version,
      settings_json: settings_json
    )
  end

  def load_game_snapshot(lobby_code : String) : Settler::Engine::Infrastructure::Persistence::PersistedGameSnapshot?
    @snapshots[lobby_code]?
  end
end

def test_client(lobby_id : String) : Settler::Engine::Transport::WebSocket::Client
  client = Settler::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
  client.lobby_id = lobby_id
  client
end

def signed_bootstrap_token(
  secret : String,
  player_id : String = "player-1",
  name : String = "Alice",
  lobby_id : String? = nil,
  exp : Int64 = (Time.utc + 5.minutes).to_unix,
) : String
  payload_json = JSON.build do |json|
    json.object do
      json.field "userId", "user-1"
      json.field "playerId", player_id
      json.field "name", name
      json.field "exp", exp
      json.field "lobbyId", lobby_id if lobby_id
    end
  end

  encoded_payload = Base64.urlsafe_encode(payload_json, padding: false)
  signature = Base64.urlsafe_encode(OpenSSL::HMAC.digest(:sha256, secret, encoded_payload), padding: false)
  "#{encoded_payload}.#{signature}"
end

describe Settler::Engine::Domain::Player do
  it "tracks disconnected state without removing the player" do
    player = Settler::Engine::Domain::Player.new("player-1", "Alice")

    player.mark_disconnected

    player.connected.should be_false
    player.disconnected_at.should_not be_nil
  end

  it "restores a disconnected player on reconnect" do
    player = Settler::Engine::Domain::Player.new("player-1", "Alice")
    player.ready = true
    player.mark_disconnected

    player.ready = false
    player.mark_connected

    player.connected.should be_true
    player.disconnected_at.should be_nil
    player.ready.should be_false
  end
end

describe Settler::Engine::Transport::WebSocket::BootstrapTokenVerifier do
  it "accepts a valid signed token with the expected lobby scope" do
    verifier = Settler::Engine::Transport::WebSocket::BootstrapTokenVerifier.new("test-secret")

    payload = verifier.verify(signed_bootstrap_token("test-secret", lobby_id: "ABC123"), "ABC123")

    payload.should_not be_nil
    payload.not_nil!.player_id.should eq("player-1")
  end

  it "rejects tokens with the wrong lobby scope" do
    verifier = Settler::Engine::Transport::WebSocket::BootstrapTokenVerifier.new("test-secret")

    payload = verifier.verify(signed_bootstrap_token("test-secret", lobby_id: "ABC123"), "DIFF99")

    payload.should be_nil
  end

  it "rejects expired tokens" do
    verifier = Settler::Engine::Transport::WebSocket::BootstrapTokenVerifier.new("test-secret")

    payload = verifier.verify(
      signed_bootstrap_token("test-secret", exp: (Time.utc - 1.minute).to_unix),
      nil
    )

    payload.should be_nil
  end
end

describe Settler::Engine::Application::LobbyManager do
  it "removes a player immediately on explicit leave" do
    manager = Settler::Engine::Application::LobbyManager.new
    lobby = manager.get_or_create_lobby("ABC123")
    lobby.add_player(Settler::Engine::Domain::Player.new("player-1", "Alice"))

    removed = manager.remove_player("ABC123", "player-1")

    removed.should be_true
    lobby.players.should be_empty
  end

  it "kicks a disconnected player without requiring an active socket" do
    manager = Settler::Engine::Application::LobbyManager.new
    lobby = manager.get_or_create_lobby("ABC123")
    player = Settler::Engine::Domain::Player.new("player-2", "Bob")
    player.mark_disconnected
    lobby.add_player(player)

    manager.kick_player("ABC123", "player-2")

    lobby.find_player("player-2").should be_nil
  end

  it "preserves ready state when a player reconnects" do
    manager = Settler::Engine::Application::LobbyManager.new
    first_client = Settler::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
    first_client.lobby_id = "ABC123"

    manager.handle_join("ABC123", "player-1", "Alice", first_client)
    manager.set_player_ready("ABC123", "player-1", true).should be_true
    manager.disconnect_client(first_client)

    second_client = Settler::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
    second_client.lobby_id = "ABC123"
    manager.handle_join("ABC123", "player-1", "Alice", second_client)

    player = manager.get_or_create_lobby("ABC123").find_player("player-1")
    player.should_not be_nil
    player = player.not_nil!
    player.ready.should be_true
    player.connected.should be_true
  end

  it "creates public lobbies through the persistence store and exposes them in the public snapshot" do
    store = SnapshotStore.new
    manager = Settler::Engine::Application::LobbyManager.new(store)

    lobby = manager.create_lobby("player-1", "Alice", true)

    lobby.host_id.should eq("player-1")
    store.load_waiting_lobby(lobby.id).should_not be_nil

    summaries = manager.public_lobby_summaries
    summaries.size.should eq(1)
    summaries.first.short_code.should eq(lobby.id)
    summaries.first.participant_count.should eq(1)
  end

  it "prevents joins that would exceed the configured max players" do
    store = SnapshotStore.new
    manager = Settler::Engine::Application::LobbyManager.new(store)
    lobby = manager.create_lobby("player-1", "Alice", true)
    client = test_client(lobby.id)
    manager.handle_join(lobby.id, "player-1", "Alice", client)

    manager.update_settings(
      lobby.id,
      JSON.parse(
        {
          turnTimerEnabled: true,
          turnTimeSeconds:  120,
          maxPlayers:       3,
          victoryPoints:    10,
          useSeafarers:     false,
          useTraders:       false,
          useExplorers:     false,
        }.to_json
      ).as_h
    )

    manager.handle_join(lobby.id, "player-2", "Bob", test_client(lobby.id))
    manager.handle_join(lobby.id, "player-3", "Cara", test_client(lobby.id))
    manager.handle_join(lobby.id, "player-4", "Drew", test_client(lobby.id))

    manager.get_or_create_lobby(lobby.id).players.map(&.id).should eq(["player-1", "player-2", "player-3"])
  end

  it "always provides six seats for a 5-6 player extension lobby" do
    store = SnapshotStore.new
    manager = Settler::Engine::Application::LobbyManager.new(store)
    lobby = manager.create_lobby("player-1", "Alice", true)
    manager.handle_join(lobby.id, "player-1", "Alice", test_client(lobby.id))

    manager.update_settings(
      lobby.id,
      JSON.parse(
        {
          gameMode:         "fiveSixExtension",
          fiveSixTurnRule:  "paired",
          maxPlayers:       5,
          turnTimerEnabled: true,
          turnTimeSeconds:  120,
          victoryPoints:    10,
          useSeafarers:     false,
          useTraders:       false,
          useExplorers:     false,
        }.to_json
      ).as_h
    ).should be_true

    (2..7).each do |index|
      manager.handle_join(lobby.id, "player-#{index}", "Player #{index}", test_client(lobby.id))
    end

    lobby.settings["maxPlayers"].as_i.should eq(6)
    lobby.players.map(&.id).should eq(["player-1", "player-2", "player-3", "player-4", "player-5", "player-6"])
  end

  it "restores public waiting lobbies from the persistence store on startup" do
    store = SnapshotStore.new
    creator = Settler::Engine::Application::LobbyManager.new(store)
    creator.create_lobby("player-1", "Alice", true)

    restored = Settler::Engine::Application::LobbyManager.new(store)

    restored.public_lobby_summaries.map(&.host_player_id).should eq(["player-1"])
  end

  it "removes a public lobby from the snapshot once the game starts" do
    store = SnapshotStore.new
    manager = Settler::Engine::Application::LobbyManager.new(store)
    lobby = manager.create_lobby("player-1", "Alice", true)
    host_client = test_client(lobby.id)
    manager.handle_join(lobby.id, "player-1", "Alice", host_client)

    manager.start_game(lobby.id)

    manager.public_lobby_summaries.should be_empty
  end

  it "exposes a lobby in the public snapshot when visibility is toggled on" do
    store = SnapshotStore.new
    manager = Settler::Engine::Application::LobbyManager.new(store)
    lobby = manager.create_lobby("player-1", "Alice", false)
    host_client = test_client(lobby.id)
    manager.handle_join(lobby.id, "player-1", "Alice", host_client)

    manager.public_lobby_summaries.should be_empty

    manager.update_visibility(lobby.id, true)

    summaries = manager.public_lobby_summaries
    summaries.size.should eq(1)
    summaries.first.short_code.should eq(lobby.id)
    store.load_waiting_lobby(lobby.id).not_nil!.is_public.should be_true
  end

  it "abandons empty waiting lobbies so they do not reappear as public" do
    store = SnapshotStore.new
    manager = Settler::Engine::Application::LobbyManager.new(store)
    lobby = manager.create_lobby("player-1", "Alice", true)
    host_client = test_client(lobby.id)
    manager.handle_join(lobby.id, "player-1", "Alice", host_client)

    manager.remove_player(lobby.id, "player-1", "player_left", "left the lobby")

    manager.public_lobby_summaries.should be_empty
    manager.lobbies[lobby.id]?.should be_nil
    store.load_waiting_lobby(lobby.id).should be_nil
  end

  it "does not restore empty public waiting lobbies on startup" do
    store = SnapshotStore.new
    empty_public = Settler::Engine::Infrastructure::Persistence::PersistedLobby.new(
      short_code: "EMPTY1",
      host_player_id: "player-1",
      status: "waiting",
      is_public: true,
      settings_json: nil,
      created_at: Time.utc,
      participants: [] of Settler::Engine::Infrastructure::Persistence::PersistedLobbyParticipant
    )
    store.waiting_lobbies["EMPTY1"] = empty_public

    manager = Settler::Engine::Application::LobbyManager.new(store)

    manager.public_lobby_summaries.should be_empty
    manager.lobbies["EMPTY1"]?.should be_nil
    store.load_waiting_lobby("EMPTY1").should be_nil
  end

  it "restores a cleaned up game from the saved snapshot on reconnect" do
    store = SnapshotStore.new
    original_manager = Settler::Engine::Application::LobbyManager.new(store)
    first_client = test_client("SNAP01")
    second_client = test_client("SNAP01")

    original_manager.handle_join("SNAP01", "player-1", "Alice", first_client)
    original_manager.handle_join("SNAP01", "player-2", "Bob", second_client)
    original_manager.start_game("SNAP01")
    complete_setup_through_manager!(original_manager, "SNAP01")

    original_state = original_manager.games["SNAP01"]
    original_state.turn.phase = TurnPhase::Main
    original_state.player!(original_state.turn.current_player_id).hand.wood = 1
    original_state.player!(original_state.turn.current_player_id).hand.brick = 1
    road_id = find_simple_road_path(original_state.topology, 1, original_state.board.roads.keys).[:edge_ids].first
    original_manager.place_road("SNAP01", original_state.turn.current_player_id.value, road_id.value)

    snapshot_before_cleanup = JSON.parse(store.load_game_snapshot("SNAP01").not_nil!.snapshot_json)

    original_manager.remove_player("SNAP01", "player-1")
    original_manager.remove_player("SNAP01", "player-2")
    original_manager.games["SNAP01"]?.should be_nil
    original_manager.lobbies["SNAP01"]?.should be_nil

    restored_manager = Settler::Engine::Application::LobbyManager.new(store)
    restored_lobby = restored_manager.get_or_create_lobby("SNAP01")
    restored_lobby.players.map(&.id).sort.should eq(["player-1", "player-2"])
    restored_lobby.players.all? { |player| !player.connected }.should be_true

    rejoining_client = test_client("SNAP01")
    restored_manager.handle_join("SNAP01", "player-1", "Alice", rejoining_client)

    restored_state = restored_manager.games["SNAP01"]
    restored_state.version.should eq(snapshot_before_cleanup["version"].as_i)
    restored_state.turn.phase.to_s.should eq(snapshot_before_cleanup["turn"]["phase"].as_s)
    restored_state.player_order.map(&.value).should eq(snapshot_before_cleanup["player_order"].as_a.map(&.as_s))
    restored_state.board.roads.keys.map(&.value).sort.should eq(
      snapshot_before_cleanup["board"]["edges"].as_a.select { |edge| !edge["road"]?.try(&.raw.nil?).nil? && !edge["road"].raw.nil? }.map { |edge| edge["id"].as_s }.sort
    )
    restored_manager.get_or_create_lobby("SNAP01").find_player("player-1").not_nil!.connected.should be_true
    restored_manager.get_or_create_lobby("SNAP01").find_player("player-2").not_nil!.connected.should be_false
  end

  it "restores pending trade and robber discard state from snapshots" do
    store = SnapshotStore.new
    manager = Settler::Engine::Application::LobbyManager.new(store, FixedDiceRoller.new([DiceRoll.new(3, 4)]))
    first_client = test_client("SNAP02")
    second_client = test_client("SNAP02")
    third_client = test_client("SNAP02")

    manager.handle_join("SNAP02", "player-1", "Alice", first_client)
    manager.handle_join("SNAP02", "player-2", "Bob", second_client)
    manager.handle_join("SNAP02", "player-3", "Cara", third_client)
    manager.start_game("SNAP02")
    complete_setup_through_manager!(manager, "SNAP02")

    game_state = manager.games["SNAP02"]
    current_player_id = game_state.turn.current_player_id.value
    other_player_ids = (game_state.player_order - [game_state.turn.current_player_id]).map(&.value)
    discard_player_id = other_player_ids.first

    discard_hand = game_state.player!(PlayerId.new(discard_player_id)).hand
    discard_hand.wood = 4
    discard_hand.brick = 2
    discard_hand.sheep = 2
    discard_hand.wheat = 0
    discard_hand.ore = 0

    manager.roll_dice("SNAP02", current_player_id)

    proposer = game_state.turn.current_player_id.value
    game_state.turn.phase = TurnPhase::Main
    game_state.player!(PlayerId.new(proposer)).hand.wood = 2
    game_state.player!(PlayerId.new(proposer)).hand.brick = 1
    game_state.player!(PlayerId.new(other_player_ids.last)).hand.sheep = 1
    game_state.player!(PlayerId.new(other_player_ids.last)).hand.wheat = 1
    manager.propose_player_trade("SNAP02", proposer, ResourcePile.new(2, 1, 0, 0, 0), ResourcePile.new(0, 0, 1, 1, 0))
    trade_id = game_state.pending_player_trades.first.id
    manager.accept_player_trade("SNAP02", other_player_ids.last, trade_id)

    manager.remove_player("SNAP02", "player-1")
    manager.remove_player("SNAP02", "player-2")
    manager.remove_player("SNAP02", "player-3")

    restored_manager = Settler::Engine::Application::LobbyManager.new(store)
    restored_state = restored_manager.get_or_create_lobby("SNAP02")
    restored_state.players.size.should eq(3)

    hydrated_game = restored_manager.games["SNAP02"]
    hydrated_game.pending_robber_discards[PlayerId.new(discard_player_id)].should eq(4)
    hydrated_game.pending_player_trades.size.should eq(1)
    hydrated_game.pending_player_trades.first.id.should eq(trade_id)
    hydrated_game.pending_player_trades.first.accepted_player_ids.map(&.value).should eq([other_player_ids.last])
  end

  it "restores robber return phase during steal resolution after a knight from roll" do
    store = SnapshotStore.new
    manager = Settler::Engine::Application::LobbyManager.new(store)
    first_client = test_client("SNAP04")
    second_client = test_client("SNAP04")

    manager.handle_join("SNAP04", "player-1", "Alice", first_client)
    manager.handle_join("SNAP04", "player-2", "Bob", second_client)
    manager.start_game("SNAP04")
    complete_setup_through_manager!(manager, "SNAP04")

    game_state = manager.games["SNAP04"]
    acting_player_id = game_state.turn.current_player_id
    victim_player_id = (game_state.player_order - [acting_player_id]).first

    game_state.turn.phase = TurnPhase::Roll
    game_state.player!(acting_player_id).dev_cards.knight = 1
    game_state.player!(victim_player_id).hand.wood = 1
    game_state.player!(victim_player_id).hand.brick = 0
    game_state.player!(victim_player_id).hand.sheep = 0
    game_state.player!(victim_player_id).hand.wheat = 0
    game_state.player!(victim_player_id).hand.ore = 0

    target_tile_id = game_state.topology.tiles.keys.sort_by(&.value).find do |tile_id|
      next false if tile_id == game_state.board.robber_tile_id

      game_state.topology.tiles[tile_id].vertex_ids.any? do |vertex_id|
        building = game_state.board.building_at?(vertex_id)
        building && building.player_id == victim_player_id
      end
    end.not_nil!

    manager.play_knight("SNAP04", acting_player_id.value, target_tile_id.value)
    game_state.turn.phase.should eq(TurnPhase::StealResource)
    game_state.robber_return_phase.should eq(TurnPhase::Roll)

    manager.remove_player("SNAP04", "player-1")
    manager.remove_player("SNAP04", "player-2")

    restored_manager = Settler::Engine::Application::LobbyManager.new(store)
    rejoining_client = test_client("SNAP04")
    restored_manager.handle_join("SNAP04", "player-1", "Alice", rejoining_client)

    restored_game = restored_manager.games["SNAP04"]
    restored_game.turn.phase.should eq(TurnPhase::StealResource)
    restored_game.robber_return_phase.should eq(TurnPhase::Roll)

    restored_manager.robber_steal("SNAP04", acting_player_id.value, victim_player_id.value)

    resolved_game = restored_manager.games["SNAP04"]
    resolved_game.turn.phase.should eq(TurnPhase::Roll)
    resolved_game.robber_return_phase.should be_nil
  end

  it "restores game over snapshots as the current game state" do
    store = SnapshotStore.new
    manager = Settler::Engine::Application::LobbyManager.new(store)
    first_client = test_client("SNAP03")
    second_client = test_client("SNAP03")

    manager.handle_join("SNAP03", "player-1", "Alice", first_client)
    manager.handle_join("SNAP03", "player-2", "Bob", second_client)
    manager.start_game("SNAP03")

    snapshot = JSON.parse(store.load_game_snapshot("SNAP03").not_nil!.snapshot_json).as_h
    turn_snapshot = JSON.parse(snapshot["turn"].to_json).as_h
    turn_snapshot["phase"] = JSON.parse(%("GameOver"))
    snapshot["turn"] = JSON.parse(turn_snapshot.to_json)
    snapshot["winner_player_id"] = JSON.parse(%("player-1"))
    store.snapshots["SNAP03"] = Settler::Engine::Infrastructure::Persistence::PersistedGameSnapshot.new(
      snapshot_json: snapshot.to_json,
      snapshot_version: snapshot["version"].as_i.to_i32,
      settings_json: snapshot["settings"].to_json
    )

    manager.remove_player("SNAP03", "player-1")
    manager.remove_player("SNAP03", "player-2")

    restored_manager = Settler::Engine::Application::LobbyManager.new(store)
    rejoining_client = test_client("SNAP03")
    restored_manager.handle_join("SNAP03", "player-2", "Bob", rejoining_client)

    restored_game = restored_manager.games["SNAP03"]
    restored_game.turn.phase.should eq(TurnPhase::GameOver)
    restored_game.winner_player_id.not_nil!.value.should eq("player-1")
  end

  it "falls back to a fresh lobby when no snapshot exists" do
    manager = Settler::Engine::Application::LobbyManager.new(SnapshotStore.new)

    lobby = manager.get_or_create_lobby("EMPTY1")

    lobby.players.should be_empty
    manager.games["EMPTY1"]?.should be_nil
  end

  it "returns nil for missing snapshots in the null store" do
    Settler::Engine::Infrastructure::Persistence::NullGameEventStore.new.load_game_snapshot("NONE").should be_nil
  end
end
