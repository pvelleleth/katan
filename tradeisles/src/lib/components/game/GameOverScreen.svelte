<script lang="ts">
	import { goto } from '$app/navigation';

	export let gameState: any;
	export let players: any[]; // lobby players (has colors)
	export let playerId: string;

	$: winnerPlayerId = gameState.winner_player_id as string | null;
	$: playerOrder = gameState.player_order as string[];

	// Merge game-state player data with lobby colors
	$: rankedPlayers = [...playerOrder]
		.map((id: string) => {
			const gPlayer = gameState.players.find((p: any) => p.id === id);
			const lPlayer = players.find((p: any) => p.id === id);
			return { ...gPlayer, color: lPlayer?.color || 'wood' };
		})
		.sort((a: any, b: any) => b.victory_points - a.victory_points);

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

	const colorBorder: Record<string, string> = {
		brick: 'border-brick',
		ocean: 'border-ocean',
		wheat: 'border-wheat',
		forest: 'border-forest',
		purple: 'border-purple',
		wood: 'border-wood'
	};
</script>

<!-- Full-screen overlay -->
<div
	class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-md"
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
		class="animate-in zoom-in-95 fade-in relative mx-4 flex w-full max-w-lg flex-col items-center gap-8 rounded-3xl border-2 border-white/20 bg-white/95 p-8 shadow-2xl duration-500"
	>
		<!-- Crown icon -->
		<div class="flex flex-col items-center gap-3">
			<div
				class="flex h-20 w-20 items-center justify-center rounded-full bg-amber-400 shadow-xl ring-4 shadow-amber-400/40 ring-amber-200"
			>
				<svg class="h-10 w-10 text-amber-900" fill="currentColor" viewBox="0 0 24 24">
					<path
						d="M2 19l2-9 4.5 4L12 5l3.5 9L20 10l2 9H2zm2.17-2h15.66l-1.25-5.63L15 15l-3-7.5L9 15l-3.58-3.63L4.17 17z"
					/>
				</svg>
			</div>

			{#if iAmWinner}
				<h1 class="text-4xl font-black tracking-tight text-amber-600">🎉 You Won!</h1>
				<p class="text-center text-lg font-semibold text-wood-dark/70">
					Congratulations, you settled the most land!
				</p>
			{:else}
				<h1 class="text-4xl font-black tracking-tight text-wood-dark">Game Over</h1>
				<p class="text-center text-lg font-semibold text-wood-dark/70">
					<span class={colorText[winner?.color] ?? 'text-wood'}>{winner?.name}</span> wins with
					<span class="font-black text-amber-600">{winner?.victory_points} VP</span>!
				</p>
			{/if}
		</div>

		<!-- Final standings -->
		<div class="w-full">
			<h2 class="mb-3 text-center text-xs font-bold tracking-widest text-wood-light/70 uppercase">
				Final Standings
			</h2>
			<div class="flex flex-col gap-2">
				{#each rankedPlayers as player, rank}
					{@const isWinner = player.id === winnerPlayerId}
					{@const isMe = player.id === playerId}
					<div
						class="flex items-center gap-3 rounded-2xl border-2 px-4 py-3 transition-all {isWinner
							? 'border-amber-300 bg-amber-50 shadow-md'
							: 'border-wood/10 bg-white/60'}"
					>
						<!-- Rank badge -->
						<div
							class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-sm font-black
							{rank === 0
								? 'bg-amber-400 text-amber-900'
								: rank === 1
									? 'bg-slate-300 text-slate-700'
									: rank === 2
										? 'bg-amber-700/60 text-amber-100'
										: 'bg-wood/10 text-wood-dark'}"
						>
							{rank + 1}
						</div>

						<!-- Color dot -->
						<div
							class="h-8 w-8 shrink-0 rounded-full border-2 border-white shadow-sm {colorBg[
								player.color
							] ?? 'bg-wood'} flex items-center justify-center text-sm font-bold text-white"
						>
							{player.name.charAt(0).toUpperCase()}
						</div>

						<!-- Name -->
						<div class="flex-1 truncate font-bold text-wood-dark">
							{player.name}
							{#if isMe}
								<span class="ml-1 text-xs font-normal text-wood-light">(You)</span>
							{/if}
							{#if isWinner}
								<span class="ml-1">👑</span>
							{/if}
						</div>

						<!-- VP -->
						<div
							class="flex items-center gap-1 font-black {isWinner
								? 'text-amber-600'
								: 'text-wood-dark/60'}"
						>
							<span class="text-lg">{player.victory_points}</span>
							<svg class="h-4 w-4" fill="currentColor" viewBox="0 0 24 24">
								<path
									d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"
								/>
							</svg>
						</div>
					</div>
				{/each}
			</div>
		</div>

		<!-- CTA -->
		<button
			on:click={() => goto('/game')}
			class="flex w-full items-center justify-center gap-2 rounded-2xl bg-ocean px-6 py-3.5 text-lg font-bold text-white shadow-xl shadow-ocean/20 transition-all hover:scale-105 hover:bg-ocean/90 active:scale-95"
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
