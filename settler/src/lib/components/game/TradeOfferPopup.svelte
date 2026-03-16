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
		class="absolute top-4 right-4 z-20 w-full max-w-sm rounded-3xl border-2 border-wood/10 bg-white/95 p-5 shadow-2xl backdrop-blur-md"
	>
		<div class="flex flex-col gap-4">
			<div class="flex items-start justify-between gap-3">
				<div>
					<div class="text-xs font-black tracking-[0.2em] text-ocean uppercase">Trade Offer</div>
					<h3 class="text-lg font-black text-wood-dark">
						{getPlayer(pendingTrade.player_id)?.name ?? 'Player'} wants to trade
					</h3>
				</div>
				<div
					class="rounded-full px-2 py-1 text-[10px] font-black tracking-wider uppercase {colorClasses[
						getPlayer(pendingTrade.player_id)?.color ?? 'wood'
					]}"
				>
					Offer
				</div>
			</div>

			<div class="grid gap-3 sm:grid-cols-2">
				<div class="rounded-2xl bg-parchment/70 p-3">
					<div class="mb-2 text-[11px] font-black tracking-wider text-wood-light uppercase">
						Giving
					</div>
					<div class="flex flex-wrap gap-2">
						{#each describePile(pendingTrade.offered) as item}
							<span class="rounded-full bg-wood/10 px-2.5 py-1 text-xs font-bold text-wood-dark"
								>{item}</span
							>
						{/each}
					</div>
				</div>

				<div class="rounded-2xl bg-parchment/70 p-3">
					<div class="mb-2 text-[11px] font-black tracking-wider text-wood-light uppercase">
						Requesting
					</div>
					<div class="flex flex-wrap gap-2">
						{#each describePile(pendingTrade.requested) as item}
							<span class="rounded-full bg-ocean/10 px-2.5 py-1 text-xs font-bold text-ocean"
								>{item}</span
							>
						{/each}
					</div>
				</div>
			</div>

			{#if isProposer}
				<div class="rounded-2xl border border-wood/10 bg-parchment/60 p-3">
					<div class="mb-2 text-[11px] font-black tracking-wider text-wood-light uppercase">
						Responses
					</div>
					<div class="flex flex-col gap-2">
						{#if responses.length === 0}
							<div class="text-sm font-semibold text-wood-light">Waiting for responses...</div>
						{/if}

						{#each responses as response}
							{@const responder = getPlayer(response.player_id)}
							<div class="flex items-center justify-between rounded-2xl bg-white/80 px-3 py-2">
								<div class="font-bold text-wood-dark">{responder?.name ?? response.player_id}</div>
								<div class="flex items-center gap-2">
									<span
										class="rounded-full px-2.5 py-1 text-[10px] font-black tracking-wider uppercase {response.status ===
										'Accepted'
											? 'bg-forest/15 text-forest'
											: 'bg-brick/15 text-brick'}"
									>
										{response.status}
									</span>
									{#if response.status === 'Accepted'}
										<button
											on:click={() => onFinalize(response.player_id)}
											disabled={!canFinalize}
											class="rounded-xl bg-ocean px-3 py-1.5 text-xs font-black text-white disabled:cursor-not-allowed disabled:opacity-50"
										>
											Choose
										</button>
									{/if}
								</div>
							</div>
						{/each}
					</div>
				</div>

				<div class="flex justify-end">
					<button
						on:click={onCancel}
						class="rounded-2xl border border-brick/20 bg-brick/10 px-4 py-2 text-sm font-black text-brick transition-colors hover:bg-brick/15"
					>
						Cancel Trade
					</button>
				</div>
			{:else}
				<div
					class="rounded-2xl border border-wood/10 bg-parchment/60 p-3 text-sm font-semibold text-wood-dark"
				>
					{#if viewerResponse === 'Accepted'}
						You accepted this trade. Waiting for the proposer to choose a trading partner.
					{:else if viewerResponse === 'Rejected'}
						You passed on this trade.
					{:else}
						Accept if you can give {describePile(pendingTrade.requested).join(', ')}.
					{/if}
				</div>

				<div class="flex items-center justify-end gap-2">
					<button
						on:click={onReject}
						disabled={!canRespond}
						class="rounded-2xl border border-brick/20 bg-brick/10 px-4 py-2 text-sm font-black text-brick disabled:cursor-not-allowed disabled:opacity-50"
					>
						Reject
					</button>
					<button
						on:click={onAccept}
						disabled={!canRespond || !canCoverRequested}
						class="rounded-2xl bg-forest px-4 py-2 text-sm font-black text-white shadow-sm disabled:cursor-not-allowed disabled:opacity-50"
					>
						Accept
					</button>
				</div>
				{#if !canCoverRequested}
					<div class="text-right text-xs font-bold text-brick">
						You do not have the requested cards right now.
					</div>
				{/if}
			{/if}

			{#if acceptedIds.length > 0 || rejectedIds.length > 0}
				<div class="border-t border-wood/10 pt-3 text-xs font-semibold text-wood-light">
					{acceptedIds.length} accepted, {rejectedIds.length} rejected
				</div>
			{/if}
		</div>
	</div>
{/if}
