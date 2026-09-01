import Link from 'next/link';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';
import { recordCallback,reviewCallback } from './actions';
const money=new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:0});
const one=(v:any)=>Array.isArray(v)?v[0]:v;

export default async function CallbackPage(){
 const user=await requireCurrentUser();
 if(!['owner','manager'].includes(user.role))return <main style={{padding:32}}><h1>Callbacks & Comebacks</h1><p>Manager access required.</p></main>;
 const s=await createSupabaseServerClient();
 const [{data:queue,error},{data:jobs}]=await Promise.all([
   s.rpc('job_callback_management_queue'),
   s.from('jobs').select('id,status,completed_at,service_type,service_summary,customers(name,customer_code),users!jobs_technician_id_fkey(name)').order('created_at',{ascending:false}).limit(500)
 ]);
 const rows:any[]=Array.isArray(queue)?queue:[];
 const completed=(jobs??[]).filter((j:any)=>j.completed_at);
 const active=(jobs??[]).filter((j:any)=>!j.completed_at);
 const pending=rows.filter(r=>r.preventability==='pending');
 const preventable=rows.filter(r=>r.preventability==='preventable');
 const cost=rows.reduce((s,r)=>s+Number(r.callbackCost??0),0);
 return <main style={{fontFamily:'system-ui',maxWidth:1250,margin:'auto',padding:32}}>
  <div style={{display:'flex',justifyContent:'space-between',gap:12,flexWrap:'wrap'}}><div><h1>Callbacks & Comebacks</h1><p>Link every return visit to the original job and require manager review before it counts as preventable.</p></div><Link href="/team">Technician scorecards →</Link></div>
  {error&&<p role="alert">Callback records could not be loaded: {error.message}</p>}
  <section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(170px,1fr))',gap:12,margin:'22px 0'}}>{[['Callbacks',String(rows.length)],['Pending Review',String(pending.length)],['Preventable',String(preventable.length)],['Recorded Callback Cost',money.format(cost)]].map(([a,b])=><article key={a} style={{border:'1px solid #ddd',borderRadius:14,padding:16}}><small>{a}</small><h2>{b}</h2></article>)}</section>
  <section style={{border:'1px solid #ddd',borderRadius:16,padding:18,marginBottom:28}}><h2>Record a Comeback</h2><form action={recordCallback} style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(190px,1fr))',gap:10}}><select name="original_job_id" required defaultValue=""><option value="" disabled>Original completed job</option>{completed.map((j:any)=>{const c=one(j.customers),t=one(j.users);return <option key={j.id} value={j.id}>{c?.customer_code||''} {c?.name||j.id.slice(0,8)} — {j.service_type||'Service'} — {t?.name||'Unassigned'}</option>})}</select><select name="callback_job_id" required defaultValue=""><option value="" disabled>Return / callback job</option>{active.map((j:any)=>{const c=one(j.customers);return <option key={j.id} value={j.id}>{c?.customer_code||''} {c?.name||j.id.slice(0,8)} — {j.service_type||'Service'} — {j.status}</option>})}</select><select name="reason" defaultValue="unknown"><option value="unknown">Reason pending</option><option value="workmanship">Workmanship</option><option value="material_failure">Material failure</option><option value="customer_change">Customer change</option><option value="scope_exclusion">Scope exclusion</option><option value="diagnostic_return">Diagnostic return</option></select><input name="manager_note" placeholder="Initial manager note"/><button type="submit">Link Callback</button></form></section>
  <h2>Management Review</h2>{rows.map((r:any)=><article key={r.id} style={{border:r.preventability==='pending'?'2px solid currentColor':'1px solid #ddd',borderRadius:16,padding:18,margin:'12px 0'}}><div style={{display:'flex',justifyContent:'space-between',gap:12,flexWrap:'wrap'}}><div><h3 style={{margin:'0 0 6px'}}>{r.originalCustomer||'Customer'} • {r.originalServiceType||'Service'}</h3><p style={{margin:0}}>Original tech: <b>{r.technicianName||'Unassigned'}</b> • Reason: <b>{String(r.reason||'unknown').replaceAll('_',' ')}</b></p><p><Link href={`/jobs/${r.originalJobId}`}>Original job</Link> → <Link href={`/jobs/${r.callbackJobId}`}>Callback job</Link></p></div><div style={{textAlign:'right'}}><b>{String(r.preventability||'pending').replaceAll('_',' ')}</b><br/><small>{money.format(Number(r.callbackCost??0))} callback cost</small></div></div>{r.preventability==='pending'?<form action={reviewCallback} style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(170px,1fr))',gap:10,marginTop:12}}><input type="hidden" name="callback_id" value={r.id}/><select name="preventability" required defaultValue=""><option value="" disabled>Manager finding</option><option value="preventable">Preventable</option><option value="not_preventable">Not preventable</option><option value="mixed">Mixed causes</option></select><input name="callback_cost" type="number" min="0" step="0.01" placeholder="Actual callback cost"/><input name="manager_note" placeholder="Review note / cause"/><button type="submit">Save Manager Review</button></form>:r.managerNote&&<p><b>Manager note:</b> {r.managerNote}</p>}</article>)}
  {!rows.length&&<p>No callback/comeback relationships have been recorded yet.</p>}
  <aside style={{marginTop:28,border:'2px solid #222',borderRadius:16,padding:18}}><h2>Attribution rule</h2><p>A return visit is not treated as technician fault until an owner or manager reviews the cause. Material failures, customer changes, excluded scope and diagnostic returns remain visible but are separated from preventable workmanship callbacks.</p></aside>
 </main>;
}
