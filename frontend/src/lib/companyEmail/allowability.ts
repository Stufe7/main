/** Free/consumer mailbox providers. UX pre-check only; the Auth hook is authoritative. */
export const FREE_CONSUMER_DOMAINS = [
	'gmail.com',
	'googlemail.com',
	'outlook.com',
	'hotmail.com',
	'live.com',
	'msn.com',
	'yahoo.com',
	'ymail.com',
	'icloud.com',
	'me.com',
	'mac.com',
	'aol.com',
	'proton.me',
	'protonmail.com',
	'pm.me',
	'gmx.com',
	'gmx.net',
	'mail.com',
	'zoho.com',
	'yandex.com',
	'yandex.ru',
	'tutanota.com',
	'tuta.com'
] as const;

export function registrableEmailDomain(email: string): string | null {
	const trimmed = email.trim().toLowerCase();
	const at = trimmed.lastIndexOf('@');
	if (at <= 0 || at === trimmed.length - 1) return null;
	const domain = trimmed.slice(at + 1).replace(/\.+$/, '');
	if (!domain.includes('.') || domain.startsWith('.') || domain.includes(' ')) return null;
	return domain;
}

export function isFreeConsumerEmail(email: string): boolean {
	const domain = registrableEmailDomain(email);
	if (!domain) return false;
	return (FREE_CONSUMER_DOMAINS as readonly string[]).includes(domain);
}

export type CompanyEmailCheck = { ok: true; domain: string } | { ok: false; reason: string };

export function checkCompanyEmail(email: string): CompanyEmailCheck {
	const domain = registrableEmailDomain(email);
	if (!domain) {
		return { ok: false, reason: 'Enter a valid work email address.' };
	}
	if (isFreeConsumerEmail(email)) {
		return {
			ok: false,
			reason: 'Use a company email address. Personal providers such as Gmail and Outlook are not accepted.'
		};
	}
	return { ok: true, domain };
}
