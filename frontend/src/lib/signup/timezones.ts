const COUNTRY_TIMEZONES: Record<string, string[]> = {
	SG: ['Asia/Singapore'],
	MY: ['Asia/Kuala_Lumpur'],
	ID: ['Asia/Jakarta', 'Asia/Makassar', 'Asia/Jayapura'],
	TH: ['Asia/Bangkok'],
	VN: ['Asia/Ho_Chi_Minh'],
	PH: ['Asia/Manila'],
	AU: [
		'Australia/Sydney',
		'Australia/Melbourne',
		'Australia/Brisbane',
		'Australia/Adelaide',
		'Australia/Perth',
		'Australia/Hobart',
		'Australia/Darwin'
	],
	NZ: ['Pacific/Auckland'],
	IN: ['Asia/Kolkata'],
	JP: ['Asia/Tokyo'],
	KR: ['Asia/Seoul'],
	CN: ['Asia/Shanghai'],
	HK: ['Asia/Hong_Kong'],
	TW: ['Asia/Taipei'],
	AE: ['Asia/Dubai'],
	SA: ['Asia/Riyadh'],
	QA: ['Asia/Qatar'],
	US: [
		'America/New_York',
		'America/Chicago',
		'America/Denver',
		'America/Los_Angeles',
		'America/Phoenix',
		'Pacific/Honolulu'
	],
	CA: ['America/Toronto', 'America/Winnipeg', 'America/Edmonton', 'America/Vancouver', 'America/Halifax'],
	MX: ['America/Mexico_City', 'America/Tijuana', 'America/Cancun'],
	GB: ['Europe/London'],
	IE: ['Europe/Dublin'],
	DE: ['Europe/Berlin'],
	FR: ['Europe/Paris'],
	NL: ['Europe/Amsterdam'],
	BE: ['Europe/Brussels'],
	CH: ['Europe/Zurich'],
	AT: ['Europe/Vienna'],
	IT: ['Europe/Rome'],
	ES: ['Europe/Madrid'],
	PT: ['Europe/Lisbon'],
	SE: ['Europe/Stockholm'],
	NO: ['Europe/Oslo'],
	DK: ['Europe/Copenhagen'],
	FI: ['Europe/Helsinki'],
	PL: ['Europe/Warsaw'],
	CZ: ['Europe/Prague'],
	BR: ['America/Sao_Paulo', 'America/Manaus', 'America/Fortaleza'],
	ZA: ['Africa/Johannesburg'],
	NG: ['Africa/Lagos'],
	KE: ['Africa/Nairobi'],
	EG: ['Africa/Cairo']
};

export function listTimeZones(country?: string): string[] {
	const intl = Intl as typeof Intl & { supportedValuesOf?: (key: string) => string[] };
	const all =
		typeof intl.supportedValuesOf === 'function' ? intl.supportedValuesOf('timeZone') : Object.values(COUNTRY_TIMEZONES).flat();
	const preferred = country ? (COUNTRY_TIMEZONES[country] ?? []) : [];
	return [...preferred, ...all.filter((zone) => !preferred.includes(zone))];
}

export function suggestedTimeZone(country?: string): string {
	const localeZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
	const countryZones = country ? COUNTRY_TIMEZONES[country] : undefined;
	if (countryZones?.includes(localeZone)) return localeZone;
	if (countryZones?.[0]) return countryZones[0];
	return localeZone || 'UTC';
}

export function countryNeedsExplicitZone(country?: string): boolean {
	return Boolean(country && (COUNTRY_TIMEZONES[country]?.length ?? 0) > 1);
}
