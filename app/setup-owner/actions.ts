'use server';
import { redirect } from 'next/navigation';
import { createSupabaseServerClient } from '@/lib/supabase/server';

const OWNER_EMAIL='durfeeplumbing@gmail.com';

export async function setupOwner(formData:FormData){
  const email=String(formData.get('email')??'').trim().toLowerCase();
  const password=String(formData.get('password')??'');
  if(email!==OWNER_EMAIL)redirect('/setup-owner?error=unauthorized');
  if(password.length<12)redirect('/setup-owner?error=password');
  const supabase=await createSupabaseServerClient();
  const {data,error}=await supabase.auth.signUp({email,password});
  if(error)redirect('/setup-owner?error=signup');
  if(data.session)redirect('/dashboard');
  redirect('/setup-owner?status=confirm');
}
