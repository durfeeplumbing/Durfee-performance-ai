import { NextResponse } from 'next/server';
import { getCurrentUser } from '@/lib/session';
import { createSupabaseAdminClient } from '@/lib/supabase/admin';
import { encryptMarketingToken,marketingBaseUrl,verifyMarketingOAuthState } from '@/lib/integrations/marketing-oauth';

export const runtime='nodejs';export const dynamic='force-dynamic';

export async function GET(request:Request){
  const user=await getCurrentUser();if(!user)return NextResponse.redirect(`${marketingBaseUrl()}/login`);if(user.role!=='owner')return NextResponse.redirect(`${marketingBaseUrl()}/marketing/connections?provider=meta_ads&status=forbidden`);
  const url=new URL(request.url);const code=url.searchParams.get('code');const state=url.searchParams.get('state');const denied=url.searchParams.get('error');
  if(denied)return NextResponse.redirect(`${marketingBaseUrl()}/marketing/connections?provider=meta_ads&status=denied`);
  try{
    if(!code||!state)throw new Error('Missing authorization response');verifyMarketingOAuthState(state,'meta_ads',user.id);
    const appId=process.env.META_ADS_APP_ID?.trim(),appSecret=process.env.META_ADS_APP_SECRET?.trim(),version=process.env.META_GRAPH_VERSION?.trim();if(!appId||!appSecret||!version)throw new Error('Meta OAuth credentials are not configured');
    const redirectUri=`${marketingBaseUrl()}/api/integrations/meta-ads/oauth/callback`;
    const shortUrl=new URL(`https://graph.facebook.com/${version}/oauth/access_token`);shortUrl.searchParams.set('client_id',appId);shortUrl.searchParams.set('client_secret',appSecret);shortUrl.searchParams.set('redirect_uri',redirectUri);shortUrl.searchParams.set('code',code);
    const shortResp=await fetch(shortUrl,{cache:'no-store'});const short:any=await shortResp.json();if(!shortResp.ok||!short.access_token)throw new Error(short.error?.message||'Meta token exchange failed');
    let accessToken=short.access_token;let expiresIn=Number(short.expires_in||0);
    const longUrl=new URL(`https://graph.facebook.com/${version}/oauth/access_token`);longUrl.searchParams.set('grant_type','fb_exchange_token');longUrl.searchParams.set('client_id',appId);longUrl.searchParams.set('client_secret',appSecret);longUrl.searchParams.set('fb_exchange_token',accessToken);
    const longResp=await fetch(longUrl,{cache:'no-store'});if(longResp.ok){const long:any=await longResp.json();if(long.access_token){accessToken=long.access_token;expiresIn=Number(long.expires_in||expiresIn)}}
    const scopes=['ads_read','ads_management','business_management'];const admin=createSupabaseAdminClient();
    const saved=await admin.schema('private').from('marketing_provider_oauth_tokens').upsert({provider:'meta_ads',access_token_ciphertext:encryptMarketingToken(accessToken),refresh_token_ciphertext:null,expires_at:expiresIn?new Date(Date.now()+expiresIn*1000).toISOString():null,token_type:'Bearer',granted_scopes:scopes,updated_at:new Date().toISOString()},{onConflict:'provider'});if(saved.error)throw new Error(saved.error.message);
    const marked=await admin.rpc('marketing_provider_mark_authorized',{p_provider:'meta_ads',p_scopes:scopes});if(marked.error)throw new Error(marked.error.message);
    return NextResponse.redirect(`${marketingBaseUrl()}/marketing/connections?provider=meta_ads&status=authorized`);
  }catch(error){console.error('Meta Ads OAuth callback failed',error instanceof Error?error.message:error);return NextResponse.redirect(`${marketingBaseUrl()}/marketing/connections?provider=meta_ads&status=error`)}
}
