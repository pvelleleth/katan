import type { ResourceKey } from './trade';

export type BoardVertex = {
	id: string;
	building?: {
		player_id: string;
	};
};

export type BoardEdge = {
	id: string;
	v1: string;
	v2: string;
	road?: {
		player_id: string;
	};
};

export type BoardState = {
	edges: BoardEdge[];
	vertices: BoardVertex[];
};

export const devCardLabels = {
	knight: 'Knight',
	victory_point: 'Victory Point',
	road_building: 'Road Building',
	year_of_plenty: 'Year of Plenty',
	monopoly: 'Monopoly'
} as const;

export const backendResourceNames: Record<ResourceKey, string> = {
	wood: 'Wood',
	brick: 'Brick',
	sheep: 'Sheep',
	wheat: 'Wheat',
	ore: 'Ore'
};

function touchesVertex(edge: BoardEdge, vertexId: string) {
	return edge.v1 === vertexId || edge.v2 === vertexId;
}

function playerRoadTouchesVertex(
	board: BoardState,
	vertexId: string,
	playerId: string,
	pendingEdgeIds: string[],
	ignoreEdgeId?: string
) {
	return board.edges.some((edge) => {
		if (!touchesVertex(edge, vertexId) || edge.id === ignoreEdgeId) {
			return false;
		}

		if (pendingEdgeIds.includes(edge.id)) {
			return true;
		}

		return edge.road?.player_id === playerId;
	});
}

function vertexConnectsToNetwork(
	board: BoardState,
	vertexId: string,
	playerId: string,
	pendingEdgeIds: string[],
	candidateEdgeId: string
) {
	const vertex = board.vertices.find((item) => item.id === vertexId);
	if (vertex?.building) {
		return vertex.building.player_id === playerId;
	}

	return playerRoadTouchesVertex(board, vertexId, playerId, pendingEdgeIds, candidateEdgeId);
}

function edgeConnectsToNetwork(
	board: BoardState,
	edge: BoardEdge,
	playerId: string,
	pendingEdgeIds: string[]
) {
	return (
		vertexConnectsToNetwork(board, edge.v1, playerId, pendingEdgeIds, edge.id) ||
		vertexConnectsToNetwork(board, edge.v2, playerId, pendingEdgeIds, edge.id)
	);
}

export function getLegalRoadBuildingEdges(
	board: BoardState | null | undefined,
	playerId: string,
	selectedEdgeIds: string[] = [],
	roadsLeft = Number.POSITIVE_INFINITY
) {
	if (!board || roadsLeft <= selectedEdgeIds.length) {
		return [];
	}

	return board.edges.filter((edge) => {
		if (selectedEdgeIds.includes(edge.id) || edge.road) {
			return false;
		}

		return edgeConnectsToNetwork(board, edge, playerId, selectedEdgeIds);
	});
}

export function canConfirmSingleRoadBuildingPlacement(
	board: BoardState | null | undefined,
	playerId: string,
	selectedEdgeIds: string[],
	roadsLeft: number
) {
	if (selectedEdgeIds.length !== 1) {
		return false;
	}

	if (roadsLeft <= selectedEdgeIds.length) {
		return true;
	}

	return getLegalRoadBuildingEdges(board, playerId, selectedEdgeIds).length === 0;
}
