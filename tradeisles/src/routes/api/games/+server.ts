import { json } from '@sveltejs/kit';
import { db } from '$lib/server/db';
import { game, gameParticipant, player } from '$lib/server/db/schema';
import { auth } from '$lib/auth';
import { eq } from 'drizzle-orm';
import type { RequestEvent } from './$types';

// Helper to generate a 6-character short code
function generateLobbyCode() {
	const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
	let result = '';
	for (let i = 0; i < 6; i++) {
		result += chars.charAt(Math.floor(Math.random() * chars.length));
	}
	return result;
}

export async function POST(event: RequestEvent) {
	try {
		// 1. Authenticate user
		const session = await auth.api.getSession({
			headers: event.request.headers
		});

		if (!session?.user) {
			return json({ error: 'Unauthorized' }, { status: 401 });
		}

		// 2. Find or create player profile for this user
		let activePlayer = await db.query.player.findFirst({
			where: eq(player.userId, session.user.id)
		});

		if (!activePlayer) {
			// This is their first time organizing/joining a game, create their profile
			const [newPlayer] = await db
				.insert(player)
				.values({
					userId: session.user.id
				})
				.returning();
			activePlayer = newPlayer;
		}

		// 3. Generate a unique code and verify it's not currently in use for waiting/active games
		// (For simplicity here, we assume collisions are rare on 36^6, but a true robust loop would retry)
		const shortCode = generateLobbyCode();

		// 4. Create the game transaction to ensure both records insert together
		const result = await db.transaction(async (tx) => {
			// Create the Lobby
			const [newGame] = await tx
				.insert(game)
				.values({
					shortCode,
					hostPlayerId: activePlayer.id
				})
				.returning();

			// Add the host as the first participant
			await tx.insert(gameParticipant).values({
				gameId: newGame.id,
				playerId: activePlayer.id,
				color: 'brick', // Default host color, they can change later
				isReady: false
			});

			return newGame;
		});

		return json({
			success: true,
			game: {
				id: result.id,
				shortCode: result.shortCode
			}
		});
	} catch (error) {
		console.error('Error creating new game:', error);
		return json({ error: 'Internal server error while creating lobby' }, { status: 500 });
	}
}
