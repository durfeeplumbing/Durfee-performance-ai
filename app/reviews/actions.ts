'use server';

import { revalidatePath } from 'next/cache';
import { createSupabaseServerClient } from '@/lib/supabase/server';

async function rpc(name:string,args:Record<string,unknown>){
  const s=await createSupabaseServerClient();
  const {error}=await s.rpc(name,args);
  if(error)throw new Error(error.message);
  revalidatePath('/reviews');
  revalidatePath('/team');
  revalidatePath('/dashboard');
}

export async function recordReviewRequest(formData:FormData){
  const jobId=String(formData.get('job_id')??'');
  const channel=String(formData.get('channel')??'manual');
  const note=String(formData.get('note')??'').trim();
  if(!jobId)throw new Error('Job required');
  await rpc('record_customer_review_request',{p_job_id:jobId,p_channel:channel,p_note:note||null});
}

export async function recordReviewResult(formData:FormData){
  const jobId=String(formData.get('job_id')??'');
  const rating=Number(formData.get('rating')??0);
  const feedback=String(formData.get('feedback')??'').trim();
  const platform=String(formData.get('platform')??'').trim();
  const externalUrl=String(formData.get('external_url')??'').trim();
  const note=String(formData.get('note')??'').trim();
  if(!jobId)throw new Error('Job required');
  if(!Number.isInteger(rating)||rating<1||rating>5)throw new Error('Rating must be 1 through 5');
  await rpc('record_customer_review_result',{p_job_id:jobId,p_rating:rating,p_feedback:feedback||null,p_platform:platform||null,p_external_url:externalUrl||null,p_note:note||null});
}
