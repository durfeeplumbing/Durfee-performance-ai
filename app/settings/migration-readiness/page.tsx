import Link from 'next/link';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';
import { updateMigrationReadiness } from './actions';

const statusLabels: Record<string,string> = {
  not_started: 'Not started',
  testing: 'Testing',
  parallel: 'Parallel run',
  ready: 'Ready',
  blocked: 'Blocked',
};
const statusScores: Record<string,number> = { not_started: 0, testing: .35, parallel: .7, ready: 1, blocked: .1 };
const weights: Record<string,number> = { critical: 4, high: 3, medium: 2, low: 1 };

function formatDate(value?: string | null) {
  if (!value) return 'No target';
  return new Date(`${value}T12:00:00`).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'America/New_York' });
}

export default async function MigrationReadinessPage() {
  const user = await requireCurrentUser();
  if (user.role !== 'owner') return <main style={{fontFamily:'system-ui',maxWidth:900,margin:'auto',padding:32}}><h1>Owner access required</h1><p>This migration-readiness workspace is restricted to the owner.</p></main>;

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from('migration_readiness_checks')
    .select('*')
    .order('target_date', { ascending: true });

  const rows:any[] = error ? [] : (data ?? []);
  const totalWeight = rows.reduce((sum,r)=>sum+(weights[r.criticality]??1),0);
  const earned = rows.reduce((sum,r)=>{
    const base=(statusScores[r.status]??0)*(weights[r.criticality]??1);
    const penalty=Math.min(.5, Number(r.open_mismatches??0)*.05);
    return sum+Math.max(0,base*(1-penalty));
  },0);
  const score = totalWeight ? Math.round((earned/totalWeight)*100) : 0;
  const ready = rows.filter(r=>r.status==='ready').length;
  const blocked = rows.filter(r=>r.status==='blocked').length;
  const dependencies = rows.filter(r=>r.servicetitan_dependency).length;
  const failedTests = rows.reduce((s,r)=>s+Number(r.tests_failed??0),0);
  const mismatches = rows.reduce((s,r)=>s+Number(r.open_mismatches??0),0);
  const cutoff = new Date('2027-06-30T12:00:00-04:00').getTime();
  const daysLeft = Math.max(0, Math.ceil((cutoff-Date.now())/86400000));

  const summary=[
    ['Cutover readiness',`${score}%`,'Weighted by criticality, status and open mismatches'],
    ['Ready modules',`${ready}/${rows.length}`,'Must reach 100% on all critical workflows'],
    ['ST dependencies',String(dependencies),'Goal: zero operating dependencies before cutover'],
    ['Open mismatches',String(mismatches),'Native vs ServiceTitan differences still unresolved'],
    ['Failed tests',String(failedTests),'Failures should be fixed and retested, not ignored'],
    ['Runway',`${daysLeft} days`,'Through June 30, 2027'],
  ];

  return <main style={{fontFamily:'system-ui',maxWidth:1320,margin:'auto',padding:32}}>
    <header style={{display:'flex',justifyContent:'space-between',gap:20,alignItems:'flex-start',flexWrap:'wrap'}}>
      <div><p style={{fontWeight:800,letterSpacing:1}}>DURFEE PERFORMANCE AI</p><h1 style={{marginBottom:8}}>ServiceTitan Exit Readiness</h1><p style={{maxWidth:820}}>Run the FSM in parallel, record test results and mismatches, then remove ServiceTitan dependencies only after the native workflow proves reliable in real jobs.</p></div>
      <Link href="/dashboard">← Owner dashboard</Link>
    </header>

    {error?<article style={{border:'2px solid #b91c1c',borderRadius:16,padding:20,margin:'24px 0'}}><strong>Readiness data unavailable</strong><p>{error.message}</p></article>:null}

    <section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(190px,1fr))',gap:14,margin:'28px 0'}}>
      {summary.map(([label,value,detail])=><article key={label} style={{border:'1px solid #ddd',borderRadius:18,padding:18}}><small>{label}</small><h2 style={{margin:'8px 0'}}>{value}</h2><p style={{margin:0}}>{detail}</p></article>)}
    </section>

    <section style={{border:'1px solid #ddd',borderRadius:18,padding:20,marginBottom:28}}>
      <h2 style={{marginTop:0}}>Cutover rule</h2>
      <p>Do not cancel ServiceTitan because the overall percentage looks good. Every <b>critical</b> module should be marked Ready, open financial mismatches should be zero, backups/restores must be proven, and normal jobs should complete end-to-end without a ServiceTitan operational dependency.</p>
    </section>

    <section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(330px,1fr))',gap:16}}>
      {rows.map(row=><form key={row.module_key} action={updateMigrationReadiness} style={{border:'1px solid #ddd',borderRadius:18,padding:20}}>
        <input type="hidden" name="module_key" value={row.module_key}/>
        <div style={{display:'flex',justifyContent:'space-between',gap:12,alignItems:'flex-start'}}><div><small>{row.category} • {row.criticality}</small><h2 style={{fontSize:20,margin:'6px 0'}}>{row.module_name}</h2></div><strong>{statusLabels[row.status]??row.status}</strong></div>
        <p style={{marginTop:4}}>Target: {formatDate(row.target_date)}</p>
        <label style={{display:'block',margin:'12px 0'}}>Status<br/><select name="status" defaultValue={row.status} style={{width:'100%',padding:9,marginTop:5}}>{Object.entries(statusLabels).map(([value,label])=><option key={value} value={value}>{label}</option>)}</select></label>
        <div style={{display:'grid',gridTemplateColumns:'repeat(3,1fr)',gap:8}}>
          <label>Passed<input name="tests_passed" type="number" min="0" defaultValue={row.tests_passed} style={{width:'100%',padding:8,marginTop:5}}/></label>
          <label>Failed<input name="tests_failed" type="number" min="0" defaultValue={row.tests_failed} style={{width:'100%',padding:8,marginTop:5}}/></label>
          <label>Mismatches<input name="open_mismatches" type="number" min="0" defaultValue={row.open_mismatches} style={{width:'100%',padding:8,marginTop:5}}/></label>
        </div>
        <label style={{display:'flex',gap:8,alignItems:'center',margin:'14px 0'}}><input name="servicetitan_dependency" type="checkbox" defaultChecked={row.servicetitan_dependency}/> Still depends on ServiceTitan</label>
        <label style={{display:'block'}}>Notes<textarea name="notes" defaultValue={row.notes??''} rows={3} style={{width:'100%',padding:8,marginTop:5,resize:'vertical'}}/></label>
        <button type="submit" style={{marginTop:12,padding:'9px 14px',fontWeight:700}}>Save test status</button>
        <p><small>Updated {new Date(row.updated_at).toLocaleString('en-US',{timeZone:'America/New_York'})}</small></p>
      </form>)}
    </section>
  </main>;
}
