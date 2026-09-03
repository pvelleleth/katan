<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount, onDestroy } from 'svelte';
	import { authClient } from '$lib/auth-client';
	import { PUBLIC_WS_URL } from '$env/static/public';
	import type { PageData } from './$types';

	export let data: PageData;

	let lobbyId = data.lobbyId;
	let user: Record<string, any> | null = null;
	let loading = true;
	let copied = false;
	let currentPlayerId = '';
	let joinError = data.joinError ?? '';

	type ColorNames = 'brick' | 'ocean' | 'wheat' | 'purple' | 'forest' | 'wood';

	type GameSettings = {
		turnTimerEnabled: boolean;
		turnTimeSeconds: number;
		maxPlayers: number;
		victoryPoints: number;
		gameMode: 'base' | 'fiveSixExtension';
		fiveSixTurnRule: 'paired' | 'specialBuild';
		useSeafarers: boolean;
		useTraders: boolean;
		useExplorers: boolean;
	};

	const defaultSettings: GameSettings = {
		turnTimerEnabled: true,
		turnTimeSeconds: 120,
		maxPlayers: 4,
		victoryPoints: 10,
		gameMode: 'base',
		fiveSixTurnRule: 'paired',
		useSeafarers: false,
		useTraders: false,
		useExplorers: false
	};

	let settings: GameSettings = { ...defaultSettings };
	let settingsSaved = false;
	let saveTimeout: ReturnType<typeof setTimeout>;
	let isPublic = data.isPublic ?? false;
	let visibilitySaving = false;
	let visibilityError = '';

	let players: {
		id: string;
		name: string;
		isHost: boolean;
		isReady: boolean;
		isConnected: boolean;
		color: ColorNames;
	}[] = [];

	let ws: WebSocket | null = null;

	let gameStarted = false;
	let gameState: any = null;
	let isConnecting = true;
	let gameLog: { type?: string; payload?: any; message: string; createdAt: string }[] = [];
	let chatMessages: {
		playerId: string;
		playerName: string;
		message: string;
		createdAt: string;
	}[] = [];
	let tradeComposerOpen = false;
	let tradeComposerMode: 'player' | 'bank' = 'player';

	import { invalidateAll } from '$app/navigation';
	import GameView from '$lib/components/game/GameView.svelte';
	import ChatPanel from '$lib/components/game/ChatPanel.svelte';
	import type { ResourceKey, ResourcePile } from '$lib/components/game/trade';
	import {
		installAudioUnlock,
		isMuted,
		playGameEvent,
		playSound,
		setMuted,
		unlockAudio
	} from '$lib/utils/sound';

	let sfxMuted = false;
	let previousGamePhase: string | null = null;
	let removeAudioUnlock: (() => void) | null = null;

	onMount(async () => {
		sfxMuted = isMuted();
		removeAudioUnlock = installAudioUnlock();

		try {
			const { data: sessionData } = await authClient.getSession();

			// Fetch existing activity and chat history
			fetch(`/api/games/${lobbyId}/events`)
				.then((res) => res.json())
				.then((data) => {
					if (data.events) {
						const loadedEvents = data.events.map((e: any) => ({
							type: e.type,
							payload: e.payload,
							message: e.message,
							createdAt: e.createdAt
						}));

						gameLog = loadedEvents.filter(
							(event: any) => event.type !== 'chat_message' && event.message
						);
						chatMessages = loadedEvents
							.filter((event: any) => event.type === 'chat_message')
							.map((event: any) => ({
								playerId: String(event.payload?.player_id ?? ''),
								playerName: String(event.payload?.player_name ?? 'Player'),
								message: String(event.payload?.message ?? event.message ?? ''),
								createdAt: String(event.payload?.created_at ?? event.createdAt)
							}))
							.filter((event: any) => event.message);
					}
				})
				.catch(console.error);

			if (sessionData?.user) {
				user = sessionData.user;
				// If they have a token on the client but the server missed it (or we just logged them in)
				if (data.needsSessionRefresh) {
					await invalidateAll();
				} else if (data.joinSuccess === false) {
					isConnecting = false;
				} else {
					try {
						await connectWebSocket();
					} catch (error) {
						console.error('Failed to connect to lobby websocket', error);
						isConnecting = false;
						joinError = 'Unable to join this lobby.';
					}
				}
			} else {
				// Try anonymous sign in if no valid session exists
				const res = await authClient.signIn.anonymous();
				if (
					res.data?.user ||
					res.error?.code === 'ANONYMOUS_USERS_CANNOT_SIGN_IN_AGAIN_ANONYMOUSLY'
				) {
					const secondTry = await authClient.getSession();
					if (secondTry.data?.user) {
						user = secondTry.data.user;
						await invalidateAll();
					}
				} else {
					goto('/login');
				}
			}
		} catch (e) {
			console.error('Auth error', e);
			goto('/login');
		} finally {
			loading = false;
		}
	});

	// Sync settings from page data or lobby updates
	$: if (data.settings) {
		settings = { ...defaultSettings, ...data.settings };
	}

	onDestroy(() => {
		if (ws) {
			ws.close();
		}
		removeAudioUnlock?.();
	});

	function toggleSfxMuted() {
		unlockAudio();
		sfxMuted = !sfxMuted;
		setMuted(sfxMuted);
		if (!sfxMuted) {
			playSound('ui');
		}
	}

	async function fetchLobbyBootstrap() {
		const res = await fetch(`/api/ws-bootstrap?lobbyId=${lobbyId}`);
		if (!res.ok) {
			throw new Error('Unable to join lobby.');
		}

		const bootstrap = await res.json();
		currentPlayerId = bootstrap.playerId;
		return bootstrap as { token: string; playerId: string; name: string; expiresAt: number };
	}

	async function connectWebSocket() {
		const bootstrap = await fetchLobbyBootstrap();

		// Connect to Crystal WebSocket Server
		ws = new WebSocket(`${PUBLIC_WS_URL}/ws/lobby/${lobbyId}`);

		ws.onopen = () => {
			console.log('Connected to game engine!');
			ws?.send(
				JSON.stringify({
					action: 'join',
					payload: {
						token: bootstrap.token
					}
				})
			);
		};

		ws.onmessage = (event) => {
			const msg = JSON.parse(event.data);

			if (msg.type === 'lobby_update') {
				isConnecting = false;
				joinError = '';
				const updatedPlayers = msg.lobby.players;
				if (msg.lobby.settings) {
					settings = { ...defaultSettings, ...msg.lobby.settings };
				}
				if (typeof msg.lobby.is_public === 'boolean') {
					isPublic = msg.lobby.is_public;
				}

				// Keep the color assignment stable by looking at the DB or doing it deterministically
				const fallbackColors: ColorNames[] = [
					'brick',
					'ocean',
					'wheat',
					'purple',
					'forest',
					'wood'
				];

				players = updatedPlayers.map((p: any, index: number) => ({
					id: p.id,
					name: p.name,
					isReady: p.ready,
					isConnected: p.connected ?? true,
					isHost: p.id === data.hostId,
					color: fallbackColors[index % fallbackColors.length]
				}));
			} else if (msg.type === 'game_started' || msg.type === 'game_update') {
				const wasStarted = gameStarted;
				isConnecting = false;
				joinError = '';
				gameStarted = true;
				gameState = msg.game_state;

				const nextPhase = msg.game_state?.turn?.phase ?? null;
				if (msg.type === 'game_started' && !wasStarted) {
					playGameEvent('game_started');
				} else if (
					nextPhase === 'GameOver' &&
					previousGamePhase &&
					previousGamePhase !== 'GameOver'
				) {
					playSound('victory');
				}
				previousGamePhase = nextPhase;
			} else if (msg.type === 'game_log') {
				gameLog = [
					...gameLog,
					{
						type: msg.event_type,
						payload: msg.payload,
						message: msg.message,
						createdAt: new Date().toISOString()
					}
				];
				// Live events only — historical log load does not go through the socket.
				if (msg.event_type && msg.event_type !== 'game_started') {
					playGameEvent(msg.event_type, msg.payload ?? null, msg.message ?? null);
				}
			} else if (msg.type === 'chat_message') {
				chatMessages = [
					...chatMessages,
					{
						playerId: msg.player_id,
						playerName: msg.player_name,
						message: msg.message,
						createdAt: msg.created_at ?? new Date().toISOString()
					}
				];
				// Soft ping for messages from other players.
				if (msg.player_id && msg.player_id !== currentPlayerId) {
					playGameEvent('chat_message');
				}
			} else if (msg.type === 'kicked') {
				// This client was kicked by the host
				ws?.close();
				goto('/game?kicked=1');
			} else if (msg.type === 'error') {
				isConnecting = false;
				if (players.length === 0 && !gameStarted) {
					joinError = msg.message || 'Unable to join this lobby.';
				} else {
					visibilityError = msg.message || 'Unable to update lobby visibility.';
				}
				playSound('error');
			}
		};

		ws.onclose = () => {
			console.log('Disconnected from game engine.');
		};
	}

	function copyInviteLink() {
		const link = `${window.location.origin}/game/${lobbyId}`;
		navigator.clipboard.writeText(link);
		copied = true;
		setTimeout(() => (copied = false), 2000);
	}

	function toggleReady() {
		if (!ws || !currentPlayerId) return;

		const myPlayer = players.find((p) => p.id === currentPlayerId);
		if (myPlayer) {
			ws.send(
				JSON.stringify({
					action: 'ready',
					payload: { player_id: currentPlayerId, ready: !myPlayer.isReady }
				})
			);
		}
	}

	function startGame() {
		if (!ws || currentPlayerId !== data.hostId) return;
		ws.send(
			JSON.stringify({
				action: 'start_game'
			})
		);
	}

	function kickPlayer(targetId: string) {
		if (!ws || !currentPlayerId) return;
		ws.send(
			JSON.stringify({
				action: 'kick',
				payload: { target_player_id: targetId }
			})
		);
	}

	function saveSettings() {
		if (!ws || currentPlayerId !== data.hostId) return;
		ws.send(
			JSON.stringify({
				action: 'settings_update',
				payload: { settings }
			})
		);

		// Visual feedback
		settingsSaved = true;
		clearTimeout(saveTimeout);
		saveTimeout = setTimeout(() => {
			settingsSaved = false;
		}, 2000);
	}

	async function setPublicLobby(next: boolean) {
		if (!canEditVisibility || visibilitySaving || next === isPublic) return;

		visibilitySaving = true;
		visibilityError = '';

		try {
			ws?.send(
				JSON.stringify({
					action: 'visibility_update',
					payload: { is_public: next }
				})
			);
		} catch (e) {
			console.error('Failed to update lobby visibility', e);
			visibilityError = 'Unable to update lobby visibility.';
		} finally {
			visibilitySaving = false;
		}
	}

	function togglePublicLobby() {
		setPublicLobby(!isPublic);
	}

	function sendGameAction(action: string, payload: any = {}) {
		if (!ws || !currentPlayerId) return;
		ws.send(
			JSON.stringify({
				action,
				payload
			})
		);
	}

	function sendChatMessage(message: string) {
		if (!ws || !currentPlayerId) return;
		ws.send(
			JSON.stringify({
				action: 'send_chat_message',
				payload: { message }
			})
		);
	}

	function openTradeComposer(mode: 'player' | 'bank' = 'player') {
		if (tradeComposerOpen && tradeComposerMode === mode) {
			tradeComposerOpen = false;
			return;
		}

		tradeComposerMode = mode;
		tradeComposerOpen = true;
	}

	function closeTradeComposer() {
		tradeComposerOpen = false;
	}

	function setTradeComposerMode(mode: 'player' | 'bank') {
		tradeComposerMode = mode;
	}

	function submitPlayerTrade(offered: ResourcePile, requested: ResourcePile) {
		sendGameAction('propose_player_trade', { offered, requested });
		closeTradeComposer();
	}

	function submitBankTrade(offeredResource: ResourceKey, requestedResource: ResourceKey) {
		sendGameAction('trade_with_bank', {
			offered_resource: offeredResource,
			requested_resource: requestedResource
		});
		closeTradeComposer();
	}

	function acceptPlayerTrade(tradeId: number) {
		sendGameAction('accept_player_trade', { trade_id: tradeId });
	}

	function rejectPlayerTrade(tradeId: number) {
		sendGameAction('reject_player_trade', { trade_id: tradeId });
	}

	function cancelPlayerTrade(tradeId: number) {
		sendGameAction('cancel_player_trade', { trade_id: tradeId });
	}

	function finalizePlayerTrade(tradeId: number, partnerPlayerId: string) {
		sendGameAction('finalize_player_trade', {
			trade_id: tradeId,
			partner_player_id: partnerPlayerId
		});
	}

	// Helper colors
	const colors: Record<ColorNames, string> = {
		brick: 'bg-brick',
		ocean: 'bg-ocean',
		wheat: 'bg-wheat',
		purple: 'bg-purple',
		forest: 'bg-forest',
		wood: 'bg-wood'
	};

	$: offlinePlayers = players.filter((player) => !player.isConnected);
	$: readyConnectedPlayers = players.filter((player) => player.isConnected && player.isReady);
	$: requiredPlayerRange = settings.gameMode === 'fiveSixExtension' ? [5, 6] : [3, 4];
	$: playerSlotCount = settings.gameMode === 'fiveSixExtension' ? 6 : settings.maxPlayers;
	$: canStartGame =
		players.length >= requiredPlayerRange[0] &&
		players.length <= requiredPlayerRange[1] &&
		players.length <= playerSlotCount &&
		players.every((player) => player.isConnected && player.isReady);
	$: canEditVisibility =
		currentPlayerId === data.hostId && data.status === 'waiting' && !gameStarted;
	$: lobbyStatus =
		offlinePlayers.length > 0
			? `${offlinePlayers.length} player${offlinePlayers.length === 1 ? '' : 's'} disconnected`
			: 'Waiting for players...';
	$: if (
		tradeComposerOpen &&
		(!gameStarted ||
			!gameState ||
			gameState.turn.current_player_id !== currentPlayerId ||
			gameState.turn.phase !== 'Main' ||
			gameState.turn.role === 'SpecialBuild')
	) {
		tradeComposerOpen = false;
	}

	function selectGameMode(mode: GameSettings['gameMode']) {
		settings.gameMode = mode;
		settings.maxPlayers = mode === 'fiveSixExtension' ? 6 : 4;
		settings = { ...settings };
	}
</script>

<svelte:head>
	<title>Lobby {lobbyId} | Settler</title>
</svelte:head>

<main
	class="relative flex min-h-screen flex-col overflow-hidden bg-parchment-texture font-trebuchet selection:bg-ocean/30"
>
	{#if !gameStarted}
		<!-- Navbar -->
		<header
			class="sticky top-0 z-50 flex h-12 items-center justify-between bg-parchment/60 px-4 backdrop-blur-xl lg:px-8"
		>
			<a
				href="/"
				class="text-xl font-[900] tracking-tight text-wood transition-colors select-none hover:text-wood-dark lg:text-2xl"
			>
				SETTLER
			</a>

			<div class="flex items-center gap-3">
				<button
					type="button"
					on:click={toggleSfxMuted}
					class="rounded-full border border-wood/20 px-3 py-1 text-xs font-bold text-wood transition-all hover:border-ocean/30 hover:text-ocean"
					title={sfxMuted ? 'Unmute sound effects' : 'Mute sound effects'}
					aria-pressed={sfxMuted}
				>
					{sfxMuted ? 'Sound Off' : 'Sound On'}
				</button>
				<button
					on:click={() => goto('/game')}
					class="rounded-full border border-wood/20 px-3 py-1 text-xs font-bold text-wood transition-all hover:border-brick/20 hover:text-brick"
				>
					Leave {gameStarted ? 'Game' : 'Lobby'}
				</button>
			</div>
		</header>
	{/if}

	{#if isConnecting}
		<div class="flex flex-1 items-center justify-center">
			<div class="flex flex-col items-center gap-4">
				<div
					class="h-12 w-12 animate-spin rounded-full border-4 border-ocean border-t-transparent"
				></div>
				<p class="font-bold text-wood-dark">Connecting to game...</p>
			</div>
		</div>
	{:else if data.joinSuccess === false && data.joinError}
		<div class="flex flex-1 items-center justify-center p-6">
			<div
				class="w-full max-w-lg rounded-[2rem] border-2 border-brick/10 bg-white/80 p-8 text-center shadow-xl glass-panel"
			>
				<h1 class="text-3xl font-black text-wood-dark">Lobby Unavailable</h1>
				<p class="mt-3 text-base font-semibold text-wood-dark/80">{data.joinError}</p>
				<div class="mt-6 flex justify-center">
					<button
						on:click={() => goto('/game')}
						class="rounded-2xl bg-ocean px-6 py-3 text-lg font-bold text-white shadow-md transition-all hover:scale-[1.02] hover:bg-[#1880a8]"
					>
						Browse Lobbies
					</button>
				</div>
			</div>
		</div>
	{:else if joinError}
		<div class="flex flex-1 items-center justify-center p-6">
			<div
				class="w-full max-w-lg rounded-[2rem] border-2 border-brick/10 bg-white/80 p-8 text-center shadow-xl glass-panel"
			>
				<h1 class="text-3xl font-black text-wood-dark">Lobby Unavailable</h1>
				<p class="mt-3 text-base font-semibold text-wood-dark/80">{joinError}</p>
				<div class="mt-6 flex justify-center">
					<button
						on:click={() => goto('/game')}
						class="rounded-2xl bg-ocean px-6 py-3 text-lg font-bold text-white shadow-md transition-all hover:scale-[1.02] hover:bg-[#1880a8]"
					>
						Browse Lobbies
					</button>
				</div>
			</div>
		</div>
	{:else if gameStarted && gameState}
		<GameView
			{gameState}
			{players}
			playerId={currentPlayerId}
			{sendGameAction}
			{sendChatMessage}
			{gameLog}
			{chatMessages}
			{tradeComposerOpen}
			{tradeComposerMode}
			{sfxMuted}
			onToggleSfx={toggleSfxMuted}
			onOpenTradeComposer={openTradeComposer}
			onCloseTradeComposer={closeTradeComposer}
			onTradeComposerModeChange={setTradeComposerMode}
			onSubmitPlayerTrade={submitPlayerTrade}
			onSubmitBankTrade={submitBankTrade}
			onAcceptPlayerTrade={acceptPlayerTrade}
			onRejectPlayerTrade={rejectPlayerTrade}
			onCancelPlayerTrade={cancelPlayerTrade}
			onFinalizePlayerTrade={finalizePlayerTrade}
			onLeaveGame={() => goto('/game')}
		/>
	{:else}
		<div class="relative flex min-h-0 flex-1 flex-col items-center justify-center p-6 lg:p-12">
			<!-- Decorative Glow -->
			<div
				class="pointer-events-none absolute top-1/2 left-1/2 h-[600px] w-full max-w-4xl -translate-x-1/2 -translate-y-1/2 rounded-full bg-ocean/10 blur-[100px]"
			></div>

			<div
				class="animate-in fade-in zoom-in-95 relative z-10 flex w-full max-w-6xl flex-col gap-8 duration-500"
			>
				<div class="grid grid-cols-1 gap-8 lg:grid-cols-[1fr_320px]">
					<div class="flex flex-col gap-8">
						<!-- Lobby Code Header -->
						<div
							class="flex flex-col items-center justify-between gap-6 rounded-3xl border-2 border-wood/10 p-8 shadow-xl glass-panel sm:flex-row"
						>
							<div>
								<div class="mb-2 flex flex-wrap items-center gap-2">
									<h1 class="text-xl font-bold tracking-widest text-wood-light/80 uppercase">
										Lobby Code
									</h1>
									<span
										class="rounded-full px-3 py-1 text-[0.65rem] font-black tracking-[0.2em] uppercase {isPublic
											? 'bg-forest/10 text-forest'
											: 'bg-wood/10 text-wood-light'}"
									>
										{isPublic ? 'Listed in browse' : 'Invite only'}
									</span>
								</div>
								<div
									class="font-mono text-4xl font-black tracking-[0.2em] text-wood-dark drop-shadow-sm lg:text-5xl"
								>
									{lobbyId}
								</div>
							</div>

							<button
								on:click={copyInviteLink}
								class="flex items-center gap-3 rounded-2xl border border-ocean/20 bg-white/80 px-6 py-4 text-lg font-bold text-ocean shadow-md transition-all hover:scale-105 hover:bg-white active:scale-95"
							>
								{#if copied}
									<svg
										class="h-6 w-6 text-forest"
										fill="none"
										stroke="currentColor"
										viewBox="0 0 24 24"
										><path
											stroke-linecap="round"
											stroke-linejoin="round"
											stroke-width="2.5"
											d="M5 13l4 4L19 7"
										/></svg
									>
									<span class="text-forest">Copied!</span>
								{:else}
									<svg class="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"
										><path
											stroke-linecap="round"
											stroke-linejoin="round"
											stroke-width="2.5"
											d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"
										/></svg
									>
									<span>Copy Link</span>
								{/if}
							</button>
						</div>

						<!-- Players List -->
						<div class="rounded-3xl border-2 border-wood/10 p-8 shadow-xl glass-panel">
							<div class="mb-6 flex items-center justify-between">
								<h2 class="text-2xl font-black text-wood-dark">
									Players ({players.length}/{playerSlotCount})
								</h2>
								<span
									class="rounded-full bg-wood/10 px-3 py-1 text-center text-sm font-bold text-wood-light"
									>{lobbyStatus}</span
								>
							</div>

							<div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
								{#each players as player}
									<div
										class="group relative flex items-center gap-4 overflow-hidden rounded-2xl border border-wood/10 bg-white/50 p-4 {player.isConnected
											? ''
											: 'opacity-70'}"
									>
										<!-- Player Color indicator -->
										<div
											class="h-12 w-12 rounded-full {colors[
												player.color
											]} flex shrink-0 items-center justify-center border-2 border-white/50 text-white shadow-md"
										>
											<svg class="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"
												><path
													stroke-linecap="round"
													stroke-linejoin="round"
													stroke-width="2.5"
													d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"
												/></svg
											>
										</div>

										<div class="min-w-0 flex-1">
											<div
												class="flex items-center gap-2 truncate text-lg font-bold text-wood-dark"
											>
												{player.name}
												{#if player.id === currentPlayerId}
													<span
														class="translate-y-[-1px] rounded-full bg-ocean/80 px-2 py-0.5 text-[0.65rem] font-black tracking-wider text-white uppercase"
														>You</span
													>
												{/if}
												{#if player.isHost}
													<svg class="h-4 w-4 text-brick" fill="currentColor" viewBox="0 0 24 24"
														><title>Host</title><path
															d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"
														/></svg
													>
												{/if}
											</div>
											<div class="flex items-center gap-2 text-sm font-semibold">
												<span class={player.isReady ? 'text-forest' : 'text-wood/50'}>
													{player.isReady ? 'Ready' : 'Not Ready'}
												</span>
												{#if !player.isConnected}
													<span
														class="rounded-full bg-brick/10 px-2 py-0.5 text-[0.65rem] font-black tracking-wider text-brick uppercase"
													>
														Offline
													</span>
												{/if}
											</div>
										</div>

										<!-- Kick button: only visible for the host, on other players' cards -->
										{#if currentPlayerId === data.hostId && player.id !== currentPlayerId}
											<button
												on:click={() => kickPlayer(player.id)}
												title="Kick player"
												class="ml-auto flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-brick/20 bg-brick/10 text-brick opacity-0 transition-all group-hover:opacity-100 hover:bg-brick hover:text-white"
											>
												<svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
													<path
														stroke-linecap="round"
														stroke-linejoin="round"
														stroke-width="2.5"
														d="M6 18L18 6M6 6l12 12"
													/>
												</svg>
											</button>
										{/if}
									</div>
								{/each}

								<!-- Empty Slots -->
								{#each Array(Math.max(0, playerSlotCount - players.length)) as _}
									<div
										class="flex h-[84px] items-center gap-4 rounded-2xl border-2 border-dashed border-wood/20 bg-wood/5 p-4"
									>
										<div
											class="flex h-12 w-12 shrink-0 items-center justify-center rounded-full border-2 border-wood/10 bg-wood/10"
										>
											<span class="text-xl font-bold text-wood/30">?</span>
										</div>
										<div class="text-lg font-bold text-wood/40">Empty Slot</div>
									</div>
								{/each}
							</div>
						</div>

						<!-- Action Area -->
						<div class="flex justify-end">
							{#if currentPlayerId && players.find((p) => p.id === currentPlayerId)}
								{@const me = players.find((p) => p.id === currentPlayerId)}
								{#if me && !me.isReady}
									<button
										on:click={toggleReady}
										class="group/start flex w-full items-center justify-center gap-2 rounded-2xl border border-[#146c8e] bg-ocean px-8 py-3.5 text-xl font-bold text-white shadow-xl shadow-ocean/20 transition-all hover:scale-105 hover:bg-[#1880a8] active:scale-95 sm:w-auto"
									>
										Ready Up
										<svg
											class="h-6 w-6 transition-transform group-hover/start:translate-x-1"
											fill="none"
											stroke="currentColor"
											viewBox="0 0 24 24"
											><path
												stroke-linecap="round"
												stroke-linejoin="round"
												stroke-width="2.5"
												d="M5 13l4 4L19 7"
											/></svg
										>
									</button>
								{:else if currentPlayerId === data.hostId}
									<button
										on:click={startGame}
										class="group/start flex w-full items-center justify-center gap-2 rounded-2xl bg-forest px-8 py-3.5 text-xl font-bold text-white shadow-xl shadow-forest/20 transition-all hover:scale-105 hover:bg-forest/90 active:scale-95 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:scale-100 sm:w-auto"
										disabled={!canStartGame}
									>
										Start Game
										<svg
											class="h-6 w-6 transition-transform group-hover/start:translate-x-1"
											fill="none"
											stroke="currentColor"
											viewBox="0 0 24 24"
											><path
												stroke-linecap="round"
												stroke-linejoin="round"
												stroke-width="2.5"
												d="M14 5l7 7m0 0l-7 7m7-7H3"
											/></svg
										>
									</button>
								{:else}
									<button
										on:click={toggleReady}
										class="flex w-full items-center justify-center gap-2 rounded-2xl border border-wood/20 bg-wood/20 px-8 py-3.5 text-xl font-bold text-wood-dark transition-all hover:scale-105 hover:bg-wood/30 active:scale-95 sm:w-auto"
									>
										Unready
									</button>
								{/if}
							{/if}
						</div>
					</div>

					<!-- Game Settings (all players can view, host can edit) -->
					<aside>
						{#if currentPlayerId}
							{@const isHost = currentPlayerId === data.hostId}
							<div class="sticky top-[112px] flex flex-col gap-6">
								<div class="rounded-3xl border-2 border-wood/10 p-6 shadow-xl glass-panel">
									<h2 class="mb-5 text-xl font-black text-wood-dark">Game Settings</h2>
									<div class="flex flex-col gap-5">
										<div>
											<label
												class="flex items-center gap-3 {!isHost
													? 'cursor-default'
													: 'cursor-pointer'}"
											>
												<input
													type="checkbox"
													bind:checked={settings.turnTimerEnabled}
													disabled={!isHost}
													class="h-4 w-4 rounded border-wood/30 text-ocean focus:ring-ocean/30 disabled:cursor-not-allowed disabled:opacity-70"
												/>
												<span class="text-sm font-semibold text-wood-dark">Enable turn timer</span>
											</label>
										</div>
										<div>
											<label
												for="turnTime"
												class="mb-1 block text-xs font-bold tracking-wider text-wood-light uppercase"
												>Turn time (sec)</label
											>
											<input
												id="turnTime"
												type="number"
												min="30"
												max="300"
												step="30"
												bind:value={settings.turnTimeSeconds}
												disabled={!isHost}
												class="w-full rounded-xl border border-wood/20 bg-white/80 px-3 py-2 text-sm font-semibold text-wood-dark focus:border-ocean/50 focus:ring-2 focus:ring-ocean/20 focus:outline-none disabled:cursor-not-allowed disabled:bg-wood/5 disabled:opacity-70"
											/>
										</div>
										<div>
											<p class="mb-2 text-xs font-bold tracking-wider text-wood-light uppercase">
												Game set
											</p>
											<div class="grid grid-cols-2 gap-2">
												<button
													type="button"
													disabled={!isHost || players.length > 4}
													on:click={() => selectGameMode('base')}
													class="rounded-xl border px-3 py-2 text-xs font-bold transition {settings.gameMode ===
													'base'
														? 'border-ocean bg-ocean text-white'
														: 'border-wood/20 bg-white/70 text-wood-dark'} disabled:cursor-not-allowed disabled:opacity-40"
												>
													Normal 3–4
												</button>
												<button
													type="button"
													disabled={!isHost}
													on:click={() => selectGameMode('fiveSixExtension')}
													class="rounded-xl border px-3 py-2 text-xs font-bold transition {settings.gameMode ===
													'fiveSixExtension'
														? 'border-forest bg-forest text-white'
														: 'border-wood/20 bg-white/70 text-wood-dark'} disabled:cursor-not-allowed disabled:opacity-40"
												>
													5–6 Extension
												</button>
											</div>
										</div>
										{#if settings.gameMode === 'base'}
											<div>
												<label
													for="maxPlayers"
													class="mb-1 block text-xs font-bold tracking-wider text-wood-light uppercase"
													>Seats</label
												>
												<select
													id="maxPlayers"
													bind:value={settings.maxPlayers}
													disabled={!isHost}
													class="w-full rounded-xl border border-wood/20 bg-white/80 px-3 py-2 text-sm font-semibold text-wood-dark disabled:cursor-not-allowed disabled:opacity-70"
												>
													<option value={3} disabled={players.length > 3}>3 players</option>
													<option value={4}>4 players</option>
												</select>
											</div>
										{/if}
										{#if settings.gameMode === 'fiveSixExtension'}
											<div>
												<label
													for="fiveSixTurnRule"
													class="mb-1 block text-xs font-bold tracking-wider text-wood-light uppercase"
													>Extension turn rules</label
												>
												<select
													id="fiveSixTurnRule"
													bind:value={settings.fiveSixTurnRule}
													disabled={!isHost}
													class="w-full rounded-xl border border-wood/20 bg-white/80 px-3 py-2 text-sm font-semibold text-wood-dark disabled:cursor-not-allowed disabled:opacity-70"
												>
													<option value="paired">Paired players (official)</option>
													<option value="specialBuild">Special Building Phase (legacy)</option>
												</select>
											</div>
										{/if}
										<div>
											<label
												for="victoryPoints"
												class="mb-1 block text-xs font-bold tracking-wider text-wood-light uppercase"
												>Victory points</label
											>
											<input
												id="victoryPoints"
												type="number"
												min="5"
												max="20"
												bind:value={settings.victoryPoints}
												disabled={!isHost}
												class="w-full rounded-xl border border-wood/20 bg-white/80 px-3 py-2 text-sm font-semibold text-wood-dark focus:border-ocean/50 focus:ring-2 focus:ring-ocean/20 focus:outline-none disabled:cursor-not-allowed disabled:bg-wood/5 disabled:opacity-70"
											/>
										</div>
										<div class="border-t border-wood/10 pt-5">
											<p id="lobby-visibility-heading" class="text-sm font-semibold text-wood-dark">
												Who can join?
											</p>
											<p
												id="lobby-visibility-help"
												class="mt-1 text-xs font-medium text-wood-light"
											>
												{isPublic
													? 'Shown on the browse page so anyone can discover and join.'
													: 'Hidden from browse. Only people you share the link with can join.'}
											</p>
											<div
												class="mt-4 flex items-center justify-center gap-3 sm:justify-start"
												role="group"
												aria-labelledby="lobby-visibility-heading"
											>
												<span
													class="w-14 text-right text-sm font-bold tracking-wide text-wood-dark uppercase transition-opacity {!isPublic
														? 'opacity-100'
														: 'opacity-40'}"
												>
													Private
												</span>
												<button
													type="button"
													role="switch"
													aria-checked={isPublic}
													aria-busy={visibilitySaving}
													aria-labelledby="lobby-visibility-heading"
													aria-describedby="lobby-visibility-help"
													disabled={!canEditVisibility || visibilitySaving}
													on:click={togglePublicLobby}
													class="relative h-8 w-[3.25rem] shrink-0 rounded-full border-2 transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-ocean/40 focus-visible:ring-offset-2 focus-visible:ring-offset-parchment disabled:cursor-not-allowed disabled:opacity-50 {isPublic
														? 'border-forest/40 bg-forest'
														: 'border-wood/25 bg-wood/15'}"
												>
													<span
														class="pointer-events-none absolute top-1/2 left-1 h-5 w-5 -translate-y-1/2 rounded-full bg-white shadow-md transition-transform duration-200 ease-out {isPublic
															? 'translate-x-[1.35rem]'
															: 'translate-x-0.5'}"
													></span>
												</button>
												<span
													class="w-14 text-left text-sm font-bold tracking-wide text-wood-dark uppercase transition-opacity {isPublic
														? 'text-forest opacity-100'
														: 'opacity-40'}"
												>
													Public
												</span>
											</div>
											{#if visibilityError}
												<p class="mt-3 text-sm font-semibold text-brick">{visibilityError}</p>
											{/if}
										</div>
										<div class="flex flex-col gap-3 pt-2">
											<label
												class="flex items-center gap-3 {!isHost
													? 'cursor-default'
													: 'cursor-pointer'}"
											>
												<input
													type="checkbox"
													bind:checked={settings.useSeafarers}
													disabled={!isHost}
													class="h-4 w-4 rounded border-wood/30 text-ocean focus:ring-ocean/30 disabled:cursor-not-allowed disabled:opacity-70"
												/>
												<span class="text-sm font-semibold text-wood-dark">Seafarers</span>
											</label>
											<label
												class="flex items-center gap-3 {!isHost
													? 'cursor-default'
													: 'cursor-pointer'}"
											>
												<input
													type="checkbox"
													bind:checked={settings.useTraders}
													disabled={!isHost}
													class="h-4 w-4 rounded border-wood/30 text-ocean focus:ring-ocean/30 disabled:cursor-not-allowed disabled:opacity-70"
												/>
												<span class="text-sm font-semibold text-wood-dark">Traders</span>
											</label>
											<label
												class="flex items-center gap-3 {!isHost
													? 'cursor-default'
													: 'cursor-pointer'}"
											>
												<input
													type="checkbox"
													bind:checked={settings.useExplorers}
													disabled={!isHost}
													class="h-4 w-4 rounded border-wood/30 text-ocean focus:ring-ocean/30 disabled:cursor-not-allowed disabled:opacity-70"
												/>
												<span class="text-sm font-semibold text-wood-dark">Explorers</span>
											</label>
										</div>
									</div>
									{#if isHost}
										<button
											on:click={saveSettings}
											class="mt-6 flex w-full items-center justify-center gap-2 rounded-xl border border-ocean/20 {settingsSaved
												? 'bg-forest'
												: 'bg-ocean'} px-4 py-2.5 text-sm font-bold text-white shadow-md transition-all hover:scale-[1.02] active:scale-[0.98]"
										>
											{#if settingsSaved}
												<svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
													<path
														stroke-linecap="round"
														stroke-linejoin="round"
														stroke-width="3"
														d="M5 13l4 4L19 7"
													/>
												</svg>
												Saved!
											{:else}
												<svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
													<path
														stroke-linecap="round"
														stroke-linejoin="round"
														stroke-width="2.5"
														d="M5 13l4 4L19 7"
													/>
												</svg>
												Save Settings
											{/if}
										</button>
									{/if}
								</div>

								<ChatPanel
									messages={chatMessages}
									playerId={currentPlayerId}
									onSend={sendChatMessage}
									title="Lobby Chat"
									emptyMessage="Chat with the lobby before the game starts."
								/>
							</div>
						{/if}
					</aside>
				</div>
			</div>
		</div>
	{/if}
</main>
