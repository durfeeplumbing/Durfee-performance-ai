'use server';

import { revalidatePath } from 'next/cache';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { serviceTitanConnectionInfo, serviceTitanPages } from '@/lib/servicetitan';

const STAGING_BATCH_SIZE = 200;

async function ownerClient() {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Authentication required');
  const { data: allowed, error: permissionError } = await supabase.rpc('has_permission_for_current_user', { p_key: 'manage_permissions' });
  if (permissionError || allowed !== true) throw new Error('Owner permission required');
  return supabase;
}

async function saveResourceBatch(supabase: Awaited<ReturnType<typeof ownerClient>>, resource: string, records: unknown[], info: ReturnType<typeof serviceTitanConnectionInfo>, offset: number) {
  const { error } = await supabase.rpc('upsert_service_titan_resource', {
    p_resource: resource,
    p_records: records,
    p_environment: info.environment,
    p_tenant_id: info.tenant,
  });
  if (error) throw new Error(`${resource} sync failed at records ${offset + 1}-${offset + records.length}: ${error.message}`);
}

async function syncPagedResource(supabase: Awaited<ReturnType<typeof ownerClient>>, resource: string, path: string, info: ReturnType<typeof serviceTitanConnectionInfo>) {
  let offset = 0;
  for await (const page of serviceTitanPages(path, STAGING_BATCH_SIZE)) {
    await saveResourceBatch(supabase, resource, page, info, offset);
    offset += page.length;
  }
  return offset;
}

export async function syncServiceTitanReferenceData() {
  const supabase = await ownerClient(); const info = serviceTitanConnectionInfo();
  await syncPagedResource(supabase, 'technicians', '/settings/v2/tenant/{tenant}/technicians?active=Any', info);
  await syncPagedResource(supabase, 'business_units', '/settings/v2/tenant/{tenant}/business-units?active=Any', info);
  revalidatePath('/settings/integrations/servicetitan');
}

export async function syncServiceTitanCrmData() {
  const supabase = await ownerClient(); const info = serviceTitanConnectionInfo();
  await syncPagedResource(supabase, 'customers', '/crm/v2/tenant/{tenant}/customers', info);
  await syncPagedResource(supabase, 'locations', '/crm/v2/tenant/{tenant}/locations', info);
  revalidatePath('/settings/integrations/servicetitan');
  revalidatePath('/customers');
}

export async function syncServiceTitanJobsData() {
  const supabase = await ownerClient(); const info = serviceTitanConnectionInfo();
  await syncPagedResource(supabase, 'jobs', '/jpm/v2/tenant/{tenant}/jobs', info);
  await syncPagedResource(supabase, 'appointments', '/jpm/v2/tenant/{tenant}/appointments', info);
  revalidatePath('/settings/integrations/servicetitan');
  revalidatePath('/dashboard');
  revalidatePath('/team');
}

export async function syncServiceTitanFinancialData() {
  const supabase = await ownerClient(); const info = serviceTitanConnectionInfo();
  await syncPagedResource(supabase, 'invoices', '/accounting/v2/tenant/{tenant}/invoices', info);
  await syncPagedResource(supabase, 'payments', '/accounting/v2/tenant/{tenant}/payments', info);
  await syncPagedResource(supabase, 'memberships', '/memberships/v2/tenant/{tenant}/memberships', info);
  revalidatePath('/settings/integrations/servicetitan');
  revalidatePath('/dashboard');
  revalidatePath('/accounting/receivables');
}

export async function refreshServiceTitanCustomerMappings() {
  const supabase = await ownerClient();
  const { error } = await supabase.rpc('refresh_service_titan_customer_mapping_candidates');
  if (error) throw new Error(`Customer mapping refresh failed: ${error.message}`);
  revalidatePath('/settings/integrations/servicetitan');
}
