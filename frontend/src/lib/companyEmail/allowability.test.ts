import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { checkCompanyEmail, registrableEmailDomain } from './allowability.ts';

describe('company email allowability (UX pre-check)', () => {
	it('accepts a company domain', () => {
		const result = checkCompanyEmail('ada@acme.com');
		assert.equal(result.ok, true);
		if (result.ok) assert.equal(result.domain, 'acme.com');
	});

	it('rejects gmail', () => {
		const result = checkCompanyEmail('ada@gmail.com');
		assert.equal(result.ok, false);
	});

	it('normalizes case and whitespace', () => {
		assert.equal(registrableEmailDomain('  Ada@ACME.COM  '), 'acme.com');
	});

	it('rejects missing domain', () => {
		assert.equal(checkCompanyEmail('not-an-email').ok, false);
	});
});
