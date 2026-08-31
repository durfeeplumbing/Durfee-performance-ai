import { redirect } from 'next/navigation';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';
import { serviceTitanConfigured } from '@/lib/servicetitan';
import { syncServiceTitanCrmData, syncServiceTitanReferenceData } from './actions';

function when(value?: string | null) {
  return value ? new Date(value).toLocaleString('en-US', { timeZone: 'America/New_York' }) : 'Never';
}

export default async function ServiceTitanIntegrationPage() {
  const me = await requireCurrentUser();
  if (me.role !== 'owner') redirect('/dashboard');
  const supabase = await createSupabaseServerClient();

  const [stateResult, techCountResult, buCountResult, customerCountResult, locationCountResult, runsResult] = await Promise.all([
    supabase.from('service_titan_integration_state').select('*').maybeSingle(),
    supabase.from('service_titan_records').select('id', { count: 'exact', head: true }).eq('resource', 'technicians'),
    supabase.from('service_titan_records').select('id', { count: 'exact', head: true }).eq('resource', 'business_units'),
    supabase.from('service_titan_records').select('id', { count: 'exact', head: true }).eq('resource', 'customers'),
    supabase.from('service_titan_records').select('id', { count: 'exact', head: true }).eq('resource', 'locations'),
    supabase.from('service_titan_sync_runs').select('id,resource,status,records_seen,records_upserted,error,started_at,completed_at').order('started_at', { ascending: false }).limit(15),
  ]);

  const state = stateResult.data as any;
  const runs = (runsResult.data ?? []) as any[];
  const configured = serviceTitanConfigured();

  return <main>
    <h1>ServiceTitan Integration</h1>
    <p>Production connector status and controlled read-only synchronization. Durfee AI does not write changes back to ServiceTitan from this screen.</p>

    <section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(180px,1fr))',gap:12,margin:'20px 0'}}>
      <div className="card"><strong>Credentials</strong><div>{configured ? 'Configured' : 'Missing'}</div></div>
      <div className="card"><strong>Environment</strong><div>{state?.environment ?? 'production'}</div></div>
      <div className="card"><strong>Technicians cached</strong><div>{techCountResult.count ?? 0}</div></div>
      <div className="card"><strong>Business units cached</strong><div>{buCountResult.count ?? 0}</div></div>
      <div className="card"><strong>Customers cached</strong><div>{customerCountResult.count ?? 0}</div></div>
      <div className="card"><strong>Locations cached</strong><div>{locationCountResult.count ?? 0}</div></div>
      <div className="card"><strong>Last successful sync</strong><div>{when(state?.last_successful_sync)}</div></div>
    </section>

    <div style={{display:'flex',gap:12,flexWrap:'wrap',marginBottom:24}}>
      <form action={syncServiceTitanReferenceData}><button type="submit">Sync technicians + business units</button></form>
      <form action={syncServiceTitanCrmData}><button type="submit">Sync customers + locations</button></form>
      <a href="/api/servicetitan/test" target="_blank" rel="noreferrer">Test connection</a>
    </div>

    <p><small>CRM sync currently stages ServiceTitan customer and location records for comparison before anything is mapped into Durfee AI customer records.</small></p>

    <h2>Recent syncs</h2>
    {runs.length === 0 ? <p>No syncs recorded yet.</p> : <div style={{overflowX:'auto'}}><table><thead><tr><th>Resource</th><th>Status</th><th>Seen</th><th>Saved</th><th>Started</th><th>Error</th></tr></thead><tbody>
      {runs.map(run => <tr key={run.id}><td>{String(run.resource).replaceAll('_',' ')}</td><td>{run.status}</td><td>{run.records_seen}</td><td>{run.records_upserted}</td><td>{when(run.started_at)}</td><td>{run.error ?? ''}</td></tr>)}
    </tbody></table></div>}
  </main>;
}
