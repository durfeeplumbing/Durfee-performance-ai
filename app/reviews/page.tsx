import Link from 'next/link';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';
import { recordReviewRequest,recordReviewResult } from './actions';

export const dynamic='force-dynamic';

export default async function ReviewsPage(){
  const user=await requireCurrentUser();
  const s=await createSupabaseServerClient();
  const canManage=['owner','manager','csr_dispatch'].includes(user.role);
  const {data,error}=await s.rpc('review_management_queue',{p_days:30});
  const rows:any[]=Array.isArray(data)?data:[];
  const recommended=rows.filter(r=>r.reviewRecommended);
  const requested=rows.filter(r=>r.status==='requested');
  const received=rows.filter(r=>r.status==='received');
  const avg=received.length?received.reduce((n,r)=>n+Number(r.rating??0),0)/received.length:0;

  return <main style={{fontFamily:'system-ui',maxWidth:1250,margin:'auto',padding:32}}>
    <div style={{display:'flex',justifyContent:'space-between',gap:14,flexWrap:'wrap'}}>
      <div><h1>Customer Review Management</h1><p>Completed jobs become review candidates, but callback/comeback quality issues are checked before a public review request is recorded.</p></div>
      <div><Link href="/jobs/callbacks">Callback Review</Link> · <Link href="/team">Technician Performance</Link></div>
    </div>
    {error&&<p role="alert">Review queue unavailable: {error.message}</p>}

    <section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(170px,1fr))',gap:12,margin:'22px 0'}}>
      {[
        ['Recommended Now',String(recommended.length)],
        ['Requests Outstanding',String(requested.length)],
        ['Reviews Recorded',String(received.length)],
        ['Average Rating',received.length?`${avg.toFixed(2)} / 5`:'—'],
      ].map(([a,b])=><article key={a} style={{border:'1px solid #ddd',borderRadius:14,padding:16}}><small>{a}</small><h2>{b}</h2></article>)}
    </section>

    <section><h2>Recommended Review Requests</h2><p><small>A job is recommended only when completed within 14 days and there is no pending, preventable, or mixed callback review tied to that original job.</small></p>
      {recommended.map(r=><article key={r.jobId} style={{border:'1px solid #ddd',borderRadius:16,padding:18,margin:'12px 0'}}>
        <div style={{display:'flex',justifyContent:'space-between',gap:12,flexWrap:'wrap'}}><div><h3 style={{margin:0}}>{r.customerName}</h3><small>{r.serviceType||'Service'} • {r.technicianName||'Unassigned'} • completed {r.completedAt?new Date(r.completedAt).toLocaleDateString('en-US',{timeZone:'America/New_York'}):'—'}</small><p>{r.serviceAddress}</p></div><Link href={`/jobs/${r.jobId}`}>Open Job</Link></div>
        {canManage&&<form action={recordReviewRequest} style={{display:'flex',gap:8,flexWrap:'wrap',alignItems:'end'}}><input type="hidden" name="job_id" value={r.jobId}/><label>Channel<br/><select name="channel" defaultValue={r.customerPhone?'sms':r.customerEmail?'email':'phone'}><option value="sms">SMS</option><option value="email">Email</option><option value="phone">Phone</option><option value="manual">Manual</option></select></label><label style={{flex:'1 1 280px'}}>Internal note<br/><input name="note" placeholder="Optional note" style={{width:'100%'}}/></label><button type="submit">Record Review Request</button></form>}
      </article>)}
      {!recommended.length&&!error&&<p>No jobs currently meet the recommended review-request criteria.</p>}
    </section>

    <section style={{marginTop:30}}><h2>Outstanding Requests</h2>
      {requested.map(r=><article key={r.jobId} style={{border:'1px solid #ddd',borderRadius:16,padding:18,margin:'12px 0'}}><h3>{r.customerName} — {r.serviceType||'Service'}</h3><p>Requested by <b>{r.channel||'manual'}</b>{r.requestedAt?` on ${new Date(r.requestedAt).toLocaleDateString('en-US',{timeZone:'America/New_York'})}`:''} • Technician: {r.technicianName||'Unassigned'}</p>{canManage&&<form action={recordReviewResult} style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(160px,1fr))',gap:8}}><input type="hidden" name="job_id" value={r.jobId}/><label>Rating<br/><select name="rating" defaultValue="5">{[5,4,3,2,1].map(n=><option value={n} key={n}>{n} stars</option>)}</select></label><label>Platform<br/><input name="platform" placeholder="Google, Facebook, etc."/></label><label>Review URL<br/><input name="external_url" placeholder="Optional URL"/></label><label>Customer feedback<br/><input name="feedback" placeholder="Optional summary"/></label><label>Manager note<br/><input name="note" placeholder="Optional note"/></label><div><br/><button type="submit">Record Received Review</button></div></form>}</article>)}
      {!requested.length&&!error&&<p>No outstanding review requests.</p>}
    </section>

    <section style={{marginTop:30}}><h2>Recent Reviews</h2><div style={{overflowX:'auto'}}><table style={{width:'100%',borderCollapse:'collapse'}}><thead><tr>{['Customer','Technician','Service','Rating','Platform','Received','Feedback'].map(h=><th key={h} style={{textAlign:'left',padding:9,borderBottom:'1px solid #bbb'}}>{h}</th>)}</tr></thead><tbody>{received.map(r=><tr key={r.jobId}><td style={{padding:9}}><Link href={`/jobs/${r.jobId}`}>{r.customerName}</Link></td><td>{r.technicianName||'—'}</td><td>{r.serviceType||'—'}</td><td><b>{r.rating}/5</b></td><td>{r.externalReviewUrl?<a href={r.externalReviewUrl} target="_blank" rel="noreferrer">{r.reviewPlatform||'Review'}</a>:r.reviewPlatform||'—'}</td><td>{r.reviewReceivedAt?new Date(r.reviewReceivedAt).toLocaleDateString('en-US',{timeZone:'America/New_York'}):'—'}</td><td>{r.feedback||'—'}</td></tr>)}</tbody></table></div></section>

    <aside style={{marginTop:28,border:'2px solid #222',borderRadius:16,padding:18}}><h2>Review safeguard</h2><p>The FSM does not automatically ask a customer for a public review when the related job has an unresolved or manager-confirmed quality callback. Review records are customer-experience context, not automatic employee grades. Sending SMS/email itself is not enabled by this screen yet; the channel records how the request was made until the messaging integration is connected.</p></aside>
  </main>;
}
