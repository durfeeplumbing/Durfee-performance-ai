import 'server-only';
import { createHash } from 'node:crypto';
import { createSupabaseAdminClient } from '@/lib/supabase/admin';
import { serviceTitanConnectionInfo, serviceTitanGet } from '@/lib/servicetitan';
import { safeWebsitePath } from './website-events';
type RecordData=Record<string,any>;
export async function syncWebsiteCalls(inspect=false,backfill=false){
 const info=serviceTitanConnectionInfo(),db=createSupabaseAdminClient();
 const now=new Date(),since=new Date(now.getTime()-90*86400000);
 const {data:health}=await db.from('website_sync_health').select('last_success_at').eq('name','attributed_lead').maybeSingle();
 const start=!backfill&&health?.last_success_at?new Date(Math.max(since.getTime(),Date.parse(health.last_success_at)-2*86400000)):since;
 const leadPaths:string[]=[];
 for(let time=start.getTime();time<now.getTime();time+=86400000){const end=Math.min(time+86400000,now.getTime());leadPaths.push(`/marketingads/v2/tenant/{tenant}/attributed-leads?fromUtc=${encodeURIComponent(new Date(time).toISOString())}&toUtc=${encodeURIComponent(new Date(end).toISOString())}&leadType=Call`);}
 const endpoints=[
  {kind:'call',paths:[`/telecom/v2/tenant/{tenant}/calls?createdOnOrAfter=${encodeURIComponent(since.toISOString())}`]},
  {kind:'attributed_lead',paths:inspect?leadPaths.slice(-1):leadPaths},
  {kind:'jobs',paths:[`/jpm/v2/tenant/{tenant}/jobs?createdOnOrAfter=${encodeURIComponent(since.toISOString())}`]},
 ];
 const results=[];
 for(const{kind,paths}of endpoints){
  let count=0;const shapes:unknown[]=[];
  try{
   for(const path of paths)for(let page=1;page<=100;page++){
    const data=await serviceTitanGet<{data?:RecordData[];hasMore?:boolean}>(`${path}&page=${page}&pageSize=100&includeTotal=true`);
    if(!Array.isArray(data.data))throw new Error('Unexpected ServiceTitan response shape');
    if(!shapes.length&&data.data[0])shapes.push(shape(data.data[0]));
    if(inspect){count+=data.data.length;break;}
    if(kind==='jobs'){
     // Existing operational job records supply explicit leadCallId and job totals.
     if(info.environment!=='production')throw new Error('Production jobs require production connection');
     const rows=data.data.map(r=>({resource:'jobs',external_id:String(r.id),payload:r,external_modified_at:validDate(r.modifiedOn),synced_at:new Date().toISOString()}));
     if(rows.length){const{error}=await db.from('service_titan_records').upsert(rows,{onConflict:'resource,external_id'});if(error)throw new Error('Could not save jobs');}
    }else{
     const rows=data.data.map(record=>{const payload=compact(kind,record);return {kind,environment:info.environment,
      external_id:kind==='call'?String(record.leadCall?.id??record.id):createHash('sha256').update(`${record.leadType}:${record.call?.id??''}:${record.dateTime}`).digest('hex'),
      payload,occurred_at:validDate(record.leadCall?.receivedOn??record.leadCall?.createdOn??record.createdOn??record.dateTime),synced_at:new Date().toISOString()};});
     if(rows.length){const unique=[...new Map(rows.map(r=>[r.external_id,r])).values()];const{error}=await db.from('website_servicetitan_records').upsert(unique,{onConflict:'kind,external_id,environment'});if(error)throw new Error('Could not save ServiceTitan report');}
    }
    count+=data.data.length;if(!data.hasMore)break;if(page===100)throw new Error('Report exceeds sync page limit');
   }
   if(!inspect){const{error}=await db.from('website_sync_health').upsert({name:kind,status:'ready',last_attempt_at:new Date().toISOString(),last_success_at:new Date().toISOString(),records:count,detail:info.environment==='production'?null:'Integration environment; these are not production results.'});if(error)throw new Error('Could not record sync status');}
   results.push({kind,ok:true,count,...(inspect?{shapes}:{})});
  }catch(error){const raw=error instanceof Error?error.message:'';const code=raw.match(/\((\d{3})\)/)?.[1];
   const message=code?`ServiceTitan returned HTTP ${code}. Check ${kind==='attributed_lead'?'Marketing Ads attributed-leads (tn.mads.attributedleads:r)':kind==='jobs'?'Jobs':'Telecom calls'} API access.`:'ServiceTitan sync did not complete.';
   if(!inspect)await db.from('website_sync_health').upsert({name:kind,status:'error',last_attempt_at:new Date().toISOString(),detail:message,records:count});
   results.push({kind,ok:false,count,error:message});
  }
 }
 return {environment:info.environment,results};
}
function compact(kind:string,r:RecordData){
 if(kind==='call'){const c=r.leadCall??r;return {id:c.id,receivedOn:c.receivedOn,createdOn:c.createdOn,callType:c.callType,direction:c.direction,duration:c.duration,customerId:c.customer?.id};}
 return {dateTime:r.dateTime,leadType:r.leadType,call:{id:r.call?.id},job:{id:r.job?.id},attribution:{landingPageUrl:safeWebsitePath(r.attribution?.landingPageUrl),utmSource:r.attribution?.utmSource,utmMedium:r.attribution?.utmMedium,utmCampaign:r.attribution?.utmCampaign}};
}
function validDate(value:unknown){if(typeof value!=='string'||!Number.isFinite(Date.parse(value)))return null;return new Date(value).toISOString();}
function shape(v:unknown,depth=0):unknown{if(depth>3)return typeof v;if(Array.isArray(v))return v.length?[shape(v[0],depth+1)]:[];if(v&&typeof v==='object')return Object.fromEntries(Object.entries(v).map(([k,value])=>[k,shape(value,depth+1)]));return v===null?'null':typeof v;}
