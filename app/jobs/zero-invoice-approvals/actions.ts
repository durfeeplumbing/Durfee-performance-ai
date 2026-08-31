'use server';
import { revalidatePath } from 'next/cache';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { hasPermission } from '@/lib/permissions';

async function managerClient(){
  const allowed=(await hasPermission('manage_jobs'))||(await hasPermission('manage_billing'));
  if(!allowed) throw new Error('Manager permission required');
  return createSupabaseServerClient();
}

export async function approveZeroInvoiceCloseout(formData:FormData){
  const jobId=String(formData.get('job_id')??'');
  const note=String(formData.get('manager_note')??'').trim();
  if(!jobId) throw new Error('Job required');
  const supabase=await managerClient();
  const {error}=await supabase.rpc('approve_zero_invoice_closeout',{p_job_id:jobId,p_manager_note:note||null});
  if(error) throw new Error(error.message||'Approval failed');
  for(const p of ['/jobs/zero-invoice-approvals','/field',`/jobs/${jobId}`,'/jobs']) revalidatePath(p);
}

export async function rejectZeroInvoiceCloseout(formData:FormData){
  const jobId=String(formData.get('job_id')??'');
  const note=String(formData.get('manager_note')??'').trim();
  if(!jobId) throw new Error('Job required');
  const supabase=await managerClient();
  const {error}=await supabase.rpc('reject_zero_invoice_closeout',{p_job_id:jobId,p_manager_note:note||null});
  if(error) throw new Error(error.message||'Rejection failed');
  for(const p of ['/jobs/zero-invoice-approvals','/field',`/jobs/${jobId}`,'/jobs']) revalidatePath(p);
}
