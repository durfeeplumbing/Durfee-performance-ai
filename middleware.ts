import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

const fallbackUrl='https://ksbmdgwiztlbthagzhpg.supabase.co';
const fallbackPublishableKey='sb_publishable_Upwje6AofSbaZmFpPe8PIg_SsjATBk8';

export async function middleware(request:NextRequest){
  const requestHeaders=new Headers(request.headers);
  requestHeaders.set('x-durfee-pathname',request.nextUrl.pathname);
  let response=NextResponse.next({request:{headers:requestHeaders}});
  const supabase=createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL||fallbackUrl,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||fallbackPublishableKey,
    {cookies:{
      getAll(){return request.cookies.getAll()},
      setAll(cookiesToSet){
        cookiesToSet.forEach(({name,value})=>request.cookies.set(name,value));
        response=NextResponse.next({request:{headers:requestHeaders}});
        cookiesToSet.forEach(({name,value,options})=>response.cookies.set(name,value,options));
      }
    }}
  );
  await supabase.auth.getUser();
  return response;
}

export const config={matcher:['/((?!_next/static|_next/image|favicon.ico).*)']};
