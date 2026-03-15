require "./spec_helper"

class RecordingGameEventStore < Katan::Engine::Infrastructure::Persistence::GameEventStore
  getter settings_updates = [] of NamedTuple(lobby_code: String, settings_json: String)
  getter events = [] of NamedTuple(
    lobby_code: String,
    event_type: String,
    actor_player_id: String?,
    turn_number: Int32?,
    phase: String?,
    payload_json: String,
    message: String?
  )
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
    message : String? = nil
  ) : Nil
    @events << {
      lobby_code: lobby_code,
      event_type: event_type,
      actor_player_id: actor_player_id,
      turn_number: turn_number,
      phase: phase,
      payload_json: payload_json,
      message: message,
    }
  end

  def save_game_snapshot(lobby_code : String, snapshot_json : String, snapshot_version : Int32) : Nil
    @snapshots << {lobby_code: lobby_code, snapshot_json: snapshot_json, snapshot_version: snapshot_version}
  end
end

describe Katan::Engine::Application::LobbyManager do
  it "appends and applies every current gameplay action path" do
    store = RecordingGameEventStore.new
    manager = Katan::Engine::Application::LobbyManager.new(store)
    lobby = manager.get_or_create_lobby("ABC123")
    lobby.host_id = "player-1"
    lobby.add_player(Katan::Engine::Domain::Player.new("player-1", "Alice"))
    lobby.add_player(Katan::Engine::Domain::Player.new("player-2", "Bob"))

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

    roll_total = 7
    robber_target = game_state.topology.tiles.keys.sort_by(&.value).find do |tile_id|
      tile_id != game_state.board.robber_tile_id
    end.not_nil!.value

    manager.roll_dice("ABC123", first_player, roll_total)
    manager.move_robber("ABC123", first_player, robber_target)
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
      "turn_ended",
    ])

    final_state = manager.games["ABC123"]
    final_state.version.should eq(13)
    final_state.turn.current_player_id.value.should eq(second_player)
    final_state.turn.phase.should eq(TurnPhase::Roll)
  end

  it "persists full hands in game_started payloads and saved snapshots" do
    store = RecordingGameEventStore.new
    manager = Katan::Engine::Application::LobbyManager.new(store)
    first_client = Katan::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
    first_client.lobby_id = "DEF456"
    second_client = Katan::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
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

    producer_tile_id, producer_tile_state = game_state.board.tile_states.find { |_, state| state.token && !state.resource.desert? }.not_nil!
    producer_vertex_id = game_state.topology.tiles[producer_tile_id].vertex_ids.find do |vertex_id|
      building = game_state.board.building_at?(vertex_id)
      building && building.player_id == game_state.turn.current_player_id
    end.not_nil!

    game_state.board.buildings[producer_vertex_id] = Building.new(game_state.turn.current_player_id, BuildingKind::City)
    game_state.turn.phase = TurnPhase::Roll
    manager.roll_dice("DEF456", game_state.turn.current_player_id.value, producer_tile_state.token.not_nil!)

    snapshot_json = JSON.parse(store.snapshots.last[:snapshot_json])
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
end
