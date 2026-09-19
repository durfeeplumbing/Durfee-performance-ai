import assert from 'node:assert/strict';
import test from 'node:test';
import { isPublicPage } from '../lib/public-routes.ts';

test('employee invites and customer approvals open without employee login', () => {
  for (const path of ['/login', '/unauthorized', '/join/test-token', '/approve/test-token', '/approve/test-token/complete']) {
    assert.equal(isPublicPage(path), true, path);
  }
});

test('private pages and misleading path prefixes still require login', () => {
  for (const path of ['/', '/dashboard', '/customers', '/jobs/123', '/billing', '/field', '/api/search', '/login-backup', '/login/private', '/join-admin', '/approval', '/approve', '/join']) {
    assert.equal(isPublicPage(path), false, path);
  }
});
