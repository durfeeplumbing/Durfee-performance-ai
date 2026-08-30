import './globals.css';
import Link from 'next/link';
import { redirect } from 'next/navigation';
import type { ReactNode } from 'react';
import { getCurrentUser } from '@/lib/session';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { logout } from '@/app/login/actions';

const nav=[['Dashboard','/dashboard','view_dashboard'],['Schedule','/schedule','view_schedule'],['Dispatch','/dispatch','view_dispatch'],['Jobs','/jobs','view_jobs'],['Customers','/customers','view_customers'],['Estimates','/estimates','view_estimates'],['Billing','/billing','view_billing'],['Price Book','/pricebook','view_pricebook'],['Technicians','/team','view_team'],['CSR','/csr','view_csr'],['Inventory','/inventory','view_inventory'],['Daily Report','/reports/daily','view_reports']];
const publicPaths=['/login','/approve/'];
export const metadata={title:'Durfee Performance AI',description:'Standalone field service management and profitability platform'};

export default async function RootLayout({children}:{children:ReactNode}){
  const { headers }=await import('next/headers');const pathname=(await headers()).get('x-durfee-pathname')??'';if(publicPaths.some(path=>pathname.startsWith(path)))return <html lang="en"><body>{children}</body></html>;const user=await getCurrentUser();if(!user)redirect('/login');
  let allowed=new Set<string>();if(user.role==='owner'){allowed=new Set(nav.map(x=>x[2]));allowed.add('field_app');allowed.add('manage_permissions');}else{const s=await createSupabaseServerClient();const {data:roleRows}=await s.from('role_permissions').select('permission_key,allowed').eq('role',user.role);const {data:overrides}=await s.from('user_permission_overrides').select('permission_key,allowed').eq('user_id',user.id);for(const r of roleRows??[])if(r.allowed)allowed.add(r.permission_key);for(const o of overrides??[]){if(o.allowed)allowed.add(o.permission_key);else allowed.delete(o.permission_key);}}
  const visibleNav=nav.filter(x=>allowed.has(x[2]));if(allowed.has('manage_permissions'))visibleNav.push(['Permissions','/settings/permissions','manage_permissions']);
  return <html lang="en"><body><div className="shell"><aside className="sidebar"><div className="brand">DURFEE<br/><span>PERFORMANCE AI</span></div><nav>{visibleNav.map(([label,href])=><Link key={href} href={href}>{label}</Link>)}</nav>{allowed.has('field_app')&&<Link className="fieldLink" href="/field">Open Field App</Link>}<div style={{marginTop:20,fontSize:12,opacity:.8}}>{user.name}<br/>{user.role}</div><form action={logout}><button type="submit" style={{marginTop:10}}>Sign out</button></form></aside><div className="content">{children}</div></div></body></html>;
}
