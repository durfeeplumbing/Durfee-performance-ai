import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';
import { googleMarketingConfigured } from '@/lib/integrations/google-marketing';
import { metaMarketingConfigured } from '@/lib/integrations/meta-marketing';

export const dynamic='force-dynamic';
const label=(p:string)=>p==='google_ads'?'Google Ads':'Facebook / Instagram';

export default async function MarketingProvidersPage(){
 await requireCurrentUser();const supabase=await createSupabaseServerClient();const [{data:connections},{data:queue}]=await Promise.all([supabase.rpc('marketing_provider_connection_summary'),supabase.rpc('marketing_sync_queue_summary')]);const rows:any[]=(connections as any[])??[],q:any[]=(queue as any[])??[];
 return <main style={{fontFamily:'system-ui',maxWidth:1100,margin:'auto',padding:32}}><header><p style={{fontWeight:800,letterSpacing:1}}>AD PLATFORM CONNECTIONS</p><h1>Provider Readiness</h1><p>The Durfee side is staged first. Authorization is the final external switch: tokens remain server-side and pending conversions are not sent until the business account is explicitly connected.</p></header>
 <section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(320px,1fr))',gap:18,marginTop:24}}>{['google_ads','meta_ads'].map(provider=>{const r=rows.find(x=>x.provider===provider)||{};const configured=provider==='google_ads'?googleMarketingConfigured():metaMarketingConfigured();const pending=q.filter(x=>x.provider===provider&&['waiting_authorization','ready','failed'].includes(x.status)).reduce((s,x)=>s+Number(x.event_count||0),0);return <article key={provider} style={{border:'1px solid #ddd',borderRadius:16,padding:20}}><h2 style={{marginTop:0}}>{label(provider)}</h2><p><b>Status:</b> {String(r.connection_status||'authorization_required').replaceAll('_',' ')}</p><p><b>Server connector:</b> {configured?'Configuration present':'Credentials not added yet'}</p><p><b>Conversions staged:</b> {pending.toLocaleString()}</p>{r.account_name&&<p><b>Account:</b> {r.account_name}</p>}{r.last_synced_at&&<p><b>Last sync:</b> {new Date(r.last_synced_at).toLocaleString()}</p>}{r.last_error&&<p role="alert"><b>Last error:</b> {r.last_error}</p>}</article>;})}</section>
 <section style={{border:'1px solid #ddd',borderRadius:16,padding:20,marginTop:24}}><h2 style={{marginTop:0}}>Authorization checkpoint</h2><p>Nothing needs to be authorized yet. When you decide to activate this, we will authorize the actual Google Ads business account and Meta Business/ad account, verify the correct account IDs and scopes, then activate the provider queues. No passwords, refresh tokens or access tokens should be pasted into chat.</p><p>For Google, the connector is being prepared for the current offline/enhanced-lead conversion path rather than assuming the older click-upload workflow.</p></section>
 </main>;
}
