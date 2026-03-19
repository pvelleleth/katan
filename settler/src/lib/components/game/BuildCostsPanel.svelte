<script lang="ts">
	import { resourceKeys, resourceLabels, type ResourceKey, type ResourcePile } from './trade';

	const BUILD_COSTS: { name: string; cost: ResourcePile }[] = [
		{ name: 'Road', cost: { wood: 1, brick: 1, sheep: 0, wheat: 0, ore: 0 } },
		{
			name: 'Settlement',
			cost: { wood: 1, brick: 1, sheep: 1, wheat: 1, ore: 0 }
		},
		{ name: 'City', cost: { wood: 0, brick: 0, sheep: 0, wheat: 2, ore: 3 } },
		{
			name: 'Development Card',
			cost: { wood: 0, brick: 0, sheep: 1, wheat: 1, ore: 1 }
		}
	];

	const resourceColors: Record<ResourceKey, string> = {
		wood: 'bg-forest text-white',
		brick: 'bg-brick text-white',
		sheep: 'bg-[#90EE90] text-wood-dark',
		wheat: 'bg-[#FBC02D] text-wood-dark',
		ore: 'bg-[#708090] text-white'
	};

	export let open = false;
	export let onClose: (() => void) | undefined;

	function handleBackdropClick() {
		if (onClose) {
			onClose();
		}
	}
</script>

{#if open}
	<!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
	<div class="absolute inset-0 z-10" role="presentation" on:click={handleBackdropClick}></div>
	<div
		class="absolute top-14 right-4 z-20 flex flex-col gap-3 rounded-2xl border-2 border-wood/10 bg-white/95 p-4 shadow-xl backdrop-blur-md"
	>
		<h3 class="text-xs font-bold tracking-wider text-wood-light uppercase">Build costs</h3>
		<ul class="flex flex-col gap-2">
			{#each BUILD_COSTS as item}
				<li class="flex items-center gap-2">
					<span class="min-w-[7rem] text-sm font-bold text-wood-dark">{item.name}</span>
					<div class="flex flex-wrap gap-1">
						{#each resourceKeys as res}
							{#if (item.cost[res] || 0) > 0}
								<span
									class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-bold {resourceColors[
										res
									]}"
								>
									{item.cost[res]}
									{resourceLabels[res]}
								</span>
							{/if}
						{/each}
					</div>
				</li>
			{/each}
		</ul>
	</div>
{/if}
