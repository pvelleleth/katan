require "db"
require "pg"
require "./game_event_store"

module Settler::Engine::Infrastructure::Persistence
  class PostgresGameEventStore < GameEventStore
    @db : DB::Database

    UPDATE_SETTINGS_SQL = <<-SQL
      UPDATE game
      SET settings = $2::jsonb
      WHERE short_code = $1
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

    def update_game_settings(lobby_code : String, settings_json : String) : Nil
      result = @db.exec(UPDATE_SETTINGS_SQL, lobby_code, settings_json)
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
  end
end
