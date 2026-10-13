export const eventKinds = ['page_view','call_click','text_click','form_open','scheduler_open'] as const;
export type WebsiteEventKind = typeof eventKinds[number];
export function safeWebsitePath(value: unknown): string | null {
  if (typeof value !== 'string' || value.length > 2000) return null;
  let input=value.trim();
  // ServiceTitan DNI emits host/path without a URL scheme.
  if (/^(?:www\.)?capecodplumber\.com(?:[/?#]|$)/i.test(input)) input='https://'+input;
  if (!/^(?:\/|https:\/\/)/i.test(input)) return null;
  try {
    const url = new URL(input, 'https://capecodplumber.com');
    if (!['capecodplumber.com','www.capecodplumber.com'].includes(url.hostname) || url.protocol !== 'https:') return null;
    return url.pathname.slice(0,512);
  } catch { return null; }
}
export function normalizeWebsiteEvent(body: Record<string, unknown>) {
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (!uuid.test(String(body.eventId)) || !uuid.test(String(body.sessionId))) return null;
  if (!eventKinds.includes(body.kind as WebsiteEventKind)) return null;
  const page = safeWebsitePath(body.pagePath), entry = safeWebsitePath(body.entryPath);
  if (!page || !entry) return null;
  const bounded = (v: unknown) => typeof v === 'string' ? v.replace(/[\r\n<>]/g,'').slice(0,128) : null;
  return { id:body.eventId,session_id:body.sessionId,event_kind:body.kind,page_path:page,entry_path:entry,
    source:bounded(body.source),medium:bounded(body.medium),campaign:bounded(body.campaign) };
}
