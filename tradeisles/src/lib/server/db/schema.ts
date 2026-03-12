import { pgTable, text, integer, timestamp, boolean, uuid, varchar, primaryKey } from 'drizzle-orm/pg-core';
import { user } from '../../auth-schema';
import { relations } from 'drizzle-orm';

export const player = pgTable('player', {
	id: uuid('id').defaultRandom().primaryKey(),
	userId: text('user_id').notNull().references(() => user.id, { onDelete: 'cascade' }),
	rating: integer('rating').notNull().default(1000),
	gamesPlayed: integer('games_played').notNull().default(0),
	createdAt: timestamp('created_at').defaultNow().notNull(),
	updatedAt: timestamp('updated_at').defaultNow().notNull()
});

export const game = pgTable('game', {
	id: uuid('id').defaultRandom().primaryKey(),
	shortCode: varchar('short_code', { length: 6 }).notNull().unique(),
	status: varchar('status', { length: 20 }).notNull().default('waiting'),
	hostPlayerId: uuid('host_player_id').notNull().references(() => player.id, { onDelete: 'cascade' }),
	createdAt: timestamp('created_at').defaultNow().notNull(),
	startedAt: timestamp('started_at'),
	finishedAt: timestamp('finished_at')
});

export const gameParticipant = pgTable('game_participant', {
	gameId: uuid('game_id').notNull().references(() => game.id, { onDelete: 'cascade' }),
	playerId: uuid('player_id').notNull().references(() => player.id, { onDelete: 'cascade' }),
	color: varchar('color', { length: 20 }),
	isReady: boolean('is_ready').notNull().default(false),
	joinedAt: timestamp('joined_at').defaultNow().notNull()
}, (table) => [
	primaryKey({ columns: [table.gameId, table.playerId] })
]);

export const playerRelations = relations(player, ({ one, many }) => ({
	user: one(user, {
		fields: [player.userId],
		references: [user.id]
	}),
	hostedGames: many(game),
	gamesJoined: many(gameParticipant)
}));

export const gameRelations = relations(game, ({ one, many }) => ({
	host: one(player, {
		fields: [game.hostPlayerId],
		references: [player.id]
	}),
	participants: many(gameParticipant)
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
