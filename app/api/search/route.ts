import { NextRequest, NextResponse } from 'next/server';
import { getCurrentUser } from '@/lib/session';
import { createSupabaseServerClient } from '@/lib/supabase/server';

export const dynamic='force-dynamic';

export async function GET(request:NextRequest){
  const user=await getCurrentUser();
  if(!user)return NextResponse.json({error:'Unauthorized'},{status:401});
  const q=(request.nextUrl.searchParams.get('q')||'').trim();
  if(q.length<2)return NextResponse.json({results:[]});
  const supabase=await createSupabaseServerClient();
  const {data,error}=await supabase.rpc('global_system_search',{p_query:q,p_limit_per_category:8});
  if(error)return NextResponse.json({error:'Search unavailable'},{status:500});
  return NextResponse.json({results:data??[]},{headers:{'Cache-Control':'private, no-store'}});
}
