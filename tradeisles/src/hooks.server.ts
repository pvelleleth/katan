import { auth } from '$lib/auth';
import { svelteKitHandler } from 'better-auth/svelte-kit';
import { building } from '$app/environment';
import type { Handle } from '@sveltejs/kit';

export const handle: Handle = async ({ event, resolve }) => {
	// Fetch current session from Better Auth
	const session = await auth.api.getSession({
		headers: event.request.headers
	});

	// Make session and user available on server endpoints, actions, and layouts
	if (session) {
		event.locals.session = session.session;
		event.locals.user = session.user;
	}

	// Handle all requests heading to better-auth
	return svelteKitHandler({ event, resolve, auth, building });
};
