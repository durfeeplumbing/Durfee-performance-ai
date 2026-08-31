import { NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { testServiceTitanConnection } from '@/lib/servicetitan';

export const dynamic = 'force-dynamic';

export async function GET() {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ ok: false, error: 'Authentication required' }, { status: 401 });

  const { data: allowed, error: permissionError } = await supabase.rpc('has_permission_for_current_user', { p_key: 'manage_permissions' });
  if (permissionError || allowed !== true) return NextResponse.json({ ok: false, error: 'Owner permission required' }, { status: 403 });

  try {
    const result = await testServiceTitanConnection();
    return NextResponse.json({ ok: result.oauth && result.apiReachable, ...result });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'ServiceTitan connection test failed';
    return NextResponse.json({ ok: false, error: message }, { status: 502 });
  }
}
