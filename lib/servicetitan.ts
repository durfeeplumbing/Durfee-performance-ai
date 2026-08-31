type ServiceTitanEnv = 'integration' | 'production';

type TokenResponse = {
  access_token: string;
  expires_in?: number;
  token_type?: string;
  scope?: string;
};

type PaginatedResponse<T> = {
  page?: number;
  pageSize?: number;
  hasMore?: boolean;
  totalCount?: number;
  data?: T[];
};

function config() {
  const appKey = process.env.SERVICETITAN_APP_KEY?.trim();
  const clientId = process.env.SERVICETITAN_CLIENT_ID?.trim();
  const clientSecret = process.env.SERVICETITAN_CLIENT_SECRET?.trim();
  const tenant = process.env.SERVICETITAN_TENANT_ID?.trim();
  const env = (process.env.SERVICETITAN_ENV?.trim().toLowerCase() || 'integration') as ServiceTitanEnv;
  if (!appKey || !clientId || !clientSecret || !tenant) throw new Error('ServiceTitan credentials are incomplete');
  if (!/^\d+$/.test(tenant)) throw new Error('ServiceTitan tenant ID must be numeric');
  if (!['integration', 'production'].includes(env)) throw new Error('SERVICETITAN_ENV must be integration or production');
  return { appKey, clientId, clientSecret, tenant, env };
}

function urls(env: ServiceTitanEnv) {
  return env === 'production'
    ? { auth: 'https://auth.servicetitan.io/connect/token', api: 'https://api.servicetitan.io' }
    : { auth: 'https://auth-integration.servicetitan.io/connect/token', api: 'https://api-integration.servicetitan.io' };
}

export function serviceTitanConfigured() {
  return Boolean(process.env.SERVICETITAN_APP_KEY && process.env.SERVICETITAN_CLIENT_ID && process.env.SERVICETITAN_CLIENT_SECRET && process.env.SERVICETITAN_TENANT_ID);
}

export function serviceTitanConnectionInfo() {
  const c = config();
  return { environment: c.env, tenant: c.tenant };
}

export async function getServiceTitanAccessToken() {
  const c = config();
  const u = urls(c.env);
  const body = new URLSearchParams({ grant_type: 'client_credentials', client_id: c.clientId, client_secret: c.clientSecret });
  const response = await fetch(u.auth, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body, cache: 'no-store' });
  if (!response.ok) throw new Error(`ServiceTitan OAuth failed (${response.status})`);
  const token = (await response.json()) as TokenResponse;
  if (!token.access_token) throw new Error('ServiceTitan OAuth returned no access token');
  return token;
}

export async function serviceTitanGet<T = unknown>(path: string): Promise<T> {
  if (!path.startsWith('/')) throw new Error('ServiceTitan API path must start with /');
  const c = config();
  const u = urls(c.env);
  const token = await getServiceTitanAccessToken();
  const response = await fetch(`${u.api}${path.replace('{tenant}', c.tenant)}`, {
    headers: { Authorization: `Bearer ${token.access_token}`, 'ST-App-Key': c.appKey, Accept: 'application/json' },
    cache: 'no-store',
  });
  if (!response.ok) {
    const detail = (await response.text()).slice(0, 500);
    throw new Error(`ServiceTitan API failed (${response.status})${detail ? `: ${detail}` : ''}`);
  }
  return (await response.json()) as T;
}

export async function serviceTitanGetAll<T = Record<string, unknown>>(path: string, pageSize = 100): Promise<T[]> {
  if (!path.startsWith('/')) throw new Error('ServiceTitan API path must start with /');
  const records: T[] = [];
  for (let page = 1; page <= 1000; page += 1) {
    const separator = path.includes('?') ? '&' : '?';
    const result = await serviceTitanGet<PaginatedResponse<T>>(`${path}${separator}page=${page}&pageSize=${pageSize}&includeTotal=true`);
    const data = Array.isArray(result?.data) ? result.data : [];
    records.push(...data);
    if (!result?.hasMore || data.length === 0) return records;
  }
  throw new Error('ServiceTitan pagination exceeded safety limit');
}

export async function testServiceTitanConnection() {
  const c = config();
  const token = await getServiceTitanAccessToken();
  let technicianCount: number | null = null;
  let apiReachable = false;
  try {
    const result = await serviceTitanGet<any>('/settings/v2/tenant/{tenant}/technicians?page=1&pageSize=5');
    apiReachable = true;
    technicianCount = Array.isArray(result?.data) ? result.data.length : null;
  } catch (error) {
    const message = error instanceof Error ? error.message : 'ServiceTitan resource API check failed';
    return { configured: true, oauth: true, apiReachable: false, environment: c.env, tenant: c.tenant, technicianCount, error: message, tokenExpiresIn: token.expires_in ?? null, scope: token.scope ?? null };
  }
  return { configured: true, oauth: true, apiReachable, environment: c.env, tenant: c.tenant, technicianCount, tokenExpiresIn: token.expires_in ?? null, scope: token.scope ?? null };
}
