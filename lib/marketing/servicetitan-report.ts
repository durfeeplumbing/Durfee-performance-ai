import 'server-only';
import { createHash } from 'node:crypto';
import { createSupabaseAdminClient } from '@/lib/supabase/admin';
import { serviceTitanConnectionInfo, serviceTitanGet } from '@/lib/servicetitan';
export async function syncWebsiteCalls(inspect=false){
 const info=serviceTitanConnectionInfo();
 const now=new Date(),since=new Date(now.getTime()-30*86400000);
 const endpoints=[
  ['call',`/telecom/v2/tenant/{tenant}/calls?createdOnOrAfter=${encodeURIComponent(since.toISOString())}`],
  ['attributed_lead',`/marketing-ads/v2/tenant/{tenant}/attributed-leads?fromUtc=${encodeURIComponent(new Date(now.getTime()-86400000).toISOString())}&toUtc=${encodeURIComponent(now.toISOString())}`],
 ] as const;
 const results=[];
 for(const[kind,path]of endpoints){
  let count=0;const shapes:unknown[]=[];
  try{
   for(let page=1;page<=50;page++){
    const data=await serviceTitanGet<{data?:Record<string,unknown>[];hasMore?:boolean}>(`${path}&page=${page}&pageSize=100&includeTotal=true`);
    if(!Array.isArray(data.data))throw new Error('Unexpected ServiceTitan response shape');
    if(page===1&&data.data[0])shapes.push(shape(data.data[0]));
    if(inspect){count=data.data.length;break;}
    const rows=data.data.map(record=>({kind,environment:info.environment,
     external_id:String(record.id??record.callId??createHash('sha256').update(JSON.stringify(record)).digest('hex')),
     payload:record,occurred_at:validDate(record.createdOn??record.dateTime??record.createdAt??record.date),synced_at:new Date().toISOString()}));
    if(rows.length){const{error}=await createSupabaseAdminClient().from('website_servicetitan_records').upsert(rows,{onConflict:'kind,external_id,environment'});if(error)throw new Error('Could not save ServiceTitan report');}
    count+=rows.length;if(!data.hasMore)break;if(page===50)throw new Error('Report exceeds sync page limit');
   }
   if(!inspect)await createSupabaseAdminClient().from('website_sync_health').upsert({name:kind,status:'ready',last_attempt_at:new Date().toISOString(),last_success_at:new Date().toISOString(),records:count,detail:info.environment==='production'?null:'ServiceTitan is connected to the integration environment; these are not production results.'});
   results.push({kind,ok:true,count,shapes});
  }catch(error){const raw=error instanceof Error?error.message:'';
   const code=raw.match(/\((\d{3})\)/)?.[1];
   const message=code?`ServiceTitan returned HTTP ${code}. Check this application's Telecom / Marketing Ads API access.`:'ServiceTitan sync did not complete.';
   if(!inspect)await createSupabaseAdminClient().from('website_sync_health').upsert({name:kind,status:'error',last_attempt_at:new Date().toISOString(),detail:message,records:count});
   results.push({kind,ok:false,count,error:message});
  }
 }
 return {environment:info.environment,results};
}
function validDate(value:unknown){if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}T/.test(value)||!Number.isFinite(Date.parse(value)))return null;return new Date(value).toISOString();}
function shape(v:unknown,depth=0):unknown{if(depth>3)return typeof v;if(Array.isArray(v))return v.length?[shape(v[0],depth+1)]:[];if(v&&typeof v==='object')return Object.fromEntries(Object.entries(v).map(([k,value])=>[k,shape(value,depth+1)]));return v===null?'null':typeof v;}
