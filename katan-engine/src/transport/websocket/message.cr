require "json"

module Katan::Engine::Transport::WebSocket
  struct IncomingMessage
    include JSON::Serializable
    
    getter action : String
    # Catch-all struct to just access arbitrary payload data
    getter payload : JSON::Any?
  end
end
