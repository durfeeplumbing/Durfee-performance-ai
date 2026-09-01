import { getFinanceDashboardSnapshot } from '@/lib/finance/dashboard';

const money = new Intl.NumberFormat('en-US', {
  style: 'currency',
  currency: 'USD',
  maximumFractionDigits: 0,
});

function formatMoney(value?: number | null) {
  return value === null || value === undefined ? '—' : money.format(value);
}

export default async function FinanceHealthPanel() {
  const finance = await getFinanceDashboardSnapshot();
  const utilization = finance.creditCardBalance !== null && finance.creditCardBalance !== undefined && finance.creditLimit
    ? (finance.creditCardBalance / finance.creditLimit) * 100
    : null;

  if (finance.status !== 'connected') {
    return (
      <section style={{ margin: '32px 0' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', gap: 16, alignItems: 'baseline', flexWrap: 'wrap' }}>
          <div>
            <h2 style={{ marginBottom: 4 }}>Live Financial Health</h2>
            <p style={{ marginTop: 0 }}>Owner-only finance feed for cash, debt, spending and operating health.</p>
          </div>
          <span style={{ fontWeight: 700 }}>{finance.status === 'error' ? 'Feed error' : 'Ready to connect'}</span>
        </div>
        <article style={{ border: '1px solid #ddd', borderRadius: 18, padding: 20 }}>
          <strong>Finance integration is installed</strong>
          <p>{finance.message}</p>
          <p><small>The dashboard only reads a normalized server-side feed. Provider credentials are never sent to the browser.</small></p>
        </article>
      </section>
    );
  }

  const cards = [
    { label: 'Cash Available', value: formatMoney(finance.cashAvailable), detail: 'Connected operating cash' },
    { label: 'Revenue MTD', value: formatMoney(finance.revenueMtd), detail: 'Posted business inflows after provider classification' },
    { label: 'Expenses MTD', value: formatMoney(finance.expensesMtd), detail: 'Operating outflows excluding internal transfers' },
    { label: 'Payroll MTD', value: formatMoney(finance.payrollMtd), detail: 'Payroll-related outflows' },
    { label: 'Taxes MTD', value: formatMoney(finance.taxesMtd), detail: 'Tax-related outflows' },
    { label: 'Card Balance', value: formatMoney(finance.creditCardBalance), detail: utilization === null ? 'Credit utilization unavailable' : `${utilization.toFixed(1)}% utilization` },
    { label: 'Upcoming Obligations', value: formatMoney(finance.upcomingObligations), detail: 'Known upcoming recurring obligations' },
  ];

  return (
    <section style={{ margin: '32px 0' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', gap: 16, alignItems: 'baseline', flexWrap: 'wrap' }}>
        <div>
          <h2 style={{ marginBottom: 4 }}>Live Financial Health</h2>
          <p style={{ marginTop: 0 }}>Cash, spending, payroll, taxes and credit exposure in the owner command center.</p>
        </div>
        <span style={{ fontWeight: 700 }}>{finance.sourceLabel ?? 'Live finance feed'}</span>
      </div>
      <section style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(190px,1fr))', gap: 16, margin: '18px 0' }}>
        {cards.map((card) => (
          <article key={card.label} style={{ border: '1px solid #ddd', borderRadius: 18, padding: 20 }}>
            <small>{card.label}</small>
            <h2>{card.value}</h2>
            <p>{card.detail}</p>
          </article>
        ))}
      </section>
      <p><small>As of {finance.asOf ? new Date(finance.asOf).toLocaleString('en-US', { timeZone: 'America/New_York' }) : 'provider timestamp unavailable'}.</small></p>
    </section>
  );
}
