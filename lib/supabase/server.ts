import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';

const fallbackUrl='https://ksbmdgwiztlbthagzhpg.supabase.co';
const fallbackPublishableKey='sb_publishable_Upwje6AofSbaZmFpPe8PIg_SsjATBk8';

export async function createSupabaseServerClient(){
  const cookieStore=await cookies();
  const url=process.env.NEXT_PUBLIC_SUPABASE_URL||fallbackUrl;
  const key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||fallbackPublishableKey;
  return createServerClient(url,key,{
    cookies:{
      getAll(){return cookieStore.getAll()},
      setAll(cookiesToSet){try{cookiesToSet.forEach(({name,value,options})=>cookieStore.set(name,value,options))}catch{/* Server Components cannot always set cookies; middleware refresh handles this. */}}
    }
  });
}
