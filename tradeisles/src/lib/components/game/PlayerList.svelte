<script lang="ts">
	export let gameState: any;
	export let players: any[]; // From lobby, has colors
	export let playerId: string;
	export let gameLog: { message: string; createdAt: string }[] = [];
	export let sendGameAction: (action: string, payload?: any) => void;

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
			color: lPlayer?.color || 'wood'
		};
	});

	const colorClasses: Record<string, string> = {
		brick: 'bg-brick text-white border-brick',
		ocean: 'bg-ocean text-white border-ocean',
		wheat: 'bg-wheat text-wood-dark border-wheat',
		forest: 'bg-forest text-white border-forest',
		wood: 'bg-wood text-white border-wood'
	};

	function handleSteal(victimId: string) {
		if (!isMyTurn || !isStealPhase || !eligibleVictims.includes(victimId)) return;
		sendGameAction('robber_steal', { victim_player_id: victimId });
	}
</script>

<div class="flex h-full flex-col gap-6">
	<div>
		<h2 class="mb-4 text-xl font-black text-wood-dark">Players</h2>
		<div class="flex flex-col gap-3">
			{#each gamePlayers as player}
				{@const isCurrentTurn = player.id === currentPlayerId}
				{@const isMe = player.id === playerId}
				<div
					class="relative flex flex-col gap-2 rounded-2xl border-2 p-3 transition-all {isCurrentTurn
						? 'border-ocean bg-white shadow-lg'
						: 'border-wood/10 bg-white/50'}"
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
						<div class="flex-1 truncate font-bold text-wood-dark">
							{player.name}
							{#if isMe}
								<span class="ml-1 text-xs text-wood-light">(You)</span>
							{/if}
						</div>
						<div class="flex items-center gap-1 font-black text-wood-dark">
							{player.victory_points}
							<svg class="text-wheat h-4 w-4" fill="currentColor" viewBox="0 0 24 24">
								<path
									d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"
								/>
							</svg>
						</div>
					</div>

					<div class="grid grid-cols-3 gap-2 text-xs font-semibold text-wood-dark/70">
						<div class="flex items-center gap-1" title="Resource Cards">
							<div class="h-3 w-2 rounded-sm bg-wood/40"></div>
							{player.resource_count}
						</div>
						<div class="flex items-center gap-1" title="Development Cards">
							<div class="h-3 w-2 rounded-sm bg-ocean/40"></div>
							{player.development_card_count}
						</div>
						<div class="flex items-center gap-1" title="Knights Played">
							<svg class="h-3 w-3" fill="currentColor" viewBox="0 0 24 24">
								<path d="M12 2L3 7v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V7l-9-5z" />
							</svg>
							{player.knights_played}
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
						<div class="pointer-events-none absolute -inset-1 animate-pulse rounded-2xl border-2 border-brick/50"></div>
					{/if}
				</div>
			{/each}
		</div>
	</div>

	<!-- Game Log -->
	<div class="flex min-h-0 flex-1 flex-col rounded-2xl border-2 border-wood/10 bg-white/50 p-4">
		<h3 class="mb-2 text-sm font-bold tracking-wider text-wood-light uppercase">Game Log</h3>
		<div class="flex-1 overflow-y-auto text-sm text-wood-dark/80 flex flex-col gap-1">
			{#each gameLog as log}
				<div class="rounded bg-white/60 px-2 py-1 shadow-sm">
					<span class="text-[10px] text-wood-light mr-1">
						{new Date(log.createdAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
					</span>
					{log.message}
				</div>
			{/each}
			<div class="mt-2 text-xs italic text-wood-light">
				It is {gamePlayers.find((p: any) => p.id === currentPlayerId)?.name}'s turn.
			</div>
		</div>
	</div>
</div>
