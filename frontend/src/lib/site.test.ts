import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { hostIsAdmin, originHost, requestHost } from './site.ts';

describe('admin host', () => {
	it('matches admin.stufe7.com only when the public origin is set', () => {
		assert.equal(hostIsAdmin('admin.stufe7.com', 'https://admin.stufe7.com'), true);
		assert.equal(hostIsAdmin('www.stufe7.com', 'https://admin.stufe7.com'), false);
		assert.equal(hostIsAdmin('admin.stufe7.com', ''), false);
	});

	it('strips ports and forwarded lists', () => {
		assert.equal(requestHost('admin.stufe7.com:443', 'localhost'), 'admin.stufe7.com');
		assert.equal(requestHost('admin.stufe7.com, www.stufe7.com', 'localhost'), 'admin.stufe7.com');
		assert.equal(originHost('https://admin.stufe7.com/'), 'admin.stufe7.com');
	});
});
