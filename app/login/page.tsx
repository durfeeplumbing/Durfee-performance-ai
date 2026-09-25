import { login } from './actions';
import AuthSubmit from '@/app/components/auth-submit';

const errors: Record<string, string> = {
  invalid: 'Unable to sign in. Check your email and password.',
  missing: 'Enter your email and password to continue.',
  unconfirmed: 'Confirm your email using the link in your inbox, then sign in here.',
  access: 'Your login is not linked to an active employee account. Contact your owner or manager to restore access.',
  confirmation: 'That confirmation link could not be completed. Try signing in if you already confirmed your email, or contact your manager for help.',
};

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ error?: string; notice?: string; employee?: string }> }) {
  const params = await searchParams;
  const confirmationPending = params.notice === 'confirm-email';
  return <main style={{ maxWidth: 460, margin: '8vh auto', padding: 28 }}>
    <article style={{ padding: 32, borderRadius: 16, boxShadow: '0 12px 40px rgba(20,40,70,.1)' }}>
      <h1>Durfee Performance AI</h1>
      <p>Employee Portal</p>
      {params.error && <p role="alert">{Object.hasOwn(errors, params.error) ? errors[params.error] : errors.invalid}</p>}
      {confirmationPending && <p role="status">Check your email to finish setting up your account. Open the confirmation link in this browser, then return here to sign in.</p>}
      {params.employee === 'created' && !confirmationPending && <p role="status">Your account setup was submitted. If you received a confirmation email, confirm it before signing in.</p>}
      <form action={login} style={{ display: 'grid', gap: 14 }}>
        <label>Email<input name="email" type="email" autoComplete="email" required maxLength={320} style={{ display: 'block', width: '100%', padding: 12, marginTop: 6 }} /></label>
        <label>Password<input name="password" type="password" autoComplete="current-password" required style={{ display: 'block', width: '100%', padding: 12, marginTop: 6 }} /></label>
        <AuthSubmit pendingLabel="Signing in…">Sign in</AuthSubmit>
      </form>
      <p style={{ fontSize: 13, opacity: .7 }}>Sign in to open your assigned workspace. Access is limited to authorized employees.</p>
      <p style={{ fontSize: 13 }}>New employee? Use the invitation link provided by your manager to create your login.</p>
    </article>
  </main>;
}
