import Link from 'next/link';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';
import { createMarketingSource,setLeadAttribution } from './actions';

const money=new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:0});
const categories=['paid_search','organic_search','referral','direct','social','home_services','email','offline','other'];
const pretty=(s:string)=>s.replaceAll('_',' ').replace(/\b\w/g,m=>m.toUpperCase());

export const dynamic='force-dynamic';

export default async function MarketingPage(){
  const user=await requireCurrentUser();
  const supabase=await createSupabaseServerClient();
  const canManage=['owner','manager','csr_dispatch'].includes(user.role);
  const [{data:summary,error:summaryError},{data:campaigns,error:campaignError},{data:customers},{data:jobs}]=await Promise.all([
    supabase.rpc('marketing_source_summary'),
    supabase.rpc('servicetitan_campaign_summary',{p_days:90}),
    canManage?supabase.from('customers').select('id,name').order('name').limit(500):Promise.resolve({data:[]}),
    canManage?supabase.from('jobs').select('id,customer_id,service_type,status').order('created_at',{ascending:false}).limit(500):Promise.resolve({data:[]}),
  ]);
  const rows:any[]=summaryError?[]:((summary as any[])??[]);
  const st:any[]=campaignError?[]:((campaigns as any[])??[]);
  const totalLeads=rows.reduce((s,r)=>s+Number(r.lead_count??0),0);
  const totalJobs=rows.reduce((s,r)=>s+Number(r.job_count??0),0);
  const revenue=rows.reduce((s,r)=>s+Number(r.booked_revenue??0),0);
  return <main style={{fontFamily:'system-ui',maxWidth:1300,margin:'auto',padding:32}}>
    <header><p style={{fontWeight:800,letterSpacing:1}}>LEAD SOURCE CONTROL</p><h1>Marketing & Lead Attribution</h1><p>Track how customers and jobs entered the business. Marketing spend and ROAS stay separate until the financial section is resumed.</p></header>
    <section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(190px,1fr))',gap:14,margin:'24px 0'}}>
      {[['Attributed Leads',totalLeads],['Attributed Jobs',totalJobs],['Attributed Revenue',money.format(revenue)],['ST Campaign IDs — 90 Days',st.length]].map(([label,value])=><article key={String(label)} style={{border:'1px solid #ddd',borderRadius:16,padding:18}}><small>{label}</small><h2>{value}</h2></article>)}
    </section>
    {canManage&&<section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(320px,1fr))',gap:18,margin:'24px 0'}}>
      <form action={createMarketingSource} style={{border:'1px solid #ddd',borderRadius:16,padding:18,display:'grid',gap:10}}><h2 style={{marginTop:0}}>Add Lead Source</h2><input name="name" placeholder="Google Ads, Referral, Yard Sign…" required/><select name="category" defaultValue="other">{categories.map(c=><option key={c} value={c}>{pretty(c)}</option>)}</select><button type="submit">Save Source</button></form>
      <form action={setLeadAttribution} style={{border:'1px solid #ddd',borderRadius:16,padding:18,display:'grid',gap:10}}><h2 style={{marginTop:0}}>Attribute Customer / Job</h2><select name="customer_id" required defaultValue=""><option value="" disabled>Customer</option>{(customers??[]).map((c:any)=><option key={c.id} value={c.id}>{c.name}</option>)}</select><select name="job_id" defaultValue=""><option value="">Customer only / no job yet</option>{(jobs??[]).map((j:any)=><option key={j.id} value={j.id}>{j.id.slice(0,8)} • {j.service_type||'Job'} • {j.status}</option>)}</select><select name="source_id" required defaultValue=""><option value="" disabled>Lead source</option>{rows.map((r:any)=><option key={r.source_id} value={r.source_id}>{r.source_name}</option>)}</select><select name="touch_type" defaultValue="primary"><option value="first">First touch</option><option value="primary">Primary source</option><option value="assist">Assist</option></select><input name="source_detail" placeholder="Keyword, referral name, neighborhood, etc."/><input name="external_campaign_id" placeholder="External campaign ID (optional)"/><button type="submit">Save Attribution</button></form>
    </section>}
    <section style={{marginTop:28}}><h2>Durfee Lead Sources</h2>{summaryError&&<p role="alert">Lead-source summary could not be loaded.</p>}<div style={{overflowX:'auto'}}><table style={{width:'100%',borderCollapse:'collapse'}}><thead><tr>{['Source','Category','Leads','Jobs','Completed','Revenue','Last Attribution'].map(x=><th key={x} style={{textAlign:'left',padding:10,borderBottom:'1px solid #ccc'}}>{x}</th>)}</tr></thead><tbody>{rows.map((r:any)=><tr key={r.source_id}><td style={{padding:10,borderBottom:'1px solid #eee'}}><b>{r.source_name}</b></td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{pretty(r.category)}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{r.lead_count}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{r.job_count}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{r.completed_jobs}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{money.format(Number(r.booked_revenue??0))}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{r.last_attributed_at?new Date(r.last_attributed_at).toLocaleDateString():'—'}</td></tr>)}</tbody></table>{!rows.length&&!summaryError&&<p>No native lead sources have been added yet.</p>}</div></section>
    <section style={{marginTop:34}}><h2>ServiceTitan Campaign Activity — Last 90 Days</h2><p>Existing ServiceTitan job records already contain campaign IDs. This gives immediate attribution coverage while named campaign/source mapping is built out.</p>{campaignError&&<p role="alert">ServiceTitan campaign activity could not be loaded.</p>}<div style={{overflowX:'auto'}}><table style={{width:'100%',borderCollapse:'collapse'}}><thead><tr>{['Campaign ID','Jobs','Completed','Job Revenue','Last Job'].map(x=><th key={x} style={{textAlign:'left',padding:10,borderBottom:'1px solid #ccc'}}>{x}</th>)}</tr></thead><tbody>{st.map((r:any)=><tr key={r.campaign_id}><td style={{padding:10,borderBottom:'1px solid #eee'}}><b>{r.campaign_id}</b></td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{r.jobs}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{r.completed_jobs}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{money.format(Number(r.total_revenue??0))}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{r.last_job_at?new Date(r.last_job_at).toLocaleDateString():'—'}</td></tr>)}</tbody></table>{!st.length&&!campaignError&&<p>No campaign IDs are available in the current ServiceTitan window.</p>}</div><p style={{marginTop:14}}><Link href="/settings/integrations/servicetitan">Open ServiceTitan integration health →</Link></p></section>
  </main>;
}
