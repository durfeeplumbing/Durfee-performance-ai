import { NextResponse } from 'next/server';
import { getCurrentUser } from '@/lib/session';
import { createSupabaseAdminClient } from '@/lib/supabase/admin';
import { encryptMarketingToken,marketingBaseUrl,verifyMarketingOAuthState,marketingOAuthMissingSettings } from '@/lib/integrations/marketing-oauth';

export const runtime='nodejs';export const dynamic='force-dynamic';

export async function GET(request:Request){
  const user=await getCurrentUser();if(!user)return NextResponse.redirect(`${marketingBaseUrl()}/login`);if(user.role!=='owner')return NextResponse.redirect(`${marketingBaseUrl()}/marketing/providers?provider=google_ads&status=forbidden`);
  const url=new URL(request.url);const code=url.searchParams.get('code');const state=url.searchParams.get('state');const denied=url.searchParams.get('error');
  if(denied)return NextResponse.redirect(`${marketingBaseUrl()}/marketing/providers?provider=google_ads&status=denied`);
  if(marketingOAuthMissingSettings('google_ads').length)return NextResponse.redirect(`${marketingBaseUrl()}/marketing/providers?provider=google_ads&status=configuration_required`);
  let step='authorization_response';
  try{
    if(!code||!state)throw new Error('Missing authorization response');verifyMarketingOAuthState(state,'google_ads',user.id);
    const clientId=process.env.GOOGLE_ADS_OAUTH_CLIENT_ID?.trim(),clientSecret=process.env.GOOGLE_ADS_OAUTH_CLIENT_SECRET?.trim();if(!clientId||!clientSecret)throw new Error('Google OAuth credentials are not configured');
    const redirectUri=`${marketingBaseUrl()}/api/integrations/google-ads/oauth/callback`;
    step='token_exchange';
    const response=await fetch('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({code,client_id:clientId,client_secret:clientSecret,redirect_uri:redirectUri,grant_type:'authorization_code'}),cache:'no-store'});
    const token:any=await response.json();if(!response.ok||!token.access_token)throw new Error(token.error_description||token.error||'Google token exchange failed');
    step='token_storage';
    const admin=createSupabaseAdminClient();
    const scopes=String(token.scope||'https://www.googleapis.com/auth/datamanager https://www.googleapis.com/auth/adwords').split(/\s+/).filter(Boolean);
    const saved=await admin.rpc('marketing_provider_save_oauth',{
      p_provider:'google_ads',p_access_token_ciphertext:encryptMarketingToken(token.access_token),
      p_refresh_token_ciphertext:token.refresh_token?encryptMarketingToken(token.refresh_token):null,
      p_expires_at:token.expires_in?new Date(Date.now()+Number(token.expires_in)*1000).toISOString():null,
      p_token_type:token.token_type||'Bearer',p_scopes:scopes,
    });if(saved.error)throw new Error(saved.error.message);
    return NextResponse.redirect(`${marketingBaseUrl()}/marketing/providers?provider=google_ads&status=authorized`);
  }catch(error){
    console.error('Google Ads OAuth callback failed',step,error instanceof Error?error.message:error);return NextResponse.redirect(`${marketingBaseUrl()}/marketing/providers?provider=google_ads&status=${step}_error`);
  }
}
