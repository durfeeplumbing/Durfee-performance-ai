import { NextResponse } from 'next/server';
import { createSupabaseAdminClient } from '@/lib/supabase/admin';

export const runtime='nodejs';
export const dynamic='force-dynamic';

function allowedOrigin(origin:string|null){
  const configured=(process.env.MARKETING_TRACKING_ALLOWED_ORIGINS||'').split(',').map(v=>v.trim()).filter(Boolean);
  return Boolean(origin&&configured.includes(origin));
}
function clean(value:unknown,max=512){const s=String(value??'').trim();return s?s.slice(0,max):null}
function cors(origin:string){return {'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Methods':'POST,OPTIONS','Access-Control-Allow-Headers':'Content-Type','Access-Control-Max-Age':'86400','Vary':'Origin'} as Record<string,string>}

export async function OPTIONS(request:Request){
  const origin=request.headers.get('origin');
  if(!allowedOrigin(origin))return new NextResponse(null,{status:403});
  return new NextResponse(null,{status:204,headers:cors(origin!)});
}

export async function POST(request:Request){
  const origin=request.headers.get('origin');
  if(!allowedOrigin(origin))return NextResponse.json({ok:false,error:'Origin not allowed'},{status:403});
  const type=request.headers.get('content-type')||'';
  if(!type.includes('application/json'))return NextResponse.json({ok:false,error:'JSON required'},{status:415,headers:cors(origin!)});
  let body:any;
  try{body=await request.json()}catch{return NextResponse.json({ok:false,error:'Invalid JSON'},{status:400,headers:cors(origin!)})}
  const sessionKey=clean(body?.sessionKey,128);
  if(!sessionKey||sessionKey.length<12)return NextResponse.json({ok:false,error:'Invalid session key'},{status:400,headers:cors(origin!)});
  const supabase=createSupabaseAdminClient();
  const {data,error}=await supabase.rpc('ingest_marketing_touchpoint_v2',{
    p_session_key:sessionKey,p_platform:clean(body?.platform,64),p_gclid:clean(body?.gclid),p_gbraid:clean(body?.gbraid),p_wbraid:clean(body?.wbraid),p_fbclid:clean(body?.fbclid),
    p_utm_source:clean(body?.utmSource,256),p_utm_medium:clean(body?.utmMedium,256),p_utm_campaign:clean(body?.utmCampaign,256),p_utm_term:clean(body?.utmTerm),p_utm_content:clean(body?.utmContent),
    p_landing_page:clean(body?.landingPage,2000),p_referrer:clean(body?.referrer,2000),p_external_campaign_id:clean(body?.externalCampaignId,256),p_external_group_id:clean(body?.externalGroupId,256),p_external_ad_id:clean(body?.externalAdId,256),
    p_device:clean(body?.device,64),p_network:clean(body?.network,64),p_match_type:clean(body?.matchType,64),
  });
  if(error)return NextResponse.json({ok:false,error:'Attribution capture failed'},{status:500,headers:cors(origin!)});
  return NextResponse.json({ok:true,touchpointId:data},{status:201,headers:{...cors(origin!),'Cache-Control':'no-store'}});
}
