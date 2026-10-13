import 'server-only';
import { createSupabaseAdminClient } from '@/lib/supabase/admin';
import { normalizeCall,applyCallAttributions,uniquePageJobRevenue,identifier, type RawRecord } from './attribution';
export async function websiteReportData(days:number){
 const db=createSupabaseAdminClient(),since=new Date(Date.now()-days*86400000).toISOString();
 async function readPages(query:()=>any){const rows:any[]=[];let error=false,truncated=false;for(let offset=0;offset<=10000;offset+=1000){const r=await query().range(offset,offset+999);if(r.error){error=true;break;}rows.push(...(r.data||[]));if(rows.length>10000){truncated=true;rows.length=10000;break;}if((r.data?.length||0)<1000)break;}return {data:rows,error,truncated};}
 const [events,records,health]=await Promise.all([
  readPages(()=>db.from('website_events').select('event_kind,page_path,entry_path,session_id,source,medium,received_at').gte('received_at',since).order('received_at',{ascending:false}).order('id')),
  readPages(()=>db.from('website_servicetitan_records').select('kind,payload,occurred_at,synced_at').eq('environment','production').gte('occurred_at',since).order('occurred_at',{ascending:false}).order('kind').order('external_id')),
  db.from('website_sync_health').select('*'),
 ]);
 const raw=records.data;
 const calls=applyCallAttributions(raw.filter(r=>r.kind==='call').map(r=>normalizeCall(r.payload)).filter(c=>c.when&&c.when>=since),raw.filter(r=>r.kind==='attributed_lead').map(r=>r.payload)).sort((a,b)=>(b.when||'').localeCompare(a.when||''));
 const jobs:RawRecord[]=[];let jobsError=false;
 const callIds=calls.map(c=>c.id);for(let i=0;i<callIds.length;i+=100){const r=await db.from('service_titan_records').select('payload,synced_at').eq('resource','jobs').in('payload->>leadCallId',callIds.slice(i,i+100));if(r.error)jobsError=true;else for(const row of r.data||[])jobs.push(row.payload);}
 const byCall=new Map(jobs.map(j=>[identifier(j.leadCallId),identifier(j.id)]));for(const c of calls)c.jobId=c.jobId??byCall.get(c.id)??null;
 const known=new Set(jobs.map(j=>identifier(j.id)));const ids=[...new Set(calls.flatMap(c=>c.jobId&&!known.has(c.jobId)?[c.jobId]:[]))];
 for(let i=0;i<ids.length;i+=100){const r=await db.from('service_titan_records').select('payload').eq('resource','jobs').in('external_id',ids.slice(i,i+100));if(r.error)jobsError=true;else for(const row of r.data||[])jobs.push(row.payload);}
 return {events:events.data,calls,health:health.data||[],revenue:uniquePageJobRevenue(calls,jobs),jobsError:jobsError||!health.data?.some(h=>h.name==='jobs'&&h.status==='ready'),
 eventsError:events.error,callsError:records.error,healthError:!!health.error,truncated:events.truncated||records.truncated};
}
