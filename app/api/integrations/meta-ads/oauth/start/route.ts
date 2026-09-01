import { NextResponse } from 'next/server';
import { getCurrentUser } from '@/lib/session';
import { makeMarketingOAuthState,marketingBaseUrl } from '@/lib/integrations/marketing-oauth';

export const runtime='nodejs';export const dynamic='force-dynamic';

export async function GET(){
  const user=await getCurrentUser();if(!user)return NextResponse.json({error:'Authentication required'},{status:401});
  if(user.role!=='owner')return NextResponse.json({error:'Owner access required'},{status:403});
  const appId=process.env.META_ADS_APP_ID?.trim(),version=process.env.META_GRAPH_VERSION?.trim();
  if(!appId||!version)return NextResponse.redirect(`${marketingBaseUrl()}/marketing/providers?provider=meta_ads&status=configuration_required`);
  const redirectUri=`${marketingBaseUrl()}/api/integrations/meta-ads/oauth/callback`;
  const url=new URL(`https://www.facebook.com/${version}/dialog/oauth`);
  url.searchParams.set('client_id',appId);url.searchParams.set('redirect_uri',redirectUri);url.searchParams.set('response_type','code');
  url.searchParams.set('scope','ads_read,ads_management,business_management');url.searchParams.set('state',makeMarketingOAuthState('meta_ads',user.id));
  return NextResponse.redirect(url);
}
