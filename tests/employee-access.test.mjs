import assert from 'node:assert/strict';
import test from 'node:test';
import { employeeHome, resolvePermissions, validInviteToken } from '../lib/access-navigation.ts';

test('each employee starts in the workspace for their job', () => {
  const allowed = new Set(['view_dashboard', 'view_csr', 'field_app', 'view_customers', 'view_accounting']);
  const expected = {
    owner: '/dashboard', manager: '/dashboard', csr_dispatch: '/csr',
    technician: '/field', marketing: '/marketing', accounting: '/accounting/vendor-bills',
  };
  for (const [role, path] of Object.entries(expected)) assert.equal(employeeHome(role, allowed), path);
});

test('revoked field and dashboard access falls back to an allowed workspace', () => {
  const allowed = resolvePermissions([
    { permission_key: 'field_app', allowed: true },
    { permission_key: 'view_dashboard', allowed: true },
    { permission_key: 'view_jobs', allowed: true },
  ], [
    { permission_key: 'field_app', allowed: false },
    { permission_key: 'view_dashboard', allowed: false },
  ]);
  assert.equal(employeeHome('technician', allowed), '/jobs');
  assert.equal(allowed.has('field_app'), false);
  assert.equal(employeeHome('technician', new Set(['view_customers'])), '/customers');
});

test('personal grants and denials take precedence without changing role defaults', () => {
  const defaults = [{ permission_key: 'view_accounting', allowed: false }];
  const allowed = resolvePermissions(defaults, [{ permission_key: 'view_accounting', allowed: true }]);
  assert.equal(employeeHome('accounting', allowed), '/accounting/vendor-bills');
  assert.deepEqual(defaults, [{ permission_key: 'view_accounting', allowed: false }]);
});

test('no allowed workspace or unknown role never sends staff to the owner dashboard', () => {
  for (const role of ['manager', 'csr_dispatch', 'technician', 'marketing', 'accounting']) {
    assert.equal(employeeHome(role, new Set()), '/unauthorized');
  }
  for (const role of ['admin', 'toString', '__proto__', '']) {
    assert.equal(employeeHome(role, new Set(['view_dashboard'])), '/unauthorized');
  }
});

test('owner entry remains available independently of editable role grants', () => {
  assert.equal(employeeHome('owner', new Set()), '/dashboard');
});

test('invitation tokens cannot inject a path, query, or redirect', () => {
  assert.equal(validInviteToken('550e8400-e29b-41d4-a716-446655440000'), true);
  for (const token of ['', '../login', '//example.com', 'abc?next=https://example.com', '550e8400-e29b-41d4-a716-446655440000/extra']) {
    assert.equal(validInviteToken(token), false);
  }
});
