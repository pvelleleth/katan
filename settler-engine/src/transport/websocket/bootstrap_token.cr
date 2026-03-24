require "base64"
require "json"
require "openssl/hmac"
require "time"

module Settler::Engine::Transport::WebSocket
  struct BootstrapTokenPayload
    include JSON::Serializable

    @[JSON::Field(key: "userId")]
    getter user_id : String

    @[JSON::Field(key: "playerId")]
    getter player_id : String

    getter name : String

    getter exp : Int64

    @[JSON::Field(key: "lobbyId")]
    getter lobby_id : String?
  end

  class BootstrapTokenVerifier
    def initialize(@secret : String? = ENV["WS_BOOTSTRAP_SECRET"]? || ENV["BETTER_AUTH_SECRET"]?)
    end

    def verify(token : String, expected_lobby_id : String? = nil) : BootstrapTokenPayload?
      return nil unless secret = @secret

      parts = token.split('.', 2)
      return nil unless parts.size == 2

      encoded_payload = parts[0]
      signature = parts[1]
      expected_signature = Base64.urlsafe_encode(OpenSSL::HMAC.digest(:sha256, secret, encoded_payload), padding: false)
      return nil unless secure_compare(signature, expected_signature)

      payload = BootstrapTokenPayload.from_json(Base64.decode_string(encoded_payload))
      return nil if payload.exp <= Time.utc.to_unix
      return nil if expected_lobby_id && payload.lobby_id != expected_lobby_id

      payload
    rescue ex
      nil
    end

    def configured? : Bool
      !@secret.nil?
    end

    private def secure_compare(left : String, right : String) : Bool
      return false unless left.bytesize == right.bytesize

      result = 0_u8
      left.bytes.zip(right.bytes) do |lhs, rhs|
        result |= lhs ^ rhs
      end
      result.zero?
    end
  end
end
