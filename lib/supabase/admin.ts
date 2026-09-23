import 'server-only';
import { createClient } from '@supabase/supabase-js';
import { supabaseProjectUrl } from './config';

function serverSecret(){
  return process.env.SUPABASE_SECRET_KEY?.trim() || process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
}

export function supabaseAdminReady(){return Boolean(serverSecret())}

export function createSupabaseAdminClient(){
  const url=supabaseProjectUrl();
  const secret=serverSecret();
  if(!secret)throw new Error('SUPABASE_SECRET_KEY or SUPABASE_SERVICE_ROLE_KEY is not configured');
  return createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
}
