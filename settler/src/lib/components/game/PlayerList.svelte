<script lang="ts">
	import { tick } from 'svelte';

	export let gameState: any;
	export let players: any[]; // From lobby, has colors
	export let playerId: string;
	export let gameLog: { message: string; createdAt: string }[] = [];
	export let sendGameAction: (action: string, payload?: any) => void;

	let gameLogContainer: HTMLDivElement;
	let previousGameLogLength = 0;

	$: currentPlayerId = gameState.turn.current_player_id;
	$: playerOrder = gameState.player_order;
	$: phase = gameState.turn.phase;
	$: isMyTurn = currentPlayerId === playerId;
	$: isStealPhase = phase === 'StealResource';
	$: eligibleVictims = gameState.turn.robber_eligible_victim_ids || [];

	// Map game state players to lobby players to get colors
	$: gamePlayers = playerOrder.map((id: string) => {
		const gPlayer = gameState.players.find((p: any) => p.id === id);
		const lPlayer = players.find((p: any) => p.id === id);
		return {
			...gPlayer,
			color: lPlayer?.color || 'wood',
			isConnected: lPlayer?.isConnected ?? true
		};
	});

	const colorClasses: Record<string, string> = {
		brick: 'bg-brick text-white border-brick',
		ocean: 'bg-ocean text-white border-ocean',
		wheat: 'bg-wheat text-wood-dark border-wheat',
		forest: 'bg-forest text-white border-forest',
		purple: 'bg-purple text-white border-purple',
		wood: 'bg-wood text-white border-wood'
	};

	function handleSteal(victimId: string) {
		if (!isMyTurn || !isStealPhase || !eligibleVictims.includes(victimId)) return;
		sendGameAction('robber_steal', { victim_player_id: victimId });
	}

	$: if (gameLog.length !== previousGameLogLength) {
		previousGameLogLength = gameLog.length;
		scrollGameLogToBottom();
	}

	async function scrollGameLogToBottom() {
		await tick();
		gameLogContainer?.scrollTo({
			top: gameLogContainer.scrollHeight,
			behavior: 'smooth'
		});
	}
</script>

<div class="flex h-full flex-col gap-6">
	<div>
		<h2 class="mb-4 text-xl font-black text-wood-dark">Players</h2>
		<div class="flex flex-col gap-3">
			{#each gamePlayers as player}
				{@const isCurrentTurn = player.id === currentPlayerId}
				{@const isMe = player.id === playerId}
				{@const hasLongestRoad = player.has_longest_road}
				{@const hasLargestArmy = player.has_largest_army}
				<div
					class="relative flex flex-col gap-2 rounded-2xl border-2 p-3 transition-all {isCurrentTurn
						? 'border-ocean bg-white shadow-lg'
						: 'border-wood/10 bg-white/50'} {player.isConnected ? '' : 'opacity-65'}"
				>
					{#if isCurrentTurn}
						<div
							class="absolute -top-3 -right-3 flex h-6 w-6 items-center justify-center rounded-full bg-ocean text-white shadow-md"
						>
							<svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
								<path
									stroke-linecap="round"
									stroke-linejoin="round"
									stroke-width="3"
									d="M13 10V3L4 14h7v7l9-11h-7z"
								/>
							</svg>
						</div>
					{/if}

					<div class="flex items-center gap-3">
						<div
							class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full border-2 border-white/50 shadow-sm {colorClasses[
								player.color
							]}"
						>
							<span class="text-sm font-bold">{player.name.charAt(0).toUpperCase()}</span>
						</div>
						<div class="min-w-0 flex-1">
							<div class="truncate font-bold text-wood-dark">
								{player.name}
								{#if isMe}
									<span class="ml-1 text-xs text-wood-light">(You)</span>
								{/if}
							</div>
							{#if !player.isConnected}
								<div class="mt-0.5">
									<span
										class="rounded-full bg-brick/10 px-2 py-0.5 text-[0.6rem] font-black tracking-wider text-brick uppercase"
									>
										Disconnected
									</span>
								</div>
							{/if}
						</div>
						<div class="flex items-center gap-1.5">
							{#if hasLongestRoad}
								<div
									class="flex h-6 w-6 items-center justify-center rounded-full border border-amber-300 bg-amber-50 text-amber-700"
									title="Longest Road (+2 VP)"
									aria-label="Longest Road"
								>
									<svg
										class="h-3.5 w-3.5"
										fill="none"
										stroke="currentColor"
										stroke-width="2"
										viewBox="0 0 24 24"
									>
										<path stroke-linecap="round" stroke-linejoin="round" d="M4 16l5-5 4 4 7-7" />
									</svg>
								</div>
							{/if}

							{#if hasLargestArmy}
								<div
									class="flex h-6 w-6 items-center justify-center rounded-full border border-slate-300 bg-slate-50 text-slate-700"
									title="Largest Army (+2 VP)"
									aria-label="Largest Army"
								>
									<svg
										class="h-3.5 w-3.5"
										fill="none"
										stroke="currentColor"
										stroke-width="2"
										viewBox="0 0 24 24"
									>
										<path
											stroke-linecap="round"
											stroke-linejoin="round"
											d="M12 3l7 4v5c0 4.3-2.86 8.32-7 9-4.14-.68-7-4.7-7-9V7l7-4z"
										/>
									</svg>
								</div>
							{/if}

							<div class="flex items-center gap-1.5 font-black text-amber-600">
								<span class="text-base">{player.victory_points}</span>
								<svg class="h-4 w-4" fill="currentColor" viewBox="0 0 24 24">
									<path
										d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"
									/>
								</svg>
							</div>
						</div>
					</div>

					<div
						class="flex items-center justify-between border-t border-wood/5 pt-2 text-[10px] font-bold"
					>
						<div class="flex items-center gap-1 text-forest" title="Resource Cards">
							<svg
								class="h-3.5 w-3.5"
								fill="none"
								stroke="currentColor"
								stroke-width="2.5"
								viewBox="0 0 24 24"
							>
								<rect x="3" y="4" width="12" height="15" rx="2" />
								<rect
									x="8"
									y="7"
									width="12"
									height="15"
									rx="2"
									fill="currentColor"
									fill-opacity="0.1"
								/>
							</svg>
							<span
								>{player.resource_count}
								<span class="text-[8px] uppercase opacity-60">Cards</span></span
							>
						</div>

						<div class="flex items-center gap-1 text-ocean" title="Development Cards">
							<svg
								class="h-3.5 w-3.5"
								fill="none"
								stroke="currentColor"
								stroke-width="2.5"
								viewBox="0 0 24 24"
							>
								<rect x="5" y="3" width="14" height="18" rx="2" />
								<path d="M12 7v10M8 12h8" stroke-linecap="round" />
							</svg>
							<span
								>{player.development_card_count}
								<span class="text-[8px] uppercase opacity-60">Dev</span></span
							>
						</div>

						<div class="flex items-center gap-1 text-wood-dark/60" title="Knights Played">
							<svg
								class="h-3.5 w-3.5"
								fill="none"
								stroke="currentColor"
								stroke-width="2.5"
								viewBox="0 0 24 24"
							>
								<path d="M12 2L3 7v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V7l-9-5z" />
							</svg>
							<span
								>{player.knights_played}
								<span class="text-[8px] uppercase opacity-60">Army</span></span
							>
						</div>
					</div>

					<!-- Steal Overlay -->
					{#if isStealPhase && isMyTurn && !isMe && eligibleVictims.includes(player.id)}
						<button
							on:click={() => handleSteal(player.id)}
							class="absolute inset-0 flex items-center justify-center rounded-2xl bg-black/60 font-black tracking-widest text-white opacity-0 backdrop-blur-sm transition-all hover:opacity-100"
						>
							STEAL
						</button>
						<!-- Pulsing indicator to show they can be stolen from -->
						<div
							class="pointer-events-none absolute -inset-1 animate-pulse rounded-2xl border-2 border-brick/50"
						></div>
					{/if}
				</div>
			{/each}
		</div>
	</div>

	<!-- Game Log -->
	<div class="flex min-h-0 flex-1 flex-col rounded-2xl border-2 border-wood/10 bg-white/50 p-4">
		<h3 class="mb-2 text-sm font-bold tracking-wider text-wood-light uppercase">Game Log</h3>
		<div
			bind:this={gameLogContainer}
			class="flex flex-1 flex-col gap-1 overflow-y-auto text-sm text-wood-dark/80"
		>
			{#each gameLog as log}
				<div class="rounded bg-white/60 px-2 py-1 shadow-sm">
					<span class="mr-1 text-[10px] text-wood-light">
						{new Date(log.createdAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
					</span>
					{log.message}
				</div>
			{/each}
			<div class="mt-2 text-xs text-wood-light italic">
				It is {gamePlayers.find((p: any) => p.id === currentPlayerId)?.name}'s turn.
			</div>
		</div>
	</div>
</div>
