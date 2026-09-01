import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

const fallbackUrl='https://ksbmdgwiztlbthagzhpg.supabase.co';
const fallbackPublishableKey='sb_publishable_Upwje6AofSbaZmFpPe8PIg_SsjATBk8';
const routePermissions:[string,string][]=[['/settings/permissions','manage_permissions'],['/settings/pricing','manage_pricing_settings'],['/accounting','view_accounting'],['/purchasing','view_purchasing'],['/opportunities','view_opportunities'],['/staging','view_staging'],['/reports','view_reports'],['/inventory','view_inventory'],['/reviews','view_csr'],['/csr','view_csr'],['/team','view_team'],['/pricebook','view_pricebook'],['/billing','view_billing'],['/estimates','view_estimates'],['/customers','view_customers'],['/jobs','view_jobs'],['/dispatch','view_dispatch'],['/schedule','view_schedule'],['/field','field_app'],['/dashboard','view_dashboard']];
const publicPaths=['/login','/approve/','/join/','/unauthorized'];

export async function middleware(request:NextRequest){
  const path=request.nextUrl.pathname;
  const requestHeaders=new Headers(request.headers);requestHeaders.set('x-durfee-pathname',path);
  let response=NextResponse.next({request:{headers:requestHeaders}});

  // Public token/login routes do not need an Auth round trip. Keeping these paths
  // completely local also prevents a transient Auth/Data API slowdown from
  // blocking customer estimate approvals or employee invite pages.
  if(publicPaths.some(p=>path===p||path.startsWith(p+'/')))return response;

  const supabase=createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL||fallbackUrl,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||fallbackPublishableKey,{cookies:{getAll(){return request.cookies.getAll()},setAll(cookiesToSet){cookiesToSet.forEach(({name,value})=>request.cookies.set(name,value));response=NextResponse.next({request:{headers:requestHeaders}});cookiesToSet.forEach(({name,value,options})=>response.cookies.set(name,value,options));}}});
  const {data:{user}}=await supabase.auth.getUser();
  if(!user)return response;
  const match=routePermissions.find(([prefix])=>path===prefix||path.startsWith(prefix+'/'));
  if(match){const {data:allowed,error}=await supabase.rpc('has_permission_for_current_user',{p_key:match[1]});if(error||allowed!==true){const url=request.nextUrl.clone();url.pathname='/unauthorized';url.search='';url.searchParams.set('permission',match[1]);return NextResponse.redirect(url);}}
  return response;
}
export const config={matcher:['/((?!_next/static|_next/image|favicon.ico).*)']};
