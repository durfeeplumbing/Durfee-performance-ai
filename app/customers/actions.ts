'use server';
import { revalidatePath } from 'next/cache';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';

export async function createCustomer(formData:FormData){
  const user=await requireCurrentUser();
  if(!['owner','manager','csr_dispatch'].includes(user.role))throw new Error('Not authorized');
  const name=String(formData.get('name')??'').trim();
  if(!name)throw new Error('Customer name is required');
  const supabase=await createSupabaseServerClient();
  const {error}=await supabase.from('customers').insert({name,phone:String(formData.get('phone')??'').trim()||null,email:String(formData.get('email')??'').trim()||null,service_address:String(formData.get('service_address')??'').trim()||null});
  if(error)throw new Error('Customer could not be created');
  revalidatePath('/customers');
}
