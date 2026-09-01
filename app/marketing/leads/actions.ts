'use server';

import { revalidatePath } from 'next/cache';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { assertPermission } from '@/lib/permissions';

function text(formData:FormData,key:string){return String(formData.get(key)??'').trim();}
function refresh(){for(const p of ['/marketing','/marketing/leads','/marketing/funnel','/marketing/setup','/marketing/campaigns'])revalidatePath(p);}

export async function matchMarketingLead(formData:FormData){
  await assertPermission('manage_csr');
  const leadId=text(formData,'lead_id'),customerId=text(formData,'customer_id'),jobId=text(formData,'job_id')||null;
  if(!leadId||!customerId)throw new Error('Lead and customer are required');
  const supabase=await createSupabaseServerClient();
  const {error}=await supabase.rpc('match_marketing_lead',{p_lead_id:leadId,p_customer_id:customerId,p_job_id:jobId});
  if(error)throw new Error(error.message);
  refresh();
}

export async function dismissMarketingLead(formData:FormData){
  await assertPermission('manage_csr');
  const leadId=text(formData,'lead_id');if(!leadId)throw new Error('Lead required');
  const supabase=await createSupabaseServerClient();
  const {error}=await supabase.rpc('dismiss_marketing_lead',{p_lead_id:leadId});
  if(error)throw new Error(error.message);
  refresh();
}
