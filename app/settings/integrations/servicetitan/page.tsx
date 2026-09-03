import { redirect } from 'next/navigation';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';
import { serviceTitanConfigured } from '@/lib/servicetitan';
import ServiceTitanSyncForm from './sync-form';
import { refreshServiceTitanCustomerMappings, syncServiceTitanAllData, syncServiceTitanCrmData, syncServiceTitanDailyData, syncServiceTitanEstimateData, syncServiceTitanFinancialData, syncServiceTitanJobsData, syncServiceTitanReferenceData, syncServiceTitanTechnicianPerformanceData } from './actions';

export const dynamic = 'force-dynamic';
export const revalidate = 0;
export const maxDuration = 300;

function when(value?: string | null) { return value ? new Date(value).toLocaleString('en-US', { timeZone: 'America/New_York' }) : 'Never'; }

export default async function ServiceTitanIntegrationPage() {
  const me = await requireCurrentUser(); if (me.role !== 'owner') redirect('/dashboard');
  const supabase = await createSupabaseServerClient();
  const resources = ['technicians','business_units','customers','locations','jobs','appointments','estimates','job_timesheets','job_splits','invoices','payments','memberships'] as const;
  const [stateResult, runsResult, mappingsResult, statusResult, incrementalResult, guardResult] = await Promise.all([
    supabase.from('service_titan_integration_state').select('*').maybeSingle(),
    supabase.from('service_titan_sync_runs').select('id,resource,status,records_seen,records_upserted,error,started_at,completed_at').order('started_at', { ascending: false }).limit(25),
    supabase.from('service_titan_record_mappings').select('match_status').eq('resource','customers'),
    supabase.rpc('service_titan_sync_status_summary'),
    supabase.from('service_titan_incremental_sync_state').select('resource,enabled,cursor_at,last_attempt_at,last_success_at,last_records_seen,last_error,consecutive_failures').order('resource'),
    supabase.from('service_titan_incremental_sync_guard').select('last_started_at,last_completed_at,last_status,last_error,lease_expires_at').maybeSingle(),
  ]);
  const state = stateResult.data as any; const runs = (runsResult.data ?? []) as any[];
  const status = (statusResult.data ?? {}) as any;
  const rawCounts = status?.counts ?? {};
  const countByResource = Object.fromEntries(resources.map(resource => [resource, Number(rawCounts[resource] ?? 0)]));
  const mappingCounts = (mappingsResult.data ?? []).reduce((acc: Record<string,number>, row: any) => { acc[row.match_status] = (acc[row.match_status] ?? 0) + 1; return acc; }, {});
  const configured = serviceTitanConfigured();
  const cronReady = Boolean(process.env.CRON_SECRET?.trim());
  const incremental = (incrementalResult.data ?? []) as any[];
  const guard = guardResult.data as any;
  const incrementalFailures = incremental.filter(row => row.last_error);
  const incrementalSuccesses = incremental.map(row=>row.last_success_at).filter(Boolean).map(value=>new Date(value).getTime());
  const oldestIncrementalSuccess = incrementalSuccesses.length ? Math.min(...incrementalSuccesses) : null;
  const newestIncrementalSuccess = incrementalSuccesses.length ? Math.max(...incrementalSuccesses) : null;
  const automaticFresh = oldestIncrementalSuccess !== null && Date.now()-oldestIncrementalSuccess < 25*60*1000;
  const automaticStatus = !cronReady ? 'Activation required' : incrementalFailures.length ? 'Attention needed' : automaticFresh ? 'Flowing' : 'Waiting for next run';
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
        {running.length > 0 ? <span>{running.length} sync batch{running.length === 1 ? '' : 'es'} currently running. </span> : <span>No manual sync is currently running. </span>}
        {countError ? <span style={{color:'#b42318'}}>Status count error: {countError}</span> : state?.last_error ? <span style={{color:'#b42318'}}>Latest integration error: {state.last_error}</span> : <span style={{color:healthColor}}>No active integration error.</span>}
        {recentFailures.length > 0 ? <span> Historical failed batches remain visible below for audit history.</span> : null}
      </div>
    </section>

    <section className="card" style={{padding:20,margin:'20px 0',border:'2px solid #222'}}>
      <h2 style={{marginTop:0}}>Continuous incremental sync</h2>
      <p>Durfee Performance now has a separate fast lane for records that changed in ServiceTitan. Vercel is scheduled to check every 10 minutes and each feed keeps its own cursor with a 10-minute safety overlap, so normal runs do not re-download the full historical database.</p>
      <div style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(180px,1fr))',gap:12,marginTop:16}}>
        <div className="card"><strong>Automatic sync</strong><div>{automaticStatus}</div></div>
        <div className="card"><strong>Schedule</strong><div>Every 10 minutes</div></div>
        <div className="card"><strong>Last automatic run</strong><div>{when(guard?.last_completed_at ?? guard?.last_started_at)}</div></div>
        <div className="card"><strong>Last feed update</strong><div>{newestIncrementalSuccess ? when(new Date(newestIncrementalSuccess).toISOString()) : 'Never'}</div></div>
        <div className="card"><strong>Feed errors</strong><div>{incrementalFailures.length}</div></div>
        <div className="card"><strong>Last run result</strong><div>{String(guard?.last_status ?? 'not run').replaceAll('_',' ')}</div></div>
      </div>
      {!cronReady ? <p style={{marginTop:14,color:'#b54708'}}><b>One activation item remains:</b> add a private <code>CRON_SECRET</code> environment variable in Vercel. Until it exists, the scheduled endpoint fails closed and makes no ServiceTitan requests.</p> : null}
      {incrementalFailures.length ? <div style={{marginTop:14}}><b>Feeds needing attention:</b> {incrementalFailures.map(row=><span key={row.resource} style={{display:'inline-block',marginLeft:8}}>{String(row.resource).replaceAll('_',' ')} ({row.consecutive_failures})</span>)}</div> : null}
      <div style={{overflowX:'auto',marginTop:16}}><table><thead><tr><th>Feed</th><th>Last success</th><th>Changed records</th><th>Cursor</th><th>Status</th></tr></thead><tbody>{incremental.map(row=><tr key={row.resource}><td>{String(row.resource).replaceAll('_',' ')}</td><td>{when(row.last_success_at)}</td><td>{Number(row.last_records_seen||0).toLocaleString()}</td><td>{when(row.cursor_at)}</td><td>{row.last_error ? `Error: ${row.last_error}` : row.last_success_at ? 'OK' : 'Waiting'}</td></tr>)}</tbody></table></div>
    </section>

    <section className="card" style={{padding:20,margin:'20px 0',border:'2px solid #222'}}>
      <h2 style={{marginTop:0}}>Manual synchronization</h2>
      <p>Use Daily Sync for a manual operational refresh. Full Sync also refreshes technicians, business units, customers, locations, and customer-match candidates.</p>
      <div style={{display:'flex',gap:12,flexWrap:'wrap',alignItems:'flex-start'}}>
        <ServiceTitanSyncForm action={syncServiceTitanDailyData} idleLabel="Run Daily ServiceTitan Sync" pendingLabel="Syncing daily operations…" successTitle="Daily ServiceTitan sync complete" successMessage="Jobs, appointments, estimates, technician activity, invoices, payments and memberships are up to date." />
        <ServiceTitanSyncForm action={syncServiceTitanAllData} idleLabel="Run Full ServiceTitan Sync" pendingLabel="Syncing all ServiceTitan data…" successTitle="Full ServiceTitan sync complete" successMessage="Reference, CRM, operating, estimate, technician, financial and customer-mapping feeds are up to date." />
      </div>
    </section>

    <section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(180px,1fr))',gap:12,margin:'20px 0'}}>
      <div className="card"><strong>Credentials</strong><div>{configured ? 'Configured' : 'Missing'}</div></div>
      <div className="card"><strong>Environment</strong><div>{state?.environment ?? 'production'}</div></div>
      {resources.map(resource => <div className="card" key={resource}><strong>{resource.replaceAll('_',' ')} cached</strong><div>{Number(countByResource[resource]).toLocaleString()}</div></div>)}
      <div className="card"><strong>Last successful sync</strong><div>{when(state?.last_successful_sync)}</div></div>
    </section>

    <details style={{marginBottom:24}}>
      <summary style={{cursor:'pointer',fontWeight:700}}>Individual sync controls</summary>
      <div style={{display:'flex',gap:12,flexWrap:'wrap',marginTop:14,alignItems:'flex-start'}}>
        <ServiceTitanSyncForm action={syncServiceTitanReferenceData} idleLabel="Sync technicians + business units" pendingLabel="Syncing technicians + business units…" successTitle="Reference sync complete" successMessage="Technicians and business units are up to date." />
        <ServiceTitanSyncForm action={syncServiceTitanCrmData} idleLabel="Sync customers + locations" pendingLabel="Syncing customers + locations…" successTitle="Customer sync complete" successMessage="Customers and locations are up to date." />
        <ServiceTitanSyncForm action={syncServiceTitanJobsData} idleLabel="Sync jobs + appointments" pendingLabel="Syncing jobs + appointments…" successTitle="Jobs sync complete" successMessage="Jobs and appointments are up to date." />
        <ServiceTitanSyncForm action={syncServiceTitanEstimateData} idleLabel="Sync estimates" pendingLabel="Syncing estimates…" successTitle="Estimate sync complete" successMessage="Estimate status, sold date and sold-by attribution are up to date." />
        <ServiceTitanSyncForm action={syncServiceTitanTechnicianPerformanceData} idleLabel="Sync technician activity" pendingLabel="Syncing technician activity…" successTitle="Technician activity sync complete" successMessage="Timesheets and job splits are up to date." />
        <ServiceTitanSyncForm action={syncServiceTitanFinancialData} idleLabel="Sync invoices + payments + memberships" pendingLabel="Syncing financial data…" successTitle="Financial sync complete" successMessage="Invoices, payments, and memberships are up to date." />
        <a href="/api/servicetitan/test" target="_blank" rel="noreferrer">Test connection</a>
      </div>
    </details>

    <p><small>The continuous fast lane currently covers customers, locations, jobs, appointments, estimates, invoices, payments and memberships using ServiceTitan's modified-date filters. Reference data and technician payroll activity remain on the controlled manual/full-sync path until their incremental behavior is separately validated.</small></p>
    <p><small>The estimate feed requires the ServiceTitan app scope <b>Sales &amp; Estimates → Estimates (Read)</b>. All ServiceTitan sync is read-only from the ServiceTitan side.</small></p>
    <h2>Customer mapping review</h2>
    <p>Generate conservative match candidates against existing Durfee AI customers using normalized email and phone. Nothing is merged or created by this action.</p>
    <div style={{display:'flex',gap:12,flexWrap:'wrap',margin:'12px 0 24px',alignItems:'flex-start'}}>
      <div className="card"><strong>Unmatched</strong><div>{mappingCounts.unmatched ?? 0}</div></div><div className="card"><strong>Candidates</strong><div>{mappingCounts.candidate ?? 0}</div></div><div className="card"><strong>Conflicts</strong><div>{mappingCounts.conflict ?? 0}</div></div><div className="card"><strong>Matched</strong><div>{mappingCounts.matched ?? 0}</div></div>
      <ServiceTitanSyncForm action={refreshServiceTitanCustomerMappings} idleLabel="Refresh customer match candidates" pendingLabel="Refreshing matches…" successTitle="Customer matches refreshed" successMessage="The customer matching review has been updated." />
    </div>
    <p><small>ServiceTitan imports are staged read-only for comparison before records are mapped into Durfee AI operational tables.</small></p>
    <h2>Recent syncs</h2>
    {runs.length === 0 ? <p>No syncs recorded yet.</p> : <div style={{overflowX:'auto'}}><table><thead><tr><th>Resource</th><th>Status</th><th>Seen</th><th>Saved</th><th>Started</th><th>Error</th></tr></thead><tbody>{runs.map(run => <tr key={run.id}><td>{String(run.resource).replaceAll('_',' ')}</td><td>{run.status}</td><td>{run.records_seen}</td><td>{run.records_upserted}</td><td>{when(run.started_at)}</td><td>{run.error ?? ''}</td></tr>)}</tbody></table></div>}
  </main>;
}
