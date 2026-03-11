<script lang="ts">
    import { authClient } from "$lib/auth-client";
    import { goto } from "$app/navigation";
    
    let isSigningIn = false;
    
    async function handlePlayNow() {
        isSigningIn = true;
        try {
            const { data, error } = await authClient.signIn.anonymous();
            if (data) {
                goto('/game');
            }
        } finally {
            isSigningIn = false;
        }
    }
</script>

<svelte:head>
	<title>TradeIsles | Play Catan Online</title>
	<meta
		name="description"
		content="Play Catan online with friends. Trade, build, and race to 10 points in fast multiplayer matches."
	/>
</svelte:head>

<main class="h-screen min-h-0 flex flex-col bg-parchment-texture overflow-hidden selection:bg-ocean/30 font-trebuchet">
	<!-- Navbar -->
	<header 
		class="h-[88px] px-8 lg:px-14 flex items-center gap-5 sticky top-0 bg-parchment/60 backdrop-blur-xl z-50 border-b border-wood/10"
	>
		<div class="font-[900] text-2xl lg:text-3xl tracking-tight text-wood select-none">TRADEISLES</div>
		
		<nav class="flex-1 hidden md:flex items-center gap-8 ml-10">
			<a href="/game" class="text-wood/70 font-bold text-sm hover:text-ocean transition-colors">Play Online</a>
			<a href="#friends" class="text-wood/70 font-bold text-sm hover:text-ocean transition-colors">Friends &amp; Lobbies</a>
		</nav>

		<a 
			class="bg-brick/10 hover:bg-brick text-brick hover:text-white border border-brick/20 rounded-full px-6 py-2 text-sm font-bold transition-all hover:scale-105 active:scale-95 shadow-sm" 
			href="/login"
		>
			Log in
		</a>
	</header>

	<!-- Hero Section -->
	<section class="flex-1 px-8 lg:px-14 py-8 lg:py-0 grid grid-cols-1 lg:grid-cols-[0.9fr_1.1fr] gap-12 lg:gap-8 items-center min-h-0 relative">
		<!-- Left Content -->
		<div class="flex flex-col gap-8 relative z-20 max-w-2xl translate-x-12">
			<div class="flex flex-col gap-4">
				<h1 class="text-5xl lg:text-7xl xl:text-[5.5rem] font-black leading-[0.88] -tracking-[0.04em] text-wood-dark drop-shadow-sm">
					Your Favorite <span class="text-brick">Catan</span>, <br />Now Online.
				</h1>
				<p class="text-lg lg:text-xl text-wood-light/90 leading-relaxed max-w-lg font-medium">
					Trade, build, and race to 10 points in quick online matches with smooth turns, easy invites, and no setup friction.
				</p>
			</div>

			<div class="flex flex-wrap gap-4">
				<button 
					class="bg-forest hover:bg-forest/90 text-white rounded-2xl px-10 py-4.5 font-bold text-lg hover:scale-105 transition-all shadow-2xl shadow-forest/30 active:scale-95 flex items-center gap-2 group disabled:opacity-75 disabled:hover:scale-100 disabled:cursor-not-allowed" 
					on:click={handlePlayNow}
					disabled={isSigningIn}
				>
					{isSigningIn ? 'Loading...' : 'Play Free Now'}
					{#if !isSigningIn}
					<svg class="w-5 h-5 group-hover:translate-x-1 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M13 7l5 5m0 0l-5 5m5-5H6"/></svg>
					{/if}
				</button>
			</div>
		</div>

		<!-- Right Image -->
		<div class="relative w-full h-full flex items-center justify-center select-none pointer-events-none group z-10">
			<!-- Visual Glow Background -->
			<div class="absolute inset-0 bg-ocean/15 rounded-[100%] blur-3xl transform -rotate-12 scale-150"></div>
			
			<img
				src="/Gemini_Generated_Image_nmnjzynmnjzynmnj-removebg-preview.png"
				alt="TradeIsles Game Preview"
				class="w-full max-w-[700px] lg:max-w-none lg:w-[145%] transform lg:-translate-x-[15%] lg:scale-[1.2] drop-shadow-[0_50px_100px_rgba(30,77,107,0.35)] transition-transform duration-700 group-hover:scale-[1.23] group-hover:rotate-1"
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
