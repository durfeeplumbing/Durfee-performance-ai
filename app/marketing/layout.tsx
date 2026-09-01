import Link from 'next/link';

export default function MarketingLayout({children}:{children:React.ReactNode}){
  const links=[['/marketing','Command Center'],['/marketing/leads','Lead Inbox'],['/marketing/campaigns','Campaign Revenue'],['/marketing/funnel','Attribution Funnel'],['/marketing/setup','Tracking & Health'],['/marketing/providers','Ad Connections']];
  return <>
    <nav aria-label="Marketing sections" style={{maxWidth:1380,margin:'18px auto -6px',padding:'0 32px',display:'flex',gap:10,flexWrap:'wrap'}}>{links.map(([href,label])=><Link key={href} href={href} style={{padding:'8px 12px',border:'1px solid #ddd',borderRadius:999,textDecoration:'none'}}>{label}</Link>)}</nav>
    {children}
  </>;
}
