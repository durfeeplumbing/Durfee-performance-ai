import { NextResponse } from 'next/server';
import { createSupabaseAdminClient } from '@/lib/supabase/admin';
import { normalizeWebsiteEvent } from '@/lib/marketing/website-events';
export const runtime='nodejs';
export const dynamic='force-dynamic';
function originFor(request:Request){const origin=request.headers.get('origin');return origin&&(process.env.MARKETING_TRACKING_ALLOWED_ORIGINS||'').split(',').map(x=>x.trim()).includes(origin)?origin:null;}
function headers(origin:string){return {'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Methods':'POST,OPTIONS','Access-Control-Allow-Headers':'Content-Type','Vary':'Origin','Cache-Control':'no-store'};}
export async function OPTIONS(request:Request){const origin=originFor(request);return new NextResponse(null,{status:origin?204:403,headers:origin?headers(origin):{}});}
export async function POST(request:Request){
 const origin=originFor(request);if(!origin)return NextResponse.json({error:'Origin not allowed'},{status:403});
 const h=headers(origin);
 try {
  if(Number(request.headers.get('content-length')||0)>4096)return NextResponse.json({error:'Request too large'},{status:413,headers:h});
  const text=await request.text();if(text.length>4096)return NextResponse.json({error:'Request too large'},{status:413,headers:h});
  const body=JSON.parse(text);const event=body&&typeof body==='object'&&!Array.isArray(body)?normalizeWebsiteEvent(body):null;
  if(!event)return NextResponse.json({error:'Invalid event'},{status:400,headers:h});
  const db=createSupabaseAdminClient();
  const {data,error}=await db.rpc('capture_website_event',{p_event:event});
  if(error)return NextResponse.json({error:'Tracking temporarily unavailable'},{status:503,headers:h});
  return NextResponse.json({ok:true,accepted:data===true},{status:202,headers:h});
 }catch{return NextResponse.json({error:'Invalid request'},{status:400,headers:h});}
}
