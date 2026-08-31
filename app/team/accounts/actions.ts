'use server';
import { revalidatePath } from 'next/cache';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';
import { assertPermission } from '@/lib/permissions';

async function teamContext(){await assertPermission('manage_team');const user=await requireCurrentUser();if(!['owner','manager'].includes(user.role))throw new Error('Not authorized');return {supabase:await createSupabaseServerClient()};}

export async function createEmployeeInvite(formData:FormData){const {supabase}=await teamContext();const email=String(formData.get('email')??'').trim().toLowerCase(),name=String(formData.get('name')??'').trim(),role=String(formData.get('role')??'');if(!email||!name||!role)throw new Error('Name, email and role are required');const {error}=await supabase.rpc('create_employee_invite_atomic',{p_email:email,p_name:name,p_role:role});if(error)throw new Error(error.message||'Employee invite could not be created');revalidatePath('/team/accounts');}

export async function revokeEmployeeInvite(formData:FormData){const {supabase}=await teamContext();const token=String(formData.get('token')??'');if(!token)throw new Error('Invite token is required');const {error}=await supabase.rpc('revoke_employee_invite_atomic',{p_token:token});if(error)throw new Error(error.message||'Invite could not be revoked');revalidatePath('/team/accounts');}
