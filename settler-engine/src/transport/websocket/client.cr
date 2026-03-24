require "http/web_socket"

module Settler::Engine::Transport::WebSocket
  class Client
    getter socket : HTTP::WebSocket
    property player_id : String?
    property lobby_id : String?
    property public_subscriber : Bool = false

    def initialize(@socket : HTTP::WebSocket)
    end

    def send_json(data : String)
      @socket.send(data) unless @socket.closed?
    end
  end
end
