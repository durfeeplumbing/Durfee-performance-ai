import './globals.css';
import Link from 'next/link';
import type { ReactNode } from 'react';

const nav=[['Dashboard','/dashboard'],['Schedule','/schedule'],['Dispatch','/dispatch'],['Jobs','/jobs'],['Customers','/customers'],['Estimates','/estimates'],['Price Book','/pricebook'],['Technicians','/team'],['CSR','/csr'],['Inventory','/inventory'],['Daily Report','/reports/daily']];
export const metadata={title:'Durfee Performance AI',description:'Standalone field service management and profitability platform'};
export default function RootLayout({children}:{children:ReactNode}){return <html lang="en"><body><div className="shell"><aside className="sidebar"><div className="brand">DURFEE<br/><span>PERFORMANCE AI</span></div><nav>{nav.map(([label,href])=><Link key={href} href={href}>{label}</Link>)}</nav><Link className="fieldLink" href="/field">Open Field App</Link></aside><div className="content">{children}</div></div></body></html>}
