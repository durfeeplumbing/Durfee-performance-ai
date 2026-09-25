'use client';
import { useFormStatus } from 'react-dom';

export default function AuthSubmit({ children, pendingLabel }: { children: React.ReactNode; pendingLabel: string }) {
  const { pending } = useFormStatus();
  return <button type="submit" disabled={pending} aria-disabled={pending} style={{ padding: 13, cursor: pending ? 'wait' : 'pointer' }}>
    {pending ? pendingLabel : children}
  </button>;
}
