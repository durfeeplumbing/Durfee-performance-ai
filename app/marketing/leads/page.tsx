import Link from 'next/link';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';
import { dismissMarketingLead,matchMarketingLead } from './actions';

export const dynamic='force-dynamic';
const pretty=(s:string)=>String(s||'').replaceAll('_',' ').replace(/\b\w/g,m=>m.toUpperCase());

export default async function MarketingLeadsPage(){
 const user=await requireCurrentUser();const canManage=['owner','manager','csr_dispatch'].includes(user.role);const supabase=await createSupabaseServerClient();
 const [{data:leads,error},{data:customers},{data:jobs}]=await Promise.all([
  supabase.rpc('marketing_lead_queue',{p_days:30,p_limit:200}),
  canManage?supabase.from('customers').select('id,name,phone,email').order('created_at',{ascending:false}).limit(500):Promise.resolve({data:[]}),
  canManage?supabase.from('jobs').select('id,customer_id,service_type,status').order('created_at',{ascending:false}).limit(500):Promise.resolve({data:[]}),
 ]);
 const rows:any[]=(leads as any[])??[];
 return <main style={{fontFamily:'system-ui',maxWidth:1380,margin:'auto',padding:32}}>
  <header><p style={{fontWeight:800,letterSpacing:1}}>MARKETING LEADS</p><h1>Website Lead Inbox</h1><p>First-party website forms land here with the click/session that produced them. Exact phone/email matches stitch automatically; ambiguous leads stay human-reviewed instead of creating duplicate customers.</p></header>
  {error&&<p role="alert">Lead inbox could not be loaded.</p>}
  <section style={{display:'grid',gap:14,marginTop:24}}>{rows.map((l:any)=><article key={l.id} style={{border:'1px solid #ddd',borderRadius:16,padding:18}}>
   <div style={{display:'flex',justifyContent:'space-between',gap:12,flexWrap:'wrap'}}><div><b>{l.lead_name||l.phone||l.email||'Website lead'}</b><div>{l.phone||'No phone'} • {l.email||'No email'}</div><small>{new Date(l.submitted_at).toLocaleString()} • {pretty(l.platform)} • {l.campaign||'(not set)'} • {pretty(l.status)}</small></div><div>{l.customer_id&&<Link href={`/customers/${l.customer_id}`}>Open customer</Link>}{l.job_id&&<> • <Link href={`/jobs/${l.job_id}`}>Open job</Link></>}</div></div>
   {l.service_request&&<p>{l.service_request}</p>}
   {canManage&&l.status!=='dismissed'&&<div style={{display:'flex',gap:12,flexWrap:'wrap',alignItems:'end'}}>
    <form action={matchMarketingLead} style={{display:'flex',gap:8,flexWrap:'wrap',alignItems:'end'}}><input type="hidden" name="lead_id" value={l.id}/><label>Customer<br/><select name="customer_id" required defaultValue={l.customer_id||''}><option value="" disabled>Select customer</option>{(customers??[]).map((c:any)=><option key={c.id} value={c.id}>{c.name} {c.phone?`• ${c.phone}`:''}</option>)}</select></label><label>Job<br/><select name="job_id" defaultValue={l.job_id||''}><option value="">No job yet</option>{(jobs??[]).map((j:any)=><option key={j.id} value={j.id}>{j.id.slice(0,8)} • {j.service_type||'Job'} • {j.status}</option>)}</select></label><button type="submit">Link lead</button></form>
    {(l.status==='new'||l.status==='matched')&&<form action={dismissMarketingLead}><input type="hidden" name="lead_id" value={l.id}/><button type="submit">Dismiss</button></form>}
   </div>}
  </article>)}{!rows.length&&!error&&<p>No website leads have been captured in the last 30 days yet.</p>}</section>
 </main>;
}
