import { NextResponse } from 'next/server';
import { getCurrentUser } from '@/lib/session';
import { createSupabaseAdminClient } from '@/lib/supabase/admin';
import { encryptMarketingToken,marketingBaseUrl,verifyMarketingOAuthState } from '@/lib/integrations/marketing-oauth';

export const runtime='nodejs';export const dynamic='force-dynamic';

export async function GET(request:Request){
  const user=await getCurrentUser();if(!user)return NextResponse.redirect(`${marketingBaseUrl()}/login`);if(user.role!=='owner')return NextResponse.redirect(`${marketingBaseUrl()}/marketing/providers?provider=google_ads&status=forbidden`);
  const url=new URL(request.url);const code=url.searchParams.get('code');const state=url.searchParams.get('state');const denied=url.searchParams.get('error');
  if(denied)return NextResponse.redirect(`${marketingBaseUrl()}/marketing/providers?provider=google_ads&status=denied`);
  try{
    if(!code||!state)throw new Error('Missing authorization response');verifyMarketingOAuthState(state,'google_ads',user.id);
    const clientId=process.env.GOOGLE_ADS_OAUTH_CLIENT_ID?.trim(),clientSecret=process.env.GOOGLE_ADS_OAUTH_CLIENT_SECRET?.trim();if(!clientId||!clientSecret)throw new Error('Google OAuth credentials are not configured');
    const redirectUri=`${marketingBaseUrl()}/api/integrations/google-ads/oauth/callback`;
    const response=await fetch('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({code,client_id:clientId,client_secret:clientSecret,redirect_uri:redirectUri,grant_type:'authorization_code'}),cache:'no-store'});
    const token:any=await response.json();if(!response.ok||!token.access_token)throw new Error(token.error_description||token.error||'Google token exchange failed');
    const admin=createSupabaseAdminClient();const existing=await admin.schema('private').from('marketing_provider_oauth_tokens').select('refresh_token_ciphertext').eq('provider','google_ads').maybeSingle();
    const scopes=String(token.scope||'https://www.googleapis.com/auth/datamanager https://www.googleapis.com/auth/adwords').split(/\s+/).filter(Boolean);
    const row={provider:'google_ads',access_token_ciphertext:encryptMarketingToken(token.access_token),refresh_token_ciphertext:token.refresh_token?encryptMarketingToken(token.refresh_token):(existing.data?.refresh_token_ciphertext||null),expires_at:token.expires_in?new Date(Date.now()+Number(token.expires_in)*1000).toISOString():null,token_type:token.token_type||'Bearer',granted_scopes:scopes,updated_at:new Date().toISOString()};
    const saved=await admin.schema('private').from('marketing_provider_oauth_tokens').upsert(row,{onConflict:'provider'});if(saved.error)throw new Error(saved.error.message);
    const marked=await admin.rpc('marketing_provider_mark_authorized',{p_provider:'google_ads',p_scopes:scopes});if(marked.error)throw new Error(marked.error.message);
    return NextResponse.redirect(`${marketingBaseUrl()}/marketing/providers?provider=google_ads&status=authorized`);
  }catch(error){
    console.error('Google Ads OAuth callback failed',error instanceof Error?error.message:error);return NextResponse.redirect(`${marketingBaseUrl()}/marketing/providers?provider=google_ads&status=error`);
  }
}
