CREATE TABLE "game_event" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"game_id" uuid NOT NULL,
	"sequence" integer NOT NULL,
	"type" varchar(50) NOT NULL,
	"actor_player_id" uuid,
	"turn_number" integer,
	"phase" varchar(30),
	"payload" jsonb NOT NULL,
	"message" text,
	"created_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "game_event" ADD CONSTRAINT "game_event_game_id_game_id_fk" FOREIGN KEY ("game_id") REFERENCES "public"."game"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
ALTER TABLE "game_event" ADD CONSTRAINT "game_event_actor_player_id_player_id_fk" FOREIGN KEY ("actor_player_id") REFERENCES "public"."player"("id") ON DELETE set null ON UPDATE no action;
--> statement-breakpoint
CREATE UNIQUE INDEX "game_event_game_sequence_idx" ON "game_event" USING btree ("game_id","sequence");
--> statement-breakpoint
CREATE INDEX "game_event_game_created_idx" ON "game_event" USING btree ("game_id","created_at");
--> statement-breakpoint
CREATE INDEX "game_event_game_type_idx" ON "game_event" USING btree ("game_id","type");
