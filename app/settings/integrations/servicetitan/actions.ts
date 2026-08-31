'use server';

import { revalidatePath } from 'next/cache';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { serviceTitanConnectionInfo, serviceTitanGetAll } from '@/lib/servicetitan';

async function ownerClient() {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Authentication required');
  const { data: allowed, error: permissionError } = await supabase.rpc('has_permission_for_current_user', { p_key: 'manage_permissions' });
  if (permissionError || allowed !== true) throw new Error('Owner permission required');
  return supabase;
}

async function saveResource(supabase: Awaited<ReturnType<typeof ownerClient>>, resource: string, records: unknown[], info: ReturnType<typeof serviceTitanConnectionInfo>) {
  const { error } = await supabase.rpc('upsert_service_titan_resource', { p_resource: resource, p_records: records, p_environment: info.environment, p_tenant_id: info.tenant });
  if (error) throw new Error(`${resource} sync failed: ${error.message}`);
}

export async function syncServiceTitanReferenceData() {
  const supabase = await ownerClient(); const info = serviceTitanConnectionInfo();
  const [technicians, businessUnits] = await Promise.all([
    serviceTitanGetAll('/settings/v2/tenant/{tenant}/technicians?active=Any'),
    serviceTitanGetAll('/settings/v2/tenant/{tenant}/business-units?active=Any'),
  ]);
  await saveResource(supabase, 'technicians', technicians, info); await saveResource(supabase, 'business_units', businessUnits, info);
  revalidatePath('/settings/integrations/servicetitan');
}

export async function syncServiceTitanCrmData() {
  const supabase = await ownerClient(); const info = serviceTitanConnectionInfo();
  const customers = await serviceTitanGetAll('/crm/v2/tenant/{tenant}/customers'); await saveResource(supabase, 'customers', customers, info);
  const locations = await serviceTitanGetAll('/crm/v2/tenant/{tenant}/locations'); await saveResource(supabase, 'locations', locations, info);
  revalidatePath('/settings/integrations/servicetitan');
}

export async function syncServiceTitanJobsData() {
  const supabase = await ownerClient(); const info = serviceTitanConnectionInfo();
  const jobs = await serviceTitanGetAll('/jpm/v2/tenant/{tenant}/jobs'); await saveResource(supabase, 'jobs', jobs, info);
  const appointments = await serviceTitanGetAll('/jpm/v2/tenant/{tenant}/appointments'); await saveResource(supabase, 'appointments', appointments, info);
  revalidatePath('/settings/integrations/servicetitan');
}

export async function syncServiceTitanFinancialData() {
  const supabase = await ownerClient(); const info = serviceTitanConnectionInfo();
  const invoices = await serviceTitanGetAll('/accounting/v2/tenant/{tenant}/invoices'); await saveResource(supabase, 'invoices', invoices, info);
  const payments = await serviceTitanGetAll('/accounting/v2/tenant/{tenant}/payments'); await saveResource(supabase, 'payments', payments, info);
  const memberships = await serviceTitanGetAll('/memberships/v2/tenant/{tenant}/memberships'); await saveResource(supabase, 'memberships', memberships, info);
  revalidatePath('/settings/integrations/servicetitan');
}

export async function refreshServiceTitanCustomerMappings() {
  const supabase = await ownerClient();
  const { error } = await supabase.rpc('refresh_service_titan_customer_mapping_candidates');
  if (error) throw new Error(`Customer mapping refresh failed: ${error.message}`);
  revalidatePath('/settings/integrations/servicetitan');
}
