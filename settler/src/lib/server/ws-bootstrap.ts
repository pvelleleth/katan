import { createHmac } from 'node:crypto';
import { env } from '$env/dynamic/private';

export type WsBootstrapPayload = {
	userId: string;
	playerId: string;
	name: string;
	exp: number;
	lobbyId?: string;
};

const DEFAULT_TTL_SECONDS = 60 * 5;

function getBootstrapSecret() {
	const secret = env.WS_BOOTSTRAP_SECRET || env.BETTER_AUTH_SECRET;
	if (!secret) {
		throw new Error('Missing websocket bootstrap secret');
	}

	return secret;
}

function toBase64Url(value: string | Buffer) {
	return Buffer.from(value).toString('base64url');
}

export function createWsBootstrapToken(
	input: Omit<WsBootstrapPayload, 'exp'> & { expiresInSeconds?: number }
) {
	const expiresAt = Math.floor(Date.now() / 1000) + (input.expiresInSeconds ?? DEFAULT_TTL_SECONDS);
	const payload: WsBootstrapPayload = {
		userId: input.userId,
		playerId: input.playerId,
		name: input.name,
		exp: expiresAt,
		...(input.lobbyId ? { lobbyId: input.lobbyId } : {})
	};
	const encodedPayload = toBase64Url(JSON.stringify(payload));
	const signature = createHmac('sha256', getBootstrapSecret())
		.update(encodedPayload)
		.digest('base64url');

	return {
		token: `${encodedPayload}.${signature}`,
		expiresAt
	};
}
