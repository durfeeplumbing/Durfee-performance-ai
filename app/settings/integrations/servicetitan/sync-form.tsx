'use client';

import { FormEvent, useState } from 'react';
import { useRouter } from 'next/navigation';

type Props = {
  action: (formData: FormData) => Promise<unknown>;
  idleLabel: string;
  pendingLabel?: string;
  successTitle?: string;
  successMessage?: string;
};

export default function ServiceTitanSyncForm({
  action,
  idleLabel,
  pendingLabel = 'Syncing…',
  successTitle = 'Sync complete',
  successMessage = 'ServiceTitan data has been updated successfully.',
}: Props) {
  const router = useRouter();
  const [pending, setPending] = useState(false);
  const [complete, setComplete] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pending) return;

    setPending(true);
    setComplete(false);
    setError(null);

    try {
      await action(new FormData(event.currentTarget));
      router.refresh();
      setComplete(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Sync failed. Please try again.');
    } finally {
      setPending(false);
    }
  }

  return (
    <>
      <form onSubmit={onSubmit}>
        <button
          type="submit"
          disabled={pending}
          aria-busy={pending}
          style={{ minWidth: 190, opacity: pending ? 0.65 : 1, cursor: pending ? 'wait' : 'pointer' }}
        >
          {pending ? pendingLabel : idleLabel}
        </button>
      </form>

      {error ? (
        <div role="alert" style={{ marginTop: 8, color: '#b42318', maxWidth: 360 }}>
          {error}
        </div>
      ) : null}

      {complete ? (
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="servicetitan-sync-complete-title"
          style={{
            position: 'fixed',
            inset: 0,
            zIndex: 1000,
            display: 'grid',
            placeItems: 'center',
            background: 'rgba(15,23,42,0.48)',
            padding: 20,
          }}
        >
          <div className="card" style={{ width: 'min(520px, 100%)', padding: 28, textAlign: 'center' }}>
            <div style={{ fontSize: 42, lineHeight: 1, marginBottom: 12 }} aria-hidden="true">✓</div>
            <h2 id="servicetitan-sync-complete-title" style={{ marginTop: 0 }}>{successTitle}</h2>
            <p>{successMessage}</p>
            <p><small>The page has already refreshed with the latest cached totals and Recent Syncs results.</small></p>
            <button type="button" onClick={() => setComplete(false)} autoFocus>Continue</button>
          </div>
        </div>
      ) : null}
    </>
  );
}
