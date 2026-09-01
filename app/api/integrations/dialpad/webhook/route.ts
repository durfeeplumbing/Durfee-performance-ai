import { NextResponse } from 'next/server';
import { createSupabaseAdminClient } from '@/lib/supabase/admin';
import { dialpadProviderEventId, extractDialpadWebhookToken, verifyDialpadWebhookJwt } from '@/lib/integrations/dialpad';

export const runtime='nodejs';
export const dynamic='force-dynamic';

type AnyRecord=Record<string,any>;

function text(value:unknown){return typeof value==='string'&&value.trim()?value.trim():null;}
function firstText(...values:unknown[]){for(const value of values){const found=text(value);if(found)return found;}return null;}
function eventDate(payload:AnyRecord){
  const raw=payload.event_timestamp??payload.timestamp??payload.date??payload.created_at;
  if(typeof raw==='number')return new Date(raw>10_000_000_000?raw:raw*1000).toISOString();
  if(typeof raw==='string'&&raw){const date=new Date(raw);if(!Number.isNaN(date.getTime()))return date.toISOString();}
  return new Date().toISOString();
}
function parseCustomData(payload:AnyRecord){
  const raw=payload.custom_data??payload.customData;
  if(!raw)return {} as AnyRecord;
  if(typeof raw==='object')return raw as AnyRecord;
  if(typeof raw==='string'){try{return JSON.parse(raw) as AnyRecord;}catch{return {} as AnyRecord;}}
  return {} as AnyRecord;
}
function directionOf(payload:AnyRecord):'inbound'|'outbound'{
  const raw=String(payload.direction??payload.call_direction??payload.sms_direction??'').toLowerCase();
  return raw.includes('inbound')||raw==='in'?'inbound':'outbound';
}
function isCall(payload:AnyRecord){return payload.call_id!=null||payload.call_state!=null||payload.call_type!=null;}
function statusOf(payload:AnyRecord,channel:'phone'|'sms',direction:'inbound'|'outbound'){
  const raw=String(payload.call_state??payload.state??payload.delivery_status??payload.status??payload.event_type??'').toLowerCase();
  if(raw.includes('fail')||raw.includes('error')||raw.includes('undeliver'))return 'failed';
  if(channel==='phone'){
    if(raw.includes('miss')||raw.includes('unanswer')||raw.includes('voicemail'))return direction==='inbound'?'missed':'completed';
    if(raw.includes('hangup')||raw.includes('ended')||raw.includes('complete')||raw.includes('postcall'))return 'completed';
    return direction==='inbound'?'received':'sent';
  }
  if(direction==='inbound')return 'received';
  if(raw.includes('deliver'))return 'delivered';
  return 'sent';
}
function phoneAddresses(payload:AnyRecord,direction:'inbound'|'outbound'){
  const external=firstText(payload.external_number,payload.contact?.phone,payload.contact?.phone_number,payload.phone_number);
  const internal=firstText(payload.internal_number,payload.target?.phone_number,payload.office_number,payload.user_number);
  return direction==='inbound'?{from:external,to:internal}:{from:internal,to:external};
}
function smsAddresses(payload:AnyRecord){
  const from=firstText(payload.from_number,payload.from,payload.sender_number,payload.sender?.phone_number);
  const list=Array.isArray(payload.to_numbers)?payload.to_numbers:[];
  const to=firstText(payload.to_number,list[0],payload.to,payload.recipient_number);
  return {from,to};
}
function durationSeconds(payload:AnyRecord){
  const value=Number(payload.duration_seconds??payload.duration??payload.call_duration);
  return Number.isFinite(value)&&value>=0?Math.round(value):null;
}

export async function POST(request:Request){
  let payload:AnyRecord;
  try{
    const raw=await request.text();
    const token=extractDialpadWebhookToken(raw);
    payload=verifyDialpadWebhookJwt(token);
  }catch(error){
    console.warn('Rejected Dialpad webhook',error instanceof Error?error.message:'invalid webhook');
    return NextResponse.json({ok:false,error:'invalid signature'},{status:401});
  }

  const admin=createSupabaseAdminClient();
  const channel:'phone'|'sms'=isCall(payload)?'phone':'sms';
  const direction=directionOf(payload);
  const providerEventId=dialpadProviderEventId(payload);
  const occurredAt=eventDate(payload);
  const eventState=String(payload.call_state??payload.state??payload.delivery_status??payload.status??payload.event_type??'event');
  const eventKey=`${providerEventId||'unidentified'}|${occurredAt}|${eventState}`.slice(0,500);
  const journal=await admin.rpc('ingest_dialpad_webhook_event',{p_event_key:eventKey,p_provider_event_id:providerEventId,p_event_timestamp:occurredAt,p_payload:payload});
  if(journal.error)console.error('Dialpad event journal failed',journal.error.message);

  const finish=async(error:string|null)=>{
    const result=await admin.rpc('finish_dialpad_webhook_event',{p_event_key:eventKey,p_error:error});
    if(result.error)console.error('Dialpad event journal completion failed',result.error.message);
  };

  const custom=parseCustomData(payload);
  const addresses=channel==='phone'?phoneAddresses(payload,direction):smsAddresses(payload);
  let existing:any=null;
  if(providerEventId){
    const {data}=await admin.from('customer_communications').select('id,customer_id,job_id').eq('provider','dialpad').eq('provider_event_id',providerEventId).maybeSingle();
    existing=data;
  }

  let customerId=existing?.customer_id||text(custom.customerId)||text(custom.customer_id);
  let jobId=existing?.job_id||text(custom.jobId)||text(custom.job_id);
  const customerPhone=direction==='inbound'?addresses.from:addresses.to;
  if(!customerId&&customerPhone){
    const {data,error}=await admin.rpc('match_customer_by_phone_for_provider',{p_phone:customerPhone});
    if(!error&&typeof data==='string')customerId=data;
  }

  if(!customerId){
    await finish('Customer match pending');
    console.warn('Dialpad event could not be matched to a customer',{providerEventId,channel,direction});
    return NextResponse.json({ok:true,matched:false},{status:202});
  }

  if(jobId){
    const {data}=await admin.from('jobs').select('id').eq('id',jobId).eq('customer_id',customerId).maybeSingle();
    if(!data)jobId=null;
  }

  const values={
    customer_id:customerId,job_id:jobId||null,channel,direction,event_type:channel==='phone'?'call':'message',
    status:statusOf(payload,channel,direction),from_address:addresses.from,to_address:addresses.to,subject:null,
    body:channel==='sms'?firstText(payload.text,payload.message,payload.content,payload.body):null,
    provider:'dialpad',provider_event_id:providerEventId,occurred_at:occurredAt,
    duration_seconds:channel==='phone'?durationSeconds(payload):null,
    recording_url:channel==='phone'?firstText(payload.recording_url,payload.recording?.url,payload.recordingUrl):null,
    transcript:null,ai_summary:null,disposition:firstText(payload.disposition,payload.result),updated_at:new Date().toISOString(),
  };

  const operation=existing?.id
    ?await admin.from('customer_communications').update(values).eq('id',existing.id)
    :await admin.from('customer_communications').insert(values);
  if(operation.error){
    await finish(operation.error.message);
    console.error('Dialpad communication write failed',operation.error.message);
    return NextResponse.json({ok:false},{status:500});
  }

  await finish(null);
  return NextResponse.json({ok:true,matched:true});
}
