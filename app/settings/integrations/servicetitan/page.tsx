import { redirect } from 'next/navigation';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';
import { serviceTitanConfigured } from '@/lib/servicetitan';
import { syncServiceTitanCrmData, syncServiceTitanFinancialData, syncServiceTitanJobsData, syncServiceTitanReferenceData } from './actions';

function when(value?: string | null) { return value ? new Date(value).toLocaleString('en-US', { timeZone: 'America/New_York' }) : 'Never'; }

export default async function ServiceTitanIntegrationPage() {
  const me = await requireCurrentUser(); if (me.role !== 'owner') redirect('/dashboard');
  const supabase = await createSupabaseServerClient();
  const resources = ['technicians','business_units','customers','locations','jobs','appointments','invoices','payments','memberships'] as const;
  const [stateResult, runsResult, ...counts] = await Promise.all([
    supabase.from('service_titan_integration_state').select('*').maybeSingle(),
    supabase.from('service_titan_sync_runs').select('id,resource,status,records_seen,records_upserted,error,started_at,completed_at').order('started_at', { ascending: false }).limit(25),
    ...resources.map(resource => supabase.from('service_titan_records').select('id', { count: 'exact', head: true }).eq('resource', resource)),
  ]);
  const state = stateResult.data as any; const runs = (runsResult.data ?? []) as any[];
  const countByResource = Object.fromEntries(resources.map((resource, index) => [resource, counts[index]?.count ?? 0]));
  const configured = serviceTitanConfigured();
  return <main>
    <h1>ServiceTitan Integration</h1>
    <p>Production connector status and controlled read-only synchronization. Durfee AI does not write changes back to ServiceTitan from this screen.</p>
    <section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(180px,1fr))',gap:12,margin:'20px 0'}}>
      <div className="card"><strong>Credentials</strong><div>{configured ? 'Configured' : 'Missing'}</div></div>
      <div className="card"><strong>Environment</strong><div>{state?.environment ?? 'production'}</div></div>
      {resources.map(resource => <div className="card" key={resource}><strong>{resource.replaceAll('_',' ')} cached</strong><div>{countByResource[resource]}</div></div>)}
      <div className="card"><strong>Last successful sync</strong><div>{when(state?.last_successful_sync)}</div></div>
    </section>
    <div style={{display:'flex',gap:12,flexWrap:'wrap',marginBottom:24}}>
      <form action={syncServiceTitanReferenceData}><button type="submit">Sync technicians + business units</button></form>
      <form action={syncServiceTitanCrmData}><button type="submit">Sync customers + locations</button></form>
      <form action={syncServiceTitanJobsData}><button type="submit">Sync jobs + appointments</button></form>
      <form action={syncServiceTitanFinancialData}><button type="submit">Sync invoices + payments + memberships</button></form>
      <a href="/api/servicetitan/test" target="_blank" rel="noreferrer">Test connection</a>
    </div>
    <p><small>All ServiceTitan imports on this page are staged read-only for comparison before records are mapped into Durfee AI operational tables.</small></p>
    <h2>Recent syncs</h2>
    {runs.length === 0 ? <p>No syncs recorded yet.</p> : <div style={{overflowX:'auto'}}><table><thead><tr><th>Resource</th><th>Status</th><th>Seen</th><th>Saved</th><th>Started</th><th>Error</th></tr></thead><tbody>
      {runs.map(run => <tr key={run.id}><td>{String(run.resource).replaceAll('_',' ')}</td><td>{run.status}</td><td>{run.records_seen}</td><td>{run.records_upserted}</td><td>{when(run.started_at)}</td><td>{run.error ?? ''}</td></tr>)}
    </tbody></table></div>}
  </main>;
}
