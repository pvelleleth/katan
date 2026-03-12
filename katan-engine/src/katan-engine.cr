require "http/server"

# Require domain logic
require "./domain/**"
# Require application logic
require "./application/**"
# Require transport layer
require "./transport/websocket/**"

module Katan::Engine
  VERSION = "0.1.0"

  def self.run
    puts "Initializing Katan Engine (v#{VERSION})..."

    # Setup application state
    lobby_manager = Application::LobbyManager.new

    # Setup transport handlers
    ws_handler = Transport::WebSocket::Handler.new(lobby_manager)

    # Initialize generic HTTP server
    server = HTTP::Server.new([
      HTTP::LogHandler.new,
      ws_handler
    ])

    port = 8080
    host = "0.0.0.0"

    address = server.bind_tcp(host, port)
    puts "Server listening for WebSocket connections at ws://#{host}:#{port}/ws/lobby/<lobby_id>"
    server.listen
  end
end

Katan::Engine.run
