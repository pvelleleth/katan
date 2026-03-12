<script lang="ts">
    import { page } from "$app/stores";
    import { goto } from "$app/navigation";
    import { onMount } from "svelte";
    import { authClient } from "$lib/auth-client";
    
    let lobbyId = $page.params.id;
    let user: Record<string, any> | null = null;
    let loading = true;
    let copied = false;
    
    type ColorNames = 'brick' | 'ocean' | 'wheat' | 'forest';
    
    // Mock player data for the lobby
    let players: { id: string, name: string, isHost: boolean, isReady: boolean, color: ColorNames }[] = [
        { id: '1', name: 'Loading...', isHost: true, isReady: true, color: 'brick' }
    ];

    onMount(async () => {
        try {
            const { data } = await authClient.getSession();
            if (data?.user) {
                user = data.user;
                players[0].name = data.user.name || (data.user.isAnonymous ? 'Guest Player' : 'Player');
            } else {
                goto('/login');
            }
        } catch (e) {
            console.error("Auth error", e);
            goto('/login');
        } finally {
            loading = false;
        }
    });

    function copyInviteLink() {
        const link = `${window.location.origin}/game/${lobbyId}`;
        navigator.clipboard.writeText(link);
        copied = true;
        setTimeout(() => copied = false, 2000);
    }

    function toggleReady() {
        players[0].isReady = !players[0].isReady;
        players = [...players];
    }

    function startGame() {
        // Placeholder for game start
        alert("Starting game!");
    }

    // Helper colors
    const colors: Record<ColorNames, string> = {
        brick: 'bg-brick',
        ocean: 'bg-ocean',
        wheat: 'bg-wheat',
        forest: 'bg-forest',
    };
    
</script>

<svelte:head>
    <title>Lobby {lobbyId} | TradeIsles</title>
</svelte:head>

<main class="min-h-screen flex flex-col bg-parchment-texture overflow-hidden selection:bg-ocean/30 font-trebuchet relative">
    <!-- Navbar -->
    <header class="h-[88px] px-8 lg:px-14 flex items-center justify-between sticky top-0 bg-parchment/60 backdrop-blur-xl z-50 border-b border-wood/10">
        <a href="/" class="font-[900] text-2xl lg:text-3xl tracking-tight text-wood select-none hover:text-wood-dark transition-colors">
            TRADEISLES
        </a>
        
        <div class="flex items-center gap-6">
            <button 
                on:click={() => goto('/game')}
                class="text-sm font-bold text-wood hover:text-brick border border-wood/20 hover:border-brick/20 px-4 py-1.5 rounded-full transition-all"
            >
                Leave Lobby
            </button>
        </div>
    </header>

    <div class="flex-1 flex flex-col items-center justify-center p-6 lg:p-12 relative min-h-0">
        <!-- Decorative Glow -->
        <div class="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-full max-w-4xl h-[600px] bg-ocean/10 rounded-full blur-[100px] pointer-events-none"></div>

        <div class="w-full max-w-3xl flex flex-col gap-8 relative z-10 animate-in fade-in zoom-in-95 duration-500">
            
            <!-- Lobby Code Header -->
            <div class="glass-panel p-8 rounded-3xl shadow-xl flex flex-col sm:flex-row items-center justify-between gap-6 border-2 border-wood/10">
                <div>
                    <h1 class="text-xl font-bold text-wood-light/80 uppercase tracking-widest mb-1">Lobby Code</h1>
                    <div class="text-4xl lg:text-5xl font-black text-wood-dark tracking-[0.2em] drop-shadow-sm font-mono">{lobbyId}</div>
                </div>
                
                <button 
                    on:click={copyInviteLink}
                    class="bg-white/80 hover:bg-white text-ocean rounded-2xl px-6 py-4 font-bold text-lg hover:scale-105 transition-all shadow-md active:scale-95 flex items-center gap-3 border border-ocean/20"
                >
                    {#if copied}
                        <svg class="w-6 h-6 text-forest" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M5 13l4 4L19 7"/></svg>
                        <span class="text-forest">Copied!</span>
                    {:else}
                        <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/></svg>
                        <span>Copy Link</span>
                    {/if}
                </button>
            </div>

            <!-- Players List -->
            <div class="glass-panel p-8 rounded-3xl shadow-xl border-2 border-wood/10">
                <div class="flex items-center justify-between mb-6">
                    <h2 class="text-2xl font-black text-wood-dark">Players (1/4)</h2>
                    <span class="text-sm font-bold text-wood-light bg-wood/10 px-3 py-1 rounded-full text-center">Waiting for players...</span>
                </div>
                
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    {#each players as player}
                        <div class="bg-white/50 border border-wood/10 rounded-2xl p-4 flex items-center gap-4 relative overflow-hidden group">
                            <!-- Player Color indicator -->
                            <div class="w-12 h-12 rounded-full {colors[player.color]} shadow-md border-2 border-white/50 flex items-center justify-center text-white shrink-0">
                                <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"/></svg>
                            </div>
                            
                            <div class="flex-1 min-w-0">
                                <div class="font-bold text-wood-dark text-lg truncate flex items-center gap-2">
                                    {player.name}
                                    {#if player.isHost}
                                        <svg class="w-4 h-4 text-brick" fill="currentColor" viewBox="0 0 24 24"><title>Host</title><path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"/></svg>
                                    {/if}
                                </div>
                                <div class="text-sm font-semibold {player.isReady ? 'text-forest' : 'text-wood/50'}">
                                    {player.isReady ? 'Ready' : 'Not Ready'}
                                </div>
                            </div>
                        </div>
                    {/each}

                    <!-- Empty Slots -->
                    {#each Array(4 - players.length) as _}
                        <div class="border-2 border-dashed border-wood/20 rounded-2xl p-4 flex items-center gap-4 h-[84px] bg-wood/5">
                            <div class="w-12 h-12 rounded-full bg-wood/10 border-2 border-wood/10 flex items-center justify-center shrink-0">
                                <span class="text-wood/30 font-bold text-xl">?</span>
                            </div>
                            <div class="text-wood/40 font-bold text-lg">Empty Slot</div>
                        </div>
                    {/each}
                </div>
            </div>

            <!-- Action Area -->
            <div class="flex justify-end pt-4">
                <button 
                    on:click={startGame}
                    class="bg-forest hover:bg-forest/90 text-white rounded-2xl px-8 py-3.5 font-bold text-xl hover:scale-105 transition-all shadow-xl shadow-forest/20 active:scale-95 disabled:opacity-50 disabled:hover:scale-100 disabled:cursor-not-allowed group/start flex items-center gap-2 w-full sm:w-auto justify-center"
                    disabled={players.some(p => !p.isReady)}
                >
                    Start Game
                    <svg class="w-6 h-6 group-hover/start:translate-x-1 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M14 5l7 7m0 0l-7 7m7-7H3"/></svg>
                </button>
            </div>

        </div>
    </div>
</main>
