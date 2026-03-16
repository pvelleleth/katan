<script lang="ts">
	import { fly } from 'svelte/transition';
	import { quintOut } from 'svelte/easing';
	import { resourceKeys, resourceLabels } from './trade';

	export let gameState: any;
	export let playerId: string;
	export let sendGameAction: (action: string, payload?: any) => void;
	export let tradeComposerOpen = false;
	export let onTradeClick: (mode?: 'player' | 'bank') => void;

	$: myPlayer = gameState.players.find((p: any) => p.id === playerId);
	$: hand = myPlayer?.hand || { wood: 0, brick: 0, sheep: 0, wheat: 0, ore: 0 };
	$: isMyTurn = gameState.turn.current_player_id === playerId;
	$: phase = gameState.turn.phase;
	$: pendingTrade = gameState.turn.pending_player_trade;
	$: tradePendingForMe = pendingTrade && pendingTrade.player_id === playerId;

	$: pendingDiscard = gameState.turn.pending_robber_discards?.find(
		(d: any) => d.player_id === playerId
	);
	$: needsToDiscard = phase === 'DiscardResources' && !!pendingDiscard;
	$: discardTarget = pendingDiscard?.count || 0;

	let discardSelection: Record<string, number> = { wood: 0, brick: 0, sheep: 0, wheat: 0, ore: 0 };
	$: currentDiscardTotal = Object.values(discardSelection).reduce((a, b) => a + b, 0);

	// Reset discard selection when phase changes
	$: if (phase !== 'DiscardResources') {
		discardSelection = { wood: 0, brick: 0, sheep: 0, wheat: 0, ore: 0 };
	}

	function toggleDiscard(resId: string, delta: number) {
		const current = discardSelection[resId];
		const max = hand[resId];

		if (delta > 0) {
			if (current < max && currentDiscardTotal < discardTarget) {
				discardSelection[resId]++;
			}
		} else {
			if (current > 0) {
				discardSelection[resId]--;
			}
		}
	}

	function confirmDiscard() {
		if (currentDiscardTotal !== discardTarget) return;
		sendGameAction('discard_robber', { discarded: discardSelection });
	}

	const resourceColors: Record<string, string> = {
		wood: 'bg-forest text-white',
		brick: 'bg-brick text-white',
		sheep: 'bg-[#90EE90] text-wood-dark',
		wheat: 'bg-[#FBC02D] text-wood-dark',
		ore: 'bg-[#708090] text-white'
	};

	$: resources = resourceKeys.map((id) => ({
		id,
		color: resourceColors[id],
		label: resourceLabels[id]
	}));
</script>

<div class="flex items-center justify-between gap-4">
	<!-- Resources -->
	<div class="flex items-end gap-4">
		<div class="mr-2 flex flex-col pb-2">
			<span class="text-sm font-black text-wood-dark">HAND</span>
			<span class="text-xs font-bold text-wood-light">{myPlayer?.resource_count || 0} cards</span>
		</div>
		{#each resources as res}
			{@const count = hand[res.id] || 0}
			<div
				class="relative h-24 transition-all duration-300"
				style="width: {64 + Math.max(0, count - 1) * 14}px"
			>
				<!-- Empty placeholder -->
				{#if count === 0}
					<div
						class="absolute bottom-0 left-0 flex h-24 w-16 flex-col items-center justify-center rounded-xl border-2 border-dashed border-wood/20 bg-wood/5"
					>
						<span class="text-[10px] font-bold tracking-wider text-wood/40 uppercase"
							>{res.label}</span
						>
					</div>
				{/if}

				<!-- Cards -->
				{#each Array(count) as _, i (res.id + '-' + i)}
					<div
						in:fly={{ y: -150, x: 0, duration: 600, easing: quintOut }}
						class="absolute bottom-0 flex h-24 w-16 flex-col items-center justify-between rounded-xl border-2 border-white/40 shadow-md {res.color} p-2 transition-transform hover:-translate-y-2"
						style="left: {i * 14}px; z-index: {i};"
					>
						<span class="text-[10px] font-bold tracking-wider uppercase opacity-90"
							>{res.label}</span
						>

						<!-- Card Icon -->
						<div
							class="flex h-8 w-8 items-center justify-center rounded-full bg-white/20 shadow-inner"
						>
							<svg viewBox="0 0 24 24" class="h-5 w-5" fill="currentColor">
								{#if res.id === 'wood'}
									<path d="M12 2L4 10h3v4H4l8 8 8-8h-3v-4h3z" />
								{:else if res.id === 'brick'}
									<path d="M2 4h20v4H2zm0 6h9v4H2zm11 0h9v4h-9zm-11 6h20v4H2z" />
								{:else if res.id === 'sheep'}
									<path
										d="M18.5 8c-1.2 0-2.2.8-2.4 1.9-.5-.3-1.1-.4-1.6-.4-1.8 0-3.3 1.3-3.6 3-.4-.3-.9-.5-1.4-.5-1.9 0-3.5 1.6-3.5 3.5 0 .3 0 .6.1.8-.8.4-1.4 1.2-1.4 2.2 0 1.4 1.1 2.5 2.5 2.5h11.5c1.9 0 3.5-1.6 3.5-3.5 0-1.6-1.1-2.9-2.6-3.3.1-.4.1-.8.1-1.2 0-2.8-2.2-5-5-5z"
									/>
								{:else if res.id === 'wheat'}
									<path
										d="M12 2C7 2 3 6 3 11c0 2.2.8 4.2 2.1 5.7L2 22l2 1 3.3-3.3C8.8 20.6 10.3 21 12 21c5 0 9-4 9-9s-4-9-9-9zm0 17c-4.4 0-8-3.6-8-8s3.6-8 8-8 8 3.6 8 8-3.6 8-8 8z"
									/>
									<path
										d="M12 5v14M8 8l4 4M16 8l-4 4M8 14l4-4M16 14l-4-4"
										stroke="currentColor"
										stroke-width="2"
									/>
								{:else if res.id === 'ore'}
									<path d="M12 2L2 22h20L12 2zm0 6l5 10H7l5-10z" />
								{/if}
							</svg>
						</div>
					</div>
				{/each}

				<!-- Count Badge (if > 1) -->
				{#if count > 1}
					<div
						in:fly={{ y: -20, duration: 400, delay: 200 }}
						class="absolute -top-2 z-50 flex h-6 w-6 items-center justify-center rounded-full bg-wood-dark text-xs font-bold text-white shadow-md ring-2 ring-white"
						style="left: {(count - 1) * 14 + 48}px"
					>
						{count}
					</div>
				{/if}

				<!-- Discard Controls Overlay -->
				{#if needsToDiscard && count > 0}
					<div class="absolute -top-10 left-0 z-50 flex w-full justify-center gap-1">
						<button
							on:click={() => toggleDiscard(res.id, -1)}
							disabled={discardSelection[res.id] === 0}
							class="flex h-8 w-8 items-center justify-center rounded-full bg-brick text-white shadow-md transition-transform hover:scale-110 active:scale-95 disabled:cursor-not-allowed disabled:opacity-50"
						>
							-
						</button>
						<div
							class="flex h-8 w-8 items-center justify-center rounded-full border-2 border-wood/20 bg-white font-bold text-wood-dark shadow-md"
						>
							{discardSelection[res.id]}
						</div>
						<button
							on:click={() => toggleDiscard(res.id, 1)}
							disabled={discardSelection[res.id] === count || currentDiscardTotal >= discardTarget}
							class="flex h-8 w-8 items-center justify-center rounded-full bg-forest text-white shadow-md transition-transform hover:scale-110 active:scale-95 disabled:cursor-not-allowed disabled:opacity-50"
						>
							+
						</button>
					</div>
					<!-- Darken cards that are selected for discard -->
					{#if discardSelection[res.id] > 0}
						<div
							class="pointer-events-none absolute bottom-0 left-0 z-40 h-24 rounded-xl bg-black/40 transition-all"
							style="width: {64 + Math.max(0, count - 1) * 14}px"
						></div>
					{/if}
				{/if}
			</div>
		{/each}
	</div>

	<!-- Actions (Build, Trade, etc) -->
	<div class="flex items-center gap-3">
		{#if needsToDiscard}
			<div class="flex flex-col items-end gap-1">
				<span class="text-xs font-bold tracking-wider text-brick uppercase"
					>Discard {currentDiscardTotal} / {discardTarget}</span
				>
				<button
					on:click={confirmDiscard}
					disabled={currentDiscardTotal !== discardTarget}
					class="rounded-xl bg-brick px-6 py-2.5 font-bold text-white shadow-sm transition-transform hover:scale-105 active:scale-95 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:scale-100"
				>
					Confirm Discard
				</button>
			</div>
		{:else if phase === 'DiscardResources'}
			<div
				class="rounded-xl border-2 border-wood/10 bg-wood/5 px-5 py-2.5 text-sm font-bold text-wood-light"
			>
				Waiting for others to discard...
			</div>
		{:else if !isMyTurn}
			<div
				class="rounded-xl border-2 border-wood/10 bg-wood/5 px-5 py-2.5 text-sm font-bold text-wood-light"
			>
				Waiting for {gameState.players.find((p: any) => p.id === gameState.turn.current_player_id)
					?.name}...
			</div>
		{:else if phase === 'Roll'}
			<button
				on:click={() => sendGameAction('roll_dice')}
				class="rounded-xl bg-brick px-6 py-3 text-lg font-black text-white shadow-md transition-transform hover:scale-105 active:scale-95"
			>
				🎲 Roll Dice
			</button>
		{:else if phase === 'Main'}
			<button
				class="rounded-xl bg-ocean px-5 py-2.5 font-bold text-white shadow-sm transition-transform hover:scale-105 active:scale-95"
			>
				Build
			</button>
			<button
				on:click={() => onTradeClick('player')}
				disabled={!!pendingTrade}
				class="rounded-xl bg-wood px-5 py-2.5 font-bold text-white shadow-sm transition-transform hover:scale-105 active:scale-95 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:scale-100"
			>
				{#if tradePendingForMe}
					Trade Pending
				{:else if tradeComposerOpen}
					Close Trade
				{:else}
					Trade
				{/if}
			</button>
			<button
				on:click={() => sendGameAction('buy_development_card')}
				class="rounded-xl bg-purple-600 px-5 py-2.5 font-bold text-white shadow-sm transition-transform hover:scale-105 active:scale-95"
			>
				Buy Dev Card
			</button>
			<button
				on:click={() => sendGameAction('end_turn')}
				class="rounded-xl border-2 border-wood/20 bg-white px-5 py-2.5 font-bold text-wood-dark shadow-sm transition-transform hover:scale-105 active:scale-95"
			>
				End Turn
			</button>
		{:else if phase.startsWith('Setup')}
			<div
				class="rounded-xl border-2 border-ocean/20 bg-ocean/10 px-5 py-2.5 text-sm font-bold text-ocean"
			>
				Place your starting {phase.includes('Settlement') ? 'Settlement' : 'Road'}
			</div>
		{:else if phase === 'DiscardResources'}
			<!-- This branch is now handled above, but just in case -->
			<div
				class="rounded-xl border-2 border-brick/20 bg-brick/10 px-5 py-2.5 text-sm font-bold text-brick"
			>
				Discarding Resources...
			</div>
		{:else if phase === 'MoveRobber'}
			<div
				class="rounded-xl border-2 border-wood-dark/20 bg-wood-dark/10 px-5 py-2.5 text-sm font-bold text-wood-dark"
			>
				Move the Robber
			</div>
		{:else if phase === 'StealResource'}
			<div
				class="rounded-xl border-2 border-brick/20 bg-brick/10 px-5 py-2.5 text-sm font-bold text-brick"
			>
				Select a player to steal from!
			</div>
		{/if}
	</div>
</div>
