<script lang="ts">
	import { tick } from 'svelte';

	type ChatMessage = {
		playerId: string;
		playerName: string;
		message: string;
		createdAt: string;
	};

	export let messages: ChatMessage[] = [];
	export let playerId = '';
	export let disabled = false;
	export let title = 'Chat';
	export let emptyMessage = 'No messages yet.';
	export let inputPlaceholder = 'Send a message';
	export let onSend: (message: string) => void;
	export let collapsible = true;

	let draft = '';
	let collapsed = false;
	let container: HTMLDivElement;
	let previousMessageCount = 0;

	function isNearBottom() {
		if (!container) return true;
		const distanceFromBottom =
			container.scrollHeight - container.scrollTop - container.clientHeight;
		return distanceFromBottom < 80;
	}

	async function scrollToBottom() {
		await tick();
		container?.scrollTo({
			top: container.scrollHeight,
			behavior: 'smooth'
		});
	}

	function submit() {
		const message = draft.trim();
		if (!message || disabled) return;
		onSend(message);
		draft = '';
	}

	function handleKeydown(event: KeyboardEvent) {
		if (event.key === 'Enter' && !event.shiftKey) {
			event.preventDefault();
			submit();
		}
	}

	$: if (messages.length !== previousMessageCount) {
		const shouldAutoscroll = previousMessageCount === 0 || isNearBottom();
		previousMessageCount = messages.length;
		if (shouldAutoscroll) {
			scrollToBottom();
		}
	}
</script>

<div
	class="flex flex-col rounded-2xl border-2 border-wood/10 bg-white/50 px-3 pt-2 pb-3 {collapsed
		? 'shrink-0 grow-0'
		: 'min-h-0 flex-1'}"
>
	<button
		class="flex w-full items-center justify-between gap-3 text-left {collapsed
			? ''
			: 'mb-1.5'} {collapsible ? 'cursor-pointer' : 'cursor-default'}"
		on:click={() => collapsible && (collapsed = !collapsed)}
		disabled={!collapsible}
	>
		<h3 class="text-sm font-bold tracking-wider text-wood-light uppercase">{title}</h3>
		<div class="flex items-center gap-2">
			<span class="text-[10px] font-bold tracking-wider text-wood-light/70 uppercase">
				{messages.length} message{messages.length === 1 ? '' : 's'}
			</span>
			{#if collapsible}
				<svg
					class="h-4 w-4 shrink-0 text-wood-light transition-transform {collapsed
						? ''
						: 'rotate-90'}"
					fill="none"
					stroke="currentColor"
					viewBox="0 0 24 24"
				>
					<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
				</svg>
			{/if}
		</div>
	</button>

	{#if !collapsed}
		<div
			bind:this={container}
			class="flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto pr-1 text-sm"
		>
			{#if messages.length === 0}
				<div class="rounded-xl bg-white/60 px-3 py-2 text-sm text-wood-light">{emptyMessage}</div>
			{:else}
				{#each messages as chat}
					{@const isOwnMessage = chat.playerId === playerId}
					<div
						class="rounded-xl px-3 py-2 shadow-sm {isOwnMessage
							? 'self-end bg-ocean/12 text-wood-dark'
							: 'bg-white/70 text-wood-dark/90'}"
					>
						<div
							class="mb-1 flex items-center gap-2 text-[10px] font-black tracking-[0.16em] uppercase"
						>
							<span class={isOwnMessage ? 'text-ocean' : 'text-wood-light'}>{chat.playerName}</span>
							<span class="text-wood-light/70">
								{new Date(chat.createdAt).toLocaleTimeString([], {
									hour: '2-digit',
									minute: '2-digit'
								})}
							</span>
						</div>
						<div class="leading-relaxed break-words whitespace-pre-wrap">{chat.message}</div>
					</div>
				{/each}
			{/if}
		</div>

		<form class="mt-3 flex items-end gap-2" on:submit|preventDefault={submit}>
			<textarea
				bind:value={draft}
				rows="1"
				maxlength="500"
				placeholder={inputPlaceholder}
				{disabled}
				on:keydown={handleKeydown}
				class="min-h-[40px] flex-1 resize-none rounded-xl border border-wood/15 bg-white/90 px-3 py-2 text-sm text-wood-dark shadow-sm transition outline-none focus:border-ocean/40 focus:ring-2 focus:ring-ocean/15 disabled:cursor-not-allowed disabled:bg-wood/5 disabled:text-wood-light"
			></textarea>
			<button
				type="submit"
				disabled={disabled || !draft.trim()}
				class="rounded-xl bg-ocean px-4 py-2 text-sm font-bold text-white shadow-md transition hover:bg-[#1880a8] disabled:cursor-not-allowed disabled:bg-wood/30"
			>
				Send
			</button>
		</form>
	{/if}
</div>
