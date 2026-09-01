export type FinanceDashboardSnapshot = {
  status: 'connected' | 'not_configured' | 'error';
  asOf?: string | null;
  cashAvailable?: number | null;
  revenueMtd?: number | null;
  expensesMtd?: number | null;
  payrollMtd?: number | null;
  taxesMtd?: number | null;
  creditCardBalance?: number | null;
  creditLimit?: number | null;
  upcomingObligations?: number | null;
  sourceLabel?: string | null;
  message?: string | null;
};

function num(value: unknown): number | null {
  if (value === null || value === undefined || value === '') return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

export async function getFinanceDashboardSnapshot(): Promise<FinanceDashboardSnapshot> {
  const endpoint = process.env.FINANCE_DATA_API_URL;
  const token = process.env.FINANCE_DATA_API_TOKEN;

  if (!endpoint || !token) {
    return {
      status: 'not_configured',
      message: 'Live bank-feed adapter is ready, but production finance API credentials are not configured yet.',
    };
  }

  try {
    const response = await fetch(endpoint, {
      method: 'GET',
      headers: {
        authorization: `Bearer ${token}`,
        accept: 'application/json',
      },
      cache: 'no-store',
    });

    if (!response.ok) {
      return {
        status: 'error',
        message: `Finance provider returned ${response.status}.`,
      };
    }

    const data = await response.json() as Record<string, unknown>;

    return {
      status: 'connected',
      asOf: typeof data.asOf === 'string' ? data.asOf : null,
      cashAvailable: num(data.cashAvailable),
      revenueMtd: num(data.revenueMtd),
      expensesMtd: num(data.expensesMtd),
      payrollMtd: num(data.payrollMtd),
      taxesMtd: num(data.taxesMtd),
      creditCardBalance: num(data.creditCardBalance),
      creditLimit: num(data.creditLimit),
      upcomingObligations: num(data.upcomingObligations),
      sourceLabel: typeof data.sourceLabel === 'string' ? data.sourceLabel : 'Live finance feed',
    };
  } catch {
    return {
      status: 'error',
      message: 'The live finance feed could not be reached.',
    };
  }
}
