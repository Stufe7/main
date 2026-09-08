import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { COMPANY_EMAIL_REJECT, formatSignInOtpError } from './errors.ts';

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
});
