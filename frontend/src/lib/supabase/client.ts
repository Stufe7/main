import { browser } from '$app/environment';
import { env } from '$env/dynamic/public';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

const GLOBAL_KEY = '__stufe7Supabase';

type AuthGlobal = typeof globalThis & {
	[GLOBAL_KEY]?: SupabaseClient;
};

export function isSupabaseConfigured(): boolean {
	return Boolean(env.PUBLIC_SUPABASE_URL && env.PUBLIC_SUPABASE_ANON_KEY);
}

export function getSupabase(): SupabaseClient | null {
	if (!browser) return null;
	const g = globalThis as AuthGlobal;
	if (g[GLOBAL_KEY]) return g[GLOBAL_KEY];
	const url = env.PUBLIC_SUPABASE_URL;
	const key = env.PUBLIC_SUPABASE_ANON_KEY;
	if (!url || !key) return null;
	g[GLOBAL_KEY] = createClient(url, key, {
		auth: {
			persistSession: true,
			autoRefreshToken: true,
			detectSessionInUrl: true
		}
	});
	return g[GLOBAL_KEY];
}
