ALTER TABLE "game" ADD COLUMN "snapshot" jsonb;
--> statement-breakpoint
ALTER TABLE "game" ADD COLUMN "snapshot_version" integer;
