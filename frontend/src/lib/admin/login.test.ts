import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { isPlatformLoginEmail, PLATFORM_LOGIN_EMAIL } from './login.ts';

describe('platform login email', () => {
	it('accepts only admin@stufe7.com', () => {
		assert.equal(PLATFORM_LOGIN_EMAIL, 'admin@stufe7.com');
		assert.equal(isPlatformLoginEmail('admin@stufe7.com'), true);
		assert.equal(isPlatformLoginEmail('  Admin@Stufe7.com  '), true);
		assert.equal(isPlatformLoginEmail('marc@mmlogistix.com'), false);
	});
});
