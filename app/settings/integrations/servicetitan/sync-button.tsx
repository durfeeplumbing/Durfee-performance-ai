'use client';

import { useFormStatus } from 'react-dom';

type Props = {
  idleLabel: string;
  pendingLabel?: string;
};

export default function ServiceTitanSyncButton({ idleLabel, pendingLabel = 'Syncing…' }: Props) {
  const { pending } = useFormStatus();
  return (
    <button type="submit" disabled={pending} aria-busy={pending} style={{ minWidth: 190, opacity: pending ? 0.65 : 1, cursor: pending ? 'wait' : 'pointer' }}>
      {pending ? pendingLabel : idleLabel}
    </button>
  );
}
