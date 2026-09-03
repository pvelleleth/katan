<script lang="ts">
	import GameBoard from './GameBoard.svelte';
	import { onDestroy, onMount } from 'svelte';
	import PlayerHand from './PlayerHand.svelte';
	import PlayerList from './PlayerList.svelte';
	import Dice from './Dice.svelte';
	import TradeComposer from './TradeComposer.svelte';
	import TradeOfferPopup from './TradeOfferPopup.svelte';
	import GameOverScreen from './GameOverScreen.svelte';
	import BuildCostsPanel from './BuildCostsPanel.svelte';
	import {
		createEmptyResourcePile,
		getBankTradeRates,
		type ResourceKey,
		type ResourcePile
	} from './trade';
	import { playSound, playTimerTick } from '$lib/utils/sound';

	type ChatMessage = {
		playerId: string;
		playerName: string;
		message: string;
		createdAt: string;
	};

	$: isGameOver = gameState?.turn?.phase === 'GameOver';
	$: turnRole = gameState?.turn?.role || 'Regular';
	$: turnRoleLabel =
		turnRole === 'PairedSecondary'
			? 'Player 2: build, play a development card, or trade with the bank'
			: turnRole === 'SpecialBuild'
				? 'Special Building Phase: build or buy a development card; trading and playing cards are disabled'
				: gameState?.settings?.gameMode === 'fiveSixExtension' &&
					  gameState?.settings?.fiveSixTurnRule === 'paired'
					? 'Player 1: roll, trade, and build normally'
					: null;
	$: timerEnabled = !!gameState?.turn?.timer_enabled;
	$: timerExpiresAtMs = gameState?.turn?.timer_expires_at
		? new Date(gameState.turn.timer_expires_at).getTime()
		: null;
	$: timerRemainingSeconds =
		timerEnabled && timerExpiresAtMs && !isGameOver
			? Math.max(0, Math.ceil((timerExpiresAtMs - nowMs) / 1000))
			: null;
	$: timerLabel = timerRemainingSeconds === null ? null : formatCountdown(timerRemainingSeconds);

	// Tick once per displayed second for the final 5s countdown (5,4,3,2,1), then buzz at 0.
	// Skip during the short Roll (dice) timer — that phase is only ~7s and shouldn't alarm.
	let lastTimerTickSecond: number | null = null;
	let playedTimerBuzz = false;
	$: {
		const phase = gameState?.turn?.phase;
		const isDiceTimer = phase === 'Roll';
		const secs = isDiceTimer ? null : timerRemainingSeconds;

		if (secs !== null && secs >= 1 && secs <= 5) {
			playedTimerBuzz = false;
			if (lastTimerTickSecond !== secs) {
				lastTimerTickSecond = secs;
				playTimerTick(secs);
			}
		} else if (secs === 0) {
			lastTimerTickSecond = null;
			if (!playedTimerBuzz) {
				playedTimerBuzz = true;
				playSound('timerBuzz');
			}
		} else {
			if (lastTimerTickSecond !== null) {
				lastTimerTickSecond = null;
			}
			if (playedTimerBuzz) {
				playedTimerBuzz = false;
			}
		}
	}

	let showGameOverSummary = false;
	let previousIsGameOver = false;

	let costsPanelOpen = false;
	let nowMs = Date.now();
	let timerInterval: ReturnType<typeof setInterval> | null = null;

	function toggleCostsPanel() {
		costsPanelOpen = !costsPanelOpen;
	}

	function formatCountdown(totalSeconds: number) {
		const minutes = Math.floor(totalSeconds / 60);
		const seconds = totalSeconds % 60;
		return `${minutes}:${seconds.toString().padStart(2, '0')}`;
	}

	export let gameState: any;
	export let playerId: string;
	export let players: any[];
	export let gameLog: { message: string; createdAt: string }[] = [];
	export let chatMessages: ChatMessage[] = [];
	export let sendGameAction: (action: string, payload?: any) => void;
	export let sendChatMessage: (message: string) => void;
	export let tradeComposerOpen = false;
	export let tradeComposerMode: 'player' | 'bank' = 'player';
	export let onOpenTradeComposer: (mode?: 'player' | 'bank') => void;
	export let onCloseTradeComposer: () => void;
	export let onTradeComposerModeChange: (mode: 'player' | 'bank') => void;
	export let onSubmitPlayerTrade: (offered: ResourcePile, requested: ResourcePile) => void;
	export let onSubmitBankTrade: (
		offeredResource: ResourceKey,
		requestedResource: ResourceKey
	) => void;
	export let onAcceptPlayerTrade: (tradeId: number) => void;
	export let onRejectPlayerTrade: (tradeId: number) => void;
	export let onCancelPlayerTrade: (tradeId: number) => void;
	export let onFinalizePlayerTrade: (tradeId: number, partnerPlayerId: string) => void;
	export let onLeaveGame: () => void;
	export let sfxMuted = false;
	export let onToggleSfx: () => void = () => {};

	let tradeOffered = createEmptyResourcePile();
	let tradeRequested = createEmptyResourcePile();

	function handleResourceClick(resource: ResourceKey) {
		if (!tradeComposerOpen) return;

		// In both modes, clicking a resource in the hand increments the offered amount
		const myHand = gameState?.players?.find((p: any) => p.id === playerId)?.hand ?? {};
		const currentOffered = tradeOffered[resource] || 0;
		const available = myHand[resource] || 0;

		if (tradeComposerMode === 'bank') {
			// In bank mode, offer only the amount needed for the trade (bank rate)
			// so the hand still shows remaining resources
			const bankRates = getBankTradeRates(gameState, playerId);
			const bankRate = bankRates[resource] ?? 4;
			const amountToOffer = Math.min(available, bankRate);
			tradeOffered = { ...createEmptyResourcePile(), [resource]: amountToOffer };
		} else if (currentOffered < available) {
			tradeOffered = { ...tradeOffered, [resource]: currentOffered + 1 };
		}
	}

	function handleTradeComposerModeChange(mode: 'player' | 'bank') {
		if (turnRole !== 'Regular' && mode === 'player') return;
		tradeOffered = createEmptyResourcePile();
		tradeRequested = createEmptyResourcePile();
		onTradeComposerModeChange(mode);
	}

	function handleCloseTradeComposer() {
		tradeOffered = createEmptyResourcePile();
		tradeRequested = createEmptyResourcePile();
		onCloseTradeComposer();
	}

	$: if (!tradeComposerOpen) {
		tradeOffered = createEmptyResourcePile();
		tradeRequested = createEmptyResourcePile();
	}

	let pendingBoardDevCardAction: 'knight' | 'road_building' | null = null;
	let pendingBoardBuildAction: 'city' | null = null;
	let roadBuildingSelection: string[] = [];

	function cancelPendingBoardDevCardAction() {
		pendingBoardDevCardAction = null;
		roadBuildingSelection = [];
	}

	function cancelPendingBoardBuildAction() {
		pendingBoardBuildAction = null;
	}

	function startKnightPlay() {
		cancelPendingBoardBuildAction();

		if (pendingBoardDevCardAction === 'knight') {
			cancelPendingBoardDevCardAction();
			return;
		}

		pendingBoardDevCardAction = 'knight';
		roadBuildingSelection = [];
	}

	function startRoadBuildingPlay() {
		cancelPendingBoardBuildAction();

		if (pendingBoardDevCardAction === 'road_building') {
			cancelPendingBoardDevCardAction();
			return;
		}

		pendingBoardDevCardAction = 'road_building';
		roadBuildingSelection = [];
	}

	function startCityPlacement() {
		cancelPendingBoardDevCardAction();

		if (pendingBoardBuildAction === 'city') {
			cancelPendingBoardBuildAction();
			return;
		}

		pendingBoardBuildAction = 'city';
	}

	function handleCityVertexSelect(vertexId: string) {
		sendGameAction('place_city', { vertex_id: vertexId });
		cancelPendingBoardBuildAction();
	}

	function handleKnightTileSelect(tileId: string) {
		sendGameAction('play_knight', { tile_id: tileId });
		cancelPendingBoardDevCardAction();
	}

	function handleRoadBuildingEdgeSelect(edgeId: string) {
		if (pendingBoardDevCardAction !== 'road_building') {
			return;
		}

		roadBuildingSelection = [...roadBuildingSelection, edgeId];

		if (roadBuildingSelection.length === 2) {
			sendGameAction('play_road_building', {
				first_edge_id: roadBuildingSelection[0],
				second_edge_id: roadBuildingSelection[1]
			});
			cancelPendingBoardDevCardAction();
		}
	}

	function confirmSingleRoadBuildingPlacement() {
		if (roadBuildingSelection.length !== 1) {
			return;
		}

		sendGameAction('play_road_building', {
			first_edge_id: roadBuildingSelection[0]
		});
		cancelPendingBoardDevCardAction();
	}

	$: if (
		pendingBoardDevCardAction &&
		(!gameState ||
			gameState.turn.current_player_id !== playerId ||
			!['Roll', 'Main'].includes(gameState.turn.phase))
	) {
		cancelPendingBoardDevCardAction();
	}

	$: if (
		pendingBoardBuildAction &&
		(!gameState || gameState.turn.current_player_id !== playerId || gameState.turn.phase !== 'Main')
	) {
		cancelPendingBoardBuildAction();
	}

	$: if (isGameOver !== previousIsGameOver) {
		if (isGameOver) {
			showGameOverSummary = true;
		} else {
			showGameOverSummary = false;
		}

		previousIsGameOver = isGameOver;
	}

	onDestroy(() => {
		if (timerInterval) {
			clearInterval(timerInterval);
		}
		cancelPendingBoardDevCardAction();
		cancelPendingBoardBuildAction();
	});

	onMount(() => {
		timerInterval = setInterval(() => {
			nowMs = Date.now();
		}, 250);

		return () => {
			if (timerInterval) {
				clearInterval(timerInterval);
			}
		};
	});
</script>

<div class="flex h-screen w-full flex-col lg:flex-row">
	<!-- Left Sidebar: Player List & Game Log -->
	<aside class="flex w-full flex-col bg-parchment/60 p-4 lg:w-80">
		<PlayerList
			{gameState}
			{players}
			{playerId}
			{gameLog}
			{chatMessages}
			{sendGameAction}
			{sendChatMessage}
		/>
	</aside>

	<!-- Main Area: Game Board -->
	<main class="relative flex flex-1 flex-col overflow-hidden">
		<!-- Board Area Container -->
		<div class="relative flex-1 overflow-hidden">
			{#if turnRoleLabel && !isGameOver}
				<div
					class="absolute top-4 left-1/2 z-20 max-w-xl -translate-x-1/2 rounded-full border border-white/30 bg-wood-dark/80 px-5 py-2 text-center text-xs font-bold text-white shadow-lg backdrop-blur-md"
				>
					{turnRoleLabel}
				</div>
			{/if}
			{#if timerEnabled && timerLabel}
				<div
					class="absolute top-4 left-4 z-20 rounded-2xl border border-white/20 bg-black/25 px-4 py-3 text-white shadow-lg backdrop-blur-md"
				>
					<div class="text-[10px] font-black tracking-[0.2em] text-white/70 uppercase">
						Turn Timer
					</div>
					<div class="mt-1 flex items-end gap-3">
						<div class="text-3xl leading-none font-black">{timerLabel}</div>
						<div class="text-xs font-semibold text-white/70">{gameState.turn.phase}</div>
					</div>
				</div>
			{/if}

			<!-- Pinned Top Controls -->
			<div class="absolute top-4 right-4 z-20 flex items-center gap-2">
				{#if isGameOver && !showGameOverSummary}
					<button
						on:click={() => (showGameOverSummary = true)}
						class="rounded-full border border-white/20 bg-ocean px-3 py-1 text-xs font-bold text-white shadow-lg shadow-ocean/30 transition-all hover:bg-ocean/90"
						title="Show game summary"
					>
						Show Summary
					</button>
				{/if}
				<button
					on:click={onToggleSfx}
					class="rounded-full border border-white/20 bg-black/10 px-3 py-1 text-xs font-bold text-white/50 backdrop-blur-md transition-all hover:bg-black/20 hover:text-white"
					title={sfxMuted ? 'Unmute sound effects' : 'Mute sound effects'}
					aria-pressed={sfxMuted}
				>
					{sfxMuted ? 'Sound Off' : 'Sound On'}
				</button>
				<button
					on:click={toggleCostsPanel}
					class="rounded-full border border-white/20 bg-black/10 px-3 py-1 text-xs font-bold text-white/50 backdrop-blur-md transition-all hover:bg-black/20 hover:text-white"
					title="Build costs"
				>
					Costs
				</button>
				<button
					on:click={onLeaveGame}
					class="rounded-full border border-white/20 bg-black/10 px-3 py-1 text-xs font-bold text-white/50 backdrop-blur-md transition-all hover:bg-black/20 hover:text-white"
				>
					Leave Game
				</button>
			</div>

			<!-- Scrollable Board Content -->
			<div class="h-full w-full overflow-auto">
				<BuildCostsPanel open={costsPanelOpen} onClose={toggleCostsPanel} />
				<GameBoard
					board={gameState.board}
					{gameState}
					{playerId}
					{players}
					{sendGameAction}
					{pendingBoardDevCardAction}
					{pendingBoardBuildAction}
					{roadBuildingSelection}
					onKnightTileSelect={handleKnightTileSelect}
					onRoadBuildingEdgeSelect={handleRoadBuildingEdgeSelect}
					onCityVertexSelect={handleCityVertexSelect}
				/>
			</div>

			<!-- Dice Display (Pinned to bottom right of board area) -->
			{#if gameState.last_roll}
				<div
					class="absolute right-6 bottom-6 z-10 flex flex-col items-center gap-2 rounded-2xl border-2 border-wood/10 bg-white/90 p-3 shadow-lg backdrop-blur-md"
				>
					<span class="text-[10px] font-bold tracking-wider text-wood-light uppercase"
						>LAST ROLL</span
					>
					<div class="flex gap-2">
						<div
							class="flex h-12 w-12 items-center justify-center rounded-xl border-2 border-wood/20 bg-white shadow-sm"
						>
							<Dice face={gameState.last_roll.die_one} color="#B22222" />
						</div>
						<div
							class="flex h-12 w-12 items-center justify-center rounded-xl border-2 border-wood/20 bg-white shadow-sm"
						>
							<Dice face={gameState.last_roll.die_two} color="#DAA520" />
						</div>
					</div>
				</div>
			{/if}
		</div>

		<TradeOfferPopup
			{gameState}
			{playerId}
			{players}
			onAccept={onAcceptPlayerTrade}
			onReject={onRejectPlayerTrade}
			onCancel={onCancelPlayerTrade}
			onFinalize={onFinalizePlayerTrade}
		/>

		<TradeComposer
			open={tradeComposerOpen}
			mode={tradeComposerMode}
			{gameState}
			{playerId}
			bind:offered={tradeOffered}
			bind:requested={tradeRequested}
			onClose={handleCloseTradeComposer}
			onModeChange={handleTradeComposerModeChange}
			{onSubmitPlayerTrade}
			{onSubmitBankTrade}
		/>

		<!-- Bottom Area: Player Hand & Actions -->
		<div class="bg-parchment/80 p-4 backdrop-blur-md">
			<PlayerHand
				{gameState}
				{playerId}
				{sendGameAction}
				{tradeComposerOpen}
				{pendingBoardDevCardAction}
				{pendingBoardBuildAction}
				{roadBuildingSelection}
				onTradeClick={onOpenTradeComposer}
				onStartKnightPlay={startKnightPlay}
				onStartRoadBuildingPlay={startRoadBuildingPlay}
				onCancelPendingBoardDevCardAction={cancelPendingBoardDevCardAction}
				onStartCityPlacement={startCityPlacement}
				onCancelPendingBoardBuildAction={cancelPendingBoardBuildAction}
				onConfirmSingleRoadBuildingPlacement={confirmSingleRoadBuildingPlacement}
				onResourceClick={handleResourceClick}
				{tradeOffered}
			/>
		</div>
	</main>

	{#if isGameOver && showGameOverSummary}
		<GameOverScreen
			{gameState}
			{players}
			{playerId}
			{gameLog}
			onShowBoard={() => (showGameOverSummary = false)}
		/>
	{/if}
</div>
