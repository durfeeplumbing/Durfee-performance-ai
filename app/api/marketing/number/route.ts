import { NextResponse } from 'next/server';
import { createSupabaseAdminClient } from '@/lib/supabase/admin';

export const runtime='nodejs';
export const dynamic='force-dynamic';

function allowedOrigin(origin:string|null){
  const configured=(process.env.MARKETING_TRACKING_ALLOWED_ORIGINS||'').split(',').map(v=>v.trim()).filter(Boolean);
  return Boolean(origin&&configured.includes(origin));
}
function cors(origin:string){return {'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Methods':'POST,OPTIONS','Access-Control-Allow-Headers':'Content-Type','Access-Control-Max-Age':'86400','Vary':'Origin'} as Record<string,string>}

export async function OPTIONS(request:Request){
  const origin=request.headers.get('origin');
  if(!allowedOrigin(origin))return new NextResponse(null,{status:403});
  return new NextResponse(null,{status:204,headers:cors(origin!)});
}

export async function POST(request:Request){
  const origin=request.headers.get('origin');
  if(!allowedOrigin(origin))return NextResponse.json({ok:false,error:'Origin not allowed'},{status:403});
  let body:any;
  try{body=await request.json()}catch{return NextResponse.json({ok:false,error:'Invalid JSON'},{status:400,headers:cors(origin!)})}
  const sessionKey=String(body?.sessionKey??'').trim().slice(0,128);
  if(sessionKey.length<12)return NextResponse.json({ok:false,error:'Invalid session key'},{status:400,headers:cors(origin!)});
  const admin=createSupabaseAdminClient();
  const {data,error}=await admin.rpc('assign_marketing_tracking_number',{p_session_key:sessionKey,p_ttl_minutes:30});
  if(error)return NextResponse.json({ok:false,error:'Tracking number assignment failed'},{status:500,headers:cors(origin!)});
  const row=Array.isArray(data)?data[0]:null;
  if(!row)return NextResponse.json({ok:true,available:false},{status:200,headers:cors(origin!)});
  return NextResponse.json({ok:true,available:true,phoneNumber:row.phone_number,expiresAt:row.expires_at},{status:200,headers:cors(origin!)});
}
