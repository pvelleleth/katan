export const resourceKeys = ['wood', 'brick', 'sheep', 'wheat', 'ore'] as const;

export type ResourceKey = (typeof resourceKeys)[number];

export type ResourcePile = Record<ResourceKey, number>;

export const resourceLabels: Record<ResourceKey, string> = {
	wood: 'Wood',
	brick: 'Brick',
	sheep: 'Sheep',
	wheat: 'Wheat',
	ore: 'Ore'
};

export function createEmptyResourcePile(): ResourcePile {
	return {
		wood: 0,
		brick: 0,
		sheep: 0,
		wheat: 0,
		ore: 0
	};
}

export function sumResourcePile(
	pile: Partial<Record<ResourceKey, number>> | null | undefined
): number {
	return resourceKeys.reduce((total, resource) => total + (pile?.[resource] ?? 0), 0);
}

export function hasAnyResources(
	pile: Partial<Record<ResourceKey, number>> | null | undefined
): boolean {
	return sumResourcePile(pile) > 0;
}

export function inferBankTradeRate(
	gameState: any,
	playerId: string,
	resource: ResourceKey
): number {
	if (!gameState?.board?.harbors || !gameState?.board?.vertices) {
		return 4;
	}

	const ownedVertexIds = new Set(
		gameState.board.vertices
			.filter((vertex: any) => vertex.building?.player_id === playerId)
			.map((vertex: any) => vertex.id)
	);

	let bestRate = 4;

	for (const harbor of gameState.board.harbors) {
		const claimed = harbor.vertex_ids?.some((vertexId: string) => ownedVertexIds.has(vertexId));
		if (!claimed) continue;

		switch (harbor.kind) {
			case 'ThreeToOne':
				bestRate = Math.min(bestRate, 3);
				break;
			case 'WoodTwoToOne':
				if (resource === 'wood') bestRate = Math.min(bestRate, 2);
				break;
			case 'BrickTwoToOne':
				if (resource === 'brick') bestRate = Math.min(bestRate, 2);
				break;
			case 'SheepTwoToOne':
				if (resource === 'sheep') bestRate = Math.min(bestRate, 2);
				break;
			case 'WheatTwoToOne':
				if (resource === 'wheat') bestRate = Math.min(bestRate, 2);
				break;
			case 'OreTwoToOne':
				if (resource === 'ore') bestRate = Math.min(bestRate, 2);
				break;
		}
	}

	return bestRate;
}
