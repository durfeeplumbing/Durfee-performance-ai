import Link from 'next/link';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';

const money = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 });
function when(value?: string | null) { return value ? new Date(value).toLocaleString('en-US', { timeZone: 'America/New_York' }) : 'Never'; }
function extraCost(j:any){return (j.job_cost_allocations??[]).filter((a:any)=>!a.reversed_at&&a.allocation_type!=='materials').reduce((s:number,a:any)=>s+Number(a.amount??0),0)}
function actualCost(j:any){return Number(j.material_cost??0)+Number(j.labor_cost??0)+Number(j.allocated_overhead??0)+extraCost(j)}

export default async function DashboardPage() {
  const user = await requireCurrentUser();
  const supabase = await createSupabaseServerClient();
  const start = new Date(); start.setHours(0, 0, 0, 0);
  const managerRole=['owner','manager'].includes(user.role);
  const serviceTitanPromise = user.role === 'owner' ? supabase.rpc('service_titan_dashboard_snapshot', { p_since: start.toISOString() }) : Promise.resolve({ data: null, error: null });
  const gpQueuePromise=managerRole?supabase.rpc('gp_closeout_queue'):Promise.resolve({data:[],error:null});

  const [{ data: jobs, error },{ data: settings },{ count: pendingLearning },{ count: dueFollowups },{ data: ap },{ data: serviceTitanData, error: serviceTitanError },gpQueueResult] = await Promise.all([
    supabase.from('jobs').select('id,status,revenue,material_cost,labor_cost,allocated_overhead,completed_at,created_at,job_cost_allocations(amount,allocation_type,reversed_at)').gte('created_at', start.toISOString()),
    supabase.from('company_pricing_settings').select('minimum_gp').limit(1).maybeSingle(),
    supabase.from('price_book_learning_proposals').select('id', { count: 'exact', head: true }).eq('status', 'pending'),
    supabase.from('customer_followups').select('id', { count: 'exact', head: true }).lte('follow_up_at', new Date().toISOString()),
    ['owner', 'manager', 'accounting'].includes(user.role) ? supabase.from('accounts_payable_entries').select('id,balance_due,status,due_date').in('status', ['open', 'partial']) : Promise.resolve({ data: [] }),
    serviceTitanPromise,
    gpQueuePromise,
  ]);

  const rows:any[] = error ? [] : (jobs ?? []),floor = Number(settings?.minimum_gp ?? 50),completedRows=rows.filter(j=>j.completed_at),revenue = completedRows.reduce((sum, j) => sum + Number(j.revenue ?? 0), 0),cost = completedRows.reduce((sum, j) => sum + actualCost(j), 0),gp = revenue > 0 ? ((revenue - cost) / revenue) * 100 : 0,completed = completedRows.length,average = completed ? revenue / completed : 0,belowFloor = completedRows.filter(j => {const r=Number(j.revenue??0),c=actualCost(j);return r>0&&((r-c)/r)*100<floor}).length,openJobs = rows.filter(j => !j.completed_at).length,openAp = (ap ?? []).reduce((sum:number,item:any)=>sum+Number(item.balance_due??0),0),overdueAp=(ap??[]).filter((item:any)=>item.due_date&&new Date(item.due_date)<new Date()).length,gpQueue:any[]=Array.isArray((gpQueueResult as any)?.data)?(gpQueueResult as any).data:[];
  const gpShortfall=completedRows.reduce((sum,j)=>{const r=Number(j.revenue??0),c=actualCost(j),gross=r-c,currentGp=r>0?gross/r*100:0;return sum+(r>0&&currentGp<floor?Math.max(0,r*(floor/100)-gross):0)},0);
  const cards=[
    {label:'Completed Revenue Today',value:money.format(revenue),detail:`${completed} completed Durfee AI jobs`},
    {label:'Actual Gross Profit',value:`${gp.toFixed(1)}%`,detail:`Company floor ${floor.toFixed(1)}%`},
    {label:'Average Ticket',value:money.format(average),detail:'Completed jobs only'},
    {label:'Open Jobs',value:String(openJobs),detail:'Not yet completed'},
    {label:'Below GP Floor',value:String(belowFloor),detail:`${money.format(gpShortfall)} target shortfall`},
    {label:'Pending GP Approvals',value:String(gpQueue.length),detail:'Manager closeout review'},
  ];
  const st=(serviceTitanData??null) as any,stAvailable=user.role==='owner'&&!serviceTitanError&&st,stCards=stAvailable?[
    {label:'ST Completed Today',value:String(st.jobsCompletedToday??0),detail:`${st.jobsCreatedToday??0} jobs created today`},
    {label:'ST Completed Revenue',value:money.format(Number(st.completedJobRevenueToday??0)),detail:'Completed ServiceTitan job totals today'},
    {label:'ST Invoiced Today',value:money.format(Number(st.invoiceTotalToday??0)),detail:'Invoice total dated today'},
    {label:'ST Payments Today',value:money.format(Number(st.paymentsToday??0)),detail:'Payments dated today'},
    {label:'ST Open A/R',value:money.format(Number(st.openAr??0)),detail:`${Number(st.totalInvoices??0).toLocaleString()} invoices cached`},
    {label:'ST Memberships',value:Number(st.activeMemberships??0).toLocaleString(),detail:'Active memberships in the staged feed'},
  ]:[];

  return <main style={{fontFamily:'system-ui',maxWidth:1280,margin:'auto',padding:32}}>
    <header><p style={{fontWeight:800,letterSpacing:1}}>DURFEE PERFORMANCE AI</p><h1>Owner Command Center</h1><p>Live operating data with financial and workflow guardrails.</p></header>
    <section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(190px,1fr))',gap:16,margin:'28px 0'}}>{cards.map(card=><article key={card.label} style={{border:'1px solid #ddd',borderRadius:18,padding:20}}><small>{card.label}</small><h2>{card.value}</h2><p>{card.detail}</p></article>)}</section>
    {gpQueue.length>0&&managerRole&&<aside style={{border:'2px solid #b45309',borderRadius:16,padding:18,margin:'18px 0'}}><h2 style={{marginTop:0}}>Profitability approval needed</h2><p><b>{gpQueue.length}</b> low-GP job{gpQueue.length===1?' is':'s are'} waiting for owner/manager review before closeout.</p><p><Link href="/jobs/gp-approvals">Review low-GP closeouts →</Link></p></aside>}
    {user.role==='owner'?<section style={{margin:'32px 0'}}><div style={{display:'flex',justifyContent:'space-between',gap:16,alignItems:'baseline',flexWrap:'wrap'}}><div><h2 style={{marginBottom:4}}>ServiceTitan Live Snapshot</h2><p style={{marginTop:0}}>Read-only production data from the staged ServiceTitan connector. Native Durfee AI records are not being overwritten.</p></div><Link href="/settings/integrations/servicetitan">Open integration health →</Link></div>{stAvailable?<><section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(190px,1fr))',gap:16,margin:'18px 0'}}>{stCards.map(card=><article key={card.label} style={{border:'1px solid #ddd',borderRadius:18,padding:20}}><small>{card.label}</small><h2>{card.value}</h2><p>{card.detail}</p></article>)}</section><p><small>{Number(st.totalCustomers??0).toLocaleString()} customers • {Number(st.totalJobs??0).toLocaleString()} jobs • {Number(st.totalPayments??0).toLocaleString()} payments cached. Last staged update: {when(st.lastSyncedAt)}.</small></p></>:<article style={{border:'1px solid #ddd',borderRadius:18,padding:20}}><strong>ServiceTitan snapshot unavailable</strong><p>{serviceTitanError?.message??'No staged ServiceTitan data is available yet.'}</p></article>}</section>:null}
    <section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(280px,1fr))',gap:18}}>
      <article style={{border:'1px solid #ddd',borderRadius:18,padding:22}}><h2>Profitability</h2>{belowFloor?<p>🔴 {belowFloor} completed job{belowFloor===1?'':'s'} below the {floor.toFixed(1)}% GP floor today.</p>:<p>✅ No completed jobs today are below the GP floor.</p>}<p><Link href="/reports/profitability">Open technician & service GP scorecards →</Link></p>{['owner','manager'].includes(user.role)&&<p><Link href="/reports/profitability/coach">Open Profitability Coach →</Link></p>}</article>
      <article style={{border:'1px solid #ddd',borderRadius:18,padding:22}}><h2>Price Book Learning</h2><p><b>{pendingLearning??0}</b> pending evidence-based proposal{pendingLearning===1?'':'s'}.</p><p><Link href="/pricebook/learning">Review price-book learning →</Link></p></article>
      <article style={{border:'1px solid #ddd',borderRadius:18,padding:22}}><h2>Customer Follow-Up</h2><p><b>{dueFollowups??0}</b> follow-up{dueFollowups===1?'':'s'} currently due.</p><p><Link href="/csr">Open CSR performance & callbacks →</Link></p></article>
      {['owner','manager','accounting'].includes(user.role)&&<article style={{border:'1px solid #ddd',borderRadius:18,padding:22}}><h2>Accounts Payable</h2><p><b>{money.format(openAp)}</b> open vendor balance • <b>{overdueAp}</b> overdue bill{overdueAp===1?'':'s'}.</p><p><Link href="/accounting/vendor-bills">Review vendor invoices →</Link></p></article>}
      <article style={{border:'1px solid #ddd',borderRadius:18,padding:22}}><h2>AI Operations</h2><p>Recommendations remain advisory. Pricing, payroll, accounting approvals, dispatch changes and personnel decisions require authorized human action.</p></article>
    </section>
  </main>;
}
