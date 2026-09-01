import Link from 'next/link';

export default function MarketingLayout({children}:{children:React.ReactNode}){
  return <>
    <nav aria-label="Marketing sections" style={{maxWidth:1380,margin:'18px auto -6px',padding:'0 32px',display:'flex',gap:10,flexWrap:'wrap'}}>
      <Link href="/marketing" style={{padding:'8px 12px',border:'1px solid #ddd',borderRadius:999,textDecoration:'none'}}>Command Center</Link>
      <Link href="/marketing/setup" style={{padding:'8px 12px',border:'1px solid #ddd',borderRadius:999,textDecoration:'none'}}>Tracking & Attribution Health</Link>
    </nav>
    {children}
  </>;
}
