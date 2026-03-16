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

	let offered = createEmptyResourcePile();
	let requested = createEmptyResourcePile();
	let bankOfferedResource: ResourceKey = 'wood';
	let bankRequestedResource: ResourceKey = 'brick';

	$: myPlayer = gameState?.players?.find((player: any) => player.id === playerId);
	$: hand = myPlayer?.hand ?? createEmptyResourcePile();
	$: pendingTrade = gameState?.turn?.pending_player_trade ?? null;
	$: bankTradeRates = getBankTradeRates(gameState, playerId);
	$: bankRate = bankTradeRates[bankOfferedResource];
	$: harborAdvantageResources = resourceKeys.filter((resource) => bankTradeRates[resource] < 4);
	$: hasHarborAdvantage = harborAdvantageResources.length > 0;
	$: canSubmitPlayerTrade =
		hasAnyResources(offered) &&
		hasAnyResources(requested) &&
		!pendingTrade &&
		resourceKeys.every((resource) => offered[resource] <= (hand[resource] ?? 0));
	$: canSubmitBankTrade =
		!pendingTrade &&
		bankOfferedResource !== bankRequestedResource &&
		(hand[bankOfferedResource] ?? 0) >= bankRate;

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
		class="absolute right-4 bottom-28 left-4 z-20 mx-auto w-full max-w-5xl rounded-3xl border-2 border-wood/10 bg-white/95 p-5 shadow-2xl backdrop-blur-md"
	>
		<div class="flex flex-col gap-5">
			<div class="flex items-start justify-between gap-4">
				<div>
					<h3 class="text-xl font-black text-wood-dark">Trade</h3>
					<p class="text-sm font-semibold text-wood-light">
						Choose what you give and what you want back.
					</p>
				</div>
				<button
					on:click={onClose}
					class="rounded-full border border-wood/15 px-3 py-1 text-xs font-black tracking-wider text-wood-dark uppercase transition-colors hover:border-brick/30 hover:text-brick"
				>
					Close
				</button>
			</div>

			<div class="flex gap-2">
				<button
					on:click={() => onModeChange('player')}
					class="rounded-2xl px-4 py-2 text-sm font-black transition-colors {mode === 'player'
						? 'bg-ocean text-white'
						: 'bg-wood/10 text-wood-dark hover:bg-wood/15'}"
				>
					Player Trade
				</button>
				<button
					on:click={() => onModeChange('bank')}
					class="rounded-2xl px-4 py-2 text-sm font-black transition-colors {mode === 'bank'
						? 'bg-ocean text-white'
						: 'bg-wood/10 text-wood-dark hover:bg-wood/15'}"
				>
					Bank Trade
				</button>
			</div>

			{#if pendingTrade}
				<div
					class="rounded-2xl border border-brick/20 bg-brick/10 px-4 py-3 text-sm font-semibold text-brick"
				>
					Finish or cancel the current player trade before creating another one.
				</div>
			{/if}

			{#if hasHarborAdvantage}
				<div
					class="rounded-2xl border border-ocean/20 bg-ocean/10 px-4 py-3 text-sm font-semibold text-ocean"
				>
					Harbor advantage:
					{#each harborAdvantageResources as resource, index}
						<span class="font-black">{resourceLabels[resource]} {bankTradeRates[resource]}:1</span
						>{index < harborAdvantageResources.length - 1 ? ', ' : ''}
					{/each}
				</div>
			{/if}

			{#if mode === 'player'}
				<div class="grid gap-5 lg:grid-cols-2">
					<div class="rounded-2xl border border-wood/10 bg-parchment/70 p-4">
						<div class="mb-3 flex items-center justify-between">
							<h4 class="text-sm font-black tracking-wider text-wood-dark uppercase">You Give</h4>
							<span class="text-xs font-bold text-wood-light">From your hand</span>
						</div>
						<div class="flex flex-col gap-2">
							{#each resourceKeys as resource}
								<div class="flex items-center justify-between rounded-2xl bg-white/80 px-3 py-2">
									<div>
										<div class="font-bold text-wood-dark">{resourceLabels[resource]}</div>
										<div class="text-xs font-semibold text-wood-light">
											Have {hand[resource] ?? 0}
										</div>
									</div>
									<div class="flex items-center gap-2">
										<button
											on:click={() => updatePile('offered', resource, -1)}
											disabled={offered[resource] === 0}
											class="flex h-8 w-8 items-center justify-center rounded-full bg-brick text-white disabled:cursor-not-allowed disabled:opacity-40"
										>
											-
										</button>
										<div class="w-8 text-center font-black text-wood-dark">{offered[resource]}</div>
										<button
											on:click={() => updatePile('offered', resource, 1)}
											disabled={offered[resource] >= (hand[resource] ?? 0)}
											class="flex h-8 w-8 items-center justify-center rounded-full bg-forest text-white disabled:cursor-not-allowed disabled:opacity-40"
										>
											+
										</button>
									</div>
								</div>
							{/each}
						</div>
					</div>

					<div class="rounded-2xl border border-wood/10 bg-parchment/70 p-4">
						<div class="mb-3 flex items-center justify-between">
							<h4 class="text-sm font-black tracking-wider text-wood-dark uppercase">You Want</h4>
							<span class="text-xs font-bold text-wood-light">Other players can accept</span>
						</div>
						<div class="flex flex-col gap-2">
							{#each resourceKeys as resource}
								<div class="flex items-center justify-between rounded-2xl bg-white/80 px-3 py-2">
									<div class="font-bold text-wood-dark">{resourceLabels[resource]}</div>
									<div class="flex items-center gap-2">
										<button
											on:click={() => updatePile('requested', resource, -1)}
											disabled={requested[resource] === 0}
											class="flex h-8 w-8 items-center justify-center rounded-full bg-brick text-white disabled:cursor-not-allowed disabled:opacity-40"
										>
											-
										</button>
										<div class="w-8 text-center font-black text-wood-dark">
											{requested[resource]}
										</div>
										<button
											on:click={() => updatePile('requested', resource, 1)}
											class="flex h-8 w-8 items-center justify-center rounded-full bg-forest text-white"
										>
											+
										</button>
									</div>
								</div>
							{/each}
						</div>
					</div>
				</div>

				<div class="flex justify-end">
					<button
						on:click={submitPlayerTrade}
						disabled={!canSubmitPlayerTrade}
						class="rounded-2xl bg-ocean px-6 py-3 font-black text-white shadow-md transition-transform hover:scale-105 active:scale-95 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:scale-100"
					>
						Propose Trade
					</button>
				</div>
			{:else}
				<div class="grid gap-5 lg:grid-cols-[1fr_1fr_auto]">
					<div class="rounded-2xl border border-wood/10 bg-parchment/70 p-4">
						<h4 class="mb-3 text-sm font-black tracking-wider text-wood-dark uppercase">
							Give To Bank
						</h4>
						<div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
							{#each resourceKeys as resource}
								<button
									on:click={() => (bankOfferedResource = resource)}
									class="rounded-2xl border px-3 py-3 text-left transition-colors {bankOfferedResource ===
									resource
										? 'border-ocean bg-ocean/10'
										: 'border-wood/10 bg-white/80 hover:bg-white'}"
								>
									<div class="font-bold text-wood-dark">{resourceLabels[resource]}</div>
									<div class="text-xs font-semibold text-wood-light">
										Rate {bankTradeRates[resource]}:1, have {hand[resource] ?? 0}
									</div>
								</button>
							{/each}
						</div>
					</div>

					<div class="rounded-2xl border border-wood/10 bg-parchment/70 p-4">
						<h4 class="mb-3 text-sm font-black tracking-wider text-wood-dark uppercase">
							Get From Bank
						</h4>
						<div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
							{#each resourceKeys as resource}
								<button
									on:click={() => (bankRequestedResource = resource)}
									class="rounded-2xl border px-3 py-3 text-left transition-colors {bankRequestedResource ===
									resource
										? 'border-forest bg-forest/10'
										: 'border-wood/10 bg-white/80 hover:bg-white'}"
								>
									<div class="font-bold text-wood-dark">{resourceLabels[resource]}</div>
								</button>
							{/each}
						</div>
					</div>

					<div
						class="flex flex-col justify-between rounded-2xl border border-wood/10 bg-white/80 p-4"
					>
						<div>
							<div class="text-sm font-black tracking-wider text-wood-dark uppercase">Summary</div>
							<p class="mt-2 text-sm font-semibold text-wood-light">
								Trade {bankRate}
								{resourceLabels[bankOfferedResource]} for 1
								{resourceLabels[bankRequestedResource]}.
							</p>
							{#if bankRate < 4}
								<p class="mt-2 text-xs font-black tracking-wider text-ocean uppercase">
									Harbor rate applied
								</p>
							{/if}
						</div>
						<button
							on:click={submitBankTrade}
							disabled={!canSubmitBankTrade}
							class="mt-4 rounded-2xl bg-wood px-5 py-3 font-black text-white shadow-md transition-transform hover:scale-105 active:scale-95 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:scale-100"
						>
							Trade With Bank
						</button>
					</div>
				</div>
			{/if}
		</div>
	</div>
{/if}
