import { createHash,timingSafeEqual } from 'node:crypto';
import { NextResponse } from 'next/server';
import { syncWebsiteCalls } from '@/lib/marketing/servicetitan-report';
export const runtime='nodejs';export const dynamic='force-dynamic';export const maxDuration=300;
export async function POST(request:Request){
 const secret=process.env.PERFORMANCE_REPORT_SECRET;
 if(!secret||!timingSafeEqual(createHash('sha256').update(request.headers.get('authorization')||'').digest(),createHash('sha256').update('Bearer '+secret).digest()))return NextResponse.json({error:'Unauthorized'},{status:401});
 try{const result=await syncWebsiteCalls(new URL(request.url).searchParams.get('inspect')==='1');return NextResponse.json(result,{headers:{'Cache-Control':'no-store'}});}catch{return NextResponse.json({error:'ServiceTitan connection unavailable'},{status:503});}
}
