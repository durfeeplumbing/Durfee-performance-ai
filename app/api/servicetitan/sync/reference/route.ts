import { NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { serviceTitanConnectionInfo, serviceTitanGetAll } from '@/lib/servicetitan';

export const dynamic = 'force-dynamic';

async function requireOwner() {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { supabase, error: NextResponse.json({ ok: false, error: 'Authentication required' }, { status: 401 }) };
  const { data: allowed, error } = await supabase.rpc('has_permission_for_current_user', { p_key: 'manage_permissions' });
  if (error || allowed !== true) return { supabase, error: NextResponse.json({ ok: false, error: 'Owner permission required' }, { status: 403 }) };
  return { supabase, error: null };
}

export async function POST() {
  const { supabase, error } = await requireOwner();
  if (error) return error;

  try {
    const info = serviceTitanConnectionInfo();
    const [technicians, businessUnits] = await Promise.all([
      serviceTitanGetAll('/settings/v2/tenant/{tenant}/technicians?active=Any'),
      serviceTitanGetAll('/settings/v2/tenant/{tenant}/business-units?active=Any'),
    ]);

    const { data: technicianSync, error: technicianError } = await supabase.rpc('upsert_service_titan_resource', {
      p_resource: 'technicians',
      p_records: technicians,
      p_environment: info.environment,
      p_tenant_id: info.tenant,
    });
    if (technicianError) throw new Error(`Technician sync failed: ${technicianError.message}`);

    const { data: businessUnitSync, error: businessUnitError } = await supabase.rpc('upsert_service_titan_resource', {
      p_resource: 'business_units',
      p_records: businessUnits,
      p_environment: info.environment,
      p_tenant_id: info.tenant,
    });
    if (businessUnitError) throw new Error(`Business unit sync failed: ${businessUnitError.message}`);

    return NextResponse.json({
      ok: true,
      environment: info.environment,
      tenant: info.tenant,
      technicians: { fetched: technicians.length, sync: technicianSync },
      businessUnits: { fetched: businessUnits.length, sync: businessUnitSync },
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'ServiceTitan reference sync failed';
    return NextResponse.json({ ok: false, error: message }, { status: 502 });
  }
}
