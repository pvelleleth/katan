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
		return { lobbyId, joinSuccess: false, needsSessionRefresh: true };
	}

	try {
		// 2. Find the game
		const activeGame = await db.query.game.findFirst({
			where: eq(game.shortCode, lobbyId),
			with: {
				participants: {
					columns: {
						playerId: true
					}
				}
			}
		});

		if (!activeGame) {
			throw error(404, 'Lobby not found');
		}

		// 3. Find existing player profile when available. The websocket bootstrap route
		// is responsible for creating it if this is the user's first lobby.
		const activePlayer = await db.query.player.findFirst({
			where: eq(player.userId, session.user.id)
		});

		// 4. Check if player is already in the game participant list
		const existingParticipant = activePlayer
			? await db.query.gameParticipant.findFirst({
					where: and(
						eq(gameParticipant.gameId, activeGame.id),
						eq(gameParticipant.playerId, activePlayer.id)
					)
				})
			: null;

		// 5. Reject only when the lobby is already full and the viewer is not yet in it.
		if (!existingParticipant) {
			const isLobbyFull = activeGame.participants.length >= activeGame.settings.maxPlayers;

			if (isLobbyFull) {
				return {
					lobbyId,
					hostId: activeGame.hostPlayerId,
					settings: activeGame.settings,
					status: activeGame.status,
					isPublic: activeGame.isPublic,
					joinSuccess: false,
					joinError: 'This lobby is full.'
				};
			}
		}

		return {
			lobbyId,
			hostId: activeGame.hostPlayerId,
			settings: activeGame.settings,
			status: activeGame.status,
			isPublic: activeGame.isPublic,
			joinSuccess: true
		};
	} catch (e) {
		console.error('Error joining lobby:', e);
		throw error(500, 'Error joining lobby');
	}
};
