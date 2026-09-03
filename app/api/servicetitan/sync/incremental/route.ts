import { NextResponse } from 'next/server';
import { createSupabaseAdminClient } from '@/lib/supabase/admin';
import { serviceTitanConnectionInfo, serviceTitanPages } from '@/lib/servicetitan';

export const runtime='nodejs';
export const dynamic='force-dynamic';
export const maxDuration=300;

const PAGE_SIZE=100;
const OVERLAP_MS=10*60*1000;
const INITIAL_LOOKBACK_MS=48*60*60*1000;
const TRANSIENT_RETRY_DELAYS_MS=[500,1500];

const resources=[
  ['customers','/crm/v2/tenant/{tenant}/customers'],
  ['locations','/crm/v2/tenant/{tenant}/locations'],
  ['jobs','/jpm/v2/tenant/{tenant}/jobs'],
  ['appointments','/jpm/v2/tenant/{tenant}/appointments'],
  ['estimates','/sales/v2/tenant/{tenant}/estimates?active=Any'],
  ['invoices','/accounting/v2/tenant/{tenant}/invoices'],
  ['payments','/accounting/v2/tenant/{tenant}/payments'],
  ['memberships','/memberships/v2/tenant/{tenant}/memberships'],
] as const;

type ResourceName=(typeof resources)[number][0];
type StateRow={resource:ResourceName;enabled:boolean;cursor_at:string|null;last_attempt_at:string|null;last_success_at:string|null;last_records_seen:number;last_error:string|null;consecutive_failures:number};

const wait=(ms:number)=>new Promise(resolve=>setTimeout(resolve,ms));
const transient=(message:string)=>{const m=message.toLowerCase();return m.includes('statement timeout')||m.includes('canceling statement')||m.includes('429')||m.includes('502')||m.includes('503')||m.includes('504')||m.includes('gateway')||m.includes('fetch failed')||m.includes('network');};

function withModifiedSince(path:string,since:string){
  const url=new URL(path,'https://durfee.invalid');
  url.searchParams.set('modifiedOnOrAfter',since);
  return `${url.pathname}?${url.searchParams.toString()}`;
}

async function saveBatch(admin:ReturnType<typeof createSupabaseAdminClient>,resource:string,records:unknown[],environment:string,tenant:string){
  let last='Unknown staging error';
  for(let attempt=0;attempt<=TRANSIENT_RETRY_DELAYS_MS.length;attempt++){
    const {error}=await admin.rpc('upsert_service_titan_resource',{p_resource:resource,p_records:records,p_environment:environment,p_tenant_id:tenant});
    if(!error)return;
    last=error.message;
    if(!transient(last))break;
    if(attempt<TRANSIENT_RETRY_DELAYS_MS.length)await wait(TRANSIENT_RETRY_DELAYS_MS[attempt]);
  }
  throw new Error(last);
}

export async function GET(request:Request){
  const secret=process.env.CRON_SECRET?.trim();
  if(!secret)return NextResponse.json({enabled:false},{status:200});
  if(request.headers.get('authorization')!==`Bearer ${secret}`)return NextResponse.json({error:'Unauthorized'},{status:401});

  const admin=createSupabaseAdminClient();
  const {data:lease,error:leaseError}=await admin.rpc('claim_service_titan_incremental_sync',{p_lease_minutes:8});
  if(leaseError)return NextResponse.json({error:'Could not claim sync lease'},{status:500});
  if(!lease)return NextResponse.json({ok:true,skipped:'already_running'},{status:202});

  const startedAt=new Date();
  const results:{resource:string;seen:number;ok:boolean;error?:string}[]=[];
  let finalStatus:'success'|'partial_error'|'failed'='success';
  let finalError:string|null=null;

  try{
    const info=serviceTitanConnectionInfo();
    const {data:stateRows,error:stateError}=await admin.from('service_titan_incremental_sync_state').select('*');
    if(stateError)throw new Error(stateError.message);
    const state=new Map((stateRows as StateRow[]|null)?.map(row=>[row.resource,row])??[]);

    for(const [resource,basePath] of resources){
      const current=state.get(resource);
      if(current?.enabled===false){results.push({resource,seen:0,ok:true});continue;}
      const cursor=current?.cursor_at?new Date(current.cursor_at).getTime()-OVERLAP_MS:startedAt.getTime()-INITIAL_LOOKBACK_MS;
      const since=new Date(cursor).toISOString();
      const path=withModifiedSince(basePath,since);
      let seen=0;
      try{
        await admin.from('service_titan_incremental_sync_state').update({last_attempt_at:startedAt.toISOString(),updated_at:new Date().toISOString()}).eq('resource',resource);
        for await(const page of serviceTitanPages(path,PAGE_SIZE)){
          await saveBatch(admin,resource,page,info.environment,info.tenant);
          seen+=page.length;
        }
        const {error:updateError}=await admin.from('service_titan_incremental_sync_state').update({cursor_at:startedAt.toISOString(),last_attempt_at:startedAt.toISOString(),last_success_at:new Date().toISOString(),last_records_seen:seen,last_error:null,consecutive_failures:0,updated_at:new Date().toISOString()}).eq('resource',resource);
        if(updateError)throw new Error(updateError.message);
        results.push({resource,seen,ok:true});
      }catch(error){
        const message=error instanceof Error?error.message:'Incremental sync failed';
        finalStatus='partial_error';
        finalError=finalError?`${finalError}; ${resource}: ${message}`:`${resource}: ${message}`;
        await admin.from('service_titan_incremental_sync_state').update({last_attempt_at:startedAt.toISOString(),last_records_seen:seen,last_error:message.slice(0,2000),consecutive_failures:Number(current?.consecutive_failures??0)+1,updated_at:new Date().toISOString()}).eq('resource',resource);
        results.push({resource,seen,ok:false,error:message.slice(0,300)});
      }
    }

    await admin.rpc('finish_service_titan_incremental_sync',{p_lease_token:lease,p_status:finalStatus,p_error:finalError});
    return NextResponse.json({ok:finalStatus==='success',status:finalStatus,startedAt:startedAt.toISOString(),completedAt:new Date().toISOString(),results});
  }catch(error){
    const message=error instanceof Error?error.message:'Incremental sync failed';
    finalStatus='failed';finalError=message;
    await admin.rpc('finish_service_titan_incremental_sync',{p_lease_token:lease,p_status:finalStatus,p_error:finalError});
    console.error('ServiceTitan incremental sync failed',message);
    return NextResponse.json({ok:false,status:'failed',error:'ServiceTitan incremental sync failed'},{status:500});
  }
}
