import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';

export const dynamic = 'force-dynamic';
const money=new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:0});

export default async function TeamPage(){
  const user=await requireCurrentUser();
  const supabase=await createSupabaseServerClient();
  let techQuery=supabase.from('users').select('id,name,role,active').eq('role','technician').eq('active',true).order('name');
  if(user.role==='technician')techQuery=techQuery.eq('id',user.id);
  const {data:techs,error}=await techQuery;
  const start=new Date();start.setDate(start.getDate()-30);
  const {data:jobs}=await supabase.from('jobs').select('id,technician_id,status,revenue,material_cost,labor_cost,allocated_overhead,completed_at,time_entries(entry_type,started_at,ended_at)').gte('completed_at',start.toISOString());
  const showServiceTitan=['owner','manager'].includes(user.role);
  const stResult=showServiceTitan?await supabase.rpc('service_titan_technician_sales_performance',{p_days:30}):{data:null,error:null};
  const stTechs:any[]=Array.isArray(stResult.data)?stResult.data:[];

  return <main style={{fontFamily:'system-ui',maxWidth:1200,margin:'auto',padding:32}}>
    <h1>Technician Performance</h1>
    <p>Rolling 30-day scorecards based on completed-job revenue, profitability and captured field time.</p>
    {error&&<p role="alert">Technician records could not be loaded.</p>}
    <section style={{display:'grid',gap:14,marginTop:24}}>{(techs??[]).map((t:any)=>{const tj=(jobs??[]).filter((j:any)=>j.technician_id===t.id),revenue=tj.reduce((s:number,j:any)=>s+Number(j.revenue??0),0),cost=tj.reduce((s:number,j:any)=>s+Number(j.material_cost??0)+Number(j.labor_cost??0)+Number(j.allocated_overhead??0),0),gp=revenue>0?((revenue-cost)/revenue)*100:0,hours=tj.reduce((sum:number,j:any)=>sum+(j.time_entries??[]).filter((x:any)=>x.entry_type==='work'&&x.ended_at).reduce((s:number,x:any)=>s+(new Date(x.ended_at).getTime()-new Date(x.started_at).getTime())/3600000,0),0),rph=hours>0?revenue/hours:0,below=tj.filter((j:any)=>{const r=Number(j.revenue??0),c=Number(j.material_cost??0)+Number(j.labor_cost??0)+Number(j.allocated_overhead??0);return r>0&&((r-c)/r)*100<50}).length,score=Math.max(0,Math.min(100,Math.round((Math.min(gp/55,1)*50)+(Math.min(rph/500,1)*30)+(tj.length?Math.max(0,1-below/tj.length)*20:0))));return <article key={t.id} style={{border:'1px solid #ddd',borderRadius:18,padding:20,display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(120px,1fr))',gap:12}}><strong>{t.name}<br/><small>Technician</small></strong><span>Score<br/><b>{score}</b></span><span>GP<br/><b>{gp.toFixed(1)}%</b></span><span>Revenue<br/><b>{money.format(revenue)}</b></span><span>Rev/Hr<br/><b>{money.format(rph)}</b></span><span>Jobs<br/><b>{tj.length}</b></span><span>Below 50% GP<br/><b>{below}</b></span></article>})}</section>

    {showServiceTitan&&<section style={{marginTop:34}}>
      <h2>ServiceTitan Sales Attribution — Last 30 Days</h2>
      <p>Read-only ServiceTitan data attributed by each job&apos;s <code>soldById</code>. This measures sold-job revenue and average ticket; it is not yet a complete measure of technician labor productivity.</p>
      {stResult.error?<p role="alert">ServiceTitan technician sales data could not be loaded: {stResult.error.message}</p>:<div style={{overflowX:'auto'}}><table style={{width:'100%',borderCollapse:'collapse'}}><thead><tr>{['Technician','Sold Jobs','Completed','Revenue','Average Ticket','Last Completed Sale'].map(x=><th key={x} style={{textAlign:'left',padding:10,borderBottom:'1px solid #ccc'}}>{x}</th>)}</tr></thead><tbody>{stTechs.map((t:any)=><tr key={t.technicianId}><td style={{padding:10,borderBottom:'1px solid #eee'}}><b>{t.name||'Unnamed technician'}</b></td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{Number(t.soldJobs??0).toLocaleString()}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{Number(t.completedSoldJobs??0).toLocaleString()}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{money.format(Number(t.revenue??0))}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{money.format(Number(t.averageTicket??0))}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{t.lastSoldJobAt?new Date(t.lastSoldJobAt).toLocaleDateString('en-US',{timeZone:'America/New_York'}):'—'}</td></tr>)}</tbody></table></div>}
    </section>}

    <aside style={{marginTop:28,border:'1px solid #ddd',borderRadius:16,padding:18}}><h2>Coaching, not autopilot</h2><p>Scores are management indicators derived from recorded operating data. They should support coaching and investigation, not automatically determine discipline, compensation, scheduling priority, or employment decisions.</p></aside>
  </main>;
}
