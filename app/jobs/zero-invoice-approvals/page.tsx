import Link from 'next/link';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';
import { hasPermission } from '@/lib/permissions';
import { approveZeroInvoiceCloseout,rejectZeroInvoiceCloseout } from './actions';

export const dynamic='force-dynamic';
const money=new Intl.NumberFormat('en-US',{style:'currency',currency:'USD'});

export default async function ZeroInvoiceApprovalPage(){
  await requireCurrentUser();
  const allowed=(await hasPermission('manage_jobs'))||(await hasPermission('manage_billing'));
  if(!allowed) return <main style={{fontFamily:'system-ui',maxWidth:900,margin:'auto',padding:32}}><h1>Zero-Invoice Approvals</h1><p>Manager permission required.</p></main>;
  const supabase=await createSupabaseServerClient();
  const {data,error}=await supabase.rpc('zero_invoice_closeout_queue');
  const rows:any[]=Array.isArray(data)?data:[];
  return <main style={{fontFamily:'system-ui',maxWidth:1000,margin:'auto',padding:32}}>
    <p><Link href="/field">← Field</Link></p>
    <h1>Zero-Invoice Closeout Approvals</h1>
    <p>Technicians cannot close a job with a $0 invoice until a manager authorizes it here.</p>
    {error&&<p role="alert">Approval queue could not be loaded: {error.message}</p>}
    {!error&&!rows.length&&<p>No pending zero-dollar closeout requests.</p>}
    <section style={{display:'grid',gap:16,marginTop:24}}>{rows.map((r:any)=><article key={r.jobId} style={{border:'1px solid #ddd',borderRadius:16,padding:18}}>
      <div style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(160px,1fr))',gap:10}}>
        <div><b>{r.customerName||'Customer'}</b><br/><small>{r.serviceAddress||'No address'}</small></div>
        <div>Technician<br/><b>{r.technicianName||'Unassigned'}</b></div>
        <div>Invoice<br/><b>{money.format(Number(r.invoiceTotal??0))}</b></div>
        <div>Requested by<br/><b>{r.requestedBy||'Employee'}</b><br/><small>{r.requestedAt?new Date(r.requestedAt).toLocaleString():'—'}</small></div>
      </div>
      <p><b>{r.serviceType||'Service'}</b>{r.serviceSummary?` — ${r.serviceSummary}`:''}</p>
      <form action={approveZeroInvoiceCloseout} style={{display:'flex',gap:8,flexWrap:'wrap',alignItems:'center'}}>
        <input type="hidden" name="job_id" value={r.jobId}/>
        <input name="manager_note" maxLength={1000} placeholder="Manager note (optional)" style={{minWidth:260,flex:'1 1 260px'}}/>
        <button type="submit">Approve $0 Closeout</button>
      </form>
      <form action={rejectZeroInvoiceCloseout} style={{display:'flex',gap:8,flexWrap:'wrap',alignItems:'center',marginTop:8}}>
        <input type="hidden" name="job_id" value={r.jobId}/>
        <input name="manager_note" maxLength={1000} placeholder="Reason for rejection" style={{minWidth:260,flex:'1 1 260px'}}/>
        <button type="submit">Reject</button>
      </form>
    </article>)}</section>
  </main>;
}
