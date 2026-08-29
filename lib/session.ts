import type { SessionUser } from './auth';
import { createSupabaseServerClient } from './supabase/server';

export async function getCurrentUser():Promise<SessionUser|null>{
  const supabase=await createSupabaseServerClient();
  const {data:{user},error}=await supabase.auth.getUser();
  if(error||!user)return null;
  const {data:employee}=await supabase.from('users').select('id,email,name,role,active').eq('auth_user_id',user.id).single();
  if(!employee||!employee.active)return null;
  return employee as SessionUser;
}

export async function requireCurrentUser(){
  const user=await getCurrentUser();
  if(!user)throw new Error('Authentication required');
  return user;
}
