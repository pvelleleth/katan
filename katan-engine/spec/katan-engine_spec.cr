require "./spec_helper"

describe Katan::Engine::Domain::Player do
  it "tracks disconnected state without removing the player" do
    player = Katan::Engine::Domain::Player.new("player-1", "Alice")

    player.mark_disconnected

    player.connected.should be_false
    player.disconnected_at.should_not be_nil
  end

  it "restores a disconnected player on reconnect" do
    player = Katan::Engine::Domain::Player.new("player-1", "Alice")
    player.ready = true
    player.mark_disconnected

    player.ready = false
    player.mark_connected

    player.connected.should be_true
    player.disconnected_at.should be_nil
    player.ready.should be_false
  end
end

describe Katan::Engine::Application::LobbyManager do
  it "removes a player immediately on explicit leave" do
    manager = Katan::Engine::Application::LobbyManager.new
    lobby = manager.get_or_create_lobby("ABC123")
    lobby.add_player(Katan::Engine::Domain::Player.new("player-1", "Alice"))

    removed = manager.remove_player("ABC123", "player-1")

    removed.should be_true
    lobby.players.should be_empty
  end

  it "kicks a disconnected player without requiring an active socket" do
    manager = Katan::Engine::Application::LobbyManager.new
    lobby = manager.get_or_create_lobby("ABC123")
    player = Katan::Engine::Domain::Player.new("player-2", "Bob")
    player.mark_disconnected
    lobby.add_player(player)

    manager.kick_player("ABC123", "player-2")

    lobby.find_player("player-2").should be_nil
  end

  it "preserves ready state when a player reconnects" do
    manager = Katan::Engine::Application::LobbyManager.new
    first_client = Katan::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
    first_client.lobby_id = "ABC123"

    manager.handle_join("ABC123", "player-1", "Alice", first_client)
    manager.set_player_ready("ABC123", "player-1", true).should be_true
    manager.disconnect_client(first_client)

    second_client = Katan::Engine::Transport::WebSocket::Client.new(HTTP::WebSocket.new(IO::Memory.new))
    second_client.lobby_id = "ABC123"
    manager.handle_join("ABC123", "player-1", "Alice", second_client)

    player = manager.get_or_create_lobby("ABC123").find_player("player-1")
    player.should_not be_nil
    player = player.not_nil!
    player.ready.should be_true
    player.connected.should be_true
  end
end
