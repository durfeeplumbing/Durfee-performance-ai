import { safeWebsitePath } from './website-events';
export type RawRecord=Record<string,any>;
export type CallRow={id:string;when:string|null;status:string;direction:string;customerId:string|null;jobId:string|null;landingPage:string|null;source:string|null;duration:string|null};
export function identifier(v:unknown):string|null{if(typeof v==='number'&&Number.isSafeInteger(v)&&v>0)return String(v);if(typeof v==='string'&&/^[1-9]\d*$/.test(v))return v;return null;}
export function normalizeCall(record:RawRecord):CallRow{
 const call=record.leadCall&&typeof record.leadCall==='object'?record.leadCall:record;
 return {id:identifier(call.id)??identifier(record.id)??'',when:typeof call.receivedOn==='string'?call.receivedOn:typeof call.createdOn==='string'?call.createdOn:null,
 status:String(record.callType??call.callType??call.type??'Unknown'),direction:String(call.direction??record.direction??'Unknown'),
 customerId:identifier(record.customer?.id??call.customer?.id??record.customerId),jobId:identifier(record.jobId??call.jobId),
 landingPage:null,source:null,duration:call.duration==null?null:String(call.duration)};
}
// Only explicit ServiceTitan call IDs may link attribution to a call. Never infer
// an individual caller's page from a shared phone number, campaign, or timestamp.
export function applyCallAttributions(calls:CallRow[],leads:RawRecord[]){
 const byId=new Map(calls.map(c=>[c.id,c]));
 for(const lead of leads){
  const id=identifier(lead.callId??lead.call?.id);if(!id)continue;
  const call=byId.get(id);if(!call)continue;
  const page=safeWebsitePath(lead.attribution?.landingPageUrl??lead.landingPageUrl??lead.landingPage??lead.url);
  if(page){call.landingPage=page;call.source=typeof lead.attribution?.utmSource==='string'?lead.attribution.utmSource:typeof lead.utmSource==='string'?lead.utmSource:null;}
  call.jobId=identifier(lead.job?.id)??call.jobId;
 }
 return calls;
}
export function uniquePageJobRevenue(calls:CallRow[],jobs:RawRecord[]){
 const byJob=new Map(jobs.map(j=>[identifier(j.id),j]));
 const assignments=new Map<string,Set<string>>();
 for(const call of calls)if(call.jobId&&call.landingPage){const pages=assignments.get(call.jobId)||new Set<string>();pages.add(call.landingPage);assignments.set(call.jobId,pages);}
 const result=new Map<string,{jobs:number;completed:number;jobTotal:number;missingJobs:number}>();
 let ambiguousJobs=0;
 for(const[id,pages]of assignments){if(pages.size!==1){ambiguousJobs++;continue;}
  const page=[...pages][0],row=result.get(page)||{jobs:0,completed:0,jobTotal:0,missingJobs:0};row.jobs++;
  const job=byJob.get(id);if(!job)row.missingJobs++;if(job&&job.jobStatus==='Completed'){row.completed++;const total=Number(job.total);if(Number.isFinite(total))row.jobTotal+=total;}
  result.set(page,row);
 }
 return {pages:result,ambiguousJobs};
}
