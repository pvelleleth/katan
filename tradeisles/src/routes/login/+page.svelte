<script lang="ts">
    import { authClient } from "$lib/auth-client";
    import { goto } from "$app/navigation";

    let email = "";
    let password = "";
    let isSubmitting = false;
    let errorMessage = "";

    async function handleLogin() {
        errorMessage = "";
        isSubmitting = true;
        try {
            const { data, error } = await authClient.signIn.email({
                email,
                password,
            });
            if (error) {
                errorMessage = error.message || "Failed to log in";
            } else if (data) {
                goto("/game");
            }
        } catch (e) {
            errorMessage = "An unexpected error occurred.";
        } finally {
            isSubmitting = false;
        }
    }

    async function handleGoogleLogin() {
        await authClient.signIn.social({
            provider: "google",
            callbackURL: "/game"
        });
    }
</script>

<svelte:head>
    <title>Log In | TradeIsles</title>
</svelte:head>

<main class="min-h-screen flex items-center justify-center bg-parchment-texture px-4 py-12 relative overflow-hidden font-trebuchet">
    <!-- Visual Glow Background -->
    <div class="absolute inset-0 bg-ocean/15 rounded-[100%] blur-3xl transform -rotate-12 scale-150 pointer-events-none"></div>

    <div class="w-full max-w-md bg-parchment/80 backdrop-blur-xl border border-wood/10 rounded-3xl shadow-[0_20px_60px_rgba(30,77,107,0.1)] p-8 relative z-10">
        <div class="text-center mb-10">
            <a href="/" class="inline-block font-[900] text-3xl tracking-tight text-wood mb-4">TRADEISLES</a>
            <h1 class="text-3xl font-black text-wood-dark mb-2">Welcome Back</h1>
            <p class="text-wood-light/80 font-medium">Log in to track your stats and join friends.</p>
        </div>

        {#if errorMessage}
            <div class="mb-6 p-4 bg-red-100/50 border border-red-200 text-red-700 rounded-xl text-sm font-medium">
                {errorMessage}
            </div>
        {/if}

        <form on:submit|preventDefault={handleLogin} class="space-y-5">
            <div>
                <label for="email" class="block text-sm font-bold text-wood mb-1.5">Email Address</label>
                <input 
                    type="email" 
                    id="email" 
                    bind:value={email} 
                    required 
                    class="w-full px-4 py-3 rounded-xl bg-white/50 border border-wood/20 focus:outline-none focus:ring-2 focus:ring-ocean/50 focus:border-ocean transition-all"
                    placeholder="you@example.com"
                />
            </div>
            
            <div>
                <label for="password" class="block text-sm font-bold text-wood mb-1.5">Password</label>
                <input 
                    type="password" 
                    id="password" 
                    bind:value={password} 
                    required 
                    class="w-full px-4 py-3 rounded-xl bg-white/50 border border-wood/20 focus:outline-none focus:ring-2 focus:ring-ocean/50 focus:border-ocean transition-all"
                    placeholder="••••••••"
                />
            </div>

            <button 
                type="submit" 
                disabled={isSubmitting}
                class="w-full bg-brick hover:bg-brick/90 text-white rounded-xl px-4 py-3.5 font-bold text-base hover:scale-[1.02] transition-all shadow-lg shadow-brick/20 active:scale-[0.98] disabled:opacity-75 disabled:hover:scale-100 disabled:cursor-not-allowed"
            >
                {isSubmitting ? 'Logging in...' : 'Log In'}
            </button>
        </form>

        <div class="my-8 flex items-center before:flex-1 before:border-t before:border-wood/10 after:flex-1 after:border-t after:border-wood/10">
            <span class="px-4 text-xs font-bold text-wood/40 uppercase tracking-wider">Or continue with</span>
        </div>

        <button 
            type="button"
            on:click={handleGoogleLogin}
            class="w-full bg-white hover:bg-white/80 text-wood-dark border border-wood/10 rounded-xl px-4 py-3.5 font-bold text-base hover:-translate-y-0.5 transition-all shadow-sm flex items-center justify-center gap-3"
        >
            <svg class="w-5 h-5" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
                <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" fill="#4285F4"/>
                <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/>
                <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05"/>
                <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/>
            </svg>
            Google
        </button>

        <p class="mt-8 text-center text-sm text-wood/60 font-medium">
            Don't have an account? 
            <a href="/register" class="text-ocean font-bold hover:underline">Sign up</a>
        </p>
    </div>
</main>
