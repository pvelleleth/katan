<script lang="ts">
    import { goto } from "$app/navigation";
    import { onMount } from "svelte";
    import { authClient } from "$lib/auth-client";
    
    let joinCode = "";
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
                }
            }
        } catch (e) {
            console.error("Auth error", e);
        } finally {
            loading = false;
        }
    });
    
    function handleCreateLobby() {
        // Placeholder for creating lobby
        alert("Creating a new lobby...");
    }
    
    function handleJoinLobby() {
        if (joinCode.length < 4) return;
        // Placeholder for joining lobby
        alert("Joining lobby: " + joinCode.toUpperCase());
    }

    async function handleSignOut() {
        await authClient.signOut();
        goto("/");
    }
</script>

<svelte:head>
    <title>Game Lobby | TradeIsles</title>
</svelte:head>

<main class="min-h-screen flex flex-col bg-parchment-texture overflow-hidden selection:bg-ocean/30 font-trebuchet relative">
    <!-- Navbar -->
    <header class="h-[88px] px-8 lg:px-14 flex items-center justify-between sticky top-0 bg-parchment/60 backdrop-blur-xl z-50 border-b border-wood/10">
        <a href="/" class="font-[900] text-2xl lg:text-3xl tracking-tight text-wood select-none hover:text-wood-dark transition-colors">
            TRADEISLES
        </a>
        
        <div class="flex items-center gap-6">
            {#if loading}
                <div class="w-24 h-4 bg-wood/10 rounded-full animate-pulse"></div>
            {:else if user}
                <div class="flex items-center gap-4">
                    <span class="text-wood-dark font-bold">
                        {user.name || (user.isAnonymous ? 'Guest Player' : 'Player')}
                    </span>
                    <button 
                        on:click={handleSignOut}
                        class="text-sm font-bold text-brick hover:text-white border border-brick/20 hover:bg-brick px-4 py-1.5 rounded-full transition-all"
                    >
                        Sign Out
                    </button>
                </div>
            {/if}
        </div>
    </header>

    <div class="flex-1 flex flex-col items-center justify-center p-6 lg:p-12 relative min-h-0">
        <!-- Decorative Glow -->
        <div class="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-full max-w-4xl h-[600px] bg-ocean/10 rounded-full blur-[100px] pointer-events-none"></div>

        {#if !loading}
            <div class="mb-10 text-center relative z-10 animate-in fade-in slide-in-from-bottom-4 duration-700">
                <h1 class="text-4xl lg:text-5xl font-black text-wood-dark mb-2 drop-shadow-sm">
                    Welcome to the Isles
                </h1>
                <p class="text-lg text-wood-light/90 font-medium max-w-lg mx-auto">
                    Create a new lobby to play with friends or join an existing game using a code.
                </p>
            </div>
        {/if}

        <div class="w-full max-w-4xl grid md:grid-cols-2 gap-8 items-stretch z-10 animate-in fade-in zoom-in-95 duration-500 delay-150 fill-mode-both">
            
            <!-- Create Game Panel -->
            <div class="glass-panel p-10 rounded-3xl shadow-xl flex flex-col items-center text-center gap-6 transform transition-all hover:scale-[1.02] hover:-translate-y-1 hover:shadow-2xl hover:bg-white/30 group relative overflow-hidden">
                <!-- Decorative Icon bg -->
                <div class="absolute -right-10 -top-10 text-forest/5 rotate-12 group-hover:rotate-45 transition-transform duration-700 pointer-events-none">
                    <svg class="w-64 h-64" fill="currentColor" viewBox="0 0 24 24"><path d="M12 2L2 7l10 5 10-5-10-5zm0 7l-10 5 10 5 10-5-10-5z"/></svg>
                </div>

                <div class="w-20 h-20 bg-forest/10 text-forest rounded-full flex items-center justify-center mb-2 group-hover:scale-110 group-hover:bg-forest group-hover:text-white transition-all duration-300 shadow-sm relative z-10">
                    <svg class="w-10 h-10" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M12 4v16m8-8H4"/></svg>
                </div>
                
                <div class="relative z-10 flex-1 flex flex-col">
                    <h2 class="text-3xl font-black text-wood-dark mb-3">Host a Game</h2>
                    <p class="text-wood-light/90 font-medium flex-1">Start a fresh match. You'll get a code to invite your friends into your lobby.</p>
                </div>
                
                <button 
                    on:click={handleCreateLobby}
                    class="relative z-10 w-full bg-forest hover:bg-forest/90 text-white rounded-2xl px-8 py-4.5 font-bold text-xl hover:scale-105 transition-all shadow-xl shadow-forest/20 active:scale-95 mt-2 flex items-center justify-center gap-2 group/btn"
                >
                    Create Lobby
                    <svg class="w-6 h-6 group-hover/btn:translate-x-1 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M13 7l5 5m0 0l-5 5m5-5H6"/></svg>
                </button>
            </div>

            <!-- Join Game Panel -->
            <div class="glass-panel p-10 rounded-3xl shadow-xl flex flex-col items-center text-center gap-6 transform transition-all hover:scale-[1.02] hover:-translate-y-1 hover:shadow-2xl hover:bg-white/30 group relative overflow-hidden">
                <!-- Decorative Icon bg -->
                <div class="absolute -left-10 -bottom-10 text-ocean/5 -rotate-12 group-hover:-rotate-45 transition-transform duration-700 pointer-events-none">
                    <svg class="w-64 h-64" fill="currentColor" viewBox="0 0 24 24"><path d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"/></svg>
                </div>

                <div class="w-20 h-20 bg-ocean/10 text-ocean rounded-full flex items-center justify-center mb-2 group-hover:scale-110 group-hover:bg-ocean group-hover:text-white transition-all duration-300 shadow-sm relative z-10">
                    <svg class="w-10 h-10" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4v-4l5.257-5.257A6 6 0 1121 9z"/></svg>
                </div>
                
                <div class="relative z-10 flex-1 flex flex-col w-full">
                    <h2 class="text-3xl font-black text-wood-dark mb-3">Join a Game</h2>
                    <p class="text-wood-light/90 font-medium mb-4">Have an invite code? Enter it below to drop right into the lobby.</p>
                    
                    <div class="mt-auto flex flex-col gap-4 w-full">
                        <input 
                            type="text" 
                            bind:value={joinCode}
                            placeholder="LOBBY CODE" 
                            class="w-full bg-white/70 border-2 border-wood/10 rounded-2xl px-6 py-4 font-black text-center text-2xl text-ocean placeholder:text-wood/30 outline-none focus:border-ocean focus:ring-4 ring-ocean/20 transition-all uppercase tracking-widest"
                            maxlength="6"
                            on:keydown={(e) => e.key === 'Enter' && joinCode.length >= 4 && handleJoinLobby()}
                        />
                        <button 
                            on:click={handleJoinLobby}
                            disabled={joinCode.length < 4}
                            class="w-full bg-ocean hover:bg-ocean/90 text-white rounded-2xl px-8 py-4.5 font-bold text-xl hover:scale-105 transition-all shadow-xl shadow-ocean/20 active:scale-95 disabled:opacity-50 disabled:hover:scale-100 disabled:cursor-not-allowed group/btn2 flex items-center justify-center gap-2"
                        >
                            Join Lobby
                            <svg class="w-6 h-6 group-hover/btn2:translate-x-1 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M13 7l5 5m0 0l-5 5m5-5H6"/></svg>
                        </button>
                    </div>
                </div>
            </div>

        </div>
    </div>
</main>
