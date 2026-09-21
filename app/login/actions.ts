'use server';
import { redirect } from 'next/navigation';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { getCurrentUser } from '@/lib/session';

export async function login(formData:FormData){
  const email=String(formData.get('email')??'').trim();
  const password=String(formData.get('password')??'');
  if(!email||!password)redirect('/login?error=missing');
  const supabase=await createSupabaseServerClient();
  const {error}=await supabase.auth.signInWithPassword({email,password});
  if(error)redirect(error.code==='email_not_confirmed'?'/login?error=unconfirmed':'/login?error=invalid');
  if(!(await getCurrentUser())){
    await supabase.auth.signOut();
    redirect('/login?error=access');
  }
  redirect('/');
}

export async function logout(){
  const supabase=await createSupabaseServerClient();
  await supabase.auth.signOut();
  redirect('/login');
}
