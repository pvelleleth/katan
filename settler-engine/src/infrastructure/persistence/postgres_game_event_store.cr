require "db"
require "pg"
require "./game_event_store"

module Settler::Engine::Infrastructure::Persistence
  class PostgresGameEventStore < GameEventStore
    @db : DB::Database

    CREATE_LOBBY_SQL = <<-SQL
      INSERT INTO game (
        short_code,
        host_player_id,
        is_public,
        settings
      )
      VALUES ($1, $2, $3, $4::jsonb)
    SQL

    INSERT_PARTICIPANT_SQL = <<-SQL
      INSERT INTO game_participant (
        game_id,
        player_id,
        is_ready
      )
      SELECT id, $2, $3
      FROM game
      WHERE short_code = $1
      ON CONFLICT (game_id, player_id) DO NOTHING
    SQL

    REMOVE_PARTICIPANT_SQL = <<-SQL
      DELETE FROM game_participant gp
      USING game g
      WHERE gp.game_id = g.id
        AND g.short_code = $1
        AND gp.player_id = $2
    SQL

    UPDATE_PARTICIPANT_READY_SQL = <<-SQL
      UPDATE game_participant gp
      SET is_ready = $3
      FROM game g
      WHERE gp.game_id = g.id
        AND g.short_code = $1
        AND gp.player_id = $2
    SQL

    UPDATE_VISIBILITY_SQL = <<-SQL
      UPDATE game
      SET is_public = $2
      WHERE short_code = $1
    SQL

    UPDATE_SETTINGS_SQL = <<-SQL
      UPDATE game
      SET settings = $2::jsonb
      WHERE short_code = $1
    SQL

    MARK_GAME_STARTED_SQL = <<-SQL
      UPDATE game
      SET status = 'started', started_at = COALESCE(started_at, NOW())
      WHERE short_code = $1
    SQL

    LOAD_LOBBY_SQL = <<-SQL
      SELECT short_code, host_player_id::text, status, is_public, settings::text, created_at
      FROM game
      WHERE short_code = $1
        AND status = 'waiting'
    SQL

    LOAD_PUBLIC_LOBBY_CODES_SQL = <<-SQL
      SELECT short_code
      FROM game
      WHERE status = 'waiting'
        AND is_public = TRUE
      ORDER BY created_at DESC
    SQL

    LOAD_PARTICIPANTS_SQL = <<-SQL
      SELECT
        gp.player_id::text,
        COALESCE(NULLIF(u.name, ''), 'Player'),
        gp.is_ready
      FROM game_participant gp
      JOIN game g ON g.id = gp.game_id
      JOIN player p ON p.id = gp.player_id
      LEFT JOIN "user" u ON u.id = p.user_id
      WHERE g.short_code = $1
      ORDER BY gp.joined_at ASC
    SQL

    INSERT_EVENT_SQL = <<-SQL
      WITH target_game AS (
        SELECT id
        FROM game
        WHERE short_code = $1
        FOR UPDATE
      ),
      next_sequence AS (
        SELECT COALESCE(MAX(sequence), 0) + 1 AS sequence
        FROM game_event
        WHERE game_id = (SELECT id FROM target_game)
      )
      INSERT INTO game_event (
        game_id,
        sequence,
        type,
        actor_player_id,
        turn_number,
        phase,
        payload,
        message
      )
      SELECT
        target_game.id,
        next_sequence.sequence,
        $2,
        $3,
        $4,
        $5,
        $6::jsonb,
        $7
      FROM target_game, next_sequence
    SQL

    SAVE_SNAPSHOT_SQL = <<-SQL
      UPDATE game
      SET snapshot = $2::jsonb, snapshot_version = $3
      WHERE short_code = $1
    SQL

    LOAD_SNAPSHOT_SQL = <<-SQL
      SELECT snapshot::text, snapshot_version, settings::text
      FROM game
      WHERE short_code = $1
    SQL

    def initialize(database_url : String)
      @db = DB.open(database_url)
    end

    def create_lobby(host_player_id : String, is_public : Bool, settings_json : String) : PersistedLobby
      10.times do
        short_code = generate_lobby_code

        begin
          @db.transaction do |tx|
            conn = tx.connection
            conn.exec(CREATE_LOBBY_SQL, short_code, host_player_id, is_public, settings_json)
            conn.exec(INSERT_PARTICIPANT_SQL, short_code, host_player_id, false)
          end

          lobby = load_waiting_lobby(short_code)
          return lobby.not_nil! if lobby
        rescue ex
          next if duplicate_short_code?(ex)
          raise ex
        end
      end

      raise "Unable to create a unique lobby code"
    end

    def load_waiting_lobby(lobby_code : String) : PersistedLobby?
      @db.query_one?(LOAD_LOBBY_SQL, lobby_code, as: {String, String, String, Bool, String?, Time}).try do |row|
        short_code, host_player_id, status, is_public, settings_json, created_at = row
        PersistedLobby.new(
          short_code: short_code,
          host_player_id: host_player_id,
          status: status,
          is_public: is_public,
          settings_json: settings_json,
          created_at: created_at,
          participants: load_lobby_participants(short_code)
        )
      end
    end

    def load_public_waiting_lobbies : Array(PersistedLobby)
      lobbies = [] of PersistedLobby
      @db.query(LOAD_PUBLIC_LOBBY_CODES_SQL) do |rs|
        rs.each do
          short_code = rs.read(String)
          if lobby = load_waiting_lobby(short_code)
            lobbies << lobby
          end
        end
      end
      lobbies
    end

    def add_participant(lobby_code : String, player_id : String, ready : Bool = false) : Nil
      result = @db.exec(INSERT_PARTICIPANT_SQL, lobby_code, player_id, ready)
      raise "No game found for lobby #{lobby_code}" if result.rows_affected.zero? && load_waiting_lobby(lobby_code).nil?
    end

    def remove_participant(lobby_code : String, player_id : String) : Nil
      @db.exec(REMOVE_PARTICIPANT_SQL, lobby_code, player_id)
    end

    def update_participant_ready(lobby_code : String, player_id : String, ready : Bool) : Nil
      @db.exec(UPDATE_PARTICIPANT_READY_SQL, lobby_code, player_id, ready)
    end

    def update_lobby_visibility(lobby_code : String, is_public : Bool) : Nil
      result = @db.exec(UPDATE_VISIBILITY_SQL, lobby_code, is_public)
      raise "No game found for lobby #{lobby_code}" if result.rows_affected.zero?
    end

    def update_game_settings(lobby_code : String, settings_json : String) : Nil
      result = @db.exec(UPDATE_SETTINGS_SQL, lobby_code, settings_json)
      raise "No game found for lobby #{lobby_code}" if result.rows_affected.zero?
    end

    def mark_game_started(lobby_code : String) : Nil
      result = @db.exec(MARK_GAME_STARTED_SQL, lobby_code)
      raise "No game found for lobby #{lobby_code}" if result.rows_affected.zero?
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
      result = @db.exec(
        INSERT_EVENT_SQL,
        lobby_code,
        event_type,
        actor_player_id,
        turn_number,
        phase,
        payload_json,
        message
      )

      raise "No game found for lobby #{lobby_code}" if result.rows_affected.zero?
    end

    def save_game_snapshot(lobby_code : String, snapshot_json : String, snapshot_version : Int32) : Nil
      result = @db.exec(SAVE_SNAPSHOT_SQL, lobby_code, snapshot_json, snapshot_version)
      raise "No game found for lobby #{lobby_code}" if result.rows_affected.zero?
    end

    def load_game_snapshot(lobby_code : String) : PersistedGameSnapshot?
      @db.query_one?(
        LOAD_SNAPSHOT_SQL,
        lobby_code,
        as: {String?, Int32?, String?}
      ).try do |snapshot_json, snapshot_version, settings_json|
        next nil unless snapshot_json && snapshot_version

        PersistedGameSnapshot.new(
          snapshot_json: snapshot_json,
          snapshot_version: snapshot_version,
          settings_json: settings_json
        )
      end
    end

    private def load_lobby_participants(lobby_code : String) : Array(PersistedLobbyParticipant)
      participants = [] of PersistedLobbyParticipant
      @db.query(LOAD_PARTICIPANTS_SQL, lobby_code) do |rs|
        rs.each do
          participants << PersistedLobbyParticipant.new(
            player_id: rs.read(String),
            player_name: rs.read(String),
            ready: rs.read(Bool)
          )
        end
      end
      participants
    end

    private def generate_lobby_code : String
      chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
      String.build(6) do |io|
        6.times do
          io << chars[Random.rand(chars.bytesize)]
        end
      end
    end

    private def duplicate_short_code?(ex : Exception) : Bool
      message = ex.message || ""
      message.includes?("game_short_code") || message.includes?("duplicate key")
    end
  end
end
