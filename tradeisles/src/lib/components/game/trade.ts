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

const harborResourceByKind: Partial<Record<string, ResourceKey>> = {
	WoodTwoToOne: 'wood',
	wood_two_to_one: 'wood',
	BrickTwoToOne: 'brick',
	brick_two_to_one: 'brick',
	SheepTwoToOne: 'sheep',
	sheep_two_to_one: 'sheep',
	WheatTwoToOne: 'wheat',
	wheat_two_to_one: 'wheat',
	OreTwoToOne: 'ore',
	ore_two_to_one: 'ore'
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
	const harbors = gameState?.board?.harbors;
	const vertices = gameState?.board?.vertices;

	if (!harbors || !vertices || !playerId) {
		return 4;
	}

	const ownedVertexIds = new Set(
		vertices
			.filter((vertex: any) => vertex.building?.player_id === playerId)
			.map((vertex: any) => vertex.id)
	);

	let bestRate = 4;

	for (const harbor of harbors) {
		const claimed = harbor.vertex_ids?.some((vertexId: string) => ownedVertexIds.has(vertexId));
		if (!claimed) continue;

		if (harbor.kind === 'ThreeToOne' || harbor.kind === 'three_to_one') {
			bestRate = Math.min(bestRate, 3);
			continue;
		}

		if (harborResourceByKind[harbor.kind] === resource) {
			bestRate = Math.min(bestRate, 2);
		}
	}

	return bestRate;
}

export function getBankTradeRates(gameState: any, playerId: string): ResourcePile {
	return resourceKeys.reduce(
		(rates, resource) => ({
			...rates,
			[resource]: inferBankTradeRate(gameState, playerId, resource)
		}),
		createEmptyResourcePile()
	);
}
