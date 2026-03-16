import { relations } from 'drizzle-orm';
import {
	pgTable,
	text,
	integer,
	timestamp,
	boolean,
	uuid,
	varchar,
	primaryKey,
	jsonb,
	index,
	uniqueIndex
} from 'drizzle-orm/pg-core';
import { user } from '../../auth-schema';

export type GameSettings = {
	turnTimeSeconds: number;
	maxPlayers: number;
	victoryPoints: number;
	useSeafarers: boolean;
	useTraders: boolean;
	useExplorers: boolean;
};

export type GameSnapshot = Record<string, unknown>;

const defaultGameSettings: GameSettings = {
	turnTimeSeconds: 120,
	maxPlayers: 4,
	victoryPoints: 10,
	useSeafarers: false,
	useTraders: false,
	useExplorers: false
};

export const player = pgTable('player', {
	id: uuid('id').defaultRandom().primaryKey(),
	userId: text('user_id')
		.notNull()
		.references(() => user.id, { onDelete: 'cascade' }),
	rating: integer('rating').notNull().default(1000),
	gamesPlayed: integer('games_played').notNull().default(0),
	createdAt: timestamp('created_at').defaultNow().notNull(),
	updatedAt: timestamp('updated_at').defaultNow().notNull()
});

export const game = pgTable('game', {
	id: uuid('id').defaultRandom().primaryKey(),
	shortCode: varchar('short_code', { length: 6 }).notNull().unique(),
	status: varchar('status', { length: 20 }).notNull().default('waiting'),
	settings: jsonb('settings').$type<GameSettings>().notNull().default(defaultGameSettings),
	snapshot: jsonb('snapshot').$type<GameSnapshot>(),
	snapshotVersion: integer('snapshot_version'),
	hostPlayerId: uuid('host_player_id')
		.notNull()
		.references(() => player.id, { onDelete: 'cascade' }),
	createdAt: timestamp('created_at').defaultNow().notNull(),
	startedAt: timestamp('started_at'),
	finishedAt: timestamp('finished_at')
});

export const gameParticipant = pgTable(
	'game_participant',
	{
		gameId: uuid('game_id')
			.notNull()
			.references(() => game.id, { onDelete: 'cascade' }),
		playerId: uuid('player_id')
			.notNull()
			.references(() => player.id, { onDelete: 'cascade' }),
		color: varchar('color', { length: 20 }),
		isReady: boolean('is_ready').notNull().default(false),
		joinedAt: timestamp('joined_at').defaultNow().notNull()
	},
	(table) => [primaryKey({ columns: [table.gameId, table.playerId] })]
);

export type GameEventPayload = Record<string, unknown>;

export const gameEvent = pgTable(
	'game_event',
	{
		id: uuid('id').defaultRandom().primaryKey(),
		gameId: uuid('game_id')
			.notNull()
			.references(() => game.id, { onDelete: 'cascade' }),
		sequence: integer('sequence').notNull(),
		type: varchar('type', { length: 50 }).notNull(),
		actorPlayerId: uuid('actor_player_id').references(() => player.id, { onDelete: 'set null' }),
		turnNumber: integer('turn_number'),
		phase: varchar('phase', { length: 30 }),
		payload: jsonb('payload').$type<GameEventPayload>().notNull(),
		message: text('message'),
		createdAt: timestamp('created_at').defaultNow().notNull()
	},
	(table) => [
		uniqueIndex('game_event_game_sequence_idx').on(table.gameId, table.sequence),
		index('game_event_game_created_idx').on(table.gameId, table.createdAt),
		index('game_event_game_type_idx').on(table.gameId, table.type)
	]
);

export const playerRelations = relations(player, ({ one, many }) => ({
	user: one(user, {
		fields: [player.userId],
		references: [user.id]
	}),
	hostedGames: many(game),
	gamesJoined: many(gameParticipant),
	emittedGameEvents: many(gameEvent)
}));

export const gameRelations = relations(game, ({ one, many }) => ({
	host: one(player, {
		fields: [game.hostPlayerId],
		references: [player.id]
	}),
	participants: many(gameParticipant),
	events: many(gameEvent)
}));

export const gameParticipantRelations = relations(gameParticipant, ({ one }) => ({
	game: one(game, {
		fields: [gameParticipant.gameId],
		references: [game.id]
	}),
	player: one(player, {
		fields: [gameParticipant.playerId],
		references: [player.id]
	})
}));

export const gameEventRelations = relations(gameEvent, ({ one }) => ({
	game: one(game, {
		fields: [gameEvent.gameId],
		references: [game.id]
	}),
	actor: one(player, {
		fields: [gameEvent.actorPlayerId],
		references: [player.id]
	})
}));
