import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { COMPANY_EMAIL_REJECT, formatSignInOtpError, OTP_NO_ACCOUNT, OTP_RATE_LIMIT } from './errors.ts';

describe('formatSignInOtpError', () => {
	it('keeps the hook company-email message', () => {
		assert.equal(
			formatSignInOtpError({ status: 400, message: COMPANY_EMAIL_REJECT }),
			`400 — ${COMPANY_EMAIL_REJECT}`
		);
	});

	it('replaces the generic hook payload error', () => {
		assert.equal(
			formatSignInOtpError({ status: 400, message: 'Invalid payload sent to hook' }),
			`400 — ${COMPANY_EMAIL_REJECT}`
		);
	});

	it('maps missing-user OTP signup blocks to a no-account message', () => {
		assert.equal(
			formatSignInOtpError({
				status: 422,
				code: 'otp_disabled',
				message: 'Signups not allowed for otp'
			}),
			OTP_NO_ACCOUNT
		);
	});

	it('maps Auth rate limits to a wait message', () => {
		assert.equal(
			formatSignInOtpError({ status: 429, code: 'over_email_send_rate_limit', message: 'rate' }),
			`429 — over_email_send_rate_limit — ${OTP_RATE_LIMIT}`
		);
	});
});
