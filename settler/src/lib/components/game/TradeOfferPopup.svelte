<script lang="ts">
	import { resourceKeys, resourceLabels, type ResourceKey } from './trade';

	export let gameState: any;
	export let playerId: string;
	export let players: any[];
	export let onAccept: () => void;
	export let onReject: () => void;
	export let onCancel: () => void;
	export let onFinalize: (partnerPlayerId: string) => void;

	const colorClasses: Record<string, string> = {
		brick: 'bg-brick text-white',
		ocean: 'bg-ocean text-white',
		wheat: 'bg-wheat text-wood-dark',
		forest: 'bg-forest text-white',
		purple: 'bg-purple text-white',
		wood: 'bg-wood text-white'
	};

	const resourceColors: Record<ResourceKey, string> = {
		wood: 'bg-forest text-white',
		brick: 'bg-brick text-white',
		sheep: 'bg-[#90EE90] text-wood-dark',
		wheat: 'bg-[#FBC02D] text-wood-dark',
		ore: 'bg-[#708090] text-white'
	};

	const resourceIcons: Record<ResourceKey, string> = {
		wood: '<path d="M12 2L4 10h3v4H4l8 8 8-8h-3v-4h3z" />',
		brick: '<path d="M2 4h20v4H2zm0 6h9v4H2zm11 0h9v4h-9zm-11 6h20v4H2z" />',
		sheep: '<path d="M18.5 8c-1.2 0-2.2.8-2.4 1.9-.5-.3-1.1-.4-1.6-.4-1.8 0-3.3 1.3-3.6 3-.4-.3-.9-.5-1.4-.5-1.9 0-3.5 1.6-3.5 3.5 0 .3 0 .6.1.8-.8.4-1.4 1.2-1.4 2.2 0 1.4 1.1 2.5 2.5 2.5h11.5c1.9 0 3.5-1.6 3.5-3.5 0-1.6-1.1-2.9-2.6-3.3.1-.4.1-.8.1-1.2 0-2.8-2.2-5-5-5z" />',
		wheat: '<path d="M12 2C7 2 3 6 3 11c0 2.2.8 4.2 2.1 5.7L2 22l2 1 3.3-3.3C8.8 20.6 10.3 21 12 21c5 0 9-4 9-9s-4-9-9-9zm0 17c-4.4 0-8-3.6-8-8s3.6-8 8-8 8 3.6 8 8-3.6 8-8 8z" /><path d="M12 5v14M8 8l4 4M16 8l-4 4M8 14l4-4M16 14l-4-4" stroke="currentColor" stroke-width="2" />',
		ore: '<path d="M12 2L2 22h20L12 2zm0 6l5 10H7l5-10z" />'
	};

	$: pendingTrade = gameState?.turn?.pending_player_trade ?? null;
	$: myPlayer = gameState?.players?.find((player: any) => player.id === playerId);
	$: hand = myPlayer?.hand ?? {};
	$: isProposer = pendingTrade?.player_id === playerId;
	$: responses = pendingTrade?.responses ?? [];
	$: acceptedIds = pendingTrade?.accepted_player_ids ?? [];
	$: rejectedIds = pendingTrade?.rejected_player_ids ?? [];
	$: viewerResponse = pendingTrade?.viewer_response ?? null;
	$: canRespond = !!pendingTrade?.can_respond && !isProposer;
	$: canFinalize = !!pendingTrade?.can_finalize && isProposer;
	$: canCoverRequested = resourceKeys.every(
		(resource) => (hand[resource] ?? 0) >= (pendingTrade?.requested?.[resource] ?? 0)
	);

	function getPlayer(playerIdToFind: string) {
		return (
			players.find((player) => player.id === playerIdToFind) ??
			gameState.players.find((player: any) => player.id === playerIdToFind)
		);
	}

	function describePile(pile: Record<ResourceKey, number>) {
		return resourceKeys
			.filter((resource) => (pile?.[resource] ?? 0) > 0)
			.map((resource) => `${pile[resource]} ${resourceLabels[resource]}`);
	}
</script>

{#if pendingTrade}
	<div
		class="absolute top-4 right-4 z-20 w-full max-w-[280px] rounded-2xl border border-wood/10 bg-white/95 p-3 shadow-xl backdrop-blur-md"
	>
		<div class="flex flex-col gap-2.5">
			<div class="flex items-center justify-between">
				<div class="flex items-center gap-2">
					<div
						class="h-1.5 w-1.5 animate-pulse rounded-full {isProposer ? 'bg-ocean' : 'bg-forest'}"
					></div>
					<div class="text-[9px] font-black tracking-widest text-wood-light uppercase">
						{isProposer ? 'Your Offer' : 'Trade Offer'}
					</div>
				</div>
				{#if !isProposer}
					<div
						class="rounded-full px-2 py-0.5 text-[9px] font-black tracking-wider uppercase {colorClasses[
							getPlayer(pendingTrade.player_id)?.color ?? 'wood'
						]}"
					>
						{getPlayer(pendingTrade.player_id)?.name ?? 'Player'}
					</div>
				{/if}
			</div>

			<div class="flex flex-col gap-1.5 rounded-xl bg-parchment/40 p-2">
				<!-- TOP ROW: GET / WANT -->
				<div class="flex items-center gap-2">
					<div class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-forest/10 text-forest">
						<svg
							xmlns="http://www.w3.org/2000/svg"
							width="16"
							height="16"
							viewBox="0 0 24 24"
							fill="none"
							stroke="currentColor"
							stroke-width="4"
							stroke-linecap="round"
							stroke-linejoin="round"
						>
							<path d="M12 5v14M5 12l7 7 7-7" />
						</svg>
					</div>
					<div class="flex flex-wrap gap-1">
						{#each resourceKeys.filter((r) => (pendingTrade[isProposer ? 'requested' : 'offered'][r] ?? 0) > 0) as r}
							{@const count = pendingTrade[isProposer ? 'requested' : 'offered'][r]}
							<div class="relative h-10" style="width: {28 + (count - 1) * 6}px">
								{#each Array(count) as _, i}
									<div
										class="absolute top-0 flex h-10 w-7 flex-col items-center justify-center rounded-md border border-white/40 p-0.5 shadow-sm {resourceColors[
											r
										]}"
										style="left: {i * 6}px; z-index: {i};"
									>
										<svg viewBox="0 0 24 24" class="h-3.5 w-3.5" fill="currentColor">
											{@html resourceIcons[r]}
										</svg>
									</div>
								{/each}
							</div>
						{/each}
					</div>
				</div>

				<!-- BOTTOM ROW: GIVE -->
				<div class="flex items-center gap-2">
					<div class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-red-500/10 text-red-500">
						<svg
							xmlns="http://www.w3.org/2000/svg"
							width="16"
							height="16"
							viewBox="0 0 24 24"
							fill="none"
							stroke="currentColor"
							stroke-width="4"
							stroke-linecap="round"
							stroke-linejoin="round"
						>
							<path d="M12 19V5M5 12l7-7 7 7" />
						</svg>
					</div>
					<div class="flex flex-wrap gap-1">
						{#each resourceKeys.filter((r) => (pendingTrade[isProposer ? 'offered' : 'requested'][r] ?? 0) > 0) as r}
							{@const count = pendingTrade[isProposer ? 'offered' : 'requested'][r]}
							<div class="relative h-10" style="width: {28 + (count - 1) * 6}px">
								{#each Array(count) as _, i}
									<div
										class="absolute top-0 flex h-10 w-7 flex-col items-center justify-center rounded-md border border-white/40 p-0.5 shadow-sm {resourceColors[
											r
										]}"
										style="left: {i * 6}px; z-index: {i};"
									>
										<svg viewBox="0 0 24 24" class="h-3.5 w-3.5" fill="currentColor">
											{@html resourceIcons[r]}
										</svg>
									</div>
								{/each}
							</div>
						{/each}
					</div>
				</div>
			</div>

			{#if isProposer}
				{#if responses.length > 0}
					<div class="flex flex-col gap-1 border-t border-wood/5 pt-2">
						{#each responses as response}
							{@const responder = getPlayer(response.player_id)}
							<div class="flex items-center justify-between rounded-lg bg-white/50 px-2 py-1">
								<div class="flex items-center gap-1.5">
									<div
										class="h-1.5 w-1.5 rounded-full {colorClasses[responder?.color ?? 'wood']
											.split(' ')[0]
											.replace('bg-', 'bg-')}"
									></div>
									<div class="text-[10px] font-bold text-wood-dark">
										{responder?.name ?? 'Player'}
									</div>
								</div>
								{#if response.status === 'Accepted'}
									<button
										on:click={() => onFinalize(response.player_id)}
										disabled={!canFinalize}
										class="rounded-md bg-ocean px-2 py-0.5 text-[9px] font-black text-white shadow-sm transition-transform hover:scale-105 active:scale-95 disabled:opacity-50"
									>
										Accept
									</button>
								{:else}
									<span class="text-[9px] font-bold text-brick/60 uppercase">No</span>
								{/if}
							</div>
						{/each}
					</div>
				{/if}

				<div class="flex justify-end">
					<button
						on:click={onCancel}
						class="text-[9px] font-black tracking-wider text-brick/60 uppercase hover:text-brick"
					>
						Cancel Trade
					</button>
				</div>
			{:else}
				<div class="flex items-center justify-between gap-2 pt-1">
					{#if viewerResponse === 'Accepted'}
						<div class="text-[10px] font-bold text-forest">Accepted...</div>
						<button
							on:click={onReject}
							class="text-[9px] font-black text-brick/60 uppercase hover:text-brick"
						>
							Withdraw
						</button>
					{:else if viewerResponse === 'Rejected'}
						<div class="text-[10px] font-bold text-wood-light">Declined</div>
						<button
							on:click={onAccept}
							disabled={!canRespond || !canCoverRequested}
							class="text-[9px] font-black text-ocean uppercase hover:text-ocean-dark disabled:opacity-50"
						>
							Undo
						</button>
					{:else}
						<div class="flex-1">
							{#if !canCoverRequested}
								<span class="text-[9px] font-bold text-brick">Missing cards</span>
							{/if}
						</div>
						<div class="flex gap-1.5">
							<button
								on:click={onReject}
								disabled={!canRespond}
								class="rounded-lg border border-brick/20 px-2.5 py-1 text-[10px] font-black text-brick hover:bg-brick/5 disabled:opacity-50"
							>
								Decline
							</button>
							<button
								on:click={onAccept}
								disabled={!canRespond || !canCoverRequested}
								class="rounded-lg bg-forest px-3 py-1 text-[10px] font-black text-white shadow-sm hover:bg-forest-dark disabled:opacity-50"
							>
								Accept
							</button>
						</div>
					{/if}
				</div>
			{/if}
		</div>
	</div>
{/if}
