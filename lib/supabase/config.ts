// Keep session and server-only clients on the same project when no URL override is set.
export function supabaseProjectUrl() {
  return process.env.NEXT_PUBLIC_SUPABASE_URL?.trim() || 'https://ksbmdgwiztlbthagzhpg.supabase.co';
}
