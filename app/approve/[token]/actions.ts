'use server';
import { redirect } from 'next/navigation';
import { createSupabaseServerClient } from '@/lib/supabase/server';

export async function acceptCustomerEstimate(formData:FormData){
  const token=String(formData.get('token')??'');
  const optionId=String(formData.get('option_id')??'');
  const signerName=String(formData.get('signer_name')??'').trim();
  const signatureText=String(formData.get('signature_text')??'').trim();
  const accepted=String(formData.get('accepted_terms')??'')==='on';
  if(!token||!optionId||signerName.length<2||!accepted)throw new Error('Choose an option, enter your name, and accept the authorization statement.');
  const supabase=await createSupabaseServerClient();
  const {error}=await supabase.rpc('accept_estimate',{p_token:token,p_option_id:optionId,p_signer_name:signerName,p_signature_text:signatureText||null});
  if(error)throw new Error(error.message||'Estimate could not be approved');
  redirect(`/approve/${token}/complete`);
}
