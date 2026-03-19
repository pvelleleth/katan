<script lang="ts">
	import { quintOut } from 'svelte/easing';
	import { fly } from 'svelte/transition';
	import {
		backendResourceNames,
		canConfirmSingleRoadBuildingPlacement,
		devCardLabels,
		type DevCardKey
	} from './devCards';
	import { resourceKeys, resourceLabels, type ResourceKey } from './trade';

	export let gameState: any;
	export let playerId: string;
	export let sendGameAction: (action: string, payload?: any) => void;
	export let tradeComposerOpen = false;
	export let pendingBoardDevCardAction: 'knight' | 'road_building' | null = null;
	export let pendingBoardBuildAction: 'city' | null = null;
	export let roadBuildingSelection: string[] = [];
	export let onTradeClick: (mode?: 'player' | 'bank') => void;
	export let onStartKnightPlay: () => void;
	export let onStartRoadBuildingPlay: () => void;
	export let onCancelPendingBoardDevCardAction: () => void;
	export let onStartCityPlacement: () => void;
	export let onCancelPendingBoardBuildAction: () => void;
	export let onConfirmSingleRoadBuildingPlacement: () => void;
	export let onResourceClick: (resource: ResourceKey) => void;
	const emptyHand = { wood: 0, brick: 0, sheep: 0, wheat: 0, ore: 0 };
	export let tradeOffered: Record<ResourceKey, number> = emptyHand;
	const emptyDevCardCounts = {
		knight: 0,
		victory_point: 0,
		road_building: 0,
		year_of_plenty: 0,
		monopoly: 0,
		total: 0
	};

	const devCardDefinitions: {
		id: DevCardKey;
		detail: string;
		color: string;
		accent: string;
	}[] = [
		{
			id: 'knight',
			detail: 'Move the robber',
			color: 'bg-slate-700 text-white',
			accent: 'ring-slate-500/40'
		},
		{
			id: 'victory_point',
			detail: 'Counts toward your score',
			color: 'bg-amber-500 text-white',
			accent: 'ring-amber-300/50'
		},
		{
			id: 'road_building',
			detail: 'Place 2 free roads',
			color: 'bg-ocean text-white',
			accent: 'ring-ocean/40'
		},
		{
			id: 'year_of_plenty',
			detail: 'Take any 2 resources',
			color: 'bg-emerald-600 text-white',
			accent: 'ring-emerald-400/40'
		},
		{
			id: 'monopoly',
			detail: 'Take 1 resource type from all opponents',
			color: 'bg-purple-600 text-white',
			accent: 'ring-purple-400/40'
		}
	];

	let discardSelection: Record<string, number> = { ...emptyHand };
	let selectedDevCard: DevCardKey | null = null;
	let monopolyResource: ResourceKey = 'wood';
	let yearOfPlentySelection: ResourceKey[] = [];

	$: myPlayer = gameState.players.find((p: any) => p.id === playerId);
	$: hand = myPlayer?.hand || emptyHand;
	$: developmentCards = myPlayer?.development_cards || {
		playable: emptyDevCardCounts,
		newly_purchased: emptyDevCardCounts
	};
	$: isMyTurn = gameState.turn.current_player_id === playerId;
	$: phase = gameState.turn.phase;
	$: pendingTrade = gameState.turn.pending_player_trade;
	$: tradePendingForMe = pendingTrade && pendingTrade.player_id === playerId;
	$: devCardPlayedThisTurn = !!gameState.turn.dev_card_played_this_turn;
	$: canPlayDevelopmentCards =
		isMyTurn && (phase === 'Roll' || phase === 'Main') && !devCardPlayedThisTurn;
	$: devCardsRemaining = (Object.values(gameState.bank?.dev_cards || {}) as number[]).reduce(
		(total, count) => total + count,
		0
	);
	$: bankResources = gameState.bank?.resources || emptyHand;
	$: canBuyDevelopmentCard =
		isMyTurn &&
		phase === 'Main' &&
		hand.sheep > 0 &&
		hand.wheat > 0 &&
		hand.ore > 0 &&
		devCardsRemaining > 0;
	$: canBuildCity =
		isMyTurn &&
		phase === 'Main' &&
		hand.wheat >= 2 &&
		hand.ore >= 3 &&
		(myPlayer?.cities_left || 0) > 0;
	$: canConfirmSingleRoadBuilding =
		pendingBoardDevCardAction === 'road_building' &&
		canConfirmSingleRoadBuildingPlacement(
			gameState.board,
			playerId,
			roadBuildingSelection,
			myPlayer?.roads_left || 0
		);

	$: pendingDiscard = gameState.turn.pending_robber_discards?.find(
		(d: any) => d.player_id === playerId
	);
	$: needsToDiscard = phase === 'DiscardResources' && !!pendingDiscard;
	$: discardTarget = pendingDiscard?.count || 0;
	$: currentDiscardTotal = Object.values(discardSelection).reduce((a, b) => a + b, 0);
	$: ownedDevCardPiles = devCardDefinitions
		.map((card) => {
			const playableCount = developmentCards.playable[card.id] || 0;
			const newCount = developmentCards.newly_purchased[card.id] || 0;

			return {
				...card,
				playableCount,
				newCount,
				totalCount: playableCount + newCount
			};
		})
		.filter((card) => card.totalCount > 0);
	$: selectedDevCardPile = ownedDevCardPiles.find((card) => card.id === selectedDevCard) || null;

	$: if (phase !== 'DiscardResources') {
		discardSelection = { ...emptyHand };
	}

	$: if (selectedDevCard !== 'year_of_plenty') {
		yearOfPlentySelection = [];
	}

	$: if (selectedDevCard && !ownedDevCardPiles.some((card) => card.id === selectedDevCard)) {
		selectedDevCard = null;
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

	function toggleDiscard(resId: string, delta: number) {
		const current = discardSelection[resId];
		const max = hand[resId];

		if (delta > 0) {
			if (current < max && currentDiscardTotal < discardTarget) {
				discardSelection[resId]++;
			}
		} else if (current > 0) {
			discardSelection[resId]--;
		}
	}

	function confirmDiscard() {
		if (currentDiscardTotal !== discardTarget) return;
		sendGameAction('discard_robber', { discarded: discardSelection });
	}

	function clearSelectedDevCard(cancelBoardAction = false) {
		selectedDevCard = null;
		yearOfPlentySelection = [];
		if (cancelBoardAction) {
			onCancelPendingBoardDevCardAction();
		}
	}

	function toggleDevCardSelection(cardId: DevCardKey) {
		if (
			pendingBoardDevCardAction &&
			((pendingBoardDevCardAction === 'knight' && cardId !== 'knight') ||
				(pendingBoardDevCardAction === 'road_building' && cardId !== 'road_building'))
		) {
			onCancelPendingBoardDevCardAction();
		}

		if (selectedDevCard === cardId) {
			clearSelectedDevCard(
				(pendingBoardDevCardAction === 'knight' && cardId === 'knight') ||
					(pendingBoardDevCardAction === 'road_building' && cardId === 'road_building')
			);
			return;
		}

		selectedDevCard = cardId;
	}

	function playMonopoly() {
		sendGameAction('play_monopoly', { resource: backendResourceNames[monopolyResource] });
		clearSelectedDevCard();
	}

	function selectYearOfPlentyResource(resource: ResourceKey) {
		if (!canSelectYearOfPlentyResource(resource)) return;
		yearOfPlentySelection = [...yearOfPlentySelection, resource];
	}

	function undoYearOfPlentyPick() {
		yearOfPlentySelection = yearOfPlentySelection.slice(0, -1);
	}

	function playYearOfPlenty() {
		if (!canApplyYearOfPlenty) return;
		sendGameAction('play_year_of_plenty', {
			first_resource: backendResourceNames[yearOfPlentySelection[0]],
			second_resource: backendResourceNames[yearOfPlentySelection[1]]
		});
		clearSelectedDevCard();
	}

	function startKnightPlay() {
		if (!canPlayDevelopmentCards || developmentCards.playable.knight <= 0) return;
		selectedDevCard = 'knight';
		onStartKnightPlay();
	}

	function startRoadBuildingPlay() {
		if (!canPlayDevelopmentCards || developmentCards.playable.road_building <= 0) return;
		selectedDevCard = 'road_building';
		onStartRoadBuildingPlay();
	}

	function toggleCityPlacement() {
		if (pendingBoardBuildAction === 'city') {
			onCancelPendingBoardBuildAction();
			return;
		}

		if (!canBuildCity) return;
		onStartCityPlacement();
	}

	function getYearOfPlentyRequestedCount(resource: ResourceKey) {
		return yearOfPlentySelection.filter((selected) => selected === resource).length;
	}

	function canSelectYearOfPlentyResource(resource: ResourceKey) {
		if (!canPlayDevelopmentCards || yearOfPlentySelection.length >= 2) {
			return false;
		}

		return (bankResources[resource] || 0) > getYearOfPlentyRequestedCount(resource);
	}

	$: yearOfPlentyRequestedCounts = yearOfPlentySelection.reduce(
		(counts, resource) => {
			counts[resource] += 1;
			return counts;
		},
		{ ...emptyHand }
	);
	$: hasValidYearOfPlentySelection =
		yearOfPlentySelection.length === 2 &&
		resourceKeys.every(
			(resource) => yearOfPlentyRequestedCounts[resource] <= (bankResources[resource] || 0)
		);
	$: canApplyYearOfPlenty = canPlayDevelopmentCards && hasValidYearOfPlentySelection;
</script>

<div class="flex flex-col gap-4">
	<div class="flex flex-wrap items-stretch justify-between gap-4">
		<div class="flex min-w-0 flex-1 flex-wrap items-end gap-4">
			{#each resources as res}
				{@const totalCount = hand[res.id] || 0}
				{@const offeredCount = tradeOffered[res.id as ResourceKey] || 0}
				{@const visibleCount = Math.max(0, totalCount - offeredCount)}
				<button
					type="button"
					on:click={() => onResourceClick(res.id as ResourceKey)}
					class="relative h-24 transition-all duration-300"
					style="width: {64 + Math.max(0, visibleCount - 1) * 14}px"
				>
					{#if visibleCount === 0}
						<div
							class="absolute bottom-0 left-0 flex h-24 w-16 flex-col items-center justify-center rounded-xl border-2 border-dashed border-wood/20 bg-wood/5"
						>
							<span class="text-[10px] font-bold tracking-wider text-wood/40 uppercase"
								>{res.label}</span
							>
						</div>
					{/if}

					{#each Array(visibleCount) as _, i (res.id + '-' + i)}
						<div
							in:fly={{ y: -150, x: 0, duration: 600, easing: quintOut }}
							class="absolute bottom-0 flex h-24 w-16 flex-col items-center justify-between rounded-xl border-2 border-white/40 p-2 shadow-md transition-transform hover:-translate-y-2 {res.color}"
							style="left: {i * 14}px; z-index: {i};"
						>
							<span class="text-[10px] font-bold tracking-wider uppercase opacity-90"
								>{res.label}</span
							>

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

					{#if visibleCount > 1}
						<div
							in:fly={{ y: -20, duration: 400, delay: 200 }}
							class="absolute -top-2 z-50 flex h-6 w-6 items-center justify-center rounded-full bg-wood-dark text-xs font-bold text-white shadow-md ring-2 ring-white"
							style="left: {(visibleCount - 1) * 14 + 48}px"
						>
							{visibleCount}
						</div>
					{/if}

					{#if needsToDiscard && visibleCount > 0}
						<div class="absolute -top-10 left-0 z-50 flex w-full justify-center gap-1">
							<span
								role="button"
								tabindex="0"
								class="flex h-8 w-8 items-center justify-center rounded-full bg-brick text-white shadow-md transition-transform hover:scale-110 active:scale-95 {discardSelection[
									res.id
								] === 0
									? 'cursor-not-allowed opacity-50'
									: 'cursor-pointer'}"
								on:click|stopPropagation={() => toggleDiscard(res.id, -1)}
								on:keydown|stopPropagation={(e) =>
									(e.key === 'Enter' || e.key === ' ') &&
									(e.preventDefault(), toggleDiscard(res.id, -1))}
							>
								-
							</span>
							<div
								class="flex h-8 w-8 items-center justify-center rounded-full border-2 border-wood/20 bg-white font-bold text-wood-dark shadow-md"
							>
								{discardSelection[res.id]}
							</div>
							<span
								role="button"
								tabindex="0"
								class="flex h-8 w-8 items-center justify-center rounded-full bg-forest text-white shadow-md transition-transform hover:scale-110 active:scale-95 {discardSelection[
									res.id
								] === visibleCount || currentDiscardTotal >= discardTarget
									? 'cursor-not-allowed opacity-50'
									: 'cursor-pointer'}"
								on:click|stopPropagation={() => toggleDiscard(res.id, 1)}
								on:keydown|stopPropagation={(e) =>
									(e.key === 'Enter' || e.key === ' ') &&
									(e.preventDefault(), toggleDiscard(res.id, 1))}
							>
								+
							</span>
						</div>
						{#if discardSelection[res.id] > 0}
							<div
								class="pointer-events-none absolute bottom-0 left-0 z-40 h-24 rounded-xl bg-black/40 transition-all"
								style="width: {64 + Math.max(0, visibleCount - 1) * 14}px"
							></div>
						{/if}
					{/if}
				</button>
			{/each}

			{#if ownedDevCardPiles.length > 0}
				<div class="ml-2 flex flex-wrap items-end gap-4">
					{#each ownedDevCardPiles as card}
						<button
							type="button"
							on:click={() => toggleDevCardSelection(card.id)}
							class="relative h-24 rounded-xl text-left transition-all duration-300 {selectedDevCard ===
							card.id
								? `scale-[1.02] ring-4 ${card.accent}`
								: ''}"
							style="width: {64 + Math.max(0, card.totalCount - 1) * 14}px"
						>
							{#each Array(card.totalCount) as _, i (card.id + '-' + i)}
								<div
									in:fly={{ y: -150, x: 0, duration: 600, easing: quintOut }}
									class="absolute bottom-0 flex h-24 w-16 flex-col items-center justify-between rounded-xl border-2 border-white/40 p-2 shadow-md transition-transform hover:-translate-y-2 {card.color} {i >=
									card.playableCount
										? 'brightness-90 saturate-75'
										: ''}"
									style="left: {i * 14}px; z-index: {i};"
								>
									<span class="text-[9px] font-bold tracking-wider uppercase opacity-90">
										{devCardLabels[card.id]}
									</span>
									<div
										class="flex h-8 w-8 items-center justify-center rounded-full bg-white/20 shadow-inner"
									>
										<svg viewBox="0 0 24 24" class="h-5 w-5" fill="currentColor">
											{#if card.id === 'knight'}
												<path
													d="M15 4a3 3 0 10-6 0c0 1.1.6 2.1 1.5 2.6L7 12v8h10v-3h-2v-2h2v-5l-3.5-3.4c.9-.5 1.5-1.5 1.5-2.6z"
												/>
											{:else if card.id === 'victory_point'}
												<path
													d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"
												/>
											{:else if card.id === 'road_building'}
												<path d="M3 17h4l2-3h6l2 3h4l-7-10h-4L3 17zm8-6h2l1.4 2h-4.8L11 11z" />
											{:else if card.id === 'year_of_plenty'}
												<path
													d="M12 3l7 4v5c0 5-3.4 8.9-7 10-3.6-1.1-7-5-7-10V7l7-4zm0 4.5L9.5 10 12 12.5 14.5 10 12 7.5zm0 6l-2.5-2.5L7 13.5l5 2.5 5-2.5-2.5-2.5L12 13.5z"
												/>
											{:else if card.id === 'monopoly'}
												<path
													d="M4 20V8l4-4h8l4 4v12H4zm4-2h2v-3H8v3zm0-5h2v-3H8v3zm6 5h2v-3h-2v3zm0-5h2v-3h-2v3z"
												/>
											{/if}
										</svg>
									</div>
								</div>
							{/each}

							{#if card.totalCount > 1}
								<div
									class="absolute -top-2 z-50 flex h-6 w-6 items-center justify-center rounded-full bg-wood-dark text-xs font-bold text-white shadow-md ring-2 ring-white"
									style="left: {(card.totalCount - 1) * 14 + 48}px"
								>
									{card.totalCount}
								</div>
							{/if}

							{#if card.newCount > 0}
								<div
									class="absolute -bottom-2 left-0 rounded-full bg-wheat px-2 py-1 text-[10px] font-black text-wood-dark shadow-sm"
								>
									New {card.newCount}
								</div>
							{/if}
						</button>
					{/each}
				</div>
			{/if}
		</div>

		<div class="flex items-stretch gap-3">
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
				<div class="flex min-w-[7rem] flex-col gap-1">
					<button
						on:click={() => onTradeClick('player')}
						disabled={!!pendingTrade}
						class="flex-1 rounded-lg bg-wood px-6 py-1.5 text-xs font-bold text-white shadow-sm transition-transform hover:scale-105 active:scale-95 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:scale-100"
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
						disabled={!canBuyDevelopmentCard}
						class="flex-1 rounded-lg bg-purple-600 px-6 py-1.5 text-xs font-bold text-white shadow-sm transition-transform hover:scale-105 active:scale-95 disabled:cursor-not-allowed disabled:opacity-40 disabled:hover:scale-100"
					>
						Buy Dev Card
					</button>
					<button
						on:click={toggleCityPlacement}
						disabled={!canBuildCity && pendingBoardBuildAction !== 'city'}
						class="flex-1 rounded-lg bg-wheat px-6 py-1.5 text-xs font-bold text-wood-dark shadow-sm transition-transform hover:scale-105 active:scale-95 disabled:cursor-not-allowed disabled:opacity-40 disabled:hover:scale-100"
					>
						{pendingBoardBuildAction === 'city' ? 'Cancel City' : 'Build City'}
					</button>
				</div>
				<button
					on:click={() => sendGameAction('end_turn')}
					class="ml-10 rounded-xl border-2 border-wood/20 bg-white px-6 py-2 font-black text-wood-dark shadow-sm transition-transform hover:scale-105 active:scale-95"
				>
					End Turn
				</button>
			{:else if phase.startsWith('Setup')}
				<div
					class="rounded-xl border-2 border-ocean/20 bg-ocean/10 px-5 py-2.5 text-sm font-bold text-ocean"
				>
					Place your starting {phase.includes('Settlement') ? 'Settlement' : 'Road'}
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

	{#if pendingBoardBuildAction === 'city'}
		<div
			class="rounded-2xl border-2 border-wheat/30 bg-wheat/10 px-4 py-3 text-sm font-semibold text-wood-dark shadow-sm"
		>
			Click one of your settlements on the board to upgrade it to a city.
		</div>
	{/if}

	{#if selectedDevCardPile}
		<div class="rounded-2xl border-2 border-wood/10 bg-white/70 p-4 shadow-sm">
			<div class="flex flex-wrap items-start justify-between gap-3">
				<div>
					<div class="text-sm font-black text-wood-dark">
						{devCardLabels[selectedDevCardPile.id]}
					</div>
					<div class="text-xs font-semibold text-wood-light">{selectedDevCardPile.detail}</div>
				</div>
				<div class="flex flex-wrap gap-2 text-[11px] font-bold">
					<span class="rounded-full bg-forest/10 px-2 py-1 text-forest">
						Ready {selectedDevCardPile.playableCount}
					</span>
					{#if selectedDevCardPile.newCount > 0}
						<span class="rounded-full bg-wheat/20 px-2 py-1 text-wood-dark">
							New {selectedDevCardPile.newCount}
						</span>
					{/if}
				</div>
			</div>

			{#if selectedDevCardPile.id === 'victory_point'}
				<div class="mt-3 text-sm font-semibold text-wood-light">
					Victory point cards are passive and already counted in your score.
				</div>
			{:else if selectedDevCardPile.playableCount <= 0}
				<div class="mt-3 text-sm font-semibold text-wood-light">
					Newly purchased development cards cannot be played until your next turn.
				</div>
			{:else if selectedDevCardPile.id === 'knight'}
				<div class="mt-3 flex flex-wrap items-center gap-2">
					<button
						on:click={startKnightPlay}
						disabled={!canPlayDevelopmentCards}
						class="rounded-lg bg-slate-700 px-3 py-2 text-sm font-bold text-white disabled:cursor-not-allowed disabled:opacity-40"
					>
						{pendingBoardDevCardAction === 'knight' ? 'Cancel Apply' : 'Apply Knight'}
					</button>
					{#if pendingBoardDevCardAction === 'knight'}
						<span class="text-sm font-semibold text-slate-700">Click a tile on the board.</span>
					{/if}
				</div>
			{:else if selectedDevCardPile.id === 'road_building'}
				<div class="mt-3 flex flex-wrap items-center gap-2">
					<button
						on:click={startRoadBuildingPlay}
						disabled={!canPlayDevelopmentCards}
						class="rounded-lg bg-ocean px-3 py-2 text-sm font-bold text-white disabled:cursor-not-allowed disabled:opacity-40"
					>
						{pendingBoardDevCardAction === 'road_building' ? 'Cancel Apply' : 'Apply Road Building'}
					</button>
					{#if pendingBoardDevCardAction === 'road_building'}
						<span class="text-sm font-semibold text-ocean">
							Select roads on the board ({roadBuildingSelection.length}/2).
						</span>
						{#if canConfirmSingleRoadBuilding}
							<button
								on:click={onConfirmSingleRoadBuildingPlacement}
								class="rounded-lg border border-ocean/20 bg-white px-3 py-2 text-sm font-bold text-ocean"
							>
								Confirm Single Road
							</button>
						{/if}
					{/if}
				</div>
			{:else if selectedDevCardPile.id === 'monopoly'}
				<div class="mt-3 flex flex-wrap gap-2">
					{#each resources as res}
						<button
							on:click={() => (monopolyResource = res.id as ResourceKey)}
							class="rounded-lg px-3 py-2 text-sm font-bold transition-transform hover:scale-[1.02] active:scale-[0.98] {monopolyResource ===
							res.id
								? 'bg-purple-600 text-white'
								: 'bg-white text-purple-900'}"
						>
							{res.label}
						</button>
					{/each}
					<button
						on:click={playMonopoly}
						disabled={!canPlayDevelopmentCards}
						class="rounded-lg bg-purple-600 px-3 py-2 text-sm font-bold text-white disabled:cursor-not-allowed disabled:opacity-40"
					>
						Apply Monopoly
					</button>
				</div>
			{:else if selectedDevCardPile.id === 'year_of_plenty'}
				<div class="mt-3 flex flex-col gap-3">
					<div class="flex flex-wrap gap-2">
						{#each resources as res}
							<button
								on:click={() => selectYearOfPlentyResource(res.id as ResourceKey)}
								disabled={!canSelectYearOfPlentyResource(res.id as ResourceKey)}
								class="rounded-lg px-3 py-2 text-sm font-bold transition-transform hover:scale-[1.02] active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-40 {resourceColors[
									res.id
								]}"
							>
								{res.label}
							</button>
						{/each}
					</div>
					<div class="flex flex-wrap items-center gap-2">
						<span class="text-xs font-bold tracking-wider text-emerald-900 uppercase">Selected</span
						>
						{#if yearOfPlentySelection.length === 0}
							<span class="text-sm font-semibold text-wood-light">Choose 2 resources.</span>
						{:else}
							{#each yearOfPlentySelection as resource}
								<div class="rounded-full bg-white px-3 py-1 text-sm font-bold text-emerald-900">
									{resourceLabels[resource]}
								</div>
							{/each}
						{/if}
						<button
							on:click={undoYearOfPlentyPick}
							disabled={yearOfPlentySelection.length === 0}
							class="rounded-lg border border-emerald-200 bg-white px-3 py-2 text-sm font-bold text-emerald-900 disabled:cursor-not-allowed disabled:opacity-40"
						>
							Undo
						</button>
						<button
							on:click={playYearOfPlenty}
							disabled={!canApplyYearOfPlenty}
							class="rounded-lg bg-emerald-600 px-3 py-2 text-sm font-bold text-white disabled:cursor-not-allowed disabled:opacity-40"
						>
							Apply Year of Plenty
						</button>
					</div>
				</div>
			{/if}
		</div>
	{/if}
</div>
