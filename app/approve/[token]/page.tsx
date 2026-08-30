import { notFound } from 'next/navigation';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { acceptCustomerEstimate } from './actions';
const money=new Intl.NumberFormat('en-US',{style:'currency',currency:'USD'});

export default async function CustomerEstimateApprovalPage({params}:{params:Promise<{token:string}>}){
  const {token}=await params;
  const supabase=await createSupabaseServerClient();
  const {data,error}=await supabase.rpc('get_estimate_acceptance',{p_token:token});
  if(error||!data)notFound();
  const options=Array.isArray(data.options)?data.options:[];
  return <main style={{fontFamily:'system-ui',maxWidth:760,margin:'0 auto',padding:'32px 20px 60px'}}>
    <div style={{fontWeight:800,letterSpacing:1}}>DURFEE PLUMBING &amp; HEATING</div>
    <h1>Review &amp; Approve Estimate</h1>
    <p><b>{data.customer_name}</b>{data.service_address?` • ${data.service_address}`:''}</p>
    <p>{data.service_type||'Service'}{data.service_summary?` — ${data.service_summary}`:''}</p>
    <p style={{fontSize:14,opacity:.75}}>This secure approval link expires {new Date(data.expires_at).toLocaleString()}.</p>
    <form action={acceptCustomerEstimate}>
      <input type="hidden" name="token" value={token}/>
      <section style={{display:'grid',gap:14,margin:'24px 0'}}>{options.map((o:any)=><label key={o.id} style={{display:'block',border:'1px solid #ddd',borderRadius:16,padding:18,cursor:'pointer'}}><div style={{display:'flex',gap:12,alignItems:'flex-start'}}><input type="radio" name="option_id" value={o.id} required style={{marginTop:5}}/><div><h2 style={{margin:'0 0 6px'}}>{o.tier}</h2><div style={{fontSize:24,fontWeight:800}}>{money.format(Number(o.price))}</div><p>{o.description}</p></div></div></label>)}</section>
      <label style={{display:'block',margin:'16px 0'}}>Full name<br/><input name="signer_name" required minLength={2} style={{width:'100%',padding:12,fontSize:16}}/></label>
      <label style={{display:'block',margin:'16px 0'}}>Typed signature (optional)<br/><input name="signature_text" placeholder="Type your name as your signature" style={{width:'100%',padding:12,fontSize:16}}/></label>
      <label style={{display:'flex',gap:10,alignItems:'flex-start',margin:'20px 0'}}><input type="checkbox" name="accepted_terms" required/><span>I authorize Durfee Plumbing &amp; Heating to perform the scope of work in the option I selected at the price shown above. I understand that additional work outside this scope requires separate authorization.</span></label>
      <button type="submit" style={{width:'100%',padding:15,fontSize:18,fontWeight:800}}>Approve Selected Option</button>
    </form>
    <p style={{fontSize:13,opacity:.7,marginTop:24}}>Internal job cost, margin, and employee information are not included on this customer approval page.</p>
  </main>;
}
