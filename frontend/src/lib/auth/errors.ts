export const COMPANY_EMAIL_REJECT =
	'Use a company email address. Personal or disposable providers are not accepted.';

type AuthLikeError = {
	message?: string;
	status?: number;
	code?: string;
};

export function formatSignInOtpError(otpError: AuthLikeError): string {
	const raw = otpError.message ?? '';
	const lower = raw.toLowerCase();
	const usable =
		lower.includes('company email') || lower.includes('personal or disposable')
			? raw
			: lower.includes('invalid payload sent to hook')
				? COMPANY_EMAIL_REJECT
				: raw;
	const status = otpError.status != null ? String(otpError.status) : '';
	const code = otpError.code ? String(otpError.code) : '';
	return [status, code, usable].filter(Boolean).join(' — ');
}
