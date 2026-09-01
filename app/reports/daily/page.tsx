import Link from 'next/link';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';
const money=new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:0});
const one=(v:any)=>Array.isArray(v)?v[0]:v;
function extraCost(j:any){return (j.job_cost_allocations??[]).filter((a:any)=>!a.reversed_at&&a.allocation_type!=='materials').reduce((s:number,a:any)=>s+Number(a.amount??0),0)}
function jobCost(j:any){return Number(j.material_cost??0)+Number(j.labor_cost??0)+Number(j.allocated_overhead??0)+extraCost(j)}

export default async function DailyReportPage(){
  const user=await requireCurrentUser();
  if(!['owner','manager','accounting'].includes(user.role))return <main style={{padding:32}}><h1>Daily Closeout</h1><p>You do not have access to company financial reporting.</p></main>;
  const supabase=await createSupabaseServerClient();
  const start=new Date();start.setHours(0,0,0,0);const now=new Date();
  const canApprove=['owner','manager'].includes(user.role);
  const [{data:jobs,error},{data:inventory},{data:invoices},{data:settings},{data:ap},{data:vendorDrafts},{count:pendingLearning},gpQueueResult]=await Promise.all([
    supabase.from('jobs').select('id,status,revenue,material_cost,labor_cost,allocated_overhead,completed_at,customers(name,customer_code),users(name),job_cost_allocations(amount,allocation_type,reversed_at)').gte('completed_at',start.toISOString()).order('completed_at',{ascending:false}),
    supabase.from('inventory_items').select('id,sku,description,on_hand,reorder_point').order('description'),
    supabase.from('invoices').select('id,job_id,status,total,balance_due,created_at').gte('created_at',start.toISOString()),
    supabase.from('company_pricing_settings').select('minimum_gp').limit(1).maybeSingle(),
    supabase.from('accounts_payable_entries').select('id,invoice_number,total,balance_due,status,due_date,suppliers(name)').in('status',['open','partial']),
    supabase.from('vendor_bill_drafts').select('id,status,total,invoice_number,created_at').in('status',['pending','needs_review']),
    supabase.from('price_book_learning_proposals').select('id',{count:'exact',head:true}).eq('status','pending'),
    canApprove?supabase.rpc('gp_closeout_queue'):Promise.resolve({data:[],error:null})
  ]);
  const minimumGp=Number(settings?.minimum_gp??50),rows:any[]=error?[]:(jobs??[]),revenue=rows.reduce((s,j)=>s+Number(j.revenue??0),0),cost=rows.reduce((s,j)=>s+jobCost(j),0),gp=revenue>0?((revenue-cost)/revenue)*100:0,invoiceJobs=new Set((invoices??[]).map(i=>i.job_id)),exceptions:any[]=[];
  const gpQueue:any[]=Array.isArray((gpQueueResult as any)?.data)?(gpQueueResult as any).data:[];
  rows.forEach((j:any)=>{const r=Number(j.revenue??0),c=jobCost(j),jg=r>0?((r-c)/r)*100:0;if(r>0&&jg<minimumGp)exceptions.push({key:j.id,issue:`${jg.toFixed(1)}% GP — below ${minimumGp.toFixed(1)}% company floor`,severity:'HIGH',href:`/jobs/${j.id}`});if(!invoiceJobs.has(j.id))exceptions.push({key:j.id,issue:'Completed without invoice',severity:'HIGH',href:`/jobs/${j.id}`});if(r<=0)exceptions.push({key:j.id,issue:'Completed with no recorded revenue',severity:'HIGH',href:`/jobs/${j.id}`});});
  gpQueue.forEach((r:any)=>exceptions.push({key:`gp-${r.jobId}`,issue:`Low-GP closeout awaiting manager review — ${r.customerName||'Customer'} • ${Number(r.gp??0).toFixed(1)}% GP vs ${Number(r.minimumGp??minimumGp).toFixed(1)}% target`,severity:'HIGH',href:'/jobs/gp-approvals'}));
  const reorder=(inventory??[]).filter(i=>Number(i.on_hand)<=Number(i.reorder_point));reorder.forEach(i=>exceptions.push({key:i.sku,issue:`Inventory reorder: ${i.description}`,severity:'MEDIUM',href:'/purchasing'}));
  const overdueAp=(ap??[]).filter((x:any)=>x.due_date&&new Date(x.due_date)<now);overdueAp.forEach((x:any)=>exceptions.push({key:x.invoice_number||x.id,issue:`Vendor bill overdue — ${one(x.suppliers)?.name||'Vendor'} • ${money.format(Number(x.balance_due||0))}`,severity:'HIGH',href:'/accounting/vendor-bills'}));
  const openAp=(ap??[]).reduce((s:any,x:any)=>s+Number(x.balance_due??0),0),unpaidCustomer=(invoices??[]).reduce((s:any,x:any)=>s+Number(x.balance_due??0),0),reviewBills=vendorDrafts?.length??0;
  if(reviewBills)exceptions.push({key:'vendor-review',issue:`${reviewBills} vendor invoice${reviewBills===1?'':'s'} awaiting accounting review`,severity:'HIGH',href:'/accounting/vendor-bills'});
  if(pendingLearning)exceptions.push({key:'price-learning',issue:`${pendingLearning} price-book learning proposal${pendingLearning===1?'':'s'} awaiting owner review`,severity:'MEDIUM',href:'/pricebook/learning'});
  return <main style={{fontFamily:'system-ui',maxWidth:1200,margin:'auto',padding:32}}>
    <div style={{display:'flex',justifyContent:'space-between',gap:12,flexWrap:'wrap'}}><div><h1>Daily Owner Closeout</h1><p>One end-of-day exception report for profitability, billing, vendor accounting and inventory. Current GP floor: <b>{minimumGp.toFixed(1)}%</b>.</p></div>{canApprove&&<p><Link href="/jobs/gp-approvals">Low-GP Approval Queue →</Link></p>}</div>
    {error&&<p role="alert">Today’s completed jobs could not be fully loaded.</p>}
    <section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(170px,1fr))',gap:12,margin:'24px 0'}}>{[['Revenue',money.format(revenue)],['Gross Profit',`${gp.toFixed(1)}%`],['Completed',String(rows.length)],['Exceptions',String(exceptions.length)],['Low-GP Pending',String(gpQueue.length)],['Open AP',money.format(openAp)],['Overdue AP',String(overdueAp.length)],['Customer Balance Today',money.format(unpaidCustomer)],['Vendor Review',String(reviewBills)]].map(([a,b])=><article key={a} style={{border:'1px solid #ddd',borderRadius:16,padding:18}}><small>{a}</small><h2>{b}</h2></article>)}</section>
    <h2>Management Exceptions</h2>{exceptions.map((e,i)=><article key={`${e.key}-${i}`} style={{borderBottom:'1px solid #eee',padding:'14px 0'}}><b>{e.severity}</b> — {e.issue} {e.href&&<Link href={e.href}>Review →</Link>}</article>)}{!exceptions.length&&<p>Nothing currently requires exception review.</p>}
    <h2 style={{marginTop:30}}>Completed Jobs</h2>{rows.map((j:any)=>{const r=Number(j.revenue??0),c=jobCost(j),jg=r>0?((r-c)/r)*100:0,cust=one(j.customers),tech=one(j.users);return <article key={j.id} style={{borderBottom:'1px solid #eee',padding:'14px 0'}}><Link href={`/jobs/${j.id}`}><b>{cust?.customer_code} {cust?.name||j.id.slice(0,8)}</b></Link> • {tech?.name||'Unassigned'} • Revenue {money.format(r)} • Cost {money.format(c)} • GP {jg.toFixed(1)}% {r>0&&jg<minimumGp?'• BELOW TARGET':''} • {j.status}</article>})}
    <aside style={{marginTop:28,border:'2px solid #222',borderRadius:16,padding:18}}><h2>Closeout Rule</h2><p>The report includes active vendor-bill allocations in actual job cost, surfaces pending low-GP approvals, missing invoices, inventory shortages, overdue vendor bills, unreviewed vendor invoice scans and pending price-book learning. It does not silently post payments, change prices, alter payroll or make personnel decisions.</p></aside>
  </main>;
}
