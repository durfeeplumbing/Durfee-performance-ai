import type { Role } from './roles';

export type PermissionRow = { permission_key: string; allowed: boolean };

/** Same precedence as private.has_permission: a personal override wins. */
export function resolvePermissions(roleRows: PermissionRow[], overrides: PermissionRow[]) {
  const allowed = new Set(roleRows.filter(row => row.allowed).map(row => row.permission_key));
  for (const row of overrides) {
    if (row.allowed) allowed.add(row.permission_key);
    else allowed.delete(row.permission_key);
  }
  return allowed;
}

const destinations = [
  ['/dashboard', 'view_dashboard'], ['/field', 'field_app'],
  ['/csr', 'view_csr'], ['/dispatch', 'view_dispatch'],
  ['/schedule', 'view_schedule'],
  ['/accounting/vendor-bills', 'view_accounting'], ['/jobs', 'view_jobs'],
  ['/customers', 'view_customers'], ['/marketing', 'view_customers'], ['/estimates', 'view_estimates'],
  ['/billing', 'view_billing'], ['/pricebook', 'view_pricebook'],
  ['/inventory', 'view_inventory'], ['/reports/daily', 'view_reports'],
  ['/team', 'view_team'], ['/purchasing', 'view_purchasing'],
  ['/opportunities', 'view_opportunities'], ['/staging', 'view_staging'],
] as const;

const preferredHome: Record<Role, string> = {
  owner: '/dashboard', manager: '/dashboard', csr_dispatch: '/csr',
  technician: '/field', marketing: '/marketing', accounting: '/accounting/vendor-bills',
};

/** Navigation never grants access; middleware and database policies still enforce it. */
export function employeeHome(role: string, allowed: ReadonlySet<string>): string {
  if (!Object.hasOwn(preferredHome, role)) return '/unauthorized';
  if (role === 'owner') return '/dashboard';
  const preferred = preferredHome[role as Role];
  const ordered = [...destinations.filter(([path]) => path === preferred), ...destinations];
  return ordered.find(([, permission]) => allowed.has(permission))?.[0] ?? '/unauthorized';
}

export function validInviteToken(token: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(token);
}
