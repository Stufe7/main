export const COMPANY_EMAIL_REJECT =
	'Use a company email address. Personal or disposable providers are not accepted.';
export const OTP_RATE_LIMIT =
	'Too many sign-in emails. Wait a minute, then request another code.';
export const OTP_NO_ACCOUNT =
	'No account for this email.';

type AuthLikeError = {
	message?: string;
	status?: number;
	code?: string;
};

export function formatSignInOtpError(otpError: AuthLikeError): string {
	const raw = otpError.message ?? '';
	const lower = raw.toLowerCase();
	const code = (otpError.code ?? '').toLowerCase();
	if (code === 'otp_disabled' || lower.includes('signups not allowed for otp')) {
		return OTP_NO_ACCOUNT;
	}
	const usable =
		lower.includes('company email') || lower.includes('personal or disposable')
			? raw
			: lower.includes('invalid payload sent to hook')
				? COMPANY_EMAIL_REJECT
				: code.includes('rate_limit') || lower.includes('rate limit') || otpError.status === 429
					? OTP_RATE_LIMIT
					: raw;
	const status = otpError.status != null ? String(otpError.status) : '';
	const shownCode = otpError.code ? String(otpError.code) : '';
	return [status, shownCode, usable].filter(Boolean).join(' — ');
}
