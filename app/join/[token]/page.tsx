import Link from 'next/link';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { validInviteToken } from '@/lib/access-navigation';
import AuthSubmit from '@/app/components/auth-submit';
import { joinEmployee } from './actions';

export default async function JoinPage({ params, searchParams }: { params: Promise<{ token: string }>; searchParams: Promise<{ error?: string }> }) {
  const { token } = await params;
  const { error } = await searchParams;
  const supabase = await createSupabaseServerClient();
  const { data } = validInviteToken(token)
    ? await supabase.rpc('get_employee_invite', { p_token: token })
    : { data: null };
  const invite = Array.isArray(data) ? data[0] : data;
  if (!invite) return <main style={{ maxWidth: 560, margin: '80px auto', padding: 32 }}>
    <h1>Invite unavailable</h1>
    <p>This employee invite is expired, revoked, used, or invalid. Ask your manager for a new invite.</p>
    <p>Already created your login? Confirm your email if requested, then <Link href="/login">sign in here</Link>.</p>
  </main>;
  return <main style={{ maxWidth: 560, margin: '80px auto', padding: 32 }}>
    <h1>Join Durfee Performance AI</h1>
    <p><b>{invite.employee_name}</b>, your account is approved for the <b>{invite.role}</b> role.</p>
    {error && <p role="alert">Account setup could not be completed. Check the invite and use matching passwords of at least 10 characters. If you already created a login, sign in below.</p>}
    <form action={joinEmployee} style={{ display: 'grid', gap: 12, marginTop: 24 }}>
      <input type="hidden" name="token" value={token} />
      <label>Email<input name="email" type="email" defaultValue={invite.email} readOnly autoComplete="email" style={{ display: 'block', width: '100%', padding: 10 }} /></label>
      <label>Create password<input name="password" type="password" minLength={10} required autoComplete="new-password" style={{ display: 'block', width: '100%', padding: 10 }} /></label>
      <label>Confirm password<input name="confirm_password" type="password" minLength={10} required autoComplete="new-password" style={{ display: 'block', width: '100%', padding: 10 }} /></label>
      <AuthSubmit pendingLabel="Creating your login…">Create Employee Login</AuthSubmit>
    </form>
    <p><small>Invite expires {new Date(invite.expires_at).toLocaleString('en-US', { timeZone: 'America/New_York' })} Eastern.</small></p>
    <p><Link href="/login">Already have a login? Sign in</Link></p>
  </main>;
}
