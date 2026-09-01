'use server';

import { revalidatePath } from 'next/cache';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';

const allowedStatuses = new Set(['not_started','testing','parallel','ready','blocked']);

export async function updateMigrationReadiness(formData: FormData) {
  const user = await requireCurrentUser();
  if (user.role !== 'owner') throw new Error('Owner access required');

  const moduleKey = String(formData.get('module_key') ?? '');
  const status = String(formData.get('status') ?? 'not_started');
  if (!moduleKey || !allowedStatuses.has(status)) throw new Error('Invalid migration readiness update');

  const testsPassed = Math.max(0, Number(formData.get('tests_passed') ?? 0) || 0);
  const testsFailed = Math.max(0, Number(formData.get('tests_failed') ?? 0) || 0);
  const openMismatches = Math.max(0, Number(formData.get('open_mismatches') ?? 0) || 0);
  const notes = String(formData.get('notes') ?? '').trim().slice(0, 4000) || null;
  const servicetitanDependency = formData.get('servicetitan_dependency') === 'on';

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase
    .from('migration_readiness_checks')
    .update({
      status,
      tests_passed: testsPassed,
      tests_failed: testsFailed,
      open_mismatches: openMismatches,
      notes,
      servicetitan_dependency: servicetitanDependency,
    })
    .eq('module_key', moduleKey);

  if (error) throw new Error(error.message);
  revalidatePath('/settings/migration-readiness');
  revalidatePath('/dashboard');
}
