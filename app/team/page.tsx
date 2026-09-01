import Link from 'next/link';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';

export const dynamic = 'force-dynamic';
const money=new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:0});
function extraCost(j:any){return (j.job_cost_allocations??[]).filter((a:any)=>!a.reversed_at&&a.allocation_type!=='materials').reduce((s:number,a:any)=>s+Number(a.amount??0),0)}
function jobCost(j:any){return Number(j.material_cost??0)+Number(j.labor_cost??0)+Number(j.allocated_overhead??0)+extraCost(j)}
function workHours(j:any){return (j.time_entries??[]).filter((x:any)=>x.entry_type==='work'&&x.ended_at).reduce((s:number,x:any)=>s+Math.max(0,(new Date(x.ended_at).getTime()-new Date(x.started_at).getTime())/3600000),0)}

export default async function TeamPage(){
  const user=await requireCurrentUser();
  const supabase=await createSupabaseServerClient();
  let techQuery=supabase.from('users').select('id,name,role,active').eq('role','technician').eq('active',true).order('name');
  if(user.role==='technician')techQuery=techQuery.eq('id',user.id);
  const {data:techs,error}=await techQuery;
  const start=new Date();start.setDate(start.getDate()-30);
  const [{data:jobs},{data:settings}]=await Promise.all([
    supabase.from('jobs').select('id,technician_id,status,service_type,revenue,material_cost,labor_hours,labor_cost,allocated_overhead,completed_at,time_entries(entry_type,started_at,ended_at),job_cost_allocations(amount,allocation_type,reversed_at)').gte('completed_at',start.toISOString()),
    supabase.from('company_pricing_settings').select('minimum_gp').limit(1).maybeSingle(),
  ]);
  const floor=Number(settings?.minimum_gp??50);
  const showManagement=['owner','manager'].includes(user.role);
  const [stResult,productivityResult]=showManagement?await Promise.all([
    supabase.rpc('service_titan_technician_sales_performance',{p_days:30}),
    supabase.rpc('service_titan_technician_productivity',{p_days:30}),
  ]):[{data:null,error:null},{data:null,error:null}];
  const stTechs:any[]=Array.isArray(stResult.data)?stResult.data:[];
  const productivity:any=productivityResult.data??{};
  const productivityTechs:any[]=Array.isArray(productivity.technicians)?productivity.technicians:[];
  const hasPayrollData=Number(productivity.timesheetRecords??0)>0;

  const scorecards=(techs??[]).map((t:any)=>{
    const tj=(jobs??[]).filter((j:any)=>j.technician_id===t.id&&Number(j.revenue??0)>0);
    const revenue=tj.reduce((s:number,j:any)=>s+Number(j.revenue??0),0);
    const cost=tj.reduce((s:number,j:any)=>s+jobCost(j),0);
    const gp=revenue>0?((revenue-cost)/revenue)*100:0;
    const hours=tj.reduce((s:number,j:any)=>s+workHours(j),0);
    const soldHours=tj.reduce((s:number,j:any)=>s+Number(j.labor_hours??0),0);
    const rph=hours>0?revenue/hours:0;
    const avg=tj.length?revenue/tj.length:0;
    const hit=tj.filter((j:any)=>{const r=Number(j.revenue??0);return r>0&&((r-jobCost(j))/r)*100>=floor}).length;
    const hitRate=tj.length?hit/tj.length*100:0;
    const below=tj.length-hit;
    const hourVariance=soldHours>0?hours-soldHours:0;
    const hourEfficiency=soldHours>0&&hours>0?soldHours/hours*100:0;
    const serviceMap=new Map<string,{jobs:number,revenue:number,cost:number,hours:number}>();
    for(const j of tj){const k=j.service_type||'Unclassified',x=serviceMap.get(k)||{jobs:0,revenue:0,cost:0,hours:0};x.jobs++;x.revenue+=Number(j.revenue??0);x.cost+=jobCost(j);x.hours+=workHours(j);serviceMap.set(k,x)}
    const services=[...serviceMap.entries()].map(([name,x])=>({name,...x,gp:x.revenue?((x.revenue-x.cost)/x.revenue)*100:0,rph:x.hours?x.revenue/x.hours:0})).sort((a,b)=>b.revenue-a.revenue);
    return {id:t.id,name:t.name,jobs:tj.length,revenue,cost,gp,hours,soldHours,rph,avg,hitRate,below,hourVariance,hourEfficiency,services};
  });

  return <main style={{fontFamily:'system-ui',maxWidth:1280,margin:'auto',padding:32}}>
    <div style={{display:'flex',justifyContent:'space-between',gap:16,flexWrap:'wrap',alignItems:'baseline'}}><div><h1>Technician Performance</h1><p>Rolling 30-day operating scorecards. GP target is the company setting: <b>{floor.toFixed(1)}%</b>.</p></div>{showManagement&&<Link href="/reports/profitability">GP Control Center →</Link>}</div>
    {error&&<p role="alert">Technician records could not be loaded.</p>}

    <section style={{display:'grid',gap:16,marginTop:24}}>{scorecards.map((t:any)=><article key={t.id} style={{border:'1px solid #ddd',borderRadius:18,padding:20}}>
      <div style={{display:'flex',justifyContent:'space-between',gap:12,flexWrap:'wrap'}}><div><h2 style={{margin:'0 0 4px'}}>{t.name}</h2><small>{t.jobs} completed billed job{t.jobs===1?'':'s'} in the last 30 days</small></div><div style={{textAlign:'right'}}><b style={{fontSize:26}}>{t.gp.toFixed(1)}% GP</b><br/><small>{t.hitRate.toFixed(0)}% target-hit rate</small></div></div>
      <div style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(125px,1fr))',gap:10,marginTop:16}}>{[['Revenue',money.format(t.revenue)],['Actual Cost',money.format(t.cost)],['Average Ticket',money.format(t.avg)],['Work Hours',t.hours.toFixed(1)],['Revenue / Work Hr',money.format(t.rph)],['Sold Hours',t.soldHours.toFixed(1)],['Sold vs Actual',t.soldHours?`${t.hourVariance>=0?'+':''}${t.hourVariance.toFixed(1)} hr`:'No sold-hour data'],['Hour Efficiency',t.soldHours&&t.hours?`${t.hourEfficiency.toFixed(0)}%`:'—'],['Below GP Target',String(t.below)]].map(([a,b])=><span key={a} style={{border:'1px solid #eee',borderRadius:12,padding:10}}><small>{a}</small><br/><b>{b}</b></span>)}</div>
      {showManagement&&t.services.length>0&&<details style={{marginTop:14}}><summary><b>Service-mix breakdown</b> — compare like work before coaching</summary><div style={{overflowX:'auto',marginTop:10}}><table style={{width:'100%',borderCollapse:'collapse'}}><thead><tr>{['Service Type','Jobs','Revenue','GP','Rev / Work Hr'].map(h=><th key={h} style={{textAlign:'left',padding:8,borderBottom:'1px solid #ddd'}}>{h}</th>)}</tr></thead><tbody>{t.services.map((x:any)=><tr key={x.name}><td style={{padding:8}}>{x.name}</td><td>{x.jobs}</td><td>{money.format(x.revenue)}</td><td><b>{x.gp.toFixed(1)}%</b></td><td>{x.hours?money.format(x.rph):'—'}</td></tr>)}</tbody></table></div></details>}
    </article>)}</section>

    {showManagement&&<section style={{marginTop:34}}>
      <h2>ServiceTitan Technician Productivity — Last 30 Days</h2>
      <p>Read-only payroll attribution using job timesheets and job splits. Revenue/hour is based on recorded arrival-to-done field time and split-adjusted job revenue.</p>
      {productivityResult.error?<p role="alert">ServiceTitan productivity data could not be loaded: {productivityResult.error.message}</p>:!hasPayrollData?<p style={{padding:16,border:'1px solid #ddd',borderRadius:14}}>Payroll staging is ready, but no ServiceTitan job-timesheet records have been synced yet. Run the Technician Payroll sync from the ServiceTitan integration page to activate these scorecards.</p>:<div style={{overflowX:'auto'}}><table style={{width:'100%',borderCollapse:'collapse'}}><thead><tr>{['Technician','Completed Jobs','On-site Hours','Dispatch → Arrival','Attributed Revenue','Revenue / On-site Hr'].map(x=><th key={x} style={{textAlign:'left',padding:10,borderBottom:'1px solid #ccc'}}>{x}</th>)}</tr></thead><tbody>{productivityTechs.map((t:any)=><tr key={t.technicianId}><td style={{padding:10,borderBottom:'1px solid #eee'}}><b>{t.name||'Unnamed technician'}</b></td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{Number(t.jobsCompleted??0).toLocaleString()}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{Number(t.onsiteHours??0).toFixed(1)}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{Number(t.dispatchToArrivalHours??0).toFixed(1)} hr</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{money.format(Number(t.attributedRevenue??0))}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{money.format(Number(t.revenuePerOnsiteHour??0))}</td></tr>)}</tbody></table></div>}
      <small>{Number(productivity.timesheetRecords??0).toLocaleString()} timesheet records · {Number(productivity.splitRecords??0).toLocaleString()} split records staged</small>
    </section>}

    {showManagement&&<section style={{marginTop:34}}>
      <h2>ServiceTitan Sales Attribution — Last 30 Days</h2>
      <p>Read-only ServiceTitan data attributed by each job&apos;s sold-by technician. Sales attribution stays separate from labor productivity so the system does not confuse selling with field execution.</p>
      {stResult.error?<p role="alert">ServiceTitan technician sales data could not be loaded: {stResult.error.message}</p>:<div style={{overflowX:'auto'}}><table style={{width:'100%',borderCollapse:'collapse'}}><thead><tr>{['Technician','Sold Jobs','Completed','Revenue','Average Ticket','Last Completed Sale'].map(x=><th key={x} style={{textAlign:'left',padding:10,borderBottom:'1px solid #ccc'}}>{x}</th>)}</tr></thead><tbody>{stTechs.map((t:any)=><tr key={t.technicianId}><td style={{padding:10,borderBottom:'1px solid #eee'}}><b>{t.name||'Unnamed technician'}</b></td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{Number(t.soldJobs??0).toLocaleString()}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{Number(t.completedSoldJobs??0).toLocaleString()}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{money.format(Number(t.revenue??0))}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{money.format(Number(t.averageTicket??0))}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{t.lastSoldJobAt?new Date(t.lastSoldJobAt).toLocaleDateString('en-US',{timeZone:'America/New_York'}):'—'}</td></tr>)}</tbody></table></div>}
    </section>}

    <aside style={{marginTop:28,border:'2px solid #222',borderRadius:16,padding:18}}><h2>Performance guardrail</h2><p>These are transparent operating measurements, not an automatic employee grade. Service mix, access conditions, callbacks, sold scope, material pricing and estimating can change the numbers. Compensation, discipline, scheduling priority and employment decisions remain authorized management decisions.</p></aside>
  </main>;
}
