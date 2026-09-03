import Link from 'next/link';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';
import { createJob,assignTechnician,rescheduleJob,cancelJob } from './actions';

const money=new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:0});
const serviceTypes=['Plumbing Service','Drain & Sewer','Water Heaters','Tankless','Boilers','Furnaces','Heat Pumps','Ductless Mini-Splits','Central AC','HVAC Service','HVAC Installation','Gas Piping','New Construction','IAQ'];
const preField=new Set(['booked','scheduled','dispatched']);

export default async function JobsPage(){
  const user=await requireCurrentUser();
  const supabase=await createSupabaseServerClient();
  const [{data:jobs,error},{data:customers},{data:techs}]=await Promise.all([
    supabase.from('jobs').select('id,status,service_type,service_summary,revenue,material_cost,labor_cost,allocated_overhead,scheduled_start,scheduled_end,technician_id,customers(name),users(name),job_notes(id),job_attachments(id)').order('created_at',{ascending:false}).limit(100),
    supabase.from('customers').select('id,name').order('name'),
    supabase.from('users').select('id,name').eq('role','technician').eq('active',true).order('name')
  ]);
  const nativeRows=error?[]:(jobs??[]);
  const {data:staged,error:stagedError}=nativeRows.length===0?await supabase.rpc('service_titan_jobs_fallback',{p_limit:100}):{data:null,error:null};
  const stagedRows=(staged??[]) as any[];
  const canManage=['owner','manager','csr_dispatch'].includes(user.role);

  return <main style={{fontFamily:'system-ui',maxWidth:1400,margin:'auto',padding:32}}>
    <h1>Jobs & Workflow</h1>
    <p>Classify the call when it is booked so dispatch, pricing and reporting use the same service language. Open native Durfee jobs to review notes, photos, materials and commercial history.</p>
    {nativeRows.length===0&&stagedRows.length>0&&<section style={{padding:14,border:'1px solid #b8a76a',borderRadius:12,background:'#fffbea',margin:'16px 0'}}><b>ServiceTitan staging view</b><div>Durfee Performance native jobs have not been migrated yet, so this page is showing the latest read-only ServiceTitan jobs instead.</div></section>}

    {canManage&&<form action={createJob} style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(180px,1fr))',gap:12,padding:18,border:'1px solid #ddd',borderRadius:16,margin:'22px 0'}}>
      <select name="customer_id" required defaultValue=""><option value="" disabled>Select customer</option>{(customers??[]).map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select>
      <select name="service_type" required defaultValue=""><option value="" disabled>Service type</option>{serviceTypes.map(s=><option key={s}>{s}</option>)}</select>
      <input name="service_summary" maxLength={5000} placeholder="What does the customer need?"/>
      <label>Start<input name="scheduled_start" type="datetime-local" style={{display:'block',width:'100%'}}/></label>
      <label>End<input name="scheduled_end" type="datetime-local" style={{display:'block',width:'100%'}}/></label>
      <button type="submit">Book Job</button>
    </form>}

    {error&&<p role="alert">Native jobs could not be loaded.</p>}
    {stagedError&&<p role="alert">ServiceTitan staged jobs could not be loaded.</p>}

    <div style={{overflowX:'auto'}}><table style={{width:'100%',borderCollapse:'collapse',marginTop:24}}><thead><tr>{['Job','Customer','Service / Summary','Technician','Scheduled','Status','Documentation','Revenue','GP','Dispatch'].map(x=><th key={x} style={{textAlign:'left',padding:12,borderBottom:'1px solid #ccc'}}>{x}</th>)}</tr></thead><tbody>
      {nativeRows.map((j:any)=>{const r=Number(j.revenue??0),c=Number(j.material_cost??0)+Number(j.labor_cost??0)+Number(j.allocated_overhead??0),gp=r>0?((r-c)/r)*100:null,mutable=canManage&&preField.has(j.status);return <tr key={j.id} style={{verticalAlign:'top'}}><td style={{padding:12}}><Link href={`/jobs/${j.id}`}><b>{j.id.slice(0,8)}</b></Link></td><td style={{padding:12}}>{j.customers?.name||'—'}</td><td style={{padding:12}}><b>{j.service_type||'Unclassified'}</b>{j.service_summary&&<small style={{display:'block'}}>{j.service_summary}</small>}</td><td style={{padding:12}}>{j.users?.name||'Unassigned'}</td><td style={{padding:12}}>{j.scheduled_start?new Date(j.scheduled_start).toLocaleString():'—'}{j.scheduled_end&&<small style={{display:'block'}}>to {new Date(j.scheduled_end).toLocaleString()}</small>}</td><td style={{padding:12}}>{j.status}</td><td style={{padding:12}}><Link href={`/jobs/${j.id}`}>{j.job_notes?.length||0} notes • {j.job_attachments?.length||0} files</Link></td><td style={{padding:12}}>{money.format(r)}</td><td style={{padding:12}}>{gp===null?'—':`${gp.toFixed(1)}%`}</td><td style={{padding:12,minWidth:260}}>{mutable&&<><form action={assignTechnician} style={{display:'flex',gap:6,marginBottom:8}}><input type="hidden" name="job_id" value={j.id}/><select name="technician_id" defaultValue={j.technician_id||''} style={{minWidth:130}}><option value="">Unassigned</option>{(techs??[]).map(t=><option key={t.id} value={t.id}>{t.name}</option>)}</select><button type="submit">Assign</button></form><details><summary style={{cursor:'pointer'}}>Schedule / cancel</summary><form action={rescheduleJob} style={{display:'grid',gap:6,marginTop:8,padding:8,border:'1px solid #ddd',borderRadius:8}}><input type="hidden" name="job_id" value={j.id}/><label>New start<input name="scheduled_start" type="datetime-local" required style={{display:'block',width:'100%'}}/></label><label>New end<input name="scheduled_end" type="datetime-local" style={{display:'block',width:'100%'}}/></label><button type="submit">Reschedule</button></form><form action={cancelJob} style={{display:'grid',gap:6,marginTop:8,padding:8,border:'1px solid #ddd',borderRadius:8}}><input type="hidden" name="job_id" value={j.id}/><input name="reason" required minLength={3} maxLength={1000} placeholder="Cancellation reason"/><button type="submit">Cancel Job</button></form></details></>}</td></tr>})}
      {nativeRows.length===0&&stagedRows.map((j:any)=><tr key={j.external_id} style={{verticalAlign:'top'}}><td style={{padding:12}}><b>{j.job_number||j.external_id}</b><small style={{display:'block'}}>ServiceTitan</small></td><td style={{padding:12}}>{j.customer_name||'—'}</td><td style={{padding:12,maxWidth:460}}>{j.summary||'—'}</td><td style={{padding:12}}>ServiceTitan assignment</td><td style={{padding:12}}>See Schedule</td><td style={{padding:12}}>{j.status}</td><td style={{padding:12}}>Read-only staging</td><td style={{padding:12}}>{money.format(Number(j.total??0))}</td><td style={{padding:12}}>—</td><td style={{padding:12}}>Managed in ServiceTitan during staging</td></tr>)}
    </tbody></table></div>
    {nativeRows.length===0&&stagedRows.length===0&&!stagedError&&<p>No jobs are available yet.</p>}
  </main>;
}
