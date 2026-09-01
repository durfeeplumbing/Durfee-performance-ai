import type { ReactNode } from 'react';
import FinanceHealthPanel from './finance-health-panel';
import { requireCurrentUser } from '@/lib/session';

export default async function DashboardLayout({ children }: { children: ReactNode }) {
  const user = await requireCurrentUser();

  return (
    <>
      {children}
      {user.role === 'owner' ? (
        <div style={{ fontFamily: 'system-ui', maxWidth: 1280, margin: 'auto', padding: '0 32px 32px' }}>
          <FinanceHealthPanel />
        </div>
      ) : null}
    </>
  );
}
