'use server';
import { revalidatePath } from 'next/cache';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';
import { hasPermission } from '@/lib/permissions';

async function managerClient(){
  const user=await requireCurrentUser();
  if(!['owner','manager'].includes(user.role)) throw new Error('Owner or manager approval required');
  const allowed=(await hasPermission('manage_jobs'))||(await hasPermission('manage_billing'));
  if(!allowed) throw new Error('Manager permission required');
  return createSupabaseServerClient();
}
function refresh(jobId:string){for(const p of ['/jobs/gp-approvals','/field',`/jobs/${jobId}`,'/jobs','/reports/daily','/reports/profitability'])revalidatePath(p);}

export async function approveGpCloseout(formData:FormData){
  const jobId=String(formData.get('job_id')??'');
  const note=String(formData.get('manager_note')??'').trim().slice(0,1000);
  if(!jobId) throw new Error('Job required');
  const supabase=await managerClient();
  const {error}=await supabase.rpc('approve_gp_closeout',{p_job_id:jobId,p_manager_note:note||null});
  if(error) throw new Error(error.message||'Low-GP approval failed');
  refresh(jobId);
}

export async function rejectGpCloseout(formData:FormData){
  const jobId=String(formData.get('job_id')??'');
  const note=String(formData.get('manager_note')??'').trim().slice(0,1000);
  if(!jobId) throw new Error('Job required');
  const supabase=await managerClient();
  const {error}=await supabase.rpc('reject_gp_closeout',{p_job_id:jobId,p_manager_note:note||null});
  if(error) throw new Error(error.message||'Low-GP rejection failed');
  refresh(jobId);
}
