export function originHost(origin: string): string {
	try {
		return new URL(origin).hostname.toLowerCase();
	} catch {
		return '';
	}
}

export function requestHost(hostHeader: string | null | undefined, fallbackHost: string): string {
	const raw = (hostHeader || fallbackHost).split(',')[0]?.trim() || fallbackHost;
	return raw.split(':')[0].toLowerCase();
}

export function hostIsAdmin(hostname: string, adminOrigin: string): boolean {
	const expected = originHost(adminOrigin);
	if (!expected) return false;
	return requestHost(hostname, hostname) === expected;
}
