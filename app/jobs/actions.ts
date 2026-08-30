'use server';
import { revalidatePath } from 'next/cache';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';
const ops=['owner','manager','csr_dispatch'];
export async function createJob(formData:FormData){
  const user=await requireCurrentUser();if(!ops.includes(user.role))throw new Error('Not authorized');const customerId=String(formData.get('customer_id')??'');if(!customerId)throw new Error('Customer required');const start=String(formData.get('scheduled_start')??'');const end=String(formData.get('scheduled_end')??'');if(start&&end&&new Date(end)<=new Date(start))throw new Error('Schedule end must be after start');const supabase=await createSupabaseServerClient();const {error}=await supabase.from('jobs').insert({customer_id:customerId,status:start?'scheduled':'booked',scheduled_start:start?new Date(start).toISOString():null,scheduled_end:end?new Date(end).toISOString():null});if(error)throw new Error('Job could not be booked');revalidatePath('/jobs');revalidatePath('/schedule');revalidatePath('/dispatch');revalidatePath('/dashboard');
}
export async function assignTechnician(formData:FormData){
  const user=await requireCurrentUser();if(!ops.includes(user.role))throw new Error('Not authorized');const jobId=String(formData.get('job_id')??'');const technicianId=String(formData.get('technician_id')??'')||null;const supabase=await createSupabaseServerClient();const {error}=await supabase.from('jobs').update({technician_id:technicianId,status:technicianId?'dispatched':'scheduled'}).eq('id',jobId);if(error)throw new Error('Assignment could not be saved');revalidatePath('/jobs');revalidatePath('/schedule');revalidatePath('/dispatch');
}
