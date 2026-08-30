import { redirect } from 'next/navigation';
import { createSupabaseServerClient } from './supabase/server';
import { requireCurrentUser } from './session';

export async function hasPermission(permissionKey:string){const user=await requireCurrentUser();if(user.role==='owner')return true;const s=await createSupabaseServerClient();const {data,error}=await s.rpc('has_permission_for_current_user',{p_key:permissionKey});if(error)return false;return data===true;}
export async function requirePermission(permissionKey:string){if(!(await hasPermission(permissionKey)))redirect('/dashboard');}
export async function assertPermission(permissionKey:string){if(!(await hasPermission(permissionKey)))throw new Error('Permission denied');}
