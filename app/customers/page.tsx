import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';

export default async function CustomersPage(){
  await requireCurrentUser();
  const supabase=await createSupabaseServerClient();
  const {data,error}=await supabase.from('customers').select('id,name,phone,email,service_address,created_at').order('created_at',{ascending:false}).limit(100);
  const customers=error?[]:(data??[]);
  return <main style={{fontFamily:'system-ui',maxWidth:1200,margin:'auto',padding:32}}><h1>Customer CRM</h1><p>Live customer records from the secured FSM database.</p>{error&&<p role="alert">Customer records could not be loaded.</p>}<div style={{overflowX:'auto'}}><table style={{width:'100%',borderCollapse:'collapse',marginTop:24}}><thead><tr>{['Customer','Phone','Email','Service Address'].map(x=><th key={x} style={{textAlign:'left',padding:12,borderBottom:'1px solid #ccc'}}>{x}</th>)}</tr></thead><tbody>{customers.map(c=><tr key={c.id}><td style={{padding:12,borderBottom:'1px solid #eee'}}>{c.name}</td><td style={{padding:12,borderBottom:'1px solid #eee'}}>{c.phone||'—'}</td><td style={{padding:12,borderBottom:'1px solid #eee'}}>{c.email||'—'}</td><td style={{padding:12,borderBottom:'1px solid #eee'}}>{c.service_address||'—'}</td></tr>)}</tbody></table>{!customers.length&&!error&&<p style={{marginTop:24}}>No customers have been added yet.</p>}</div></main>;
}
