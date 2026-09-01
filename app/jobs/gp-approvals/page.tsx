import Link from 'next/link';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';
import { hasPermission } from '@/lib/permissions';
import { approveGpCloseout,rejectGpCloseout } from './actions';

export const dynamic='force-dynamic';
const money=new Intl.NumberFormat('en-US',{style:'currency',currency:'USD'});

export default async function GpApprovalPage(){
  const user=await requireCurrentUser();
  const allowed=['owner','manager'].includes(user.role)&&((await hasPermission('manage_jobs'))||(await hasPermission('manage_billing')));
  if(!allowed)return <main style={{fontFamily:'system-ui',maxWidth:900,margin:'auto',padding:32}}><h1>Low-GP Approvals</h1><p>Owner or manager authorization is required.</p></main>;
  const supabase=await createSupabaseServerClient();
  const {data,error}=await supabase.rpc('gp_closeout_queue');
  const rows:any[]=Array.isArray(data)?data:[];
  return <main style={{fontFamily:'system-ui',maxWidth:1050,margin:'auto',padding:32}}>
    <p><Link href="/field">← Field</Link> · <Link href="/jobs/zero-invoice-approvals">$0 Invoice Queue</Link> · <Link href="/reports/profitability">Profitability Report</Link></p>
    <h1>Low-GP Closeout Approvals</h1>
    <p>Jobs below the company minimum gross-profit target cannot be closed by the field until an owner or manager reviews the current economics. Approval is single-use and becomes invalid if revenue, costs, or the company GP target change.</p>
    {error&&<p role="alert">Approval queue could not be loaded: {error.message}</p>}
    {!error&&!rows.length&&<p>No pending low-GP closeout requests.</p>}
    <section style={{display:'grid',gap:16,marginTop:24}}>{rows.map((r:any)=><article key={r.jobId} style={{border:'2px solid #b00020',borderRadius:16,padding:18}}>
      <div style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(150px,1fr))',gap:10}}>
        <div><b>{r.customerName||'Customer'}</b><br/><small>{r.serviceAddress||'No address'}</small></div>
        <div>Technician<br/><b>{r.technicianName||'Unassigned'}</b></div>
        <div>Revenue<br/><b>{money.format(Number(r.revenue??0))}</b></div>
        <div>Recorded cost<br/><b>{money.format(Number(r.cost??0))}</b></div>
        <div>Current GP<br/><b>{Number(r.gp??0).toFixed(1)}%</b></div>
        <div>Minimum GP<br/><b>{Number(r.minimumGp??0).toFixed(1)}%</b></div>
      </div>
      <p><b>{r.serviceType||'Service'}</b>{r.serviceSummary?` — ${r.serviceSummary}`:''}</p>
      <p><small>Requested by {r.requestedBy||'Employee'} • {r.requestedAt?new Date(r.requestedAt).toLocaleString('en-US',{timeZone:'America/New_York'}):'—'}</small></p>
      <form action={approveGpCloseout} style={{display:'flex',gap:8,flexWrap:'wrap',alignItems:'center'}}><input type="hidden" name="job_id" value={r.jobId}/><input name="manager_note" maxLength={1000} placeholder="Approval reason / coaching note" style={{minWidth:280,flex:'1 1 280px'}}/><button type="submit">Authorize Low-GP Closeout</button></form>
      <form action={rejectGpCloseout} style={{display:'flex',gap:8,flexWrap:'wrap',alignItems:'center',marginTop:8}}><input type="hidden" name="job_id" value={r.jobId}/><input name="manager_note" required minLength={3} maxLength={1000} placeholder="Reason to reject / correction required" style={{minWidth:280,flex:'1 1 280px'}}/><button type="submit">Reject — Correct Job</button></form>
      <p><Link href={`/jobs/${r.jobId}`}>Open full job record →</Link></p>
    </article>)}</section>
  </main>;
}
