<script lang="ts">
	import {
		createEmptyResourcePile,
		getBankTradeRates,
		hasAnyResources,
		resourceKeys,
		resourceLabels,
		type ResourceKey,
		type ResourcePile
	} from './trade';

	export let open = false;
	export let mode: 'player' | 'bank' = 'player';
	export let gameState: any;
	export let playerId: string;
	export let onClose: () => void;
	export let onModeChange: (mode: 'player' | 'bank') => void;
	export let onSubmitPlayerTrade: (offered: ResourcePile, requested: ResourcePile) => void;
	export let onSubmitBankTrade: (
		offeredResource: ResourceKey,
		requestedResource: ResourceKey
	) => void;
	export let offered = createEmptyResourcePile();
	export let requested = createEmptyResourcePile();

	let bankOfferedResource: ResourceKey = 'wood';
	let bankRequestedResource: ResourceKey = 'brick';

	$: myPlayer = gameState?.players?.find((player: any) => player.id === playerId);
	$: hand = myPlayer?.hand ?? createEmptyResourcePile();
	$: pendingTrade = gameState?.turn?.pending_player_trade ?? null;
	$: bankTradeRates = getBankTradeRates(gameState, playerId);
	$: bankRate = bankTradeRates[bankOfferedResource];
	$: harborAdvantageResources = resourceKeys.filter((resource) => bankTradeRates[resource] < 4);
	$: hasHarborAdvantage = harborAdvantageResources.length > 0;

	const resourceColors: Record<ResourceKey, string> = {
		wood: 'bg-forest text-white',
		brick: 'bg-brick text-white',
		sheep: 'bg-[#90EE90] text-wood-dark',
		wheat: 'bg-[#FBC02D] text-wood-dark',
		ore: 'bg-[#708090] text-white'
	};

	$: canSubmitPlayerTrade =
		hasAnyResources(offered) &&
		hasAnyResources(requested) &&
		!pendingTrade &&
		resourceKeys.every((resource) => offered[resource] <= (hand[resource] ?? 0));
	$: canSubmitBankTrade =
		!pendingTrade &&
		bankOfferedResource !== bankRequestedResource &&
		(hand[bankOfferedResource] ?? 0) >= bankRate;

	const resourceIcons: Record<ResourceKey, string> = {
		wood: '<path d="M12 2L4 10h3v4H4l8 8 8-8h-3v-4h3z" />',
		brick: '<path d="M2 4h20v4H2zm0 6h9v4H2zm11 0h9v4h-9zm-11 6h20v4H2z" />',
		sheep: '<path d="M18.5 8c-1.2 0-2.2.8-2.4 1.9-.5-.3-1.1-.4-1.6-.4-1.8 0-3.3 1.3-3.6 3-.4-.3-.9-.5-1.4-.5-1.9 0-3.5 1.6-3.5 3.5 0 .3 0 .6.1.8-.8.4-1.4 1.2-1.4 2.2 0 1.4 1.1 2.5 2.5 2.5h11.5c1.9 0 3.5-1.6 3.5-3.5 0-1.6-1.1-2.9-2.6-3.3.1-.4.1-.8.1-1.2 0-2.8-2.2-5-5-5z" />',
		wheat: '<path d="M12 2C7 2 3 6 3 11c0 2.2.8 4.2 2.1 5.7L2 22l2 1 3.3-3.3C8.8 20.6 10.3 21 12 21c5 0 9-4 9-9s-4-9-9-9zm0 17c-4.4 0-8-3.6-8-8s3.6-8 8-8 8 3.6 8 8-3.6 8-8 8z" /><path d="M12 5v14M8 8l4 4M16 8l-4 4M8 14l4-4M16 14l-4-4" stroke="currentColor" stroke-width="2" />',
		ore: '<path d="M12 2L2 22h20L12 2zm0 6l5 10H7l5-10z" />'
	};

	$: if (mode === 'bank') {
		// In bank mode, sync bankOfferedResource with what's in 'offered' pile
		const offeredRes = resourceKeys.find((r) => offered[r] > 0);
		if (offeredRes) {
			bankOfferedResource = offeredRes;
		}
	}

	$: if (!open) {
		resetSelections();
	}

	function resetSelections() {
		offered = createEmptyResourcePile();
		requested = createEmptyResourcePile();
		bankOfferedResource = 'wood';
		bankRequestedResource = 'brick';
	}

	function updatePile(pile: 'offered' | 'requested', resource: ResourceKey, delta: number) {
		if (pile === 'offered') {
			const next = Math.max(0, Math.min(hand[resource] ?? 0, offered[resource] + delta));
			offered = { ...offered, [resource]: next };
			return;
		}

		const next = Math.max(0, Math.min(10, requested[resource] + delta));
		requested = { ...requested, [resource]: next };
	}

	function submitPlayerTrade() {
		if (!canSubmitPlayerTrade) return;
		onSubmitPlayerTrade(offered, requested);
		resetSelections();
	}

	function submitBankTrade() {
		if (!canSubmitBankTrade) return;
		onSubmitBankTrade(bankOfferedResource, bankRequestedResource);
		resetSelections();
	}
</script>

{#if open}
	<div
		class="absolute bottom-28 left-4 z-20 w-full max-w-lg rounded-2xl border border-wood/10 bg-white/95 p-3 shadow-xl backdrop-blur-md"
	>
		<div class="flex flex-col gap-3">
			<div class="flex items-center justify-between px-1">
				<div class="flex items-center gap-3">
					<div class="flex gap-1 rounded-lg bg-wood/5 p-0.5">
						<button
							on:click={() => onModeChange('player')}
							class="rounded-md px-2.5 py-1 text-[10px] font-black transition-all {mode ===
							'player'
								? 'bg-white text-ocean shadow-sm'
								: 'text-wood-light hover:text-wood-dark'}"
						>
							Player
						</button>
						<button
							on:click={() => onModeChange('bank')}
							class="rounded-md px-2.5 py-1 text-[10px] font-black transition-all {mode ===
							'bank'
								? 'bg-white text-ocean shadow-sm'
								: 'text-wood-light hover:text-wood-dark'}"
						>
							Bank
						</button>
					</div>
					<span class="text-[10px] font-black tracking-widest text-wood-light uppercase">
						{mode === 'player' ? 'Propose Trade' : 'Bank Exchange'}
					</span>
				</div>
				<button
					on:click={onClose}
					class="text-[10px] font-black tracking-widest text-wood-light uppercase hover:text-brick"
				>
					Cancel
				</button>
			</div>

			<div class="flex flex-col gap-2 rounded-xl bg-parchment/40 p-3">
				<!-- TOP ROW: WANT -->
				<div class="flex items-center justify-between gap-3">
					<div class="flex items-center gap-3">
						<div class="flex h-9 w-9 items-center justify-center rounded-full bg-forest/10 text-forest">
							<svg
								xmlns="http://www.w3.org/2000/svg"
								width="20"
								height="20"
								viewBox="0 0 24 24"
								fill="none"
								stroke="currentColor"
								stroke-width="3.5"
								stroke-linecap="round"
								stroke-linejoin="round"
							>
								<path d="M12 5v14M5 12l7 7 7-7" />
							</svg>
						</div>
						<div class="flex flex-col items-start">
							<span class="text-[9px] font-black text-wood-light uppercase">Want</span>
							<div class="flex flex-wrap gap-1.5">
								{#each resourceKeys.filter((r) => requested[r] > 0) as r}
									<div class="relative h-12" style="width: {32 + (requested[r] - 1) * 8}px">
										{#each Array(requested[r]) as _, i}
											<button
												on:click={() => updatePile('requested', r, -1)}
												class="group absolute top-0 flex h-12 w-8 flex-col items-center justify-center rounded-md border border-white/40 p-1 shadow-sm transition-all hover:-translate-y-1 hover:scale-110 active:scale-95 {resourceColors[
													r
												]}"
												style="left: {i * 8}px; z-index: {i};"
											>
												<svg viewBox="0 0 24 24" class="h-4 w-4" fill="currentColor">
													{@html resourceIcons[r]}
												</svg>
												<div
													class="absolute -top-1 -right-1 hidden h-3 w-3 items-center justify-center rounded-full bg-brick text-[8px] font-black text-white group-hover:flex"
												>
													×
												</div>
											</button>
										{/each}
									</div>
								{/each}
								{#if !hasAnyResources(requested)}
									<span class="text-[10px] font-bold text-wood-light/50 italic"
										>Select cards to get</span
									>
								{/if}
							</div>
						</div>
					</div>
					<div class="flex gap-1">
						{#each resourceKeys as r}
							<button
								on:click={() => {
									if (mode === 'bank') {
										bankRequestedResource = r;
										requested = { ...createEmptyResourcePile(), [r]: 1 };
									} else {
										updatePile('requested', r, 1);
									}
								}}
								class="flex h-10 w-7 flex-col items-center justify-center rounded-md border transition-all hover:scale-105 {resourceColors[
									r
								]} {requested[r] > 0
									? 'ring-2 ring-forest ring-offset-1'
									: 'opacity-60 grayscale-[0.5] hover:opacity-100 hover:grayscale-0'}"
							>
								<svg viewBox="0 0 24 24" class="h-3.5 w-3.5" fill="currentColor">
									{@html resourceIcons[r]}
								</svg>
								<span class="mt-0.5 text-[7px] font-black uppercase"
									>{resourceLabels[r][0]}</span
								>
							</button>
						{/each}
					</div>
				</div>

				<!-- DIVIDER -->
				<div class="h-px w-full bg-wood/5"></div>

				<!-- BOTTOM ROW: GIVE -->
				<div class="flex items-center justify-between gap-3">
					<div class="flex items-center gap-3">
						<div class="flex h-9 w-9 items-center justify-center rounded-full bg-red-500/10 text-red-500">
							<svg
								xmlns="http://www.w3.org/2000/svg"
								width="20"
								height="20"
								viewBox="0 0 24 24"
								fill="none"
								stroke="currentColor"
								stroke-width="3.5"
								stroke-linecap="round"
								stroke-linejoin="round"
							>
								<path d="M12 19V5M5 12l7-7 7 7" />
							</svg>
						</div>
						<div class="flex flex-col items-start">
							<span class="text-[9px] font-black text-wood-light uppercase">Give</span>
							<div class="flex flex-wrap gap-1.5">
								{#each resourceKeys.filter((r) => offered[r] > 0) as r}
									<div class="relative h-12" style="width: {32 + (offered[r] - 1) * 8}px">
										{#each Array(offered[r]) as _, i}
											<button
												on:click={() => updatePile('offered', r, -1)}
												class="group absolute top-0 flex h-12 w-8 flex-col items-center justify-center rounded-md border border-white/40 p-1 shadow-sm transition-all hover:-translate-y-1 hover:scale-110 active:scale-95 {resourceColors[
													r
												]}"
												style="left: {i * 8}px; z-index: {i};"
											>
												<svg viewBox="0 0 24 24" class="h-4 w-4" fill="currentColor">
													{@html resourceIcons[r]}
												</svg>
												<div
													class="absolute -top-1 -right-1 hidden h-3 w-3 items-center justify-center rounded-full bg-brick text-[8px] font-black text-white group-hover:flex"
												>
													×
												</div>
											</button>
										{/each}
									</div>
								{/each}
								{#if !hasAnyResources(offered)}
									<span class="text-[10px] font-bold text-wood-light/50 italic"
										>Click cards below</span
									>
								{/if}
							</div>
						</div>
					</div>
				</div>
			</div>

			<div class="flex items-center justify-between pt-1">
				<div class="flex items-center gap-2">
					{#if mode === 'bank'}
						{@const canBank = canSubmitBankTrade}
						<div class="text-[10px] font-bold text-wood-light">
							{#if bankRate < 4}
								<span class="text-ocean">Harbor Rate {bankRate}:1</span>
							{:else}
								Standard 4:1
							{/if}
						</div>
					{/if}
				</div>
				<button
					on:click={mode === 'player' ? submitPlayerTrade : submitBankTrade}
					disabled={mode === 'player' ? !canSubmitPlayerTrade : !canSubmitBankTrade}
					class="rounded-xl px-6 py-2 text-xs font-black text-white shadow-md transition-all hover:scale-105 active:scale-95 disabled:opacity-50 {mode ===
					'player'
						? 'bg-ocean'
						: 'bg-forest'}"
				>
					{mode === 'player' ? 'Propose Trade' : 'Exchange with Bank'}
				</button>
			</div>
		</div>
	</div>
{/if}
