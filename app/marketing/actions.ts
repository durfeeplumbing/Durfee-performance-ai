'use server';

import { revalidatePath } from 'next/cache';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';

function text(formData:FormData,key:string){return String(formData.get(key)??'').trim()}

export async function createMarketingSource(formData:FormData){
  await requireCurrentUser();
  const name=text(formData,'name');
  const category=text(formData,'category')||'other';
  if(!name)throw new Error('Source name is required');
  const supabase=await createSupabaseServerClient();
  const {error}=await supabase.rpc('create_marketing_source',{p_name:name,p_category:category});
  if(error)throw new Error(error.message);
  revalidatePath('/marketing');
}

export async function setLeadAttribution(formData:FormData){
  await requireCurrentUser();
  const customerId=text(formData,'customer_id');
  const jobId=text(formData,'job_id')||null;
  const sourceId=text(formData,'source_id');
  if(!customerId||!sourceId)throw new Error('Customer and source are required');
  const supabase=await createSupabaseServerClient();
  const {error}=await supabase.rpc('set_lead_attribution',{
    p_customer_id:customerId,
    p_job_id:jobId,
    p_source_id:sourceId,
    p_source_detail:text(formData,'source_detail')||null,
    p_external_campaign_id:text(formData,'external_campaign_id')||null,
    p_touch_type:text(formData,'touch_type')||'primary',
  });
  if(error)throw new Error(error.message);
  revalidatePath('/marketing');
  revalidatePath('/customers');
  revalidatePath('/dashboard');
}
