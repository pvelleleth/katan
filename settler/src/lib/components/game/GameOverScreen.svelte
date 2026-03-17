<script lang="ts">
	import { goto } from '$app/navigation';
	import { computeDiceStats, theoreticalProbabilities } from '$lib/utils/diceStats';

	export let gameState: any;
	export let players: any[]; // lobby players (has colors)
	export let playerId: string;
	export let gameLog: { type?: string; payload?: any; message: string; createdAt: string }[] = [];
	export let onShowBoard: () => void;

	let showDiceStats = false;

	$: diceStats = computeDiceStats(gameLog);
	$: totalRolls = Object.values(diceStats).reduce((a, b) => a + b, 0);
	$: highestRollCount = Math.max(...Object.values(diceStats), 0);

	const rollNumbers = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

	$: winnerPlayerId = gameState.winner_player_id as string | null;
	$: playerOrder = gameState.player_order as string[];

	// Total VP = public (buildings, longest road, largest army) + hidden victory point cards
	const totalVP = (p: any) =>
		(p?.victory_points ?? 0) + (p?.victory_point_cards ?? 0);

	// Merge game-state player data with lobby colors
	$: rankedPlayers = [...playerOrder]
		.map((id: string) => {
			const gPlayer = gameState.players.find((p: any) => p.id === id);
			const lPlayer = players.find((p: any) => p.id === id);
			const settlementsBuilt = Math.max(0, 5 - (gPlayer?.settlements_left ?? 0));
			const citiesBuilt = Math.max(0, 4 - (gPlayer?.cities_left ?? 0));

			return {
				...gPlayer,
				color: lPlayer?.color || 'wood',
				settlementsBuilt,
				citiesBuilt,
				longestRoadPoints: gPlayer?.has_longest_road ? 2 : 0,
				largestArmyPoints: gPlayer?.has_largest_army ? 2 : 0
			};
		})
		.sort((a: any, b: any) => totalVP(b) - totalVP(a));

	$: winner = rankedPlayers.find((p: any) => p.id === winnerPlayerId) ?? rankedPlayers[0];
	$: iAmWinner = winnerPlayerId === playerId;

	const colorBg: Record<string, string> = {
		brick: 'bg-brick',
		ocean: 'bg-ocean',
		wheat: 'bg-wheat',
		forest: 'bg-forest',
		purple: 'bg-purple',
		wood: 'bg-wood'
	};

	const colorText: Record<string, string> = {
		brick: 'text-brick',
		ocean: 'text-ocean',
		wheat: 'text-wheat',
		forest: 'text-forest',
		purple: 'text-purple',
		wood: 'text-wood'
	};

</script>

<!-- Full-screen overlay -->
<div
	class="fixed inset-0 z-50 overflow-y-auto bg-black/70 px-4 py-6 backdrop-blur-md"
	aria-modal="true"
	role="dialog"
	aria-label="Game Over"
>
	<!-- Confetti / decorative particles (CSS-only) -->
	<div class="pointer-events-none absolute inset-0 overflow-hidden" aria-hidden="true">
		{#each Array(18) as _, i}
			<div
				class="particle absolute rounded-full opacity-80"
				style="
					--delay: {(i * 0.37) % 3}s;
					--x: {(i * 53) % 100}%;
					--size: {8 + ((i * 7) % 18)}px;
					--hue: {(i * 37) % 360}deg;
					left: var(--x);
					top: -20px;
					width: var(--size);
					height: var(--size);
					background: hsl(var(--hue), 80%, 60%);
					animation: fall 4s ease-in var(--delay) infinite;
				"
			></div>
		{/each}
	</div>

	<!-- Card -->
	<div
		class="animate-in zoom-in-95 fade-in relative mx-auto flex w-full max-w-6xl flex-col gap-8 rounded-3xl border-2 border-white/20 bg-white/95 p-6 shadow-2xl duration-500 lg:p-8"
	>
		<div class="flex flex-col gap-6 lg:flex-row lg:items-start lg:justify-between">
			<div class="flex flex-col gap-4 text-center lg:max-w-2xl lg:text-left">
				<div class="flex flex-col items-center gap-3 lg:flex-row lg:items-center">
					<div
						class="flex h-20 w-20 items-center justify-center rounded-full bg-amber-400 shadow-xl ring-4 shadow-amber-400/40 ring-amber-200"
					>
						<svg class="h-10 w-10 text-amber-900" fill="currentColor" viewBox="0 0 24 24">
							<path
								d="M2 19l2-9 4.5 4L12 5l3.5 9L20 10l2 9H2zm2.17-2h15.66l-1.25-5.63L15 15l-3-7.5L9 15l-3.58-3.63L4.17 17z"
							/>
						</svg>
					</div>

					<div>
						{#if iAmWinner}
							<h1 class="text-4xl font-black tracking-tight text-amber-600">You Won!</h1>
							<p class="mt-2 text-lg font-semibold text-wood-dark/70">
								Your final score was <span class="font-black text-amber-600">{totalVP(winner)} VP</span>.
							</p>
						{:else}
							<h1 class="text-4xl font-black tracking-tight text-wood-dark">Game Over</h1>
							<p class="mt-2 text-lg font-semibold text-wood-dark/70">
								<span class={colorText[winner?.color] ?? 'text-wood'}>{winner?.name}</span> wins with
								<span class="font-black text-amber-600">{totalVP(winner)} VP</span>.
							</p>
						{/if}
					</div>
				</div>

				<p class="text-sm font-semibold text-wood-light/80 lg:pr-12">
					Review how each player reached their final score, then switch back to the map to inspect the final
					board position.
				</p>
			</div>

			<div class="flex flex-col gap-3 lg:w-64">
				<button
					on:click={onShowBoard}
					class="flex w-full items-center justify-center gap-2 rounded-2xl bg-ocean px-5 py-3 text-sm font-bold text-white shadow-xl shadow-ocean/20 transition-all hover:scale-[1.01] hover:bg-ocean/90 active:scale-95"
				>
					<svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path
							stroke-linecap="round"
							stroke-linejoin="round"
							stroke-width="2.5"
							d="M15 19l-7-7 7-7"
						/>
					</svg>
					View Final Board
				</button>

				<button
					on:click={() => (showDiceStats = !showDiceStats)}
					class="flex w-full items-center justify-center gap-2 rounded-2xl border border-wood/15 bg-white px-5 py-3 text-sm font-bold text-wood-dark transition-all hover:border-ocean/30 hover:text-ocean"
				>
					<svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path
							stroke-linecap="round"
							stroke-linejoin="round"
							stroke-width="2.5"
							d={showDiceStats ? 'M5 15l7-7 7 7' : 'M19 9l-7 7-7-7'}
						/>
					</svg>
					{showDiceStats ? 'Hide Dice Stats' : 'Show Dice Stats'}
				</button>
			</div>
		</div>

		<div class="w-full">
			<div class="mb-3 flex items-center justify-between gap-4">
				<h2 class="text-xs font-bold tracking-widest text-wood-light/70 uppercase">
					Final Game Summary
				</h2>
				<p class="text-xs font-semibold text-wood-light/80">
					Built pieces, awards, revealed VP cards, and final score at game end.
				</p>
			</div>

			<div class="overflow-hidden rounded-3xl border border-wood/10 bg-white/70 shadow-sm">
				<div class="overflow-x-auto">
					<table class="min-w-full border-collapse text-sm text-wood-dark">
						<thead class="bg-parchment/80 text-[11px] font-black tracking-widest text-wood-light uppercase">
							<tr>
								<th class="px-4 py-3 text-left">Player</th>
								<th class="px-4 py-3 text-center">Cities</th>
								<th class="px-4 py-3 text-center">Settlements</th>
								<th class="px-4 py-3 text-center">Longest Road</th>
								<th class="px-4 py-3 text-center">Largest Army</th>
								<th class="px-4 py-3 text-center">VP Cards</th>
								<th class="px-4 py-3 text-center">Total VP</th>
							</tr>
						</thead>
						<tbody>
							{#each rankedPlayers as player, rank}
								{@const isWinner = player.id === winnerPlayerId}
								{@const isMe = player.id === playerId}
								<tr class={isWinner ? 'bg-amber-50/80' : rank % 2 === 0 ? 'bg-white/70' : 'bg-parchment/35'}>
									<td class="px-4 py-3">
										<div class="flex items-center gap-3">
											<div
												class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-sm font-black {rank === 0
													? 'bg-amber-400 text-amber-900'
													: rank === 1
														? 'bg-slate-300 text-slate-700'
														: rank === 2
															? 'bg-amber-700/60 text-amber-100'
															: 'bg-wood/10 text-wood-dark'}"
											>
												{rank + 1}
											</div>
											<div
												class="flex h-9 w-9 shrink-0 items-center justify-center rounded-full border-2 border-white text-sm font-bold text-white shadow-sm {colorBg[
													player.color
												] ?? 'bg-wood'}"
											>
												{player.name.charAt(0).toUpperCase()}
											</div>
											<div class="min-w-0">
												<div class="truncate font-bold">
													{player.name}
													{#if isMe}
														<span class="ml-1 text-xs font-normal text-wood-light">(You)</span>
													{/if}
													{#if isWinner}
														<span class="ml-1">👑</span>
													{/if}
												</div>
												<div class="text-xs font-semibold text-wood-light/80">
													<span class={colorText[player.color] ?? 'text-wood'}>{player.color}</span>
													<span class="mx-1.5">•</span>
													<span>{isWinner ? 'Winner' : 'Finished'}</span>
												</div>
											</div>
										</div>
									</td>
									<td class="px-4 py-3 text-center font-bold">{player.citiesBuilt}</td>
									<td class="px-4 py-3 text-center font-bold">{player.settlementsBuilt}</td>
									<td class="px-4 py-3 text-center font-bold">
										{player.longestRoadPoints ? `Yes (+${player.longestRoadPoints})` : 'No'}
									</td>
									<td class="px-4 py-3 text-center font-bold">
										{player.largestArmyPoints ? `Yes (+${player.largestArmyPoints})` : 'No'}
									</td>
									<td class="px-4 py-3 text-center font-bold">{player.victory_point_cards ?? 0}</td>
									<td class="px-4 py-3 text-center">
										<span class="inline-flex items-center gap-1 font-black text-amber-600">
											{totalVP(player)}
											<svg class="h-4 w-4" fill="currentColor" viewBox="0 0 24 24">
												<path
													d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"
												/>
											</svg>
										</span>
									</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
			</div>
		</div>

		{#if showDiceStats}
			<div class="w-full rounded-3xl border border-wood/10 bg-parchment/45 p-5">
				<h2 class="mb-4 text-center text-xs font-bold tracking-widest text-wood-light/70 uppercase">
					Dice Stats ({totalRolls} total rolls)
				</h2>
				<div class="flex h-32 items-end justify-between gap-1 px-2">
					{#each rollNumbers as num}
						{@const count = diceStats[num] || 0}
						{@const theoreticalPct = theoreticalProbabilities[num] * 100}
						{@const actualPct = totalRolls > 0 ? (count / totalRolls) * 100 : 0}
						<div class="group relative flex flex-1 flex-col items-center">
							<div
								class="w-full rounded-t-sm bg-ocean transition-all duration-500"
								style="height: {highestRollCount > 0 ? (count / highestRollCount) * 80 : 0}px"
							></div>
							<div
								class="absolute h-1 w-1 rounded-full bg-brick opacity-40"
								style="bottom: {highestRollCount > 0 ? ((theoreticalProbabilities[num] * totalRolls) / highestRollCount) * 80 + 24 : 24}px"
							></div>

							<span class="mt-2 text-[10px] font-black text-wood-dark/40">{num}</span>

							<div
								class="pointer-events-none absolute bottom-full mb-2 hidden -translate-y-1 rounded bg-wood-dark px-2 py-1 text-[10px] text-white whitespace-nowrap group-hover:block"
							>
								Roll {num}: {count} ({actualPct.toFixed(1)}%)
								<br />
								Expected: {theoreticalPct.toFixed(1)}%
							</div>
						</div>
					{/each}
				</div>
				<div class="mt-4 flex items-center justify-center gap-4 text-[10px] font-bold">
					<div class="flex items-center gap-1.5">
						<div class="h-2 w-2 rounded-full bg-ocean"></div>
						<span class="text-wood-light uppercase">Actual</span>
					</div>
					<div class="flex items-center gap-1.5">
						<div class="h-2 w-2 rounded-full bg-brick opacity-40"></div>
						<span class="text-wood-light uppercase">Expected</span>
					</div>
				</div>
			</div>
		{/if}

		<div class="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
			<button
				on:click={() => goto('/game')}
				class="flex items-center justify-center gap-2 rounded-2xl border border-wood/15 bg-white px-6 py-3 text-sm font-bold text-wood-dark transition-all hover:border-brick/20 hover:text-brick"
			>
				<svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
					<path
						stroke-linecap="round"
						stroke-linejoin="round"
						stroke-width="2.5"
						d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6"
					/>
				</svg>
				Back to Lobby
			</button>
		</div>
	</div>
</div>

<style>
	@keyframes fall {
		0% {
			transform: translateY(0) rotate(0deg);
			opacity: 1;
		}
		100% {
			transform: translateY(110vh) rotate(720deg);
			opacity: 0;
		}
	}

	.particle {
		animation: fall 4s ease-in infinite;
	}
</style>
