<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { authClient } from '$lib/auth-client';

	let joinCode = '';
	let user: Record<string, any> | null = null;
	let loading = true;

	onMount(async () => {
		try {
			const { data } = await authClient.getSession();
			if (data?.user) {
				user = data.user;
			} else {
				// If they bypassed the landing page, sign them in anonymously
				const res = await authClient.signIn.anonymous();
				if (res.data?.user) {
					user = res.data.user;
				} else if (res.error?.code === 'ANONYMOUS_USERS_CANNOT_SIGN_IN_AGAIN_ANONYMOUSLY') {
					const secondTry = await authClient.getSession();
					if (secondTry.data?.user) user = secondTry.data.user;
				}
			}
		} catch (e) {
			console.error('Auth error', e);
		} finally {
			loading = false;
		}
	});

	async function handleCreateLobby() {
		try {
			const res = await fetch('/api/games', { method: 'POST' });
			if (res.ok) {
				const { game } = await res.json();
				goto(`/game/${game.shortCode}`);
			} else {
				console.error('Failed to create lobby');
			}
		} catch (e) {
			console.error(e);
		}
	}

	function handleJoinLobby() {
		if (joinCode.length < 4) return;
		goto(`/game/${joinCode.toUpperCase()}`);
	}

	async function handleSignOut() {
		await authClient.signOut();
		goto('/');
	}
</script>

<svelte:head>
	<title>Game Lobby | Settler</title>
</svelte:head>

<main
	class="relative flex min-h-screen flex-col gap-6 overflow-hidden bg-parchment-texture p-4 font-trebuchet selection:bg-ocean/30 lg:p-6"
>
	<!-- Navbar Card -->
	<header
		class="z-50 mx-auto flex h-16 w-full max-w-6xl items-center justify-between rounded-2xl border border-wood/10 px-6 shadow-sm glass-panel"
	>
		<a
			href="/"
			class="text-xl font-[900] tracking-tight text-wood transition-colors hover:text-wood-dark"
		>
			SETTLER
		</a>

		<div class="flex items-center gap-4">
			{#if loading}
				<div class="h-4 w-24 animate-pulse rounded-full bg-wood/10"></div>
			{:else if user}
				<span class="text-sm font-bold text-wood-dark">
					{user.name || (user.isAnonymous ? 'Guest Player' : 'Player')}
				</span>
				<button
					on:click={handleSignOut}
					class="rounded-xl border border-brick/40 px-4 py-1.5 text-xs font-bold text-brick shadow-sm transition-all hover:bg-brick hover:text-white active:scale-95"
				>
					Sign Out
				</button>
			{/if}
		</div>
	</header>

	<div class="relative z-10 flex min-h-0 w-full flex-1 flex-col items-center justify-center pb-10">
		<!-- Main Action Card -->
		<div
			class="animate-in fade-in zoom-in-95 relative flex w-full max-w-md flex-col gap-8 overflow-hidden rounded-[2rem] border-2 border-white/60 p-6 shadow-[0_20px_60px_-15px_rgba(0,0,0,0.1)] glass-panel duration-500 sm:p-8"
		>
			<!-- Decorative Glow Backgrounds -->
			<div
				class="pointer-events-none absolute top-0 right-0 h-64 w-64 translate-x-1/2 -translate-y-1/2 rounded-full bg-ocean/10 blur-[60px]"
			></div>
			<div
				class="pointer-events-none absolute bottom-0 left-0 h-64 w-64 -translate-x-1/2 translate-y-1/2 rounded-full bg-forest/10 blur-[60px]"
			></div>

			<div class="relative z-10 mt-2 text-center">
				<h1 class="text-3xl font-black tracking-tight text-wood-dark drop-shadow-sm">
					Play Online
				</h1>
			</div>

			<div class="relative z-10 mb-2 flex flex-col gap-4">
				<!-- Host Game Button -->
				<button
					on:click={handleCreateLobby}
					class="group flex w-full items-center justify-between rounded-[1.25rem] border border-[#164a31] bg-gradient-to-br from-forest to-[#1a5b3d] p-4 text-lg font-bold text-white transition-all hover:-translate-y-0.5 hover:shadow-lg hover:shadow-forest/30 active:scale-[0.98]"
				>
					<div class="flex items-center gap-4">
						<div class="rounded-xl bg-white/20 p-2.5 shadow-inner">
							<svg class="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"
								><path
									stroke-linecap="round"
									stroke-linejoin="round"
									stroke-width="2.5"
									d="M12 4v16m8-8H4"
								/></svg
							>
						</div>
						<span class="tracking-wide">Host a Game</span>
					</div>
					<svg
						class="h-6 w-6 opacity-80 transition-transform group-hover:translate-x-1"
						fill="none"
						stroke="currentColor"
						viewBox="0 0 24 24"
						><path
							stroke-linecap="round"
							stroke-linejoin="round"
							stroke-width="2.5"
							d="M9 5l7 7-7 7"
						/></svg
					>
				</button>

				<!-- Divider -->
				<div class="flex items-center gap-4 py-2 opacity-40">
					<div class="h-0.5 flex-1 rounded-full bg-wood"></div>
					<span class="text-xs font-black tracking-widest text-wood uppercase">Or</span>
					<div class="h-0.5 flex-1 rounded-full bg-wood"></div>
				</div>

				<!-- Join Game Input -->
				<div
					class="flex flex-col gap-3 rounded-[1.25rem] border border-wood/15 bg-white/70 p-4 shadow-sm transition-all focus-within:border-ocean/40 focus-within:bg-white focus-within:shadow-md"
				>
					<div class="flex items-center gap-3 px-1 font-bold text-wood-dark">
						<div class="rounded-xl bg-ocean/10 p-2 text-ocean">
							<svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"
								><path
									stroke-linecap="round"
									stroke-linejoin="round"
									stroke-width="2.5"
									d="M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4v-4l5.257-5.257A6 6 0 1121 9z"
								/></svg
							>
						</div>
						<span class="tracking-wide">Join with Code</span>
					</div>

					<div class="flex gap-2">
						<input
							type="text"
							bind:value={joinCode}
							placeholder="6-DIGIT CODE"
							class="flex-1 rounded-xl border border-wood/20 bg-white/50 px-4 py-3.5 text-center text-xl font-black tracking-[0.15em] text-ocean uppercase ring-ocean/10 transition-all outline-none placeholder:text-wood/30 focus:border-ocean focus:bg-white focus:ring-4"
							maxlength="6"
							on:keydown={(e) => e.key === 'Enter' && joinCode.length >= 4 && handleJoinLobby()}
						/>
						<button
							on:click={handleJoinLobby}
							disabled={joinCode.length < 4}
							aria-label="Join Lobby"
							class="flex shrink-0 items-center justify-center rounded-xl border border-[#146c8e] bg-ocean px-5 font-bold text-white shadow-md transition-all hover:-translate-y-0.5 hover:bg-[#1880a8] hover:shadow-ocean/30 active:scale-[0.95] disabled:-scale-100 disabled:cursor-not-allowed disabled:opacity-50 disabled:shadow-none disabled:hover:translate-y-0"
						>
							<svg class="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"
								><path
									stroke-linecap="round"
									stroke-linejoin="round"
									stroke-width="3"
									d="M14 5l7 7m0 0l-7 7m7-7H3"
								/></svg
							>
						</button>
					</div>
				</div>
			</div>
		</div>
	</div>
</main>
