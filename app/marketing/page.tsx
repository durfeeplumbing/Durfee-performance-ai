import Link from 'next/link';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';
import { createMarketingSource,setLeadAttribution } from './actions';

const money=new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:0});
const number=new Intl.NumberFormat('en-US',{maximumFractionDigits:0});
const categories=['paid_search','organic_search','referral','direct','social','home_services','email','offline','other'];
const pretty=(s:string)=>s.replaceAll('_',' ').replace(/\b\w/g,m=>m.toUpperCase());
const platformName=(s:string)=>s==='google_ads'?'Google Ads':s==='meta_ads'?'Meta Ads':pretty(s||'Unknown');

export const dynamic='force-dynamic';

export default async function MarketingPage(){
  const user=await requireCurrentUser();
  const supabase=await createSupabaseServerClient();
  const canManage=['owner','manager','csr_dispatch'].includes(user.role);
  const collectorConfigured=Boolean((process.env.MARKETING_TRACKING_ALLOWED_ORIGINS||'').trim());
  const [{data:summary,error:summaryError},{data:campaigns,error:campaignError},{data:customers},{data:jobs},{data:attribution},{data:platforms},{data:paidCampaigns},{data:touchpoints}]=await Promise.all([
    supabase.rpc('marketing_source_summary'),
    supabase.rpc('servicetitan_campaign_summary',{p_days:90}),
    canManage?supabase.from('customers').select('id,name').order('name').limit(500):Promise.resolve({data:[]}),
    canManage?supabase.from('jobs').select('id,customer_id,service_type,status').order('created_at',{ascending:false}).limit(500):Promise.resolve({data:[]}),
    supabase.rpc('marketing_attribution_dashboard',{p_days:30}),
    supabase.rpc('marketing_platform_summary',{p_days:30}),
    supabase.rpc('marketing_campaign_performance',{p_days:30,p_limit:50}),
    supabase.rpc('marketing_touchpoint_recent',{p_days:30,p_limit:20}),
  ]);
  const rows:any[]=summaryError?[]:((summary as any[])??[]);
  const st:any[]=campaignError?[]:((campaigns as any[])??[]);
  const a:any=attribution??{};
  const platformRows:any[]=(platforms as any[])??[];
  const paidRows:any[]=(paidCampaigns as any[])??[];
  const touches:any[]=(touchpoints as any[])??[];
  const totalLeads=rows.reduce((s,r)=>s+Number(r.lead_count??0),0);
  const totalJobs=rows.reduce((s,r)=>s+Number(r.job_count??0),0);
  const revenue=rows.reduce((s,r)=>s+Number(r.booked_revenue??0),0);
  const spend=Number(a.spend??0),attribRevenue=Number(a.revenue??0),roas=a.roas==null?null:Number(a.roas),cpb=a.costPerBookedJob==null?null:Number(a.costPerBookedJob);
  return <main style={{fontFamily:'system-ui',maxWidth:1380,margin:'auto',padding:32}}>
    <header><p style={{fontWeight:800,letterSpacing:1}}>MARKETING ATTRIBUTION</p><h1>Marketing Command Center</h1><p>Trace paid clicks and calls through customer, job, invoice and payment outcomes. Durfee revenue remains the source of truth; ad-platform conversion counts are supporting signals.</p></header>

    <section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(190px,1fr))',gap:14,margin:'24px 0'}}>
      {[
        ['Paid Spend — 30 Days',money.format(spend)],['Paid Clicks',number.format(Number(a.clicks??0))],['Tracked Calls',number.format(Number(a.calls??0))],['Booked Jobs',number.format(Number(a.bookedJobs??0))],['Attributed Revenue',money.format(attribRevenue)],['ROAS',roas==null?'—':`${roas.toFixed(2)}×`],['Cost / Booked Job',cpb==null?'—':money.format(cpb)],['Identified Click Sessions',`${number.format(Number(a.identifiedTouchpoints??0))} / ${number.format(Number(a.touchpoints??0))}`]
      ].map(([label,value])=><article key={String(label)} style={{border:'1px solid #ddd',borderRadius:16,padding:18}}><small>{label}</small><h2>{value}</h2></article>)}
    </section>

    <section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(290px,1fr))',gap:16,margin:'24px 0'}}>
      <article style={{border:'1px solid #ddd',borderRadius:16,padding:18}}><h2 style={{marginTop:0}}>Google Ads</h2>{platformRows.filter(r=>r.platform==='google_ads').length?platformRows.filter(r=>r.platform==='google_ads').map((r:any)=><p key={r.account_name||'google'}><b>{r.account_name||'Connected account'}</b><br/>{money.format(Number(r.spend??0))} spend • {number.format(Number(r.clicks??0))} clicks • {r.status}</p>):<p><b>Authorization pending.</b> The data model is ready for campaign, ad-group, ad, click-ID and offline conversion data.</p>}</article>
      <article style={{border:'1px solid #ddd',borderRadius:16,padding:18}}><h2 style={{marginTop:0}}>Facebook / Instagram</h2>{platformRows.filter(r=>r.platform==='meta_ads').length?platformRows.filter(r=>r.platform==='meta_ads').map((r:any)=><p key={r.account_name||'meta'}><b>{r.account_name||'Connected account'}</b><br/>{money.format(Number(r.spend??0))} spend • {number.format(Number(r.clicks??0))} clicks • {r.status}</p>):<p><b>Authorization pending.</b> The platform layer is ready for account, campaign, ad-set, ad and click-attribution data.</p>}</article>
      <article style={{border:'1px solid #ddd',borderRadius:16,padding:18}}><h2 style={{marginTop:0}}>Website Click Collector</h2><p><b>{collectorConfigured?'Configured':'Waiting for website origin'}</b></p><p>The first-party collector stores GCLID, GBRAID, WBRAID, FBCLID and UTM values without exposing Supabase credentials to the public website.</p><p><code>/api/marketing/track</code></p></article>
    </section>

    {paidRows.length>0&&<section style={{marginTop:30}}><h2>Paid Campaign Performance — 30 Days</h2><div style={{overflowX:'auto'}}><table style={{width:'100%',borderCollapse:'collapse'}}><thead><tr>{['Platform','Campaign','Spend','Impressions','Clicks','Platform Conversions','Platform Value'].map(x=><th key={x} style={{textAlign:'left',padding:10,borderBottom:'1px solid #ccc'}}>{x}</th>)}</tr></thead><tbody>{paidRows.map((r:any)=><tr key={`${r.platform}:${r.campaign_external_id}`}><td style={{padding:10,borderBottom:'1px solid #eee'}}>{platformName(r.platform)}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}><b>{r.campaign_name||r.campaign_external_id||'Unknown'}</b></td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{money.format(Number(r.spend??0))}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{number.format(Number(r.impressions??0))}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{number.format(Number(r.clicks??0))}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{Number(r.provider_conversions??0).toFixed(1)}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{money.format(Number(r.provider_conversion_value??0))}</td></tr>)}</tbody></table></div></section>}

    {touches.length>0&&<section style={{marginTop:30}}><h2>Recent Click / Session Attribution</h2><p>These are first-party touchpoints waiting to be linked through calls, customers and jobs.</p><div style={{overflowX:'auto'}}><table style={{width:'100%',borderCollapse:'collapse'}}><thead><tr>{['When','Platform','Campaign / Source','Click ID','Linked'].map(x=><th key={x} style={{textAlign:'left',padding:10,borderBottom:'1px solid #ccc'}}>{x}</th>)}</tr></thead><tbody>{touches.map((t:any)=><tr key={t.id}><td style={{padding:10,borderBottom:'1px solid #eee'}}>{new Date(t.first_seen_at).toLocaleString()}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{t.platform?platformName(t.platform):t.utm_source||'Direct / unknown'}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{t.utm_campaign||t.utm_medium||'—'}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{t.gclid?'GCLID':t.gbraid?'GBRAID':t.wbraid?'WBRAID':t.fbclid?'FBCLID':'—'}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{t.job_id?'Job':t.customer_id?'Customer':t.communication_id?'Call/message':'Unlinked'}</td></tr>)}</tbody></table></div></section>}

    {canManage&&<section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(320px,1fr))',gap:18,margin:'30px 0'}}>
      <form action={createMarketingSource} style={{border:'1px solid #ddd',borderRadius:16,padding:18,display:'grid',gap:10}}><h2 style={{marginTop:0}}>Add Lead Source</h2><input name="name" placeholder="Google Ads, Referral, Yard Sign…" required/><select name="category" defaultValue="other">{categories.map(c=><option key={c} value={c}>{pretty(c)}</option>)}</select><button type="submit">Save Source</button></form>
      <form action={setLeadAttribution} style={{border:'1px solid #ddd',borderRadius:16,padding:18,display:'grid',gap:10}}><h2 style={{marginTop:0}}>Attribute Customer / Job</h2><select name="customer_id" required defaultValue=""><option value="" disabled>Customer</option>{(customers??[]).map((c:any)=><option key={c.id} value={c.id}>{c.name}</option>)}</select><select name="job_id" defaultValue=""><option value="">Customer only / no job yet</option>{(jobs??[]).map((j:any)=><option key={j.id} value={j.id}>{j.id.slice(0,8)} • {j.service_type||'Job'} • {j.status}</option>)}</select><select name="source_id" required defaultValue=""><option value="" disabled>Lead source</option>{rows.map((r:any)=><option key={r.source_id} value={r.source_id}>{r.source_name}</option>)}</select><select name="touch_type" defaultValue="primary"><option value="first">First touch</option><option value="primary">Primary source</option><option value="assist">Assist</option></select><input name="source_detail" placeholder="Keyword, referral name, neighborhood, etc."/><input name="external_campaign_id" placeholder="External campaign ID (optional)"/><button type="submit">Save Attribution</button></form>
    </section>}

    <section style={{marginTop:28}}><h2>Durfee Lead Sources</h2>{summaryError&&<p role="alert">Lead-source summary could not be loaded.</p>}<div style={{overflowX:'auto'}}><table style={{width:'100%',borderCollapse:'collapse'}}><thead><tr>{['Source','Category','Leads','Jobs','Completed','Revenue','Last Attribution'].map(x=><th key={x} style={{textAlign:'left',padding:10,borderBottom:'1px solid #ccc'}}>{x}</th>)}</tr></thead><tbody>{rows.map((r:any)=><tr key={r.source_id}><td style={{padding:10,borderBottom:'1px solid #eee'}}><b>{r.source_name}</b></td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{pretty(r.category)}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{r.lead_count}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{r.job_count}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{r.completed_jobs}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{money.format(Number(r.booked_revenue??0))}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{r.last_attributed_at?new Date(r.last_attributed_at).toLocaleDateString():'—'}</td></tr>)}</tbody></table>{!rows.length&&!summaryError&&<p>No native lead sources have been added yet.</p>}</div></section>

    <section style={{marginTop:34}}><h2>ServiceTitan Campaign Activity — Last 90 Days</h2><p>Existing ServiceTitan job records already contain campaign IDs. This gives immediate historical coverage while Google/Meta account authorization is still pending.</p>{campaignError&&<p role="alert">ServiceTitan campaign activity could not be loaded.</p>}<div style={{overflowX:'auto'}}><table style={{width:'100%',borderCollapse:'collapse'}}><thead><tr>{['Campaign ID','Jobs','Completed','Job Revenue','Last Job'].map(x=><th key={x} style={{textAlign:'left',padding:10,borderBottom:'1px solid #ccc'}}>{x}</th>)}</tr></thead><tbody>{st.map((r:any)=><tr key={r.campaign_id}><td style={{padding:10,borderBottom:'1px solid #eee'}}><b>{r.campaign_id}</b></td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{r.jobs}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{r.completed_jobs}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{money.format(Number(r.total_revenue??0))}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{r.last_job_at?new Date(r.last_job_at).toLocaleDateString():'—'}</td></tr>)}</tbody></table>{!st.length&&!campaignError&&<p>No campaign IDs are available in the current ServiceTitan window.</p>}</div><p style={{marginTop:14}}><Link href="/settings/integrations/servicetitan">Open ServiceTitan integration health →</Link></p></section>

    <aside style={{border:'1px solid #ddd',borderRadius:16,padding:18,marginTop:30}}><h2 style={{marginTop:0}}>Authorization checkpoint</h2><p>No Google or Meta credentials are required yet. When you are ready, this page will walk you through authorizing the business ad accounts; credentials/tokens will stay server-side and will never be committed to GitHub.</p></aside>
  </main>;
}
