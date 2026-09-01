import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';

const money=new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:0});
const number=new Intl.NumberFormat('en-US',{maximumFractionDigits:0});
const platformName=(s:string)=>s==='google_ads'?'Google Ads':s==='meta_ads'?'Meta Ads':s.replaceAll('_',' ').replace(/\b\w/g,m=>m.toUpperCase());

export const dynamic='force-dynamic';

export default async function MarketingFunnelPage(){
  await requireCurrentUser();
  const supabase=await createSupabaseServerClient();
  const {data,error}=await supabase.rpc('marketing_touchpoint_funnel',{p_days:30,p_limit:200});
  const rows:any[]=error?[]:((data as any[])??[]);
  return <main style={{fontFamily:'system-ui',maxWidth:1280,margin:'auto',padding:32}}>
    <header><p style={{fontWeight:800,letterSpacing:1}}>FIRST-PARTY ATTRIBUTION</p><h1>Marketing Funnel — 30 Days</h1><p>Follow captured sessions through calls, customers, jobs, completed work and collected payments. This report uses Durfee Performance outcomes rather than ad-platform self-reported revenue.</p></header>
    {error&&<p role="alert">The attribution funnel could not be loaded.</p>}
    <div style={{overflowX:'auto',marginTop:24}}><table style={{width:'100%',borderCollapse:'collapse'}}><thead><tr>{['Platform','Campaign','Sessions','ID Sessions','Calls','Customers','Jobs','Completed','Earned Revenue','Collected Revenue'].map(x=><th key={x} style={{textAlign:'left',padding:10,borderBottom:'1px solid #ccc'}}>{x}</th>)}</tr></thead><tbody>{rows.map((r:any)=><tr key={`${r.platform}:${r.campaign}`}><td style={{padding:10,borderBottom:'1px solid #eee'}}>{platformName(r.platform)}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}><b>{r.campaign}</b></td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{number.format(Number(r.sessions??0))}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{number.format(Number(r.identified_sessions??0))}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{number.format(Number(r.calls??0))}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{number.format(Number(r.customers??0))}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{number.format(Number(r.jobs??0))}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{number.format(Number(r.completed_jobs??0))}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{money.format(Number(r.earned_revenue??0))}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{money.format(Number(r.collected_revenue??0))}</td></tr>)}</tbody></table>{!rows.length&&!error&&<p>No first-party tracked sessions are available in this window yet.</p>}</div>
    <aside style={{border:'1px solid #ddd',borderRadius:16,padding:18,marginTop:26}}><b>Attribution rule:</b> earned revenue comes from completed jobs; collected revenue comes from actual payments. Those are shown separately so revenue is not counted twice.</aside>
  </main>;
}
