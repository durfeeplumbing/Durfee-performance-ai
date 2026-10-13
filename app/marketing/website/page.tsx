import Link from 'next/link';
import { redirect } from 'next/navigation';
import { requireCurrentUser } from '@/lib/session';
import { websiteAnalytics } from '@/lib/marketing/google-report';
import { websiteReportData } from '@/lib/marketing/report-data';
import { refreshWebsiteCalls } from './actions';
export const dynamic='force-dynamic';
const number=new Intl.NumberFormat('en-US');
const money=new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:0});
const when=(value:string|null)=>value?new Intl.DateTimeFormat('en-US',{timeZone:'America/New_York',dateStyle:'short',timeStyle:'short'}).format(new Date(value)):'—';
export default async function WebsiteCallsPage({searchParams}:{searchParams:Promise<{days?:string}>}){
 const user=await requireCurrentUser();if(!['owner','marketing'].includes(user.role))redirect('/unauthorized');
 const params=await searchParams;const requested=Number(params.days||30),days=[7,30,90].includes(requested)?requested:30;
 const [analytics,data]=await Promise.all([websiteAnalytics(days),websiteReportData(days)]);
 const pages=new Map<string,{views:number;sessions:Set<string>;clicks:number;texts:number;forms:number;calls:number}>();
 const ensure=(path:string)=>{let r=pages.get(path);if(!r){r={views:0,sessions:new Set(),clicks:0,texts:0,forms:0,calls:0};pages.set(path,r);}return r;};
 const clicks=data.events.filter(e=>e.event_kind==='call_click');
 for(const e of data.events){const r=ensure(e.page_path);r.sessions.add(e.session_id);if(e.event_kind==='page_view')r.views++;if(e.event_kind==='call_click')r.clicks++;if(e.event_kind==='text_click')r.texts++;if(e.event_kind==='form_open'||e.event_kind==='scheduler_open')r.forms++;}
 for(const c of data.calls)if(c.landingPage)ensure(c.landingPage).calls++;
 const attributed=data.calls.filter(c=>c.landingPage).length;
 const callsReady=data.health.some(h=>h.name==='call'&&h.last_success_at);
 const leadReady=data.health.some(h=>h.name==='attributed_lead'&&h.last_success_at);
 return <main style={{maxWidth:1400,margin:'auto',padding:28}}>
  <header><p style={{fontWeight:800,color:'#166c75',letterSpacing:2}}>DURFEE • MARKETING</p><h1>Website & Calls</h1><p>See which pages attract interest, which calls have verified page attribution, and which lead to booked work.</p></header>
  <div style={{display:'flex',gap:10,flexWrap:'wrap',alignItems:'center',margin:'20px 0'}}>{[7,30,90].map(n=><Link key={n} href={`/marketing/website?days=${n}`} aria-current={days===n?'page':undefined} style={{padding:'8px 14px',border:'1px solid #cbd5e1',borderRadius:8,background:days===n?'#e0f2f1':'white'}}>Last {n} days</Link>)}<form action={refreshWebsiteCalls}><button type="submit">Refresh ServiceTitan calls</button></form></div>
  <div style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(180px,1fr))',gap:12}}>{[
   ['Website sessions',data.eventsError?'Unavailable':number.format(new Set(data.events.map(e=>e.session_id)).size)],
   ['Call-button clicks',data.eventsError?'Unavailable':number.format(clicks.length)],
   ['ServiceTitan calls',data.callsError||!callsReady?'Not synced':number.format(data.calls.length)],
   ['Calls with a page',!leadReady?'Awaiting attribution':number.format(attributed)],
   ['Calls without a page',!callsReady?'Not synced':number.format(data.calls.length-attributed)],
  ].map(([label,value])=><article key={label} style={{background:'white',border:'1px solid #dbe3eb',borderRadius:14,padding:18}}><small>{label}</small><h2 style={{margin:'12px 0 0'}}>{value}</h2></article>)}</div>
  <p style={{color:'#526273'}}>Website intent tracking starts October 13, 2026. Call clicks and scheduler openings do not prove a completed call or booking. ServiceTitan refresh loads the last 90 days; click Refresh to update calls, attribution, and jobs. Times below are Eastern.</p>
  {(data.eventsError||data.callsError||data.healthError)&&<p role="alert">Part of this report could not be loaded. Unavailable data is not counted as zero.</p>}
  {data.truncated&&<p role="alert">This report reached its row limit. Choose a shorter date range; totals are partial.</p>}
  <section style={{background:'white',padding:20,borderRadius:14,marginTop:24}}><h2>Pages that generate interest and calls</h2><p>Clicks are grouped by the page clicked. Confirmed calls and jobs are grouped by ServiceTitan’s attributed landing page.</p><div style={{overflowX:'auto'}}><table style={{width:'100%',borderCollapse:'collapse'}}><thead><tr>{['Page','Views','Call clicks','Text clicks','Form / scheduler opens','Attributed calls','Booked jobs','Completed job total'].map(h=><th key={h} style={{textAlign:'left',padding:10,borderBottom:'1px solid #ccc'}}>{h}</th>)}</tr></thead><tbody>{[...pages].sort((a,b)=>b[1].clicks-a[1].clicks||b[1].views-a[1].views).map(([path,r])=>{const revenue=data.revenue.pages.get(path);return <tr key={path}><td style={{padding:10}}><a href={'https://capecodplumber.com'+path} target="_blank" rel="noreferrer">{path}</a></td><td>{r.views}</td><td>{r.clicks}</td><td>{r.texts}</td><td>{r.forms}</td><td>{leadReady?r.calls:'—'}</td><td>{leadReady?revenue?.jobs||0:'—'}</td><td>{leadReady&&!data.jobsError&&!revenue?.missingJobs?money.format(revenue?.jobTotal||0):'—'}</td></tr>})}</tbody></table></div>{pages.size===0&&<p>No website events or attributed pages have arrived in this date range yet.</p>}<small>Each job is counted once. Conflicting page assignments are excluded. Job totals are not collected payments; this view does not claim collected revenue.</small></section>
  <section style={{marginTop:26}}><h2>Entry page → call-click page</h2><p>Recent anonymous website sessions; these are call intentions, not identified callers.</p><div style={{overflowX:'auto'}}><table style={{width:'100%'}}><thead><tr><th align="left">When</th><th align="left">Entered through</th><th align="left">Clicked Call on</th><th align="left">Source / medium</th></tr></thead><tbody>{clicks.slice(0,50).map((e,i)=><tr key={`${e.session_id}:${e.received_at}:${i}`}><td>{when(e.received_at)}</td><td>{e.entry_path}</td><td>{e.page_path}</td><td>{e.source||'Unknown'} / {e.medium||'Unknown'}</td></tr>)}</tbody></table></div>{!clicks.length&&<p>No call-button clicks recorded yet.</p>}</section>
  <section style={{marginTop:26}}><h2>ServiceTitan call outcomes</h2><div style={{overflowX:'auto'}}><table style={{width:'100%'}}><thead><tr>{['When','Call ID','Direction / classification','Attributed page','Booked job'].map(h=><th align="left" key={h}>{h}</th>)}</tr></thead><tbody>{data.calls.slice(0,100).map(c=><tr key={c.id}><td>{when(c.when)}</td><td>{c.id}</td><td>{c.direction} / {c.status}</td><td>{c.landingPage||'Unattributed'}</td><td>{c.jobId?<Link href={`/jobs/servicetitan/${c.jobId}`}>Job {c.jobId}</Link>:'No linked job'}</td></tr>)}</tbody></table></div>{!data.calls.length&&<p>{callsReady?'No calls in this date range.':'ServiceTitan calls have not synced successfully yet.'}</p>}</section>
  <section style={{background:'#eff6f8',padding:20,borderRadius:14,marginTop:26}}><h2>Connection health</h2>{data.health.map(h=><p key={h.name}><b>{h.name==='call'?'ServiceTitan calls':h.name==='jobs'?'ServiceTitan jobs':'ServiceTitan page attribution'}:</b> {h.status} • Last success: {when(h.last_success_at)}{h.detail?` • ${h.detail}`:''}</p>)}{!data.health.length&&<p>Run Refresh ServiceTitan calls to check the connection.</p>}<p><b>Google Analytics:</b> {process.env.GOOGLE_REPORT_ENABLED!=='true'?'Prepared; awaiting approval to transfer reports into Performance AI.':analytics?'Connected':'Unavailable — check connection.'}</p><p><Link href="/marketing/providers">Ad account connections</Link> · <Link href="/marketing/campaigns">Campaign revenue</Link> · <Link href="/marketing/setup">Tracking health</Link></p></section>
  {analytics&&<section style={{marginTop:26}}><h2>Google Analytics page activity</h2><p>Includes today; recent data may still be processing. Property timezone: {analytics.timeZone||'Unknown'}.</p>{analytics.pages.error?<p role="alert">Google page report unavailable.</p>:<table style={{width:'100%'}}><thead><tr><th align="left">Page</th><th align="left">Views</th><th align="left">Users</th></tr></thead><tbody>{analytics.pages.rows.slice(0,100).map(r=><tr key={String(r.pagePath)}><td>{r.pagePath}</td><td>{r.screenPageViews}</td><td>{r.activeUsers}</td></tr>)}</tbody></table>}</section>}
 </main>;
}
