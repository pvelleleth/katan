import { json } from '@sveltejs/kit';
import { db } from '$lib/server/db';
import { game, gameEvent } from '$lib/server/db/schema';
import { eq, asc } from 'drizzle-orm';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ params }) => {
	const shortCode = params.id;

	const gameRecord = await db.query.game.findFirst({
		where: eq(game.shortCode, shortCode),
		columns: { id: true }
	});

	if (!gameRecord) {
		return json({ error: 'Game not found' }, { status: 404 });
	}

	const events = await db.query.gameEvent.findMany({
		where: eq(gameEvent.gameId, gameRecord.id),
		orderBy: [asc(gameEvent.sequence)],
		columns: {
			id: true,
			sequence: true,
			message: true,
			createdAt: true
		}
	});

	return json({ events });
};
