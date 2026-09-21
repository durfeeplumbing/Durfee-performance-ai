import 'server-only';
import type { SessionUser } from './auth';
import { resolvePermissions } from './access-navigation';
import { createSupabaseServerClient } from './supabase/server';

export async function employeePermissions(user: SessionUser): Promise<Set<string>> {
  if (!user.active) return new Set();
  const supabase = await createSupabaseServerClient();
  if (user.role === 'owner') {
    const { data, error } = await supabase.from('permission_definitions').select('permission_key');
    if (error) throw new Error('Employee access could not be loaded. Please try again.');
    return new Set((data ?? []).map(row => row.permission_key));
  }
  const [roles, overrides] = await Promise.all([
    supabase.from('role_permissions').select('permission_key,allowed').eq('role', user.role),
    supabase.from('user_permission_overrides').select('permission_key,allowed').eq('user_id', user.id),
  ]);
  // A failed override lookup may hide an explicit denial, so fail closed.
  if (roles.error || overrides.error) throw new Error('Employee access could not be loaded. Please try again.');
  return resolvePermissions(roles.data ?? [], overrides.data ?? []);
}
