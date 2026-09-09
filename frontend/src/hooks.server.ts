import { dev } from '$app/environment';
import { env } from '$env/dynamic/public';
import type { Handle } from '@sveltejs/kit';

function connectSources(): string {
	const parts = ["'self'"];
	const api = (env.PUBLIC_API_BASE_URL || '').replace(/\/$/, '');
	const supabase = (env.PUBLIC_SUPABASE_URL || '').replace(/\/$/, '');
	if (api) parts.push(api);
	if (supabase) {
		parts.push(supabase);
		if (supabase.startsWith('https://')) parts.push(supabase.replace('https://', 'wss://'));
		if (supabase.startsWith('http://')) parts.push(supabase.replace('http://', 'ws://'));
	}
	return parts.join(' ');
}

export const handle: Handle = async ({ event, resolve }) => {
	const response = await resolve(event, {
		preload: ({ type }) => type === 'js' || type === 'font'
	});
	response.headers.set('X-Content-Type-Options', 'nosniff');
	response.headers.set('X-Frame-Options', 'DENY');
	response.headers.set('Referrer-Policy', 'strict-origin-when-cross-origin');
	response.headers.set('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
	if (event.url.protocol === 'https:') {
		response.headers.set('Strict-Transport-Security', 'max-age=63072000; includeSubDomains');
	}
	if (!dev) {
		response.headers.set(
			'Content-Security-Policy',
			[
				"default-src 'self'",
				`connect-src ${connectSources()}`,
				"img-src 'self' data:",
				"style-src 'self' 'unsafe-inline'",
				"script-src 'self'",
				"font-src 'self'",
				"frame-ancestors 'none'",
				"base-uri 'self'",
				"form-action 'self'"
			].join('; ')
		);
	}
	return response;
};
