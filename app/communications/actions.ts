'use server';

import { revalidatePath } from 'next/cache';
import { createSupabaseServerClient } from '@/lib/supabase/server';

async function rpc(name:string,args:Record<string,unknown>){
  const s=await createSupabaseServerClient();
  const {error}=await s.rpc(name,args);
  if(error)throw new Error(error.message);
  revalidatePath('/communications');
  revalidatePath('/customers');
  revalidatePath('/csr');
  revalidatePath('/dashboard');
}

export async function queueCommunication(formData:FormData){
  const customerId=String(formData.get('customer_id')??'');
  const jobId=String(formData.get('job_id')??'').trim();
  const channel=String(formData.get('channel')??'sms');
  const to=String(formData.get('to')??'').trim();
  const subject=String(formData.get('subject')??'').trim();
  const body=String(formData.get('body')??'').trim();
  if(!customerId)throw new Error('Customer required');
  if(!['phone','sms','email'].includes(channel))throw new Error('Invalid channel');
  if(!to)throw new Error('Destination required');
  if(channel!=='phone'&&!body)throw new Error('Message body required');
  await rpc('queue_customer_communication',{p_customer_id:customerId,p_job_id:jobId||null,p_channel:channel,p_to:to,p_subject:subject||null,p_body:body||null});
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
