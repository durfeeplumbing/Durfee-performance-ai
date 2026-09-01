import { NextResponse } from 'next/server';
import { getCurrentUser } from '@/lib/session';
import { makeMarketingOAuthState,marketingBaseUrl } from '@/lib/integrations/marketing-oauth';

export const runtime='nodejs';export const dynamic='force-dynamic';

export async function GET(){
  const user=await getCurrentUser();if(!user)return NextResponse.json({error:'Authentication required'},{status:401});
  if(user.role!=='owner')return NextResponse.json({error:'Owner access required'},{status:403});
  const clientId=process.env.GOOGLE_ADS_OAUTH_CLIENT_ID?.trim();if(!clientId)return NextResponse.redirect(`${marketingBaseUrl()}/marketing/connections?provider=google_ads&status=configuration_required`);
  const redirectUri=`${marketingBaseUrl()}/api/integrations/google-ads/oauth/callback`;
  const url=new URL('https://accounts.google.com/o/oauth2/v2/auth');
  url.searchParams.set('client_id',clientId);url.searchParams.set('redirect_uri',redirectUri);url.searchParams.set('response_type','code');
  url.searchParams.set('scope','https://www.googleapis.com/auth/datamanager https://www.googleapis.com/auth/adwords');
  url.searchParams.set('access_type','offline');url.searchParams.set('prompt','consent');url.searchParams.set('include_granted_scopes','true');
  url.searchParams.set('state',makeMarketingOAuthState('google_ads',user.id));
  return NextResponse.redirect(url);
}
