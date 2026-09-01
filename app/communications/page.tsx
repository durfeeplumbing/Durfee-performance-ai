import Link from 'next/link';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';
import { dialpadConnected } from '@/lib/integrations/dialpad';
import { queueCommunication,recordCommunication } from './actions';

export const dynamic='force-dynamic';

const badge=(v:string)=>({display:'inline-block',border:'1px solid #ccc',borderRadius:999,padding:'2px 8px',fontSize:12,marginRight:6} as const);
const when=(v:string)=>new Date(v).toLocaleString('en-US',{timeZone:'America/New_York',month:'short',day:'numeric',hour:'numeric',minute:'2-digit'});

export default async function CommunicationsPage(){
  const user=await requireCurrentUser();
  const s=await createSupabaseServerClient();
  const [inbox,manage,customers,jobs]=await Promise.all([
    s.rpc('customer_communication_inbox',{p_days:30}),
    s.rpc('has_permission_for_current_user',{p_key:'manage_csr'}),
    s.from('customers').select('id,name,phone,email').order('name').limit(500),
    s.from('jobs').select('id,customer_id,service_type,status,scheduled_start').in('status',['scheduled','en_route','on_site','work_complete']).order('scheduled_start',{ascending:false}).limit(300),
  ]);
  const rows:any[]=Array.isArray(inbox.data)?inbox.data:[];
  const canManage=['owner','manager'].includes(user.role)||manage.data===true;
  const dialpadApiReady=dialpadConnected();
  const dialpadWebhookReady=Boolean(process.env.DIALPAD_WEBHOOK_SECRET?.trim());
  const supabaseWebhookReady=Boolean((process.env.SUPABASE_SECRET_KEY||process.env.SUPABASE_SERVICE_ROLE_KEY)?.trim());
  const dialpadReady=dialpadApiReady&&dialpadWebhookReady&&supabaseWebhookReady;
  const inbound=rows.filter(r=>r.direction==='inbound').length;
  const missed=rows.filter(r=>r.status==='missed').length;
  const followup=rows.filter(r=>r.bookingOutcome==='follow_up'||r.status==='queued').length;
  const booked=rows.filter(r=>r.bookingOutcome==='booked').length;

  return <main style={{fontFamily:'system-ui',maxWidth:1320,margin:'auto',padding:32}}>
    <div style={{display:'flex',justifyContent:'space-between',gap:16,flexWrap:'wrap'}}>
      <div><h1>Customer Communications</h1><p>One timeline for phone calls, SMS and email, with job/customer attribution, booking outcomes, transcripts and AI summaries.</p></div>
      <div><Link href="/csr">CSR</Link> · <Link href="/reviews">Reviews</Link> · <Link href="/customers">Customers</Link></div>
    </div>

    <section style={{border:`2px solid ${dialpadReady?'#4d7':'#ca8'}`,borderRadius:16,padding:16,margin:'18px 0'}}>
      <h2 style={{marginTop:0}}>Dialpad {dialpadReady?'Ready':'Connection Setup'}</h2>
      <p>{dialpadReady?'Phone calls and SMS can be started directly from Durfee Performance AI. Signed Dialpad call/text events will return to this timeline automatically.':'The Durfee side is built. Add the Dialpad API key, webhook signing secret, and Supabase server secret to the deployment environment to turn on live calls/texts.'}</p>
      <p><small>Webhook: <code>https://durfee-performance-ai.vercel.app/api/integrations/dialpad/webhook</code></small></p>
      {user.role==='owner'&&<p><small>Server checks: API key {dialpadApiReady?'✓':'—'} · webhook secret {dialpadWebhookReady?'✓':'—'} · database server key {supabaseWebhookReady?'✓':'—'}. Dialpad SMS also requires business-messaging registration. Enable SMS-content export for message bodies and recordings export if you want recording links returned to the FSM.</small></p>}
    </section>

    {inbox.error&&<p role="alert">Communications inbox unavailable: {inbox.error.message}</p>}
    <section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(150px,1fr))',gap:10,margin:'20px 0'}}>
      {[["30-Day Activity",rows.length],["Inbound",inbound],["Missed Calls",missed],["Needs Follow-up",followup],["Booked",booked]].map(([a,b])=><article key={String(a)} style={{border:'1px solid #ddd',borderRadius:14,padding:14}}><small>{a}</small><h2>{String(b)}</h2></article>)}
    </section>

    {canManage&&<section style={{border:'1px solid #ccc',borderRadius:18,padding:20,marginBottom:26}}>
      <h2>Compose / Start Contact</h2>
      <p><small>Phone and SMS run through Dialpad when connected. Email stays in the same queue/timeline and will become live when the email delivery provider is connected.</small></p>
      <form action={queueCommunication} style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(190px,1fr))',gap:10}}>
        <label>Customer<br/><select name="customer_id" required defaultValue=""><option value="" disabled>Select customer</option>{(customers.data??[]).map((c:any)=><option key={c.id} value={c.id}>{c.name} — {c.phone||c.email||'no contact'}</option>)}</select></label>
        <label>Channel<br/><select name="channel" defaultValue="sms"><option value="phone">Phone</option><option value="sms">SMS</option><option value="email">Email</option></select></label>
        <label>Destination<br/><input name="to" required placeholder="Phone number or email"/></label>
        <label>Job (optional)<br/><select name="job_id" defaultValue=""><option value="">No job</option>{(jobs.data??[]).map((j:any)=><option key={j.id} value={j.id}>{j.service_type||'Service'} — {j.status}</option>)}</select></label>
        <label>Subject (email)<br/><input name="subject" placeholder="Optional subject"/></label>
        <label style={{gridColumn:'1 / -1'}}>Message / call purpose<br/><textarea name="body" rows={3} placeholder="SMS or email body; for phone, optional call purpose" style={{width:'100%'}}/></label>
        <div><button type="submit">Send / Start Communication</button></div>
      </form>
    </section>}

    {canManage&&<details style={{marginBottom:26}}><summary><b>Record a call/text/email manually</b></summary>
      <p><small>This is useful during provider rollout or for communications that happened outside the FSM.</small></p>
      <form action={recordCommunication} style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(180px,1fr))',gap:9}}>
        <label>Customer<br/><select name="customer_id" required defaultValue=""><option value="" disabled>Select customer</option>{(customers.data??[]).map((c:any)=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
        <label>Channel<br/><select name="channel" defaultValue="phone"><option value="phone">Phone</option><option value="sms">SMS</option><option value="email">Email</option></select></label>
        <label>Direction<br/><select name="direction"><option value="inbound">Inbound</option><option value="outbound">Outbound</option></select></label>
        <label>Status<br/><select name="status"><option value="received">Received</option><option value="completed">Completed</option><option value="missed">Missed</option><option value="delivered">Delivered</option><option value="failed">Failed</option></select></label>
        <label>From<br/><input name="from"/></label><label>To<br/><input name="to"/></label>
        <label>Duration seconds<br/><input name="duration_seconds" type="number" min="0"/></label>
        <label>Booking outcome<br/><select name="booking_outcome"><option value="none">None</option><option value="booked">Booked</option><option value="not_booked">Not booked</option><option value="follow_up">Follow-up</option></select></label>
        <label>Related job<br/><select name="job_id" defaultValue=""><option value="">No job</option>{(jobs.data??[]).map((j:any)=><option key={j.id} value={j.id}>{j.service_type||'Service'} — {j.status}</option>)}</select></label>
        <label>Booked job<br/><select name="booked_job_id" defaultValue=""><option value="">None</option>{(jobs.data??[]).map((j:any)=><option key={j.id} value={j.id}>{j.service_type||'Service'} — {j.status}</option>)}</select></label>
        <label>Subject<br/><input name="subject"/></label><label>Disposition<br/><input name="disposition" placeholder="Booked, estimate question, no answer…"/></label>
        <label style={{gridColumn:'1 / -1'}}>Message / notes<br/><textarea name="body" rows={2} style={{width:'100%'}}/></label>
        <label style={{gridColumn:'1 / -1'}}>AI / CSR summary<br/><textarea name="ai_summary" rows={2} style={{width:'100%'}}/></label>
        <label style={{gridColumn:'1 / -1'}}>Transcript<br/><textarea name="transcript" rows={4} style={{width:'100%'}}/></label>
        <div><button type="submit">Record Communication</button></div>
      </form>
    </details>}

    <section><h2>Unified Timeline</h2>
      {rows.map((r:any)=><article key={r.communicationId} style={{border:'1px solid #ddd',borderRadius:16,padding:16,margin:'10px 0'}}>
        <div style={{display:'flex',justifyContent:'space-between',gap:12,flexWrap:'wrap'}}>
          <div><span style={badge(r.channel)}>{String(r.channel).toUpperCase()}</span><span style={badge(r.direction)}>{r.direction}</span><span style={badge(r.status)}>{r.status}</span><b>{r.customerName}</b>{r.serviceType?` — ${r.serviceType}`:''}</div>
          <small>{when(r.occurredAt)}</small>
        </div>
        {r.subject&&<p><b>{r.subject}</b></p>}
        {r.body&&<p>{r.body}</p>}
        {r.aiSummary&&<p><b>Summary:</b> {r.aiSummary}</p>}
        <p><small>{r.fromAddress?`From ${r.fromAddress} `:''}{r.toAddress?`→ ${r.toAddress} `:''}{r.durationSeconds?`• ${Math.round(Number(r.durationSeconds)/60)} min `:''}{r.disposition?`• ${r.disposition} `:''}{r.bookingOutcome&&r.bookingOutcome!=='none'?`• ${r.bookingOutcome.replace('_',' ')}`:''}</small></p>
        {r.transcript&&<details><summary>Transcript</summary><p style={{whiteSpace:'pre-wrap'}}>{r.transcript}</p></details>}
        {r.recordingUrl&&<p><a href={r.recordingUrl} target="_blank" rel="noreferrer">Open recording</a></p>}
        {r.jobId&&<Link href={`/jobs/${r.jobId}`}>Open related job</Link>}{r.bookedJobId&&<> · <Link href={`/jobs/${r.bookedJobId}`}>Open booked job</Link></>}
      </article>)}
      {!rows.length&&!inbox.error&&<p>No phone, text or email activity recorded yet.</p>}
    </section>

    <aside style={{marginTop:28,border:'2px solid #222',borderRadius:16,padding:18}}><h2>Communications guardrail</h2><p>Call recordings and transcripts are management/CSR-detail data and are withheld from lower-privilege views. AI summaries and booking metrics are operational context, not automatic employee discipline. Provider webhook signatures and credentials must live in deployment secrets, never in this repository.</p></aside>
  </main>;
}
