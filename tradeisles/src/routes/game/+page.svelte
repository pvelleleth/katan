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
                } else if (res.error?.code === 'ANONYMOUS_USERS_CANNOT_SIGN_IN_AGAIN_ANONYMOUSLY') {
                    const secondTry = await authClient.getSession();
                    if (secondTry.data?.user) user = secondTry.data.user;
                }
            }
        } catch (e) {
            console.error("Auth error", e);
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
                console.error("Failed to create lobby");
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
        goto("/");
    }
</script>

<svelte:head>
    <title>Game Lobby | TradeIsles</title>
</svelte:head>

<main class="min-h-screen flex flex-col bg-parchment-texture overflow-hidden selection:bg-ocean/30 font-trebuchet relative p-4 lg:p-6 gap-6">
    <!-- Navbar Card -->
    <header class="h-16 px-6 glass-panel rounded-2xl flex items-center justify-between border border-wood/10 shadow-sm w-full max-w-6xl mx-auto z-50">
        <a href="/" class="font-[900] text-xl tracking-tight text-wood hover:text-wood-dark transition-colors">
            TRADEISLES
        </a>
        
        <div class="flex items-center gap-4">
            {#if loading}
                <div class="w-24 h-4 bg-wood/10 rounded-full animate-pulse"></div>
            {:else if user}
                <span class="text-sm text-wood-dark font-bold">
                    {user.name || (user.isAnonymous ? 'Guest Player' : 'Player')}
                </span>
                <button 
                    on:click={handleSignOut}
                    class="text-xs font-bold text-brick hover:text-white border border-brick/40 hover:bg-brick px-4 py-1.5 rounded-xl transition-all shadow-sm active:scale-95"
                >
                    Sign Out
                </button>
            {/if}
        </div>
    </header>

    <div class="flex-1 flex flex-col items-center justify-center relative min-h-0 z-10 w-full pb-10">
        <!-- Main Action Card -->
        <div class="w-full max-w-md glass-panel rounded-[2rem] p-6 sm:p-8 shadow-[0_20px_60px_-15px_rgba(0,0,0,0.1)] border-2 border-white/60 relative overflow-hidden flex flex-col gap-8 animate-in fade-in zoom-in-95 duration-500">
            <!-- Decorative Glow Backgrounds -->
            <div class="absolute top-0 right-0 w-64 h-64 bg-ocean/10 rounded-full blur-[60px] pointer-events-none -translate-y-1/2 translate-x-1/2"></div>
            <div class="absolute bottom-0 left-0 w-64 h-64 bg-forest/10 rounded-full blur-[60px] pointer-events-none translate-y-1/2 -translate-x-1/2"></div>

            <div class="text-center relative z-10 mt-2">
                <h1 class="text-3xl font-black text-wood-dark drop-shadow-sm tracking-tight">Play Online</h1>
            </div>

            <div class="flex flex-col gap-4 relative z-10 mb-2">
                <!-- Host Game Button -->
                <button 
                    on:click={handleCreateLobby}
                    class="w-full bg-gradient-to-br from-forest to-[#1a5b3d] text-white rounded-[1.25rem] p-4 font-bold text-lg hover:-translate-y-0.5 hover:shadow-lg hover:shadow-forest/30 transition-all active:scale-[0.98] flex items-center justify-between group border border-[#164a31]"
                >
                    <div class="flex items-center gap-4">
                        <div class="bg-white/20 p-2.5 rounded-xl shadow-inner">
                            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M12 4v16m8-8H4"/></svg>
                        </div>
                        <span class="tracking-wide">Host a Game</span>
                    </div>
                    <svg class="w-6 h-6 group-hover:translate-x-1 transition-transform opacity-80" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M9 5l7 7-7 7"/></svg>
                </button>

                <!-- Divider -->
                <div class="flex items-center gap-4 py-2 opacity-40">
                    <div class="flex-1 h-0.5 bg-wood rounded-full"></div>
                    <span class="text-xs font-black text-wood tracking-widest uppercase">Or</span>
                    <div class="flex-1 h-0.5 bg-wood rounded-full"></div>
                </div>

                <!-- Join Game Input -->
                <div class="bg-white/70 rounded-[1.25rem] p-4 border border-wood/15 shadow-sm flex flex-col gap-3 transition-all focus-within:bg-white focus-within:border-ocean/40 focus-within:shadow-md">
                    <div class="flex items-center gap-3 text-wood-dark font-bold px-1">
                        <div class="bg-ocean/10 text-ocean p-2 rounded-xl">
                            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4v-4l5.257-5.257A6 6 0 1121 9z"/></svg>
                        </div>
                        <span class="tracking-wide">Join with Code</span>
                    </div>
                    
                    <div class="flex gap-2">
                        <input 
                            type="text" 
                            bind:value={joinCode}
                            placeholder="6-DIGIT CODE" 
                            class="flex-1 bg-white/50 border border-wood/20 rounded-xl px-4 py-3.5 font-black text-center text-xl text-ocean placeholder:text-wood/30 outline-none focus:bg-white focus:border-ocean focus:ring-4 ring-ocean/10 transition-all uppercase tracking-[0.15em]"
                            maxlength="6"
                            on:keydown={(e) => e.key === 'Enter' && joinCode.length >= 4 && handleJoinLobby()}
                        />
                        <button 
                            on:click={handleJoinLobby}
                            disabled={joinCode.length < 4}
                            aria-label="Join Lobby"
                            class="bg-ocean hover:bg-[#1880a8] text-white rounded-xl px-5 font-bold hover:-translate-y-0.5 transition-all shadow-md hover:shadow-ocean/30 active:scale-[0.95] disabled:opacity-50 disabled:hover:translate-y-0 disabled:-scale-100 disabled:shadow-none disabled:cursor-not-allowed flex items-center justify-center shrink-0 border border-[#146c8e]"
                        >
                            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M14 5l7 7m0 0l-7 7m7-7H3"/></svg>
                        </button>
                    </div>
                </div>
            </div>
        </div>
    </div>
</main>
