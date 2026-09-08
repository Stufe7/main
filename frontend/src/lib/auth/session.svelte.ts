import { browser } from '$app/environment';
import { getSupabase } from '$lib/supabase/client';

export const auth = $state({
	email: null as string | null,
	ready: false
});

let listening = false;

export function startAuthListener() {
	if (!browser || listening) return;
	listening = true;
	const supabase = getSupabase();
	if (!supabase) {
		auth.ready = true;
		return;
	}
	void supabase.auth.getSession().then(({ data }) => {
		auth.email = data.session?.user.email ?? null;
		auth.ready = true;
	});
	supabase.auth.onAuthStateChange((_event, session) => {
		auth.email = session?.user.email ?? null;
		auth.ready = true;
	});
}

export async function requireSession(): Promise<string | null> {
	if (!browser) return null;
	const supabase = getSupabase();
	if (!supabase) {
		auth.ready = true;
		return null;
	}
	const { data } = await supabase.auth.getSession();
	auth.email = data.session?.user.email ?? null;
	auth.ready = true;
	return auth.email;
}

export async function signOut() {
	const supabase = getSupabase();
	if (supabase) await supabase.auth.signOut();
	auth.email = null;
}
