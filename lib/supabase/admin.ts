import 'server-only';
import { createClient } from '@supabase/supabase-js';

export function createSupabaseAdminClient(){
  const url=process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const secret=(process.env.SUPABASE_SECRET_KEY||process.env.SUPABASE_SERVICE_ROLE_KEY)?.trim();
  if(!url||!secret)throw new Error('Supabase server secret is not configured');
  return createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
}
