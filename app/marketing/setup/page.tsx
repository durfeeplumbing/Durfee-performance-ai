import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';

const money=new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:0});
const number=new Intl.NumberFormat('en-US',{maximumFractionDigits:0});
const pretty=(s:string)=>s.replaceAll('_',' ').replace(/\b\w/g,m=>m.toUpperCase());

export const dynamic='force-dynamic';

export default async function MarketingSetupPage(){
  await requireCurrentUser();
  const supabase=await createSupabaseServerClient();
  const [{data:qa},{data:queue},{data:dashboard},{data:diag}]=await Promise.all([
    supabase.rpc('marketing_attribution_qa',{p_days:30}),
    supabase.rpc('marketing_sync_queue_summary'),
    supabase.rpc('marketing_attribution_dashboard',{p_days:30}),
    supabase.rpc('marketing_attribution_diagnostics',{p_days:30}),
  ]);
  const q:any=qa??{}; const d:any=dashboard??{}; const h:any=diag??{}; const rows:any[]=(queue as any[])??[];
  const origins=(process.env.MARKETING_TRACKING_ALLOWED_ORIGINS||'').split(',').map(v=>v.trim()).filter(Boolean);
  const scriptSrc='https://durfee-performance-ai.vercel.app/api/marketing/client';
  const snippet=`<script src="${scriptSrc}" defer></script>`;
  return <main style={{fontFamily:'system-ui',maxWidth:1180,margin:'auto',padding:32}}>
    <header><p style={{fontWeight:800,letterSpacing:1}}>MARKETING TRACKING</p><h1>Tracking & Attribution Health</h1><p>This is the pre-authorization control room for website clicks, dynamic phone numbers, call linkage, revenue reconciliation and future Google/Meta conversion uploads.</p></header>

    <section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(180px,1fr))',gap:12,margin:'24px 0'}}>
      {[
        ['Website origins',origins.length],['Tracking numbers',h.trackingNumbers??0],['Unlinked paid sessions',q.unlinkedIdentifiedTouchpoints??0],['Unlinked inbound calls',q.unlinkedCalls??0],['Jobs without attribution',q.jobsWithoutAttribution??0],['Failed provider syncs',q.failedSyncs??0]
      ].map(([label,value])=><article key={String(label)} style={{border:'1px solid #ddd',borderRadius:14,padding:16}}><small>{label}</small><h2 style={{marginBottom:0}}>{number.format(Number(value??0))}</h2></article>)}
    </section>

    <section style={{border:'1px solid #ddd',borderRadius:16,padding:20,margin:'24px 0'}}><h2 style={{marginTop:0}}>Website tracker</h2><p>The tracker creates a durable first-party session ID, captures Google/Meta click IDs plus UTMs, records the landing page/referrer, inserts the session into website forms as <code>durfee_marketing_session</code>, and swaps elements marked <code>data-durfee-phone</code> to a dynamically assigned tracking number when a number pool is available.</p><pre style={{whiteSpace:'pre-wrap',overflowWrap:'anywhere',background:'#f6f7f8',padding:14,borderRadius:10}}><code>{snippet}</code></pre><p><b>Allowed origins:</b> {origins.length?origins.join(', '):'Not configured yet'}</p><p><small>Nothing is sent to ad platforms by this browser script. It only sends first-party attribution data to Durfee Performance.</small></p></section>

    <section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(280px,1fr))',gap:16,margin:'24px 0'}}>
      <article style={{border:'1px solid #ddd',borderRadius:16,padding:18}}><h2 style={{marginTop:0}}>Revenue truth</h2><p><b>Earned/completed revenue:</b> {money.format(Number(d.earnedRevenue??0))}</p><p><b>Collected revenue:</b> {money.format(Number(d.collectedRevenue??0))}</p><p><b>ROAS basis:</b> {Number(d.collectedRevenue??0)>0?'Collected payments':'Completed-job revenue until payment data exists'}</p><p>This prevents the same job from being counted once as completed revenue and again when payment arrives.</p></article>
      <article style={{border:'1px solid #ddd',borderRadius:16,padding:18}}><h2 style={{marginTop:0}}>Attribution chain</h2><p>Click/session → tracking number → Dialpad inbound call → customer → booked job → completed job → invoice → payment.</p><p>New job, invoice and payment writes automatically reconcile staged conversion events through database triggers.</p></article>
      <article style={{border:'1px solid #ddd',borderRadius:16,padding:18}}><h2 style={{marginTop:0}}>Authorization boundary</h2><p>Google and Meta remain disconnected. Eligible conversions are queued as <b>waiting authorization</b>; they cannot be claimed for upload until the provider is explicitly activated after account authorization.</p></article>
    </section>

    <section style={{marginTop:30}}><h2>Provider conversion queue</h2>{rows.length?<div style={{overflowX:'auto'}}><table style={{width:'100%',borderCollapse:'collapse'}}><thead><tr>{['Provider','Status','Events','Value','Oldest Event'].map(x=><th key={x} style={{textAlign:'left',padding:10,borderBottom:'1px solid #ccc'}}>{x}</th>)}</tr></thead><tbody>{rows.map((r:any)=><tr key={`${r.provider}:${r.status}`}><td style={{padding:10,borderBottom:'1px solid #eee'}}>{r.provider==='google_ads'?'Google Ads':'Meta Ads'}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{pretty(r.status)}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{number.format(Number(r.event_count??0))}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{money.format(Number(r.total_value??0))}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{r.oldest_event?new Date(r.oldest_event).toLocaleString():'—'}</td></tr>)}</tbody></table></div>:<p>No provider conversion events are queued yet.</p>}</section>

    <section style={{marginTop:30}}><h2>Go-live checklist</h2><ol><li>Allow the real public website origin in <code>MARKETING_TRACKING_ALLOWED_ORIGINS</code>.</li><li>Install the tracker script on the public website and mark displayed phone elements with <code>data-durfee-phone</code>.</li><li>Provision a tracking-number pool and route each number to the normal Durfee call destination through Dialpad.</li><li>Verify a test paid-style URL creates a touchpoint and dynamic-number assignment.</li><li>Verify the test Dialpad call resolves to that touchpoint/customer/job.</li><li>Authorize Google Ads, activate its queue, and validate test conversion diagnostics before enabling recurring uploads.</li><li>Authorize Meta Ads, activate its queue, and validate test events before recurring uploads.</li></ol></section>
  </main>;
}
