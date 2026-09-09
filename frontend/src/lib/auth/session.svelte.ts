import { browser } from '$app/environment';
import { clearApiCaches, rememberAccessToken } from '$lib/api/client';
import { getSupabase } from '$lib/supabase/client';

export const auth = $state({
	email: null as string | null,
	ready: false
});

let listening = false;
let authInflight: Promise<string | null> | null = null;

function ensureAuth(): Promise<string | null> {
	if (auth.ready) return Promise.resolve(auth.email);
	if (authInflight) return authInflight;
	const supabase = getSupabase();
	if (!supabase) {
		auth.ready = true;
		return Promise.resolve(null);
	}
	authInflight = supabase.auth
		.getSession()
		.then(({ data }) => {
			rememberAccessToken(data.session?.access_token ?? null);
			auth.email = data.session?.user.email ?? null;
			auth.ready = true;
			return auth.email;
		})
		.finally(() => {
			authInflight = null;
		});
	return authInflight;
}

export function startAuthListener() {
	if (!browser || listening) return;
	listening = true;
	const supabase = getSupabase();
	if (!supabase) {
		auth.ready = true;
		return;
	}
	void ensureAuth();
	supabase.auth.onAuthStateChange((event, session) => {
		rememberAccessToken(session?.access_token ?? null);
		auth.email = session?.user.email ?? null;
		auth.ready = true;
		if (event === 'SIGNED_OUT') clearApiCaches();
	});
}

export async function requireSession(): Promise<string | null> {
	if (!browser) return null;
	return ensureAuth();
}

export async function signOut() {
	clearApiCaches();
	const supabase = getSupabase();
	if (supabase) await supabase.auth.signOut();
	auth.email = null;
}
