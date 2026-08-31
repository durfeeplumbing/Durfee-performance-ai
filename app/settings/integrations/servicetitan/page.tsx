import { redirect } from 'next/navigation';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';
import { serviceTitanConfigured } from '@/lib/servicetitan';
import ServiceTitanSyncForm from './sync-form';
import { refreshServiceTitanCustomerMappings, syncServiceTitanCrmData, syncServiceTitanFinancialData, syncServiceTitanJobsData, syncServiceTitanReferenceData } from './actions';

export const dynamic = 'force-dynamic';
export const revalidate = 0;

function when(value?: string | null) { return value ? new Date(value).toLocaleString('en-US', { timeZone: 'America/New_York' }) : 'Never'; }

export default async function ServiceTitanIntegrationPage() {
  const me = await requireCurrentUser(); if (me.role !== 'owner') redirect('/dashboard');
  const supabase = await createSupabaseServerClient();
  const resources = ['technicians','business_units','customers','locations','jobs','appointments','invoices','payments','memberships'] as const;
  const [stateResult, runsResult, mappingsResult, statusResult] = await Promise.all([
    supabase.from('service_titan_integration_state').select('*').maybeSingle(),
    supabase.from('service_titan_sync_runs').select('id,resource,status,records_seen,records_upserted,error,started_at,completed_at').order('started_at', { ascending: false }).limit(25),
    supabase.from('service_titan_record_mappings').select('match_status').eq('resource','customers'),
    supabase.rpc('service_titan_sync_status_summary'),
  ]);
  const state = stateResult.data as any; const runs = (runsResult.data ?? []) as any[];
  const status = (statusResult.data ?? {}) as any;
  const rawCounts = status?.counts ?? {};
  const countByResource = Object.fromEntries(resources.map(resource => [resource, Number(rawCounts[resource] ?? 0)]));
  const mappingCounts = (mappingsResult.data ?? []).reduce((acc: Record<string,number>, row: any) => { acc[row.match_status] = (acc[row.match_status] ?? 0) + 1; return acc; }, {});
  const configured = serviceTitanConfigured();
  const recentFailures = runs.filter(run => run.status === 'failed');
  const running = runs.filter(run => run.status === 'running');
  const loadedResources = resources.filter(resource => Number(countByResource[resource] ?? 0) > 0).length;
  const totalCached = Number(status?.totalCached ?? resources.reduce((sum, resource) => sum + Number(countByResource[resource] ?? 0), 0));
  const countError = statusResult.error?.message;
  const healthy = configured && loadedResources === resources.length && running.length === 0 && !state?.last_error && !countError;
  const healthLabel = healthy ? 'Healthy' : configured ? 'Attention needed' : 'Not configured';
  const healthColor = healthy ? '#067647' : configured ? '#b54708' : '#b42318';
  const healthBg = healthy ? '#ecfdf3' : configured ? '#fffaeb' : '#fef3f2';
  return <main>
    <h1>ServiceTitan Integration</h1>
    <p>Production connector status and controlled read-only synchronization. Durfee AI does not write changes back to ServiceTitan from this screen.</p>

    <section className="card" style={{margin:'20px 0',padding:20,border:`1px solid ${healthColor}`,background:healthBg}}>
      <div style={{display:'flex',justifyContent:'space-between',gap:16,alignItems:'center',flexWrap:'wrap'}}>
        <div><div style={{fontSize:13,fontWeight:700,textTransform:'uppercase',letterSpacing:'.05em'}}>System health</div><div style={{fontSize:28,fontWeight:800,color:healthColor}}>{healthy ? '✓ ' : '● '}{healthLabel}</div></div>
        <div style={{display:'grid',gridTemplateColumns:'repeat(4,minmax(120px,1fr))',gap:16,flex:'1 1 560px'}}>
          <div><strong>Connection</strong><div>{configured ? 'Connected' : 'Missing credentials'}</div></div>
          <div><strong>Data feeds loaded</strong><div>{loadedResources} / {resources.length}</div></div>
          <div><strong>Total cached records</strong><div>{totalCached.toLocaleString()}</div></div>
          <div><strong>Last successful sync</strong><div>{when(state?.last_successful_sync)}</div></div>
        </div>
      </div>
      <div style={{marginTop:14,fontSize:14}}>
        {running.length > 0 ? <span>{running.length} sync batch{running.length === 1 ? '' : 'es'} currently running. </span> : <span>No sync is currently running. </span>}
        {countError ? <span style={{color:'#b42318'}}>Status count error: {countError}</span> : state?.last_error ? <span style={{color:'#b42318'}}>Latest integration error: {state.last_error}</span> : <span style={{color:healthColor}}>No active integration error.</span>}
        {recentFailures.length > 0 ? <span> Historical failed batches remain visible below for audit history.</span> : null}
      </div>
    </section>

    <section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(180px,1fr))',gap:12,margin:'20px 0'}}>
      <div className="card"><strong>Credentials</strong><div>{configured ? 'Configured' : 'Missing'}</div></div>
      <div className="card"><strong>Environment</strong><div>{state?.environment ?? 'production'}</div></div>
      {resources.map(resource => <div className="card" key={resource}><strong>{resource.replaceAll('_',' ')} cached</strong><div>{Number(countByResource[resource]).toLocaleString()}</div></div>)}
      <div className="card"><strong>Last successful sync</strong><div>{when(state?.last_successful_sync)}</div></div>
    </section>
    <div style={{display:'flex',gap:12,flexWrap:'wrap',marginBottom:24,alignItems:'flex-start'}}>
      <ServiceTitanSyncForm action={syncServiceTitanReferenceData} idleLabel="Sync technicians + business units" pendingLabel="Syncing technicians + business units…" successTitle="Reference sync complete" successMessage="Technicians and business units are up to date." />
      <ServiceTitanSyncForm action={syncServiceTitanCrmData} idleLabel="Sync customers + locations" pendingLabel="Syncing customers + locations…" successTitle="Customer sync complete" successMessage="Customers and locations are up to date." />
      <ServiceTitanSyncForm action={syncServiceTitanJobsData} idleLabel="Sync jobs + appointments" pendingLabel="Syncing jobs + appointments…" successTitle="Jobs sync complete" successMessage="Jobs and appointments are up to date." />
      <ServiceTitanSyncForm action={syncServiceTitanFinancialData} idleLabel="Sync invoices + payments + memberships" pendingLabel="Syncing financial data…" successTitle="Financial sync complete" successMessage="Invoices, payments, and memberships are up to date." />
      <a href="/api/servicetitan/test" target="_blank" rel="noreferrer">Test connection</a>
    </div>
    <p><small>Each sync refreshes this page automatically when it finishes and displays a confirmation screen. Cached totals, system health, and Recent syncs update without a manual reload.</small></p>
    <h2>Customer mapping review</h2>
    <p>Generate conservative match candidates against existing Durfee AI customers using normalized email and phone. Nothing is merged or created by this action.</p>
    <div style={{display:'flex',gap:12,flexWrap:'wrap',margin:'12px 0 24px',alignItems:'flex-start'}}>
      <div className="card"><strong>Unmatched</strong><div>{mappingCounts.unmatched ?? 0}</div></div><div className="card"><strong>Candidates</strong><div>{mappingCounts.candidate ?? 0}</div></div><div className="card"><strong>Conflicts</strong><div>{mappingCounts.conflict ?? 0}</div></div><div className="card"><strong>Matched</strong><div>{mappingCounts.matched ?? 0}</div></div>
      <ServiceTitanSyncForm action={refreshServiceTitanCustomerMappings} idleLabel="Refresh customer match candidates" pendingLabel="Refreshing matches…" successTitle="Customer matches refreshed" successMessage="The customer matching review has been updated." />
    </div>
    <p><small>All ServiceTitan imports on this page are staged read-only for comparison before records are mapped into Durfee AI operational tables.</small></p>
    <h2>Recent syncs</h2>
    {runs.length === 0 ? <p>No syncs recorded yet.</p> : <div style={{overflowX:'auto'}}><table><thead><tr><th>Resource</th><th>Status</th><th>Seen</th><th>Saved</th><th>Started</th><th>Error</th></tr></thead><tbody>{runs.map(run => <tr key={run.id}><td>{String(run.resource).replaceAll('_',' ')}</td><td>{run.status}</td><td>{run.records_seen}</td><td>{run.records_upserted}</td><td>{when(run.started_at)}</td><td>{run.error ?? ''}</td></tr>)}</tbody></table></div>}
  </main>;
}
