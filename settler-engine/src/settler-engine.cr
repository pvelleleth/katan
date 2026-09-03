require "http/server"
require "dotenv"

Dotenv.load

# Require domain logic
require "./domain/**"
# Require application logic
require "./application/**"
# Require infrastructure
require "./infrastructure/**"
# Require transport layer
require "./transport/websocket/**"

module Settler::Engine
  VERSION = "0.1.0"

  def self.run
    puts "Initializing Settler Engine (v#{VERSION})..."

    database_url = ENV["DATABASE_URL"]?
    game_event_store =
      if database_url
        Infrastructure::Persistence::PostgresGameEventStore.new(database_url)
      else
        puts "DATABASE_URL not set; game events will not be persisted."
        Infrastructure::Persistence::NullGameEventStore.new
      end

    # Setup application state
    lobby_manager = Application::LobbyManager.new(game_event_store)

    # Setup transport handlers
    ws_handler = Transport::WebSocket::Handler.new(lobby_manager)

    # Initialize generic HTTP server
    server = HTTP::Server.new([
      HTTP::LogHandler.new,
      ws_handler,
    ])

    port = ENV.fetch("PORT", "8080").to_i
    host = ENV.fetch("HOST", "0.0.0.0")

    address = server.bind_tcp(host, port)
    puts "Server listening for WebSocket connections at ws://#{host}:#{port}/ws/lobby/<lobby_id> and ws://#{host}:#{port}/ws/public-lobbies"
    server.listen
  end
end

Settler::Engine.run
