import { redirect } from 'next/navigation';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';
import { serviceTitanConfigured } from '@/lib/servicetitan';
import ServiceTitanSyncForm from './sync-form';
import { refreshServiceTitanCustomerMappings, syncServiceTitanCrmData, syncServiceTitanFinancialData, syncServiceTitanJobsData, syncServiceTitanReferenceData } from './actions';

function when(value?: string | null) { return value ? new Date(value).toLocaleString('en-US', { timeZone: 'America/New_York' }) : 'Never'; }

export default async function ServiceTitanIntegrationPage() {
  const me = await requireCurrentUser(); if (me.role !== 'owner') redirect('/dashboard');
  const supabase = await createSupabaseServerClient();
  const resources = ['technicians','business_units','customers','locations','jobs','appointments','invoices','payments','memberships'] as const;
  const [stateResult, runsResult, mappingsResult, ...counts] = await Promise.all([
    supabase.from('service_titan_integration_state').select('*').maybeSingle(),
    supabase.from('service_titan_sync_runs').select('id,resource,status,records_seen,records_upserted,error,started_at,completed_at').order('started_at', { ascending: false }).limit(25),
    supabase.from('service_titan_record_mappings').select('match_status').eq('resource','customers'),
    ...resources.map(resource => supabase.from('service_titan_records').select('id', { count: 'exact', head: true }).eq('resource', resource)),
  ]);
  const state = stateResult.data as any; const runs = (runsResult.data ?? []) as any[];
  const countByResource = Object.fromEntries(resources.map((resource, index) => [resource, counts[index]?.count ?? 0]));
  const mappingCounts = (mappingsResult.data ?? []).reduce((acc: Record<string,number>, row: any) => { acc[row.match_status] = (acc[row.match_status] ?? 0) + 1; return acc; }, {});
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
    <div style={{display:'flex',gap:12,flexWrap:'wrap',marginBottom:24,alignItems:'flex-start'}}>
      <ServiceTitanSyncForm
        action={syncServiceTitanReferenceData}
        idleLabel="Sync technicians + business units"
        pendingLabel="Syncing technicians + business units…"
        successTitle="Reference sync complete"
        successMessage="Technicians and business units are up to date."
      />
      <ServiceTitanSyncForm
        action={syncServiceTitanCrmData}
        idleLabel="Sync customers + locations"
        pendingLabel="Syncing customers + locations…"
        successTitle="Customer sync complete"
        successMessage="Customers and locations are up to date."
      />
      <ServiceTitanSyncForm
        action={syncServiceTitanJobsData}
        idleLabel="Sync jobs + appointments"
        pendingLabel="Syncing jobs + appointments…"
        successTitle="Jobs sync complete"
        successMessage="Jobs and appointments are up to date."
      />
      <ServiceTitanSyncForm
        action={syncServiceTitanFinancialData}
        idleLabel="Sync invoices + payments + memberships"
        pendingLabel="Syncing financial data…"
        successTitle="Financial sync complete"
        successMessage="Invoices, payments, and memberships are up to date."
      />
      <a href="/api/servicetitan/test" target="_blank" rel="noreferrer">Test connection</a>
    </div>
    <p><small>Each sync now refreshes this page automatically when it finishes and displays a confirmation screen. The cached totals and Recent syncs section below update without a manual reload.</small></p>
    <h2>Customer mapping review</h2>
    <p>Generate conservative match candidates against existing Durfee AI customers using normalized email and phone. Nothing is merged or created by this action.</p>
    <div style={{display:'flex',gap:12,flexWrap:'wrap',margin:'12px 0 24px',alignItems:'flex-start'}}>
      <div className="card"><strong>Unmatched</strong><div>{mappingCounts.unmatched ?? 0}</div></div>
      <div className="card"><strong>Candidates</strong><div>{mappingCounts.candidate ?? 0}</div></div>
      <div className="card"><strong>Conflicts</strong><div>{mappingCounts.conflict ?? 0}</div></div>
      <div className="card"><strong>Matched</strong><div>{mappingCounts.matched ?? 0}</div></div>
      <ServiceTitanSyncForm
        action={refreshServiceTitanCustomerMappings}
        idleLabel="Refresh customer match candidates"
        pendingLabel="Refreshing matches…"
        successTitle="Customer matches refreshed"
        successMessage="The customer matching review has been updated."
      />
    </div>
    <p><small>All ServiceTitan imports on this page are staged read-only for comparison before records are mapped into Durfee AI operational tables.</small></p>
    <h2>Recent syncs</h2>
    {runs.length === 0 ? <p>No syncs recorded yet.</p> : <div style={{overflowX:'auto'}}><table><thead><tr><th>Resource</th><th>Status</th><th>Seen</th><th>Saved</th><th>Started</th><th>Error</th></tr></thead><tbody>
      {runs.map(run => <tr key={run.id}><td>{String(run.resource).replaceAll('_',' ')}</td><td>{run.status}</td><td>{run.records_seen}</td><td>{run.records_upserted}</td><td>{when(run.started_at)}</td><td>{run.error ?? ''}</td></tr>)}
    </tbody></table></div>}
  </main>;
}
