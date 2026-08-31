import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';

export const dynamic = 'force-dynamic';
const money=new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:0});
const when=(v?:string|null)=>v?new Date(v).toLocaleString('en-US',{timeZone:'America/New_York'}):'—';

export default async function ServiceTitanCustomerPage({params}:{params:Promise<{id:string}>}){
  await requireCurrentUser();
  const {id}=await params;
  const supabase=await createSupabaseServerClient();
  const {data,error}=await supabase.rpc('get_service_titan_customer_history',{p_customer_id:id});
  if(error||!data||(data as any).customer==null) notFound();
  const h:any=data,c=h.customer||{},a=c.address||{},jobs:any[]=h.jobs||[],appointments:any[]=h.appointments||[],invoices:any[]=h.invoices||[],locations:any[]=h.locations||[];
  return <main style={{fontFamily:'system-ui',maxWidth:1150,margin:'auto',padding:32}}>
    <p><Link href="/customers">← Customer CRM</Link></p>
    <div style={{display:'flex',justifyContent:'space-between',gap:16,flexWrap:'wrap',alignItems:'start'}}><div><h1 style={{marginBottom:6}}>{c.name||`ServiceTitan Customer ${id}`}</h1><p style={{marginTop:0}}>ServiceTitan #{id} • {c.type||'Customer'} • {c.active===false?'Inactive':'Active'}</p><p>{[a.street,a.unit,a.city,a.state,a.zip].filter(Boolean).join(', ')||'No address loaded'}</p></div><span style={{border:'1px solid #bbb',borderRadius:999,padding:'7px 11px'}}>Read-only ServiceTitan</span></div>
    <section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(170px,1fr))',gap:12,margin:'22px 0'}}>{[['Lifetime Jobs',jobs.length],['Locations',locations.length],['Appointments',appointments.length],['Lifetime Invoiced',money.format(Number(h.lifetimeRevenue||0))],['Open A/R',money.format(Number(h.openBalance||0))]].map(([k,v])=><div key={String(k)} style={{border:'1px solid #ddd',borderRadius:14,padding:14}}><small>{k}</small><div style={{fontWeight:800,fontSize:20}}>{v}</div></div>)}</section>
    <h2>ServiceTitan Job History</h2>{jobs.slice(0,100).map((j:any)=><article key={j.id} style={{border:'1px solid #ddd',borderRadius:14,padding:16,margin:'10px 0'}}><h3 style={{margin:'0 0 6px'}}>Job {j.jobNumber||j.id} — {j.jobStatus||'Unknown'}</h3><p>{j.summary||j.summaryOfWork||'No summary loaded.'}</p><p><b>Total:</b> {money.format(Number(j.total||0))} • <b>Completed:</b> {when(j.completedOn)} • <b>Business unit:</b> {j.businessUnitId||'—'}</p></article>)}{!jobs.length&&<p>No ServiceTitan jobs found.</p>}
    <h2 style={{marginTop:30}}>Invoices</h2><div style={{overflowX:'auto'}}><table style={{width:'100%',borderCollapse:'collapse'}}><thead><tr>{['Invoice','Date','Total','Balance','Paid'].map(x=><th key={x} style={{textAlign:'left',padding:10,borderBottom:'1px solid #ccc'}}>{x}</th>)}</tr></thead><tbody>{invoices.slice(0,100).map((i:any)=><tr key={i.id}><td style={{padding:10,borderBottom:'1px solid #eee'}}>{i.referenceNumber||i.id}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{when(i.invoiceDate)}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{money.format(Number(i.total||0))}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{money.format(Number(i.balance||0))}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{when(i.paidOn)}</td></tr>)}</tbody></table></div>
  </main>;
}
