import Link from 'next/link';
import {createSupabaseServerClient} from '@/lib/supabase/server';
import {requireCurrentUser} from '@/lib/session';

const money=new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:0});
const one=(v:any)=>Array.isArray(v)?v[0]:v;
function extraCost(j:any){return (j.job_cost_allocations??[]).filter((a:any)=>!a.reversed_at&&a.allocation_type!=='materials').reduce((s:number,a:any)=>s+Number(a.amount??0),0)}
function aggregate(rows:any[],key:(r:any)=>string,floor:number){const m=new Map<string,any[]>();for(const r of rows){const k=key(r)||'Unassigned';m.set(k,[...(m.get(k)??[]),r])}return [...m.entries()].map(([name,jobs])=>{const revenue=jobs.reduce((s,j)=>s+j.revenue,0),cost=jobs.reduce((s,j)=>s+j.cost,0),gp=revenue>0?(revenue-cost)/revenue*100:0,low=jobs.filter(j=>j.gp<floor),shortfall=low.reduce((s,j)=>s+Math.max(0,j.revenue*(floor/100)-j.gross),0);return {name,n:jobs.length,revenue,cost,gp,low:low.length,hitRate:jobs.length?(jobs.length-low.length)/jobs.length*100:0,shortfall}})}

export default async function ProfitCoach(){
  const user=await requireCurrentUser();if(!['owner','manager'].includes(user.role))return <main style={{padding:32}}><h1>Profitability Coach</h1><p>No access.</p></main>;
  const s=await createSupabaseServerClient(),since=new Date(Date.now()-90*86400000);
  const [{data:jobs},{data:settings}]=await Promise.all([
    s.from('jobs').select('id,status,service_type,revenue,material_cost,labor_hours,labor_cost,allocated_overhead,technician_id,completed_at,users!jobs_technician_id_fkey(name),customers(name,customer_code),job_cost_allocations(amount,allocation_type,reversed_at)').gte('completed_at',since.toISOString()).gt('revenue',0).order('completed_at',{ascending:false}).limit(1000),
    s.from('company_pricing_settings').select('minimum_gp').limit(1).maybeSingle()
  ]);
  const floor=Number(settings?.minimum_gp??50),rows=(jobs??[]).map((j:any)=>{const revenue=Number(j.revenue??0),m=Number(j.material_cost??0),l=Number(j.labor_cost??0),o=Number(j.allocated_overhead??0),x=extraCost(j),cost=m+l+o+x,gross=revenue-cost,gp=revenue>0?gross/revenue*100:0;return {...j,revenue,m,l,o,x,cost,gross,gp}}),low=rows.filter(r=>r.gp<floor),service=aggregate(rows,r=>r.service_type||'Unclassified',floor),tech=aggregate(rows,r=>one(r.users)?.name||'Unassigned',floor),serviceRisks=service.filter(x=>x.n>=2&&(x.gp<floor+5||x.hitRate<75)).sort((a,b)=>a.gp-b.gp),techRisks=tech.filter(x=>x.n>=3&&(x.gp<floor+5||x.hitRate<75)).sort((a,b)=>a.gp-b.gp),materialHeavy=low.filter(r=>r.m/r.revenue>.3).sort((a,b)=>b.m/b.revenue-a.m/a.revenue).slice(0,10),laborHeavy=low.filter(r=>r.l/r.revenue>.25).sort((a,b)=>b.l/b.revenue-a.l/a.revenue).slice(0,10),vendorHeavy=low.filter(r=>r.x/r.revenue>.1).sort((a,b)=>b.x/b.revenue-a.x/a.revenue).slice(0,10),lost=low.reduce((a,r)=>a+Math.max(0,floor/100*r.revenue-r.gross),0);
  const broadServiceProblems=new Set(serviceRisks.filter(x=>x.n>=3&&x.hitRate<60).map(x=>x.name));
  return <main style={{fontFamily:'system-ui',maxWidth:1200,margin:'auto',padding:32}}>
    <div style={{display:'flex',justifyContent:'space-between',gap:12,flexWrap:'wrap'}}><div><h1>Profitability Coach</h1><p>90-day management coaching from completed-job economics. Recommendations only — no automatic pricing, payroll or personnel actions.</p></div><Link href="/reports/profitability">GP Control Center →</Link></div>
    <section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(180px,1fr))',gap:12,margin:'22px 0'}}>{[['Jobs analyzed',String(rows.length)],['Below GP floor',String(low.length)],['GP opportunity',money.format(lost)],['Service risks',String(serviceRisks.length)],['Tech coaching flags',String(techRisks.length)]].map(([a,b])=><article key={a} style={{border:'1px solid #ddd',borderRadius:14,padding:16}}><small>{a}</small><h2>{b}</h2></article>)}</section>
    <h2>Recommended Management Review</h2>
    {serviceRisks.map(x=><article key={`s-${x.name}`} style={{border:'1px solid #ddd',borderRadius:14,padding:14,margin:'10px 0'}}><b>PRICE BOOK / OPERATIONS • {x.name}</b><p>{x.n} completed jobs produced {x.gp.toFixed(1)}% weighted GP with a {x.hitRate.toFixed(0)}% target-hit rate; {x.low} were below the {floor.toFixed(1)}% floor. GP shortfall: <b>{money.format(x.shortfall)}</b>. Review sold price, expected labor, material allowance, vendor costs and scope consistency.</p></article>)}
    {techRisks.map(x=><article key={`t-${x.name}`} style={{border:'1px solid #ddd',borderRadius:14,padding:14,margin:'10px 0'}}><b>{broadServiceProblems.size?'COACHING / JOB-MIX REVIEW':'COACHING REVIEW'} • {x.name}</b><p>{x.n} completed billed jobs produced {x.gp.toFixed(1)}% weighted GP with a {x.hitRate.toFixed(0)}% target-hit rate; {x.low} were below floor. GP shortfall: <b>{money.format(x.shortfall)}</b>. Compare this technician's service mix against the service-type scorecards before attributing the result to field execution.</p></article>)}
    {!serviceRisks.length&&!techRisks.length&&<p>No sustained technician or service-type profitability pattern currently needs coaching review.</p>}
    <h2>Cost Pattern Flags</h2>
    <p><b>Material-heavy low-GP jobs:</b> {materialHeavy.length}. Review PO/vendor invoice cost, material allowance, substitutions and field quantity usage.</p>
    <p><b>Labor-heavy low-GP jobs:</b> {laborHeavy.length}. Compare sold hours to actual hours and check scope, training, access conditions, callbacks and dispatch fit.</p>
    <p><b>Other vendor-cost-heavy low-GP jobs:</b> {vendorHeavy.length}. Review subcontractor, equipment, permit and other AP allocations for estimate coverage.</p>
    <aside style={{marginTop:28,border:'2px solid #222',borderRadius:14,padding:16}}><h2>Decision guardrail</h2><p>A flag is evidence to investigate, not proof that a technician or CSR caused the problem. The coach uses weighted job economics and separates broad service-type weakness from technician-level patterns to reduce misleading conclusions. Any pricing, compensation, disciplinary or staffing change remains an authorized management decision.</p></aside>
  </main>;
}
