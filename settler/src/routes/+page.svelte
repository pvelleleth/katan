<script lang="ts">
	import { authClient } from '$lib/auth-client';
	import { goto } from '$app/navigation';

	let isSigningIn = false;

	async function handlePlayNow() {
		isSigningIn = true;
		try {
			const { data: session } = await authClient.getSession();
			if (session?.user) {
				goto('/game');
				return;
			}

			const { data, error } = await authClient.signIn.anonymous();
			if (data || (error && error.code === 'ANONYMOUS_USERS_CANNOT_SIGN_IN_AGAIN_ANONYMOUSLY')) {
				goto('/game');
			}
		} catch (e) {
			console.error(e);
		} finally {
			isSigningIn = false;
		}
	}
</script>

<svelte:head>
	<title>Settler | Play Online</title>
	<meta
		name="description"
		content="Play Settler online with friends. Trade, build, and race to 10 points in fast multiplayer matches."
	/>
</svelte:head>

<main
	class="flex h-screen min-h-0 flex-col overflow-hidden bg-parchment-texture font-trebuchet selection:bg-ocean/30"
>
	<!-- Navbar -->
	<header
		class="sticky top-0 z-50 flex h-[88px] items-center gap-5 border-b border-wood/10 bg-parchment/60 px-8 backdrop-blur-xl lg:px-14"
	>
		<div class="text-2xl font-[900] tracking-tight text-wood select-none lg:text-3xl">
			SETTLER
		</div>

		<nav class="ml-10 hidden flex-1 items-center gap-8 md:flex">
			<a href="/game" class="text-sm font-bold text-wood/70 transition-colors hover:text-ocean"
				>Play Online</a
			>
			<a href="#friends" class="text-sm font-bold text-wood/70 transition-colors hover:text-ocean"
				>Friends &amp; Lobbies</a
			>
		</nav>

		<a
			class="rounded-full border border-brick/20 bg-brick/10 px-6 py-2 text-sm font-bold text-brick shadow-sm transition-all hover:scale-105 hover:bg-brick hover:text-white active:scale-95"
			href="/login"
		>
			Log in
		</a>
	</header>

	<!-- Hero Section -->
	<section
		class="relative grid min-h-0 flex-1 grid-cols-1 items-center gap-12 px-8 py-8 lg:grid-cols-[0.9fr_1.1fr] lg:gap-8 lg:px-14 lg:py-0"
	>
		<!-- Left Content -->
		<div class="relative z-20 flex max-w-2xl translate-x-12 flex-col gap-8">
			<div class="flex flex-col gap-4">
				<h1
					class="text-5xl leading-[0.88] font-black -tracking-[0.04em] text-wood-dark drop-shadow-sm lg:text-7xl xl:text-[5.5rem]"
				>
					Your Favorite <span class="text-brick">Strategy Game</span>, <br />Now Online.
				</h1>
				<p class="max-w-lg text-lg leading-relaxed font-medium text-wood-light/90 lg:text-xl">
					Trade, build, and race to 10 points in quick online matches with smooth turns, easy
					invites, and no setup friction.
				</p>
			</div>

			<div class="flex flex-wrap gap-4">
				<button
					class="group flex items-center gap-2 rounded-2xl bg-forest px-10 py-4.5 text-lg font-bold text-white shadow-2xl shadow-forest/30 transition-all hover:scale-105 hover:bg-forest/90 active:scale-95 disabled:cursor-not-allowed disabled:opacity-75 disabled:hover:scale-100"
					on:click={handlePlayNow}
					disabled={isSigningIn}
				>
					{isSigningIn ? 'Loading...' : 'Play Free Now'}
					{#if !isSigningIn}
						<svg
							class="h-5 w-5 transition-transform group-hover:translate-x-1"
							fill="none"
							stroke="currentColor"
							viewBox="0 0 24 24"
							><path
								stroke-linecap="round"
								stroke-linejoin="round"
								stroke-width="2.5"
								d="M13 7l5 5m0 0l-5 5m5-5H6"
							/></svg
						>
					{/if}
				</button>
			</div>
		</div>

		<!-- Right Image -->
		<div
			class="group pointer-events-none relative z-10 flex h-full w-full items-center justify-center select-none"
		>
			<!-- Visual Glow Background -->
			<div
				class="absolute inset-0 scale-150 -rotate-12 transform rounded-[100%] bg-ocean/15 blur-3xl"
			></div>

			<img
				src="/Gemini_Generated_Image_nmnjzynmnjzynmnj-removebg-preview.png"
				alt="Settler Game Preview"
				class="w-full max-w-[700px] transform drop-shadow-[0_50px_100px_rgba(30,77,107,0.35)] transition-transform duration-700 group-hover:scale-[1.23] group-hover:rotate-1 lg:w-[145%] lg:max-w-none lg:-translate-x-[15%] lg:scale-[1.2]"
			/>
		</div>
	</section>
</main>

<style>
	:global(html, body) {
		margin: 0;
		padding: 0;
		background: #f4ebdc;
	}

	@media (max-width: 1024px) {
		main {
			height: auto;
			overflow-y: auto;
		}
	}
</style>
