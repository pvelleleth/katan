<script lang="ts">
	import GameBoard from './GameBoard.svelte';
	import { onDestroy } from 'svelte';
	import PlayerHand from './PlayerHand.svelte';
	import PlayerList from './PlayerList.svelte';
	import Dice from './Dice.svelte';
	import TradeComposer from './TradeComposer.svelte';
	import TradeOfferPopup from './TradeOfferPopup.svelte';
	import GameOverScreen from './GameOverScreen.svelte';
	import type { ResourceKey, ResourcePile } from './trade';

	$: isGameOver = gameState?.turn?.phase === 'GameOver';

	export let gameState: any;
	export let playerId: string;
	export let players: any[];
	export let gameLog: { message: string; createdAt: string }[] = [];
	export let sendGameAction: (action: string, payload?: any) => void;
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
	export let onAcceptPlayerTrade: () => void;
	export let onRejectPlayerTrade: () => void;
	export let onCancelPlayerTrade: () => void;
	export let onFinalizePlayerTrade: (partnerPlayerId: string) => void;

	let pendingBoardDevCardAction: 'knight' | 'road_building' | null = null;
	let roadBuildingSelection: string[] = [];

	function cancelPendingBoardDevCardAction() {
		pendingBoardDevCardAction = null;
		roadBuildingSelection = [];
	}

	function startKnightPlay() {
		if (pendingBoardDevCardAction === 'knight') {
			cancelPendingBoardDevCardAction();
			return;
		}

		pendingBoardDevCardAction = 'knight';
		roadBuildingSelection = [];
	}

	function startRoadBuildingPlay() {
		if (pendingBoardDevCardAction === 'road_building') {
			cancelPendingBoardDevCardAction();
			return;
		}

		pendingBoardDevCardAction = 'road_building';
		roadBuildingSelection = [];
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

	onDestroy(() => {
		cancelPendingBoardDevCardAction();
	});
</script>

<div class="flex h-[calc(100vh-48px)] w-full flex-col lg:flex-row">
	<!-- Left Sidebar: Player List & Game Log -->
	<aside class="flex w-full flex-col border-r border-wood/10 bg-parchment/60 p-4 lg:w-80">
		<PlayerList {gameState} {players} {playerId} {gameLog} {sendGameAction} />
	</aside>

	<!-- Main Area: Game Board -->
	<main class="relative flex flex-1 flex-col overflow-hidden bg-ocean/5">
		<div class="flex-1 overflow-auto p-4">
			<GameBoard
				board={gameState.board}
				{gameState}
				{playerId}
				{players}
				{sendGameAction}
				{pendingBoardDevCardAction}
				{roadBuildingSelection}
				onKnightTileSelect={handleKnightTileSelect}
				onRoadBuildingEdgeSelect={handleRoadBuildingEdgeSelect}
			/>
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
			onClose={onCloseTradeComposer}
			onModeChange={onTradeComposerModeChange}
			{onSubmitPlayerTrade}
			{onSubmitBankTrade}
		/>

		<!-- Dice Display (Bottom Right) -->
		{#if gameState.last_roll}
			<div
				class="absolute right-6 bottom-28 z-10 flex flex-col items-center gap-2 rounded-2xl border-2 border-wood/10 bg-white/90 p-3 shadow-lg backdrop-blur-md"
			>
				<span class="text-[10px] font-bold tracking-wider text-wood-light uppercase">LAST ROLL</span
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

		<!-- Bottom Area: Player Hand & Actions -->
		<div class="border-t border-wood/10 bg-parchment/80 p-4 backdrop-blur-md">
			<PlayerHand
				{gameState}
				{playerId}
				{sendGameAction}
				{tradeComposerOpen}
				{pendingBoardDevCardAction}
				{roadBuildingSelection}
				onTradeClick={onOpenTradeComposer}
				onStartKnightPlay={startKnightPlay}
				onStartRoadBuildingPlay={startRoadBuildingPlay}
				onCancelPendingBoardDevCardAction={cancelPendingBoardDevCardAction}
				onConfirmSingleRoadBuildingPlacement={confirmSingleRoadBuildingPlacement}
			/>
		</div>
	</main>

	{#if isGameOver}
		<GameOverScreen {gameState} {players} {playerId} />
	{/if}
</div>
