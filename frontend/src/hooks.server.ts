import { env } from '$env/dynamic/public';
import { redirect, type Handle } from '@sveltejs/kit';
import { hostIsAdmin, requestHost } from '$lib/site';

export const handle: Handle = async ({ event, resolve }) => {
	const adminOrigin = (env.PUBLIC_ADMIN_ORIGIN || '').replace(/\/$/, '');
	const host = requestHost(event.request.headers.get('x-forwarded-host'), event.url.host);
	const path = event.url.pathname;
	const admin = hostIsAdmin(host, adminOrigin);

	if (adminOrigin && admin && (path.startsWith('/app') || path.startsWith('/signup'))) {
		redirect(303, '/');
	}
	if (adminOrigin && !admin && path.startsWith('/platform')) {
		redirect(307, `${adminOrigin}${path}${event.url.search}`);
	}
	event.locals.adminHost = Boolean(adminOrigin && admin);

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
	return response;
};
