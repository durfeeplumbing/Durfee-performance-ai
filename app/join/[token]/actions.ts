'use server';

import { redirect } from 'next/navigation';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { validInviteToken } from '@/lib/access-navigation';

export async function joinEmployee(formData: FormData) {
  const token = String(formData.get('token') ?? '');
  if (!validInviteToken(token)) redirect('/login?error=access');
  const email = String(formData.get('email') ?? '').trim().toLowerCase();
  const password = String(formData.get('password') ?? '');
  const confirmation = String(formData.get('confirm_password') ?? '');
  if (!email || password.length < 10 || password !== confirmation) redirect(`/join/${token}?error=invalid`);
  const supabase = await createSupabaseServerClient();
  const { data: invite, error: inviteError } = await supabase.rpc('get_employee_invite', { p_token: token });
  const row = Array.isArray(invite) ? invite[0] : invite;
  if (inviteError || !row || String(row.email).toLowerCase() !== email) redirect(`/join/${token}?error=invite`);
  const appUrl = process.env.NEXT_PUBLIC_APP_URL?.trim();
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    ...(appUrl ? { options: { emailRedirectTo: new URL('/auth/callback', appUrl).toString() } } : {}),
  });
  if (error) redirect(`/join/${token}?error=signup`);
  if (data.session) redirect('/');
  redirect('/login?notice=confirm-email');
}
