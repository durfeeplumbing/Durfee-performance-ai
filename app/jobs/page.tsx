import Link from 'next/link';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';
import { createJob,assignTechnician,rescheduleJob,cancelJob } from './actions';

export const dynamic='force-dynamic';
const money=new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:0});
const serviceTypes=['Plumbing Service','Drain & Sewer','Water Heaters','Tankless','Boilers','Furnaces','Heat Pumps','Ductless Mini-Splits','Central AC','HVAC Service','HVAC Installation','Gas Piping','New Construction','IAQ'];
const preField=new Set(['booked','scheduled','dispatched']);
const fmt=(v?:string|null)=>v?new Date(v).toLocaleString('en-US',{timeZone:'America/New_York',month:'short',day:'numeric',hour:'numeric',minute:'2-digit'}):'—';
const pill=(status:string)=>({display:'inline-block',border:'1px solid #bbb',borderRadius:999,padding:'4px 9px',fontSize:12,fontWeight:800,textTransform:'uppercase' as const,letterSpacing:'.03em'});

export default async function JobsPage({searchParams}:{searchParams:Promise<{status?:string}>}){
  const user=await requireCurrentUser();
  const sp=await searchParams;
  const supabase=await createSupabaseServerClient();
  const [{data:jobs,error},{data:customers},{data:techs}]=await Promise.all([
    supabase.from('jobs').select('id,status,service_type,service_summary,revenue,material_cost,labor_cost,allocated_overhead,scheduled_start,scheduled_end,technician_id,customers(name),users(name),job_notes(id),job_attachments(id)').order('created_at',{ascending:false}).limit(150),
    supabase.from('customers').select('id,name').order('name'),
    supabase.from('users').select('id,name').eq('role','technician').eq('active',true).order('name')
  ]);
  const nativeRows=error?[]:(jobs??[]);
  const {data:staged,error:stagedError}=nativeRows.length===0?await supabase.rpc('service_titan_jobs_fallback',{p_limit:200}):{data:null,error:null};
  const stagedRows=(staged??[]) as any[];
  const canManage=['owner','manager','csr_dispatch'].includes(user.role);
  const usingStaging=nativeRows.length===0&&stagedRows.length>0;
  const allRows:any[]=usingStaging?stagedRows:nativeRows;
  const statusCounts=allRows.reduce((acc:Record<string,number>,r:any)=>{const s=String(r.status||'Unknown');acc[s]=(acc[s]||0)+1;return acc;},{});
  const selected=sp.status||'';
  const visible=selected?allRows.filter((r:any)=>String(r.status||'Unknown')===selected):allRows;
  const openCount=allRows.filter((r:any)=>!['Completed','Canceled','Cancelled','completed','canceled'].includes(String(r.status))).length;
  const completedCount=allRows.filter((r:any)=>String(r.status).toLowerCase()==='completed').length;
  const revenue=allRows.reduce((sum:number,r:any)=>sum+Number((usingStaging?r.total:r.revenue)??0),0);

  return <main style={{fontFamily:'system-ui',maxWidth:1500,margin:'auto',padding:28}}>
    <header style={{display:'flex',justifyContent:'space-between',gap:18,alignItems:'flex-end',flexWrap:'wrap',paddingBottom:18,borderBottom:'1px solid #ddd'}}>
      <div><p style={{margin:'0 0 6px',fontSize:13,fontWeight:800,textTransform:'uppercase',letterSpacing:'.08em'}}>Operations</p><h1 style={{margin:0,fontSize:34}}>Jobs</h1><p style={{margin:'8px 0 0',maxWidth:760,color:'#555'}}>A fast-scanning work queue: customer, job status, value and the next important detail first. Expand a card only when you need the rest.</p></div>
      <div style={{display:'flex',gap:10,flexWrap:'wrap'}}><Link href="/schedule" style={{border:'1px solid #bbb',borderRadius:10,padding:'9px 12px',textDecoration:'none'}}>Schedule</Link><Link href="/dispatch" style={{border:'1px solid #bbb',borderRadius:10,padding:'9px 12px',textDecoration:'none'}}>Smart Dispatch</Link></div>
    </header>

    {usingStaging&&<section style={{padding:14,border:'1px solid #b8a76a',borderRadius:12,background:'#fffbea',margin:'16px 0'}}><b>ServiceTitan staging view</b><div>Showing current staged ServiceTitan jobs until native Durfee Performance jobs are migrated. These records stay read-only here.</div></section>}

    <section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(180px,1fr))',gap:10,margin:'18px 0'}}>
      {[["Loaded",allRows.length.toLocaleString()],["Open / active",openCount.toLocaleString()],["Completed",completedCount.toLocaleString()],["Visible job value",money.format(revenue)]].map(([k,v])=><div key={String(k)} style={{border:'1px solid #ddd',borderRadius:14,padding:14}}><small>{k}</small><div style={{fontWeight:850,fontSize:24,marginTop:3}}>{v}</div></div>)}
    </section>

    <nav style={{display:'flex',gap:8,flexWrap:'wrap',margin:'8px 0 20px'}}><Link href="/jobs" style={{border:selected?'1px solid #ccc':'2px solid #111',borderRadius:999,padding:'6px 11px',textDecoration:'none'}}>All {allRows.length}</Link>{Object.entries(statusCounts).sort((a,b)=>b[1]-a[1]).map(([status,count])=><Link key={status} href={`/jobs?status=${encodeURIComponent(status)}`} style={{border:selected===status?'2px solid #111':'1px solid #ccc',borderRadius:999,padding:'6px 11px',textDecoration:'none'}}>{status} {count}</Link>)}</nav>

    {canManage&&!usingStaging&&<details style={{border:'1px solid #ddd',borderRadius:14,padding:14,margin:'18px 0'}}><summary style={{cursor:'pointer',fontWeight:800}}>Book a new Durfee job</summary><form action={createJob} style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(180px,1fr))',gap:12,marginTop:14}}><select name="customer_id" required defaultValue=""><option value="" disabled>Select customer</option>{(customers??[]).map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select><select name="service_type" required defaultValue=""><option value="" disabled>Service type</option>{serviceTypes.map(s=><option key={s}>{s}</option>)}</select><input name="service_summary" maxLength={5000} placeholder="What does the customer need?"/><label>Start<input name="scheduled_start" type="datetime-local" style={{display:'block',width:'100%'}}/></label><label>End<input name="scheduled_end" type="datetime-local" style={{display:'block',width:'100%'}}/></label><button type="submit">Book Job</button></form></details>}

    {error&&<p role="alert">Native jobs could not be loaded.</p>}{stagedError&&<p role="alert">ServiceTitan staged jobs could not be loaded.</p>}

    <section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(360px,1fr))',gap:14}}>
      {usingStaging&&visible.map((j:any)=><article key={j.external_id} style={{border:'1px solid #d8d8d8',borderRadius:16,padding:16,boxShadow:'0 1px 2px rgba(0,0,0,.04)'}}><div style={{display:'flex',justifyContent:'space-between',gap:12,alignItems:'start'}}><div><small style={{fontWeight:800,color:'#666'}}>JOB #{j.job_number||j.external_id}</small><h2 style={{fontSize:20,margin:'4px 0'}}>{j.customer_name||'Customer not loaded'}</h2></div><span style={pill(j.status)}>{j.status}</span></div><p style={{margin:'10px 0',lineHeight:1.4,minHeight:40}}>{j.summary||'No job summary loaded.'}</p><div style={{display:'grid',gridTemplateColumns:'1fr 1fr',gap:10,padding:'10px 0',borderTop:'1px solid #eee',borderBottom:'1px solid #eee'}}><div><small>Job value</small><div style={{fontWeight:800,fontSize:20}}>{money.format(Number(j.total||0))}</div></div><div><small>Last updated</small><div style={{fontWeight:700}}>{fmt(j.modified_on)}</div></div></div><details style={{marginTop:10}}><summary style={{cursor:'pointer',fontWeight:750}}>More job information</summary><div style={{paddingTop:9,fontSize:14,lineHeight:1.6}}><div><b>Created:</b> {fmt(j.created_on)}</div><div><b>ServiceTitan ID:</b> {j.external_id}</div><div><b>Assignment / appointment:</b> Open Schedule for current appointment information.</div></div></details></article>)}
      {!usingStaging&&visible.map((j:any)=>{const r=Number(j.revenue??0),c=Number(j.material_cost??0)+Number(j.labor_cost??0)+Number(j.allocated_overhead??0),gp=r>0?((r-c)/r)*100:null,mutable=canManage&&preField.has(j.status);return <article key={j.id} style={{border:'1px solid #d8d8d8',borderRadius:16,padding:16,boxShadow:'0 1px 2px rgba(0,0,0,.04)'}}><div style={{display:'flex',justifyContent:'space-between',gap:12,alignItems:'start'}}><div><small style={{fontWeight:800,color:'#666'}}>JOB {j.id.slice(0,8)}</small><h2 style={{fontSize:20,margin:'4px 0'}}><Link href={`/jobs/${j.id}`}>{j.customers?.name||'Customer'}</Link></h2></div><span style={pill(j.status)}>{j.status}</span></div><p style={{margin:'10px 0',lineHeight:1.4}}><b>{j.service_type||'Unclassified'}</b>{j.service_summary?` — ${j.service_summary}`:''}</p><div style={{display:'grid',gridTemplateColumns:'repeat(3,1fr)',gap:10,padding:'10px 0',borderTop:'1px solid #eee',borderBottom:'1px solid #eee'}}><div><small>Scheduled</small><div style={{fontWeight:700}}>{fmt(j.scheduled_start)}</div></div><div><small>Technician</small><div style={{fontWeight:700}}>{j.users?.name||'Unassigned'}</div></div><div><small>Revenue / GP</small><div style={{fontWeight:800}}>{money.format(r)} · {gp===null?'—':`${gp.toFixed(1)}%`}</div></div></div><details style={{marginTop:10}}><summary style={{cursor:'pointer',fontWeight:750}}>Details & dispatch controls</summary><div style={{paddingTop:10}}><p><b>Documentation:</b> {j.job_notes?.length||0} notes · {j.job_attachments?.length||0} files · <Link href={`/jobs/${j.id}`}>open full job →</Link></p>{mutable&&<><form action={assignTechnician} style={{display:'flex',gap:6,marginBottom:8}}><input type="hidden" name="job_id" value={j.id}/><select name="technician_id" defaultValue={j.technician_id||''}><option value="">Unassigned</option>{(techs??[]).map(t=><option key={t.id} value={t.id}>{t.name}</option>)}</select><button type="submit">Assign</button></form><form action={rescheduleJob} style={{display:'flex',gap:6,flexWrap:'wrap',marginBottom:8}}><input type="hidden" name="job_id" value={j.id}/><input name="scheduled_start" type="datetime-local" required/><input name="scheduled_end" type="datetime-local"/><button type="submit">Reschedule</button></form><form action={cancelJob} style={{display:'flex',gap:6,flexWrap:'wrap'}}><input type="hidden" name="job_id" value={j.id}/><input name="reason" required minLength={3} maxLength={1000} placeholder="Cancellation reason"/><button type="submit">Cancel</button></form></>}</div></details></article>})}
    </section>
    {!visible.length&&!stagedError&&<p style={{padding:24,border:'1px dashed #bbb',borderRadius:14}}>No jobs match this view.</p>}
  </main>;
}
