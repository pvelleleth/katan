<script lang="ts">
	import { authClient } from '$lib/auth-client';
	import { goto } from '$app/navigation';

	let email = '';
	let password = '';
	let isSubmitting = false;
	let errorMessage = '';

	async function handleLogin() {
		errorMessage = '';
		isSubmitting = true;
		try {
			const { data, error } = await authClient.signIn.email({
				email,
				password
			});
			if (error) {
				errorMessage = error.message || 'Failed to log in';
			} else if (data) {
				goto('/game');
			}
		} catch (e) {
			errorMessage = 'An unexpected error occurred.';
		} finally {
			isSubmitting = false;
		}
	}

	async function handleGoogleLogin() {
		await authClient.signIn.social({
			provider: 'google',
			callbackURL: '/game'
		});
	}
</script>

<svelte:head>
	<title>Log In | Settler</title>
</svelte:head>

<main
	class="relative flex min-h-screen items-center justify-center overflow-hidden bg-parchment-texture px-4 py-12 font-trebuchet"
>
	<!-- Visual Glow Background -->
	<div
		class="pointer-events-none absolute inset-0 scale-150 -rotate-12 transform rounded-[100%] bg-ocean/15 blur-3xl"
	></div>

	<div
		class="relative z-10 w-full max-w-md rounded-3xl border border-wood/10 bg-parchment/80 p-8 shadow-[0_20px_60px_rgba(30,77,107,0.1)] backdrop-blur-xl"
	>
		<div class="mb-10 text-center">
			<a href="/" class="mb-4 inline-block text-3xl font-[900] tracking-tight text-wood"
				>SETTLER</a
			>
			<h1 class="mb-2 text-3xl font-black text-wood-dark">Welcome Back</h1>
			<p class="font-medium text-wood-light/80">Log in to track your stats and join friends.</p>
		</div>

		{#if errorMessage}
			<div
				class="mb-6 rounded-xl border border-red-200 bg-red-100/50 p-4 text-sm font-medium text-red-700"
			>
				{errorMessage}
			</div>
		{/if}

		<form on:submit|preventDefault={handleLogin} class="space-y-5">
			<div>
				<label for="email" class="mb-1.5 block text-sm font-bold text-wood">Email Address</label>
				<input
					type="email"
					id="email"
					bind:value={email}
					required
					class="w-full rounded-xl border border-wood/20 bg-white/50 px-4 py-3 transition-all focus:border-ocean focus:ring-2 focus:ring-ocean/50 focus:outline-none"
					placeholder="you@example.com"
				/>
			</div>

			<div>
				<label for="password" class="mb-1.5 block text-sm font-bold text-wood">Password</label>
				<input
					type="password"
					id="password"
					bind:value={password}
					required
					class="w-full rounded-xl border border-wood/20 bg-white/50 px-4 py-3 transition-all focus:border-ocean focus:ring-2 focus:ring-ocean/50 focus:outline-none"
					placeholder="••••••••"
				/>
			</div>

			<button
				type="submit"
				disabled={isSubmitting}
				class="w-full rounded-xl bg-brick px-4 py-3.5 text-base font-bold text-white shadow-lg shadow-brick/20 transition-all hover:scale-[1.02] hover:bg-brick/90 active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-75 disabled:hover:scale-100"
			>
				{isSubmitting ? 'Logging in...' : 'Log In'}
			</button>
		</form>

		<div
			class="my-8 flex items-center before:flex-1 before:border-t before:border-wood/10 after:flex-1 after:border-t after:border-wood/10"
		>
			<span class="px-4 text-xs font-bold tracking-wider text-wood/40 uppercase"
				>Or continue with</span
			>
		</div>

		<button
			type="button"
			on:click={handleGoogleLogin}
			class="flex w-full items-center justify-center gap-3 rounded-xl border border-wood/10 bg-white px-4 py-3.5 text-base font-bold text-wood-dark shadow-sm transition-all hover:-translate-y-0.5 hover:bg-white/80"
		>
			<svg class="h-5 w-5" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
				<path
					d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
					fill="#4285F4"
				/>
				<path
					d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
					fill="#34A853"
				/>
				<path
					d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
					fill="#FBBC05"
				/>
				<path
					d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
					fill="#EA4335"
				/>
			</svg>
			Google
		</button>

		<p class="mt-8 text-center text-sm font-medium text-wood/60">
			Don't have an account?
			<a href="/register" class="font-bold text-ocean hover:underline">Sign up</a>
		</p>
	</div>
</main>
