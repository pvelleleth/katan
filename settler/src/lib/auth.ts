import { betterAuth } from 'better-auth';
import { drizzleAdapter } from 'better-auth/adapters/drizzle';
import { drizzle } from 'drizzle-orm/node-postgres';
import { Pool } from 'pg';
import { anonymous } from 'better-auth/plugins';
import { sveltekitCookies } from 'better-auth/svelte-kit';
import { getRequestEvent } from '$app/server';
import * as schema from './auth-schema';
import { env } from '$env/dynamic/private';

const db = drizzle(new Pool({ connectionString: env.DATABASE_URL }), {
	schema
});

export const auth = betterAuth({
	database: drizzleAdapter(db, { provider: 'pg', schema }),
	emailAndPassword: { enabled: true },
	socialProviders: {
		google: {
			clientId: env.GOOGLE_CLIENT_ID!,
			clientSecret: env.GOOGLE_CLIENT_SECRET!
		}
	},
	plugins: [
		anonymous({
			generateName: () => {
				const adjs = [
					'Wandering',
					'Lucky',
					'Clever',
					'Wealthy',
					'Brave',
					'Sneaky',
					'Swift',
					'Mighty'
				];
				const nouns = [
					'Trader',
					'Builder',
					'Settler',
					'Knight',
					'Merchant',
					'Explorer',
					'Captain',
					'Pioneer'
				];
				const adj = adjs[Math.floor(Math.random() * adjs.length)];
				const noun = nouns[Math.floor(Math.random() * nouns.length)];
				return `${adj} ${noun}`;
			}
		}),
		sveltekitCookies(getRequestEvent)
	]
});
