import Link from 'next/link';
import { getCurrentUser } from '@/lib/session';
import { employeePermissions } from '@/lib/employee-access';
import { employeeHome } from '@/lib/access-navigation';
import { logout } from '@/app/login/actions';

export default async function UnauthorizedPage() {
  const user = await getCurrentUser();
  let home = '/login';
  if (user) {
    try { home = employeeHome(user.role, await employeePermissions(user)); }
    catch { home = '/unauthorized'; }
  }
  return <main style={{ maxWidth: 620, margin: '10vh auto', padding: 32 }}>
    <article style={{ border: '1px solid #ddd', borderRadius: 16, padding: 28 }}>
      <h1>Access restricted</h1>
      <p>Your account does not currently have permission to open that area.</p>
      {home !== '/unauthorized' && <p><Link href={home}>{user ? 'Return to my workspace' : 'Sign in'}</Link></p>}
      <p>Contact your owner or authorized manager if you need access.</p>
      {user && <form action={logout}><button type="submit">Sign out</button></form>}
    </article>
  </main>;
}
