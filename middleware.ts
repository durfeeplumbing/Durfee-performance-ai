import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

const fallbackUrl='https://ksbmdgwiztlbthagzhpg.supabase.co';
const fallbackPublishableKey='sb_publishable_Upwje6AofSbaZmFpPe8PIg_SsjATBk8';
const routePermissions:[string,string][]=[['/settings/permissions','manage_permissions'],['/accounting','view_accounting'],['/reports','view_reports'],['/inventory','view_inventory'],['/csr','view_csr'],['/team','view_team'],['/pricebook','view_pricebook'],['/billing','view_billing'],['/estimates','view_estimates'],['/customers','view_customers'],['/jobs','view_jobs'],['/dispatch','view_dispatch'],['/schedule','view_schedule'],['/field','field_app'],['/dashboard','view_dashboard']];
const publicPaths=['/login','/approve/'];

export async function middleware(request:NextRequest){
  const requestHeaders=new Headers(request.headers);requestHeaders.set('x-durfee-pathname',request.nextUrl.pathname);let response=NextResponse.next({request:{headers:requestHeaders}});
  const supabase=createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL||fallbackUrl,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||fallbackPublishableKey,{cookies:{getAll(){return request.cookies.getAll()},setAll(cookiesToSet){cookiesToSet.forEach(({name,value})=>request.cookies.set(name,value));response=NextResponse.next({request:{headers:requestHeaders}});cookiesToSet.forEach(({name,value,options})=>response.cookies.set(name,value,options));}}});
  const {data:{user}}=await supabase.auth.getUser();const path=request.nextUrl.pathname;if(publicPaths.some(p=>path.startsWith(p)))return response;if(!user)return response;
  const match=routePermissions.find(([prefix])=>path===prefix||path.startsWith(prefix+'/'));if(match){const {data:allowed,error}=await supabase.rpc('has_permission_for_current_user',{p_key:match[1]});if(error||allowed!==true){const url=request.nextUrl.clone();url.pathname='/dashboard';url.searchParams.set('permission_denied',match[1]);return NextResponse.redirect(url);}}
  return response;
}
export const config={matcher:['/((?!_next/static|_next/image|favicon.ico).*)']};
