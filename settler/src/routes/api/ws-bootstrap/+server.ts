import { json } from '@sveltejs/kit';
import { auth } from '$lib/auth';
import { db } from '$lib/server/db';
import { game, player } from '$lib/server/db/schema';
import { eq } from 'drizzle-orm';
import { createWsBootstrapToken } from '$lib/server/ws-bootstrap';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ request, url }) => {
	const session = await auth.api.getSession({
		headers: request.headers
	});

	if (!session?.user) {
		return json({ error: 'Unauthorized' }, { status: 401 });
	}

	const lobbyId = url.searchParams.get('lobbyId')?.toUpperCase();

	if (lobbyId) {
		const existingGame = await db.query.game.findFirst({
			where: eq(game.shortCode, lobbyId),
			columns: {
				id: true,
				status: true
			}
		});

		if (!existingGame || existingGame.status === 'abandoned') {
			return json({ error: 'Lobby not found' }, { status: 404 });
		}
	}

	let activePlayer = await db.query.player.findFirst({
		where: eq(player.userId, session.user.id)
	});

	if (!activePlayer) {
		const [newPlayer] = await db
			.insert(player)
			.values({
				userId: session.user.id
			})
			.returning();
		activePlayer = newPlayer;
	}

	const name =
		typeof session.user.name === 'string' && session.user.name.length > 0
			? session.user.name
			: session.user.isAnonymous
				? 'Guest Player'
				: 'Player';

	const { token, expiresAt } = createWsBootstrapToken({
		userId: session.user.id,
		playerId: activePlayer.id,
		name,
		lobbyId
	});

	return json({
		token,
		playerId: activePlayer.id,
		name,
		expiresAt
	});
};
