export type DiceStats = Record<number, number>;

export function computeDiceStats(gameLog: { type?: string; payload?: any }[]): DiceStats {
	const stats: DiceStats = {
		2: 0,
		3: 0,
		4: 0,
		5: 0,
		6: 0,
		7: 0,
		8: 0,
		9: 0,
		10: 0,
		11: 0,
		12: 0
	};

	for (const event of gameLog) {
		if (event.type === 'dice_rolled' && event.payload?.total) {
			const total = Number(event.payload.total);
			if (stats[total] !== undefined) {
				stats[total]++;
			}
		}
	}

	return stats;
}

export const theoreticalProbabilities: Record<number, number> = {
	2: 1 / 36,
	3: 2 / 36,
	4: 3 / 36,
	5: 4 / 36,
	6: 5 / 36,
	7: 6 / 36,
	8: 5 / 36,
	9: 4 / 36,
	10: 3 / 36,
	11: 2 / 36,
	12: 1 / 36
};
