'use server';

import { revalidatePath } from 'next/cache';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { serviceTitanConnectionInfo, serviceTitanPages } from '@/lib/servicetitan';

const STAGING_BATCH_SIZE = 100;
const MIN_SPLIT_BATCH_SIZE = 25;
const TRANSIENT_RETRY_DELAYS_MS = [500, 1500];

type OwnerSupabase = Awaited<ReturnType<typeof ownerClient>>;
type SyncInfo = ReturnType<typeof serviceTitanConnectionInfo>;

async function ownerClient() {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Authentication required');
  const { data: allowed, error: permissionError } = await supabase.rpc('has_permission_for_current_user', { p_key: 'manage_permissions' });
  if (permissionError || allowed !== true) throw new Error('Owner permission required');
  return supabase;
}

const wait = (ms:number) => new Promise(resolve => setTimeout(resolve, ms));

function transientSyncError(message:string) {
  const m=message.toLowerCase();
  return m.includes('statement timeout') || m.includes('canceling statement') || m.includes('520') || m.includes('gateway') || m.includes('fetch failed') || m.includes('network');
}

async function rpcResourceBatch(supabase: OwnerSupabase, resource: string, records: unknown[], info: SyncInfo) {
  const { error } = await supabase.rpc('upsert_service_titan_resource', { p_resource: resource, p_records: records, p_environment: info.environment, p_tenant_id: info.tenant });
  return error?.message ?? null;
}

async function saveResourceBatch(supabase: OwnerSupabase, resource: string, records: unknown[], info: SyncInfo, offset: number):Promise<void> {
  let lastError:string|null=null;
  for(let attempt=0;attempt<=TRANSIENT_RETRY_DELAYS_MS.length;attempt++){
    lastError=await rpcResourceBatch(supabase,resource,records,info);
    if(!lastError)return;
    if(!transientSyncError(lastError))break;
    if(attempt<TRANSIENT_RETRY_DELAYS_MS.length)await wait(TRANSIENT_RETRY_DELAYS_MS[attempt]);
  }

  if(lastError&&transientSyncError(lastError)&&records.length>MIN_SPLIT_BATCH_SIZE){
    const midpoint=Math.ceil(records.length/2);
    const first=records.slice(0,midpoint),second=records.slice(midpoint);
    await saveResourceBatch(supabase,resource,first,info,offset);
    if(second.length)await saveResourceBatch(supabase,resource,second,info,offset+midpoint);
    return;
  }

  throw new Error(`${resource} sync failed at records ${offset + 1}-${offset + records.length}: ${lastError ?? 'Unknown staging error'}`);
}

async function syncPagedResource(supabase: OwnerSupabase, resource: string, path: string, info: SyncInfo) {
  let offset = 0;
  for await (const page of serviceTitanPages(path, STAGING_BATCH_SIZE)) {
    await saveResourceBatch(supabase, resource, page, info, offset);
    offset += page.length;
  }
  return offset;
}

async function refreshMappings(supabase: OwnerSupabase) {
  const { error } = await supabase.rpc('refresh_service_titan_customer_mapping_candidates');
  if (error) throw new Error(`Customer mapping refresh failed: ${error.message}`);
}

function revalidateServiceTitanViews() {
  ['/settings/integrations/servicetitan','/dashboard','/team','/customers','/accounting/receivables'].forEach(path=>revalidatePath(path));
}

async function syncOperationalResources(supabase: OwnerSupabase, info: SyncInfo) {
  await syncPagedResource(supabase, 'jobs', '/jpm/v2/tenant/{tenant}/jobs', info);
  await syncPagedResource(supabase, 'appointments', '/jpm/v2/tenant/{tenant}/appointments', info);
  await syncPagedResource(supabase, 'estimates', '/sales/v2/tenant/{tenant}/estimates?active=Any', info);
  await syncPagedResource(supabase, 'job_timesheets', '/payroll/v2/tenant/{tenant}/jobs/timesheets?active=Any', info);
  await syncPagedResource(supabase, 'job_splits', '/payroll/v2/tenant/{tenant}/jobs/splits?active=Any', info);
  await syncPagedResource(supabase, 'invoices', '/accounting/v2/tenant/{tenant}/invoices', info);
  await syncPagedResource(supabase, 'payments', '/accounting/v2/tenant/{tenant}/payments', info);
  await syncPagedResource(supabase, 'memberships', '/memberships/v2/tenant/{tenant}/memberships', info);
}

export async function syncServiceTitanDailyData() {
  const supabase = await ownerClient();
  const info = serviceTitanConnectionInfo();
  await syncOperationalResources(supabase, info);
  revalidateServiceTitanViews();
}

export async function syncServiceTitanAllData() {
  const supabase = await ownerClient();
  const info = serviceTitanConnectionInfo();
  await syncPagedResource(supabase, 'technicians', '/settings/v2/tenant/{tenant}/technicians?active=Any', info);
  await syncPagedResource(supabase, 'business_units', '/settings/v2/tenant/{tenant}/business-units?active=Any', info);
  await syncPagedResource(supabase, 'customers', '/crm/v2/tenant/{tenant}/customers', info);
  await syncPagedResource(supabase, 'locations', '/crm/v2/tenant/{tenant}/locations', info);
  await syncOperationalResources(supabase, info);
  await refreshMappings(supabase);
  revalidateServiceTitanViews();
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
  revalidatePath('/settings/integrations/servicetitan'); revalidatePath('/customers');
}

export async function syncServiceTitanJobsData() {
  const supabase = await ownerClient(); const info = serviceTitanConnectionInfo();
  await syncPagedResource(supabase, 'jobs', '/jpm/v2/tenant/{tenant}/jobs', info);
  await syncPagedResource(supabase, 'appointments', '/jpm/v2/tenant/{tenant}/appointments', info);
  revalidatePath('/settings/integrations/servicetitan'); revalidatePath('/dashboard'); revalidatePath('/team');
}

export async function syncServiceTitanEstimateData() {
  const supabase = await ownerClient(); const info = serviceTitanConnectionInfo();
  await syncPagedResource(supabase, 'estimates', '/sales/v2/tenant/{tenant}/estimates?active=Any', info);
  revalidatePath('/settings/integrations/servicetitan'); revalidatePath('/team'); revalidatePath('/dashboard');
}

export async function syncServiceTitanTechnicianPerformanceData() {
  const supabase = await ownerClient(); const info = serviceTitanConnectionInfo();
  await syncPagedResource(supabase, 'job_timesheets', '/payroll/v2/tenant/{tenant}/jobs/timesheets?active=Any', info);
  await syncPagedResource(supabase, 'job_splits', '/payroll/v2/tenant/{tenant}/jobs/splits?active=Any', info);
  revalidatePath('/settings/integrations/servicetitan'); revalidatePath('/team');
}

export async function syncServiceTitanFinancialData() {
  const supabase = await ownerClient(); const info = serviceTitanConnectionInfo();
  await syncPagedResource(supabase, 'invoices', '/accounting/v2/tenant/{tenant}/invoices', info);
  await syncPagedResource(supabase, 'payments', '/accounting/v2/tenant/{tenant}/payments', info);
  await syncPagedResource(supabase, 'memberships', '/memberships/v2/tenant/{tenant}/memberships', info);
  revalidatePath('/settings/integrations/servicetitan'); revalidatePath('/dashboard'); revalidatePath('/accounting/receivables');
}

export async function refreshServiceTitanCustomerMappings() {
  const supabase = await ownerClient();
  await refreshMappings(supabase);
  revalidatePath('/settings/integrations/servicetitan');
}
