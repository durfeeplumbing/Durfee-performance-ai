import Link from 'next/link';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';

export const dynamic='force-dynamic';

const money=new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:0});

function extraCost(j:any){
  return (j.job_cost_allocations??[])
    .filter((a:any)=>!a.reversed_at&&a.allocation_type!=='materials')
    .reduce((s:number,a:any)=>s+Number(a.amount??0),0);
}

function jobCost(j:any){
  return Number(j.material_cost??0)+Number(j.labor_cost??0)+Number(j.allocated_overhead??0)+extraCost(j);
}

function workHours(j:any){
  return (j.time_entries??[])
    .filter((x:any)=>x.entry_type==='work'&&x.ended_at)
    .reduce((s:number,x:any)=>s+Math.max(0,(new Date(x.ended_at).getTime()-new Date(x.started_at).getTime())/3600000),0);
}

export default async function TeamPage(){
  const user=await requireCurrentUser();
  const s=await createSupabaseServerClient();
  const mgmt=['owner','manager'].includes(user.role);

  let tq=s.from('users').select('id,name,role,active').eq('role','technician').eq('active',true).order('name');
  if(user.role==='technician') tq=tq.eq('id',user.id);

  const start=new Date();
  start.setDate(start.getDate()-30);

  let jq=s.from('jobs').select('id,technician_id,status,service_type,revenue,material_cost,labor_hours,labor_cost,allocated_overhead,completed_at,time_entries(entry_type,started_at,ended_at),job_cost_allocations(amount,allocation_type,reversed_at)').gte('completed_at',start.toISOString());
  if(user.role==='technician') jq=jq.eq('technician_id',user.id);

  const [{data:techs,error},{data:jobs},{data:settings},callbacks]=await Promise.all([
    tq,
    jq,
    s.from('company_pricing_settings').select('minimum_gp').limit(1).maybeSingle(),
    s.rpc('technician_callback_snapshot',{p_days:30}),
  ]);

  const floor=Number(settings?.minimum_gp??50);
  const [st,prod,funnel,recalls]=mgmt
    ?await Promise.all([
      s.rpc('service_titan_technician_sales_performance',{p_days:30}),
      s.rpc('service_titan_technician_productivity',{p_days:30}),
      s.rpc('service_titan_technician_sales_funnel',{p_days:30}),
      s.rpc('service_titan_recall_snapshot',{p_days:90}),
    ])
    :[{data:null,error:null},{data:null,error:null},{data:null,error:null},{data:null,error:null}];

  const stTechs:any[]=Array.isArray(st.data)?st.data:[];
  const p:any=prod.data??{};
  const pTechs:any[]=Array.isArray(p.technicians)?p.technicians:[];
  const cb:any[]=Array.isArray(callbacks.data)?callbacks.data:[];
  const sf:any[]=Array.isArray(funnel.data)?funnel.data:[];
  const rec:any=recalls.data??{};

  const cards=(techs??[]).map((t:any)=>{
    const tj=(jobs??[]).filter((j:any)=>j.technician_id===t.id&&Number(j.revenue??0)>0);
    const revenue=tj.reduce((a:number,j:any)=>a+Number(j.revenue??0),0);
    const cost=tj.reduce((a:number,j:any)=>a+jobCost(j),0);
    const gp=revenue?((revenue-cost)/revenue)*100:0;
    const hours=tj.reduce((a:number,j:any)=>a+workHours(j),0);
    const sold=tj.reduce((a:number,j:any)=>a+Number(j.labor_hours??0),0);
    const hit=tj.filter((j:any)=>{
      const r=Number(j.revenue??0);
      return r&&((r-jobCost(j))/r)*100>=floor;
    }).length;
    const c=cb.find((x:any)=>x.technicianId===t.id)||{};

    return {
      id:t.id,
      name:t.name,
      jobs:tj.length,
      revenue,
      cost,
      gp,
      hours,
      sold,
      rph:hours?revenue/hours:0,
      avg:tj.length?revenue/tj.length:0,
      hitRate:tj.length?hit/tj.length*100:0,
      below:tj.length-hit,
      eff:sold&&hours?sold/hours*100:0,
      callbacks:Number(c.callbacks??0),
      preventable:Number(c.preventableCallbacks??0),
      callbackCost:Number(c.callbackCost??0),
      callbackRate:Number(c.callbackRate??0),
    };
  });

  return <main style={{fontFamily:'system-ui',maxWidth:1280,margin:'auto',padding:32}}>
    <div style={{display:'flex',justifyContent:'space-between',gap:16,flexWrap:'wrap'}}>
      <div>
        <h1>Technician Performance</h1>
        <p>30-day operating scorecards. GP target: <b>{floor.toFixed(1)}%</b>. Callback quality uses manager-reviewed incidents only.</p>
        {!mgmt&&<p><small>Your scorecard shows your operating and sales metrics. Internal company cost and callback-cost detail stays management-only.</small></p>}
      </div>
      {mgmt&&<div><Link href="/reports/profitability">GP Control Center</Link> · <Link href="/jobs/callbacks">Callbacks</Link></div>}
    </div>

    {error&&<p role="alert">Technicians could not be loaded.</p>}
    {callbacks.error&&<p role="alert">Callback quality metrics could not be loaded.</p>}

    <section style={{display:'grid',gap:16,marginTop:24}}>
      {cards.map((t:any)=>{
        const metrics:[string,string][]=[
          ['Revenue',money.format(t.revenue)],
          ['Avg Ticket',money.format(t.avg)],
          ['Work Hours',t.hours.toFixed(1)],
          ['Revenue / Hr',money.format(t.rph)],
          ['Sold Hours',t.sold.toFixed(1)],
          ['Hour Efficiency',t.sold&&t.hours?`${t.eff.toFixed(0)}%`:'—'],
          ['Below GP',String(t.below)],
          ['Reviewed Callbacks',String(t.callbacks)],
          ['Preventable',String(t.preventable)],
          ['Callback Rate',`${t.callbackRate.toFixed(1)}%`],
        ];
        if(mgmt){
          metrics.splice(1,0,['Actual Cost',money.format(t.cost)]);
          metrics.push(['Callback Cost',money.format(t.callbackCost)]);
        }

        return <article key={t.id} style={{border:'1px solid #ddd',borderRadius:18,padding:20}}>
          <div style={{display:'flex',justifyContent:'space-between',gap:12,flexWrap:'wrap'}}>
            <div><h2 style={{margin:0}}>{t.name}</h2><small>{t.jobs} completed billed jobs</small></div>
            <div style={{textAlign:'right'}}><b style={{fontSize:26}}>{t.gp.toFixed(1)}% GP</b><br/><small>{t.hitRate.toFixed(0)}% target-hit</small></div>
          </div>
          <div style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(125px,1fr))',gap:10,marginTop:16}}>
            {metrics.map(([a,b])=><span key={a} style={{border:'1px solid #eee',borderRadius:12,padding:10}}><small>{a}</small><br/><b>{b}</b></span>)}
          </div>
        </article>;
      })}
    </section>

    {mgmt&&<section style={{marginTop:34}}>
      <h2>ServiceTitan Sales Funnel — Last 30 Days</h2>
      <p>Sales attribution stays separate from field execution. “Jobs with estimate” is an opportunity-context signal, <b>not a true close-rate denominator</b> until estimate status/decision records are synced.</p>
      {funnel.error?<p role="alert">Sales funnel unavailable: {funnel.error.message}</p>:<div style={{overflowX:'auto'}}><table style={{width:'100%',borderCollapse:'collapse'}}><thead><tr>{['Technician','Jobs w/ Estimate','Sold Jobs','Completed Sold','Sold Revenue','Avg Sold Ticket','Recall Jobs'].map(x=><th key={x} style={{textAlign:'left',padding:9,borderBottom:'1px solid #ccc'}}>{x}</th>)}</tr></thead><tbody>{sf.map((x:any)=><tr key={x.technicianId}><td style={{padding:9}}><b>{x.name||'Unnamed'}</b></td><td>{x.jobsWithEstimate}</td><td>{x.soldJobs}</td><td>{x.completedSoldJobs}</td><td>{money.format(Number(x.soldRevenue??0))}</td><td>{money.format(Number(x.averageSoldTicket??0))}</td><td>{x.recallJobs}</td></tr>)}</tbody></table></div>}
      <p><small>ServiceTitan also contains <b>{Number(rec.recalls??0)}</b> recall-linked jobs in the last 90 days. These are kept separate from manager-reviewed FSM callbacks because a ServiceTitan recall link alone does not establish preventability.</small></p>
    </section>}

    {mgmt&&<section style={{marginTop:34}}>
      <h2>ServiceTitan Field Productivity</h2>
      {prod.error?<p role="alert">Productivity unavailable.</p>:Number(p.timesheetRecords??0)===0?<p>No job-timesheet records synced yet.</p>:<div style={{overflowX:'auto'}}><table style={{width:'100%',borderCollapse:'collapse'}}><thead><tr>{['Technician','Completed','On-site Hrs','Dispatch → Arrival','Attributed Revenue','Revenue / On-site Hr'].map(x=><th key={x} style={{textAlign:'left',padding:9,borderBottom:'1px solid #ccc'}}>{x}</th>)}</tr></thead><tbody>{pTechs.map((x:any)=><tr key={x.technicianId}><td style={{padding:9}}><b>{x.name}</b></td><td>{x.jobsCompleted}</td><td>{Number(x.onsiteHours??0).toFixed(1)}</td><td>{Number(x.dispatchToArrivalHours??0).toFixed(1)} hr</td><td>{money.format(Number(x.attributedRevenue??0))}</td><td>{money.format(Number(x.revenuePerOnsiteHour??0))}</td></tr>)}</tbody></table></div>}
    </section>}

    {mgmt&&stTechs.length>0&&<details style={{marginTop:24}}><summary>Legacy ServiceTitan sold-by snapshot</summary><p>{stTechs.length} technician records available. The sales funnel above supersedes this for management review.</p></details>}

    <aside style={{marginTop:28,border:'2px solid #222',borderRadius:16,padding:18}}>
      <h2>Performance guardrail</h2>
      <p>These are operating measurements, not automatic employee grades. Callback attribution requires manager review; ServiceTitan recalls are informational. Service mix, access conditions, sold scope, pricing and estimating can change the numbers. Compensation, discipline and employment decisions remain human management decisions.</p>
    </aside>
  </main>;
}
