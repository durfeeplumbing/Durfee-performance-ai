import { NextResponse } from 'next/server';
import { createSupabaseAdminClient } from '@/lib/supabase/admin';

export const runtime='nodejs';
export const dynamic='force-dynamic';

function allowedOrigin(origin:string|null){const configured=(process.env.MARKETING_TRACKING_ALLOWED_ORIGINS||'').split(',').map(v=>v.trim()).filter(Boolean);return Boolean(origin&&configured.includes(origin));}
function clean(value:unknown,max:number){const s=String(value??'').trim();return s?s.slice(0,max):null;}
function cors(origin:string){return {'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Methods':'POST,OPTIONS','Access-Control-Allow-Headers':'Content-Type','Access-Control-Max-Age':'86400','Vary':'Origin'} as Record<string,string>;}

export async function OPTIONS(request:Request){const origin=request.headers.get('origin');if(!allowedOrigin(origin))return new NextResponse(null,{status:403});return new NextResponse(null,{status:204,headers:cors(origin!)});}

export async function POST(request:Request){
  const origin=request.headers.get('origin');
  if(!allowedOrigin(origin))return NextResponse.json({ok:false,error:'Origin not allowed'},{status:403});
  if(!(request.headers.get('content-type')||'').includes('application/json'))return NextResponse.json({ok:false,error:'JSON required'},{status:415,headers:cors(origin!)});
  let body:any;try{body=await request.json();}catch{return NextResponse.json({ok:false,error:'Invalid JSON'},{status:400,headers:cors(origin!)});}
  const sessionKey=clean(body?.sessionKey,128),phone=clean(body?.phone,100),email=clean(body?.email,320);
  if(!sessionKey||sessionKey.length<12)return NextResponse.json({ok:false,error:'Invalid session key'},{status:400,headers:cors(origin!)});
  if(!phone&&!email)return NextResponse.json({ok:false,error:'Phone or email required'},{status:400,headers:cors(origin!)});
  const admin=createSupabaseAdminClient();
  const {data,error}=await admin.rpc('ingest_marketing_lead',{p_session_key:sessionKey,p_form_name:clean(body?.formName,200),p_name:clean(body?.name,300),p_phone:phone,p_email:email,p_service_request:clean(body?.serviceRequest,4000),p_landing_page:clean(body?.landingPage,2000)});
  if(error){console.error('Marketing lead capture failed',error.message);return NextResponse.json({ok:false,error:'Lead attribution capture failed'},{status:500,headers:cors(origin!)});}
  return NextResponse.json({ok:true,leadId:data},{status:201,headers:{...cors(origin!),'Cache-Control':'no-store'}});
}
