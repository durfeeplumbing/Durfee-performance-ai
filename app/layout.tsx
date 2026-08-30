import './globals.css';
import Link from 'next/link';
import { redirect } from 'next/navigation';
import type { ReactNode } from 'react';
import { getCurrentUser } from '@/lib/session';
import { logout } from '@/app/login/actions';

const nav=[['Dashboard','/dashboard'],['Schedule','/schedule'],['Dispatch','/dispatch'],['Jobs','/jobs'],['Customers','/customers'],['Estimates','/estimates'],['Billing','/billing'],['Price Book','/pricebook'],['Technicians','/team'],['CSR','/csr'],['Inventory','/inventory'],['Daily Report','/reports/daily']];
const publicPaths=['/login','/setup-owner'];
export const metadata={title:'Durfee Performance AI',description:'Standalone field service management and profitability platform'};

export default async function RootLayout({children}:{children:ReactNode}){
  const { headers }=await import('next/headers');
  const pathname=(await headers()).get('x-durfee-pathname')??'';
  if(publicPaths.some(path=>pathname.startsWith(path)))return <html lang="en"><body>{children}</body></html>;
  const user=await getCurrentUser();
  if(!user)redirect('/login');
  return <html lang="en"><body><div className="shell"><aside className="sidebar"><div className="brand">DURFEE<br/><span>PERFORMANCE AI</span></div><nav>{nav.map(([label,href])=><Link key={href} href={href}>{label}</Link>)}</nav><Link className="fieldLink" href="/field">Open Field App</Link><div style={{marginTop:20,fontSize:12,opacity:.8}}>{user.name}<br/>{user.role}</div><form action={logout}><button type="submit" style={{marginTop:10}}>Sign out</button></form></aside><div className="content">{children}</div></div></body></html>
}
