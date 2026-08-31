'use server';

import { revalidatePath } from 'next/cache';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { serviceTitanConnectionInfo, serviceTitanGetAll } from '@/lib/servicetitan';

export async function syncServiceTitanReferenceData() {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Authentication required');
  const { data: allowed, error: permissionError } = await supabase.rpc('has_permission_for_current_user', { p_key: 'manage_permissions' });
  if (permissionError || allowed !== true) throw new Error('Owner permission required');

  const info = serviceTitanConnectionInfo();
  const [technicians, businessUnits] = await Promise.all([
    serviceTitanGetAll('/settings/v2/tenant/{tenant}/technicians?active=Any'),
    serviceTitanGetAll('/settings/v2/tenant/{tenant}/business-units?active=Any'),
  ]);

  const { error: technicianError } = await supabase.rpc('upsert_service_titan_resource', {
    p_resource: 'technicians', p_records: technicians, p_environment: info.environment, p_tenant_id: info.tenant,
  });
  if (technicianError) throw new Error(`Technician sync failed: ${technicianError.message}`);

  const { error: businessUnitError } = await supabase.rpc('upsert_service_titan_resource', {
    p_resource: 'business_units', p_records: businessUnits, p_environment: info.environment, p_tenant_id: info.tenant,
  });
  if (businessUnitError) throw new Error(`Business unit sync failed: ${businessUnitError.message}`);

  revalidatePath('/settings/integrations/servicetitan');
}
