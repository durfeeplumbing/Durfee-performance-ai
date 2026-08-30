import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';

const money=new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:0});

export default async function DashboardPage(){
  await requireCurrentUser();
  const supabase=await createSupabaseServerClient();
  const start=new Date(); start.setHours(0,0,0,0);
  const {data:jobs,error}=await supabase.from('jobs').select('id,status,revenue,material_cost,labor_cost,allocated_overhead,completed_at,created_at').gte('created_at',start.toISOString());
  const rows=error?[]:(jobs??[]);
  const revenue=rows.reduce((sum,j)=>sum+Number(j.revenue??0),0);
  const cost=rows.reduce((sum,j)=>sum+Number(j.material_cost??0)+Number(j.labor_cost??0)+Number(j.allocated_overhead??0),0);
  const gp=revenue>0?((revenue-cost)/revenue)*100:0;
  const completed=rows.filter(j=>j.completed_at).length;
  const average=completed?revenue/completed:0;
  const belowFloor=rows.filter(j=>{const r=Number(j.revenue??0);const c=Number(j.material_cost??0)+Number(j.labor_cost??0)+Number(j.allocated_overhead??0);return r>0&&((r-c)/r)*100<50}).length;
  const openJobs=rows.filter(j=>!j.completed_at).length;
  const cards=[
    {label:'Revenue Today',value:money.format(revenue),detail:`${rows.length} jobs recorded today`},
    {label:'Gross Profit',value:`${gp.toFixed(1)}%`,detail:'Floor 50%'},
    {label:'Average Ticket',value:money.format(average),detail:`${completed} completed jobs`},
    {label:'Open Jobs',value:String(openJobs),detail:'Not yet completed'},
    {label:'Below GP Floor',value:String(belowFloor),detail:'Needs owner review'}
  ];
  return <main style={{fontFamily:'system-ui',maxWidth:1280,margin:'auto',padding:32}}><header><p style={{fontWeight:800,letterSpacing:1}}>DURFEE PERFORMANCE AI</p><h1>Owner Command Center</h1><p>Live operating data from the secured FSM database.</p></header><section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(190px,1fr))',gap:16,margin:'28px 0'}}>{cards.map(c=><article key={c.label} style={{border:'1px solid #ddd',borderRadius:18,padding:20}}><small>{c.label}</small><h2>{c.value}</h2><p>{c.detail}</p></article>)}</section><section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(300px,1fr))',gap:20}}><article style={{border:'1px solid #ddd',borderRadius:18,padding:22}}><h2>Needs Attention</h2>{belowFloor?<p>🔴 {belowFloor} job{belowFloor===1?'':'s'} below 50% GP</p>:<p>✅ No jobs recorded today are below the 50% GP floor.</p>}</article><article style={{border:'1px solid #ddd',borderRadius:18,padding:22}}><h2>AI Operations</h2><p>Recommendations remain advisory. Pricing and other consequential changes require authorized approval.</p></article></section></main>;
}
