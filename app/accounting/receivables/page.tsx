import Link from 'next/link';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';

export const dynamic = 'force-dynamic';
const money=new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:0});

export default async function ReceivablesPage(){
  await requireCurrentUser();
  const supabase=await createSupabaseServerClient();
  const {data,error}=await supabase.rpc('service_titan_ar_aging',{p_limit:250});
  const payload:any=data??{};
  const summary:any=payload.summary??{};
  const invoices:any[]=Array.isArray(payload.invoices)?payload.invoices:[];
  const buckets=[
    ['Current',summary.current],
    ['1–30 Days',summary.days1to30],
    ['31–60 Days',summary.days31to60],
    ['61–90 Days',summary.days61to90],
    ['90+ Days',summary.days90plus],
    ['Total Open',summary.totalOpen],
  ];
  return <main style={{fontFamily:'system-ui',maxWidth:1200,margin:'auto',padding:32}}>
    <p><Link href="/dashboard">← Dashboard</Link></p>
    <h1>Accounts Receivable</h1>
    <p>Read-only ServiceTitan invoice balances grouped by due-date aging. Use this as the owner/accounting collection worklist while ServiceTitan remains the source system.</p>
    {error&&<p role="alert">ServiceTitan A/R could not be loaded: {error.message}</p>}
    {!error&&<>
      <section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(150px,1fr))',gap:12,margin:'22px 0'}}>{buckets.map(([label,value])=><div key={String(label)} style={{border:'1px solid #ddd',borderRadius:14,padding:16}}><small>{label}</small><div style={{fontSize:22,fontWeight:800}}>{money.format(Number(value??0))}</div></div>)}</section>
      <p><b>{Number(summary.openInvoices??0).toLocaleString()}</b> invoices currently have an open balance. Showing the oldest/highest-balance 250.</p>
      <div style={{overflowX:'auto'}}><table style={{width:'100%',borderCollapse:'collapse',marginTop:18}}><thead><tr>{['Customer','Invoice','Invoice Date','Due Date','Age','Total','Open Balance'].map(x=><th key={x} style={{textAlign:'left',padding:10,borderBottom:'1px solid #ccc'}}>{x}</th>)}</tr></thead><tbody>{invoices.map((i:any)=><tr key={i.externalId}><td style={{padding:10,borderBottom:'1px solid #eee'}}>{i.customerId?<Link href={`/customers/servicetitan/${i.customerId}`}>{i.customerName||`Customer ${i.customerId}`}</Link>:(i.customerName||'—')}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{i.referenceNumber||i.externalId}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{i.invoiceDate||'—'}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{i.dueDate||'—'}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{Number(i.ageDays??0)} days</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{money.format(Number(i.total??0))}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}><b>{money.format(Number(i.balance??0))}</b></td></tr>)}</tbody></table></div>
    </>}
  </main>;
}
