'use server';
import { revalidatePath } from 'next/cache';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';

async function owner(){const u=await requireCurrentUser();if(u.role!=='owner')throw new Error('Owner authorization required');return u;}
export async function setRolePermission(formData:FormData){await owner();const role=String(formData.get('role')??'');const key=String(formData.get('permission_key')??'');const allowed=String(formData.get('allowed')??'')==='true';const supabase=await createSupabaseServerClient();const {error}=await supabase.rpc('set_role_permission_atomic',{p_role:role,p_permission_key:key,p_allowed:allowed});if(error)throw new Error(error.message);revalidatePath('/settings/permissions');}
export async function setUserPermission(formData:FormData){await owner();const userId=String(formData.get('user_id')??'');const key=String(formData.get('permission_key')??'');const mode=String(formData.get('mode')??'inherit');const supabase=await createSupabaseServerClient();const {error}=await supabase.rpc('set_user_permission_override_atomic',{p_user_id:userId,p_permission_key:key,p_mode:mode});if(error)throw new Error(error.message);revalidatePath('/settings/permissions');}
