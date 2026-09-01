'use server';

import { revalidatePath } from 'next/cache';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';
import { dialpadConnected, dialpadProviderEventId, initiateDialpadCall, sendDialpadSms } from '@/lib/integrations/dialpad';

async function rpc<T=unknown>(name:string,args:Record<string,unknown>){
  const s=await createSupabaseServerClient();
  const {data,error}=await s.rpc(name,args);
  if(error)throw new Error(error.message);
  revalidatePath('/communications');
  revalidatePath('/customers');
  revalidatePath('/csr');
  revalidatePath('/dashboard');
  return data as T;
}

function normalizeUsPhone(value:string){
  const raw=value.trim();
  if(raw.startsWith('+')&&/^\+[1-9]\d{7,14}$/.test(raw))return raw;
  const digits=raw.replace(/\D/g,'');
  if(digits.length===10)return `+1${digits}`;
  if(digits.length===11&&digits.startsWith('1'))return `+${digits}`;
  throw new Error('Phone number must be a valid US number or E.164 number');
}

async function updateDelivery(id:string,status:'sent'|'failed',providerEventId:string|null,disposition?:string){
  await rpc('update_customer_communication_delivery',{
    p_id:id,p_status:status,p_provider:'dialpad',p_provider_event_id:providerEventId,p_from_address:null,p_disposition:disposition||null,
  });
}

export async function queueCommunication(formData:FormData){
  const customerId=String(formData.get('customer_id')??'');
  const jobId=String(formData.get('job_id')??'').trim();
  const channel=String(formData.get('channel')??'sms');
  const rawTo=String(formData.get('to')??'').trim();
  const subject=String(formData.get('subject')??'').trim();
  const body=String(formData.get('body')??'').trim();
  if(!customerId)throw new Error('Customer required');
  if(!['phone','sms','email'].includes(channel))throw new Error('Invalid channel');
  if(!rawTo)throw new Error('Destination required');
  if(channel!=='phone'&&!body)throw new Error('Message body required');

  const to=channel==='phone'||channel==='sms'?normalizeUsPhone(rawTo):rawTo;
  const id=await rpc<string>('queue_customer_communication',{p_customer_id:customerId,p_job_id:jobId||null,p_channel:channel,p_to:to,p_subject:subject||null,p_body:body||null});

  // Email remains provider-neutral until the transactional email provider is connected.
  // Phone/SMS remain safely queued if the Dialpad server credential has not been installed yet.
  if(channel==='email'||!dialpadConnected())return;

  const user=await requireCurrentUser();
  try{
    const response=channel==='phone'
      ?await initiateDialpadCall({email:user.email,phoneNumber:to,customerId,jobId:jobId||null})
      :await sendDialpadSms({email:user.email,to,text:body});
    await updateDelivery(id,'sent',dialpadProviderEventId(response));
  }catch(error){
    const message=error instanceof Error?error.message:'Dialpad request failed';
    try{await updateDelivery(id,'failed',null,message.slice(0,500));}catch{/* preserve the provider error */}
    throw new Error(message);
  }
}

export async function recordCommunication(formData:FormData){
  const customerId=String(formData.get('customer_id')??'');
  const jobId=String(formData.get('job_id')??'').trim();
  const bookedJobId=String(formData.get('booked_job_id')??'').trim();
  const channel=String(formData.get('channel')??'phone');
  const direction=String(formData.get('direction')??'inbound');
  const eventType=channel==='phone'?'call':'message';
  const status=String(formData.get('status')??(direction==='inbound'?'received':'completed'));
  const from=String(formData.get('from')??'').trim();
  const to=String(formData.get('to')??'').trim();
  const subject=String(formData.get('subject')??'').trim();
  const body=String(formData.get('body')??'').trim();
  const summary=String(formData.get('ai_summary')??'').trim();
  const transcript=String(formData.get('transcript')??'').trim();
  const disposition=String(formData.get('disposition')??'').trim();
  const bookingOutcome=String(formData.get('booking_outcome')??'none');
  const duration=Number(formData.get('duration_seconds')??0);
  if(!customerId)throw new Error('Customer required');
  await rpc('record_customer_communication',{
    p_customer_id:customerId,p_job_id:jobId||null,p_channel:channel,p_direction:direction,p_event_type:eventType,p_status:status,
    p_from:from||null,p_to:to||null,p_subject:subject||null,p_body:body||null,p_occurred_at:new Date().toISOString(),
    p_duration_seconds:Number.isFinite(duration)&&duration>0?Math.round(duration):null,p_provider:null,p_provider_event_id:null,p_recording_url:null,
    p_transcript:transcript||null,p_ai_summary:summary||null,p_disposition:disposition||null,p_booking_outcome:bookingOutcome,p_booked_job_id:bookedJobId||null,
  });
}
