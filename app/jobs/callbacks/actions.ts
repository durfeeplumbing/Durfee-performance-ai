'use server';
import { revalidatePath } from 'next/cache';
import { createSupabaseServerClient } from '@/lib/supabase/server';

export async function recordCallback(formData:FormData){
  const s=await createSupabaseServerClient();
  const original=String(formData.get('original_job_id')||''),callback=String(formData.get('callback_job_id')||''),reason=String(formData.get('reason')||'unknown'),note=String(formData.get('manager_note')||'');
  const {error}=await s.rpc('record_job_callback',{p_original_job_id:original,p_callback_job_id:callback,p_reason:reason,p_manager_note:note||null});
  if(error) throw new Error(error.message);
  revalidatePath('/jobs/callbacks');revalidatePath('/team');
}

export async function reviewCallback(formData:FormData){
  const s=await createSupabaseServerClient();
  const id=String(formData.get('callback_id')||''),preventability=String(formData.get('preventability')||''),cost=Number(formData.get('callback_cost')||0),note=String(formData.get('manager_note')||'');
  const {error}=await s.rpc('review_job_callback',{p_callback_id:id,p_preventability:preventability,p_callback_cost:Number.isFinite(cost)?cost:0,p_manager_note:note||null});
  if(error) throw new Error(error.message);
  revalidatePath('/jobs/callbacks');revalidatePath('/team');revalidatePath('/dashboard');
}
