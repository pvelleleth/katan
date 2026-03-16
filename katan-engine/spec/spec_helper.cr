require "spec"
require "../src/domain/**"
require "../src/application/**"
require "../src/transport/websocket/**"

def legal_setup_vertex_for_current_player(game_state : GameState) : VertexId
  game_state.topology.vertices.keys.sort_by(&.value).find do |vertex_id|
    next false if game_state.board.occupied_vertex?(vertex_id)

    game_state.topology.neighboring_vertices(vertex_id).none? do |neighbor_id|
      game_state.board.occupied_vertex?(neighbor_id)
    end
  end || raise "no legal setup settlement available"
end

def legal_setup_road_for_current_player(game_state : GameState) : EdgeId
  player_id = game_state.turn.current_player_id
  candidate_vertices = game_state.board.buildings.each_with_object([] of VertexId) do |(vertex_id, building), memo|
    next unless building.player_id == player_id
    next unless player_road_ids_touching_vertex(game_state, vertex_id, player_id).empty?
    memo << vertex_id
  end

  raise "expected exactly one pending setup settlement" unless candidate_vertices.size == 1

  settlement_vertex_id = candidate_vertices.first
  game_state.topology.vertices[settlement_vertex_id].edge_ids.find do |edge_id|
    !game_state.board.occupied_edge?(edge_id)
  end || raise "no legal setup road available"
end

def player_road_ids_touching_vertex(game_state : GameState, vertex_id : VertexId, player_id : PlayerId) : Array(EdgeId)
  game_state.topology.vertices[vertex_id].edge_ids.select do |edge_id|
    road = game_state.board.road_at?(edge_id)
    !!road && road.player_id == player_id
  end
end

def find_simple_road_path(
  topology : BoardTopology,
  length : Int32,
  forbidden_edge_ids : Array(EdgeId) = [] of EdgeId,
  forbidden_vertex_ids : Array(VertexId) = [] of VertexId,
) : NamedTuple(start_vertex_id: VertexId, edge_ids: Array(EdgeId))
  topology.vertices.keys.sort_by(&.value).each do |start_vertex_id|
    next if forbidden_vertex_ids.includes?(start_vertex_id)

    if edge_ids = find_simple_road_path_from_vertex(topology, start_vertex_id, length, forbidden_edge_ids, forbidden_vertex_ids, [] of EdgeId)
      return {start_vertex_id: start_vertex_id, edge_ids: edge_ids}
    end
  end

  raise "could not find simple road path of length #{length}"
end

def find_simple_road_path_from_vertex(
  topology : BoardTopology,
  current_vertex_id : VertexId,
  remaining_length : Int32,
  forbidden_edge_ids : Array(EdgeId),
  forbidden_vertex_ids : Array(VertexId),
  used_edge_ids : Array(EdgeId),
) : Array(EdgeId)?
  return [] of EdgeId if remaining_length.zero?

  topology.vertices[current_vertex_id].edge_ids.each do |edge_id|
    next if forbidden_edge_ids.includes?(edge_id)
    next if used_edge_ids.includes?(edge_id)

    edge = topology.edges[edge_id]
    next_vertex_id = edge.vertex_ids[0] == current_vertex_id ? edge.vertex_ids[1] : edge.vertex_ids[0]
    next if forbidden_vertex_ids.includes?(next_vertex_id)

    used_edge_ids << edge_id
    suffix = find_simple_road_path_from_vertex(topology, next_vertex_id, remaining_length - 1, forbidden_edge_ids, forbidden_vertex_ids, used_edge_ids)
    return [edge_id] + suffix.not_nil! if suffix
    used_edge_ids.pop
  end

  nil
end

def vertices_for_road_path(topology : BoardTopology, start_vertex_id : VertexId, edge_ids : Array(EdgeId)) : Array(VertexId)
  vertices = [start_vertex_id]
  current_vertex_id = start_vertex_id

  edge_ids.each do |edge_id|
    edge = topology.edges[edge_id]
    current_vertex_id = edge.vertex_ids[0] == current_vertex_id ? edge.vertex_ids[1] : edge.vertex_ids[0]
    vertices << current_vertex_id
  end

  vertices
end

def complete_setup!(game_state : GameState) : Nil
  until game_state.turn.phase.roll?
    current_player = game_state.turn.current_player_id

    case game_state.turn.phase
    when .setup1_settlement?, .setup2_settlement?
      game_state.apply!(SettlementPlaced.new(game_state.version + 1, current_player, legal_setup_vertex_for_current_player(game_state), true))
    when .setup1_road?, .setup2_road?
      game_state.apply!(RoadPlaced.new(game_state.version + 1, current_player, legal_setup_road_for_current_player(game_state), true))
    else
      raise "unexpected phase during setup: #{game_state.turn.phase}"
    end
  end
end

def complete_setup_through_manager!(manager : Katan::Engine::Application::LobbyManager, lobby_id : String) : Nil
  game_state = manager.games[lobby_id]

  20.times do
    return if game_state.turn.phase.roll?

    version_before = game_state.version
    current_player = game_state.turn.current_player_id.value

    case game_state.turn.phase
    when .setup1_settlement?, .setup2_settlement?
      manager.place_settlement(lobby_id, current_player, legal_setup_vertex_for_current_player(game_state).value, true)
    when .setup1_road?, .setup2_road?
      manager.place_road(lobby_id, current_player, legal_setup_road_for_current_player(game_state).value, true)
    else
      raise "unexpected phase during setup: #{game_state.turn.phase}"
    end

    raise "setup action failed to advance state" if game_state.version == version_before
  end

  raise "setup did not complete"
end
