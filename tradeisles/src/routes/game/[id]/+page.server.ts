import { error } from '@sveltejs/kit';
import { db } from '$lib/server/db';
import { game, gameParticipant, player } from '$lib/server/db/schema';
import { eq, and } from 'drizzle-orm';
import type { PageServerLoad } from './$types';
import { auth } from '$lib/auth';

export const load: PageServerLoad = async (event) => {
	const lobbyId = event.params.id.toUpperCase();
	
	// 1. Authenticate user
	const session = await auth.api.getSession({
		headers: event.request.headers
	});

	if (!session?.user) {
		// They will be redirected by the client-side logic, or we could redirect here
		return { lobbyId, joinSuccess: false };
	}

	try {
		// 2. Find the game
		const activeGame = await db.query.game.findFirst({
			where: eq(game.shortCode, lobbyId)
		});

		if (!activeGame) {
			throw error(404, 'Lobby not found');
		}

		// 3. Find or create player profile
		let activePlayer = await db.query.player.findFirst({
			where: eq(player.userId, session.user.id)
		});

		if (!activePlayer) {
			const [newPlayer] = await db
				.insert(player)
				.values({ userId: session.user.id })
				.returning();
			activePlayer = newPlayer;
		}

		// 4. Check if player is already in the game participant list
		const existingParticipant = await db.query.gameParticipant.findFirst({
			where: and(
				eq(gameParticipant.gameId, activeGame.id),
				eq(gameParticipant.playerId, activePlayer.id)
			)
		});

		// 5. If not, join them to the game
		if (!existingParticipant) {
			// Find how many players are in the game to assign a different color maybe?
			// Keeping it simple and assigning a default for now.
			await db.insert(gameParticipant).values({
				gameId: activeGame.id,
				playerId: activePlayer.id,
				isReady: false,
				color: 'ocean' // fallback color
			});
		}

		return {
			lobbyId,
			playerId: activePlayer.id,
            hostId: activeGame.hostPlayerId
		};

	} catch (e) {
		console.error('Error joining lobby:', e);
		throw error(500, 'Error joining lobby');
	}
};
