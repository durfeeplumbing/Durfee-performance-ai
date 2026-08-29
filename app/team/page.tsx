const team = [
 {name:"Technician A",role:"Plumbing",score:91,gp:"56%",close:"78%",rph:"$425"},
 {name:"Technician B",role:"HVAC",score:87,gp:"53%",close:"74%",rph:"$510"},
 {name:"Technician C",role:"Service",score:72,gp:"47%",close:"61%",rph:"$340"}
];
export default function TeamPage(){return <main style={{fontFamily:"system-ui",maxWidth:1200,margin:"auto",padding:32}}><h1>Technician Performance</h1><p>Scorecards combine profitability, conversion, billable efficiency, productivity, reviews and callbacks.</p><section style={{display:"grid",gap:14,marginTop:24}}>{team.map(t=><article key={t.name} style={{border:"1px solid #ddd",borderRadius:18,padding:20,display:"grid",gridTemplateColumns:"2fr repeat(4,1fr)",gap:12}}><strong>{t.name}<br/><small>{t.role}</small></strong><span>Score<br/><b>{t.score}</b></span><span>GP<br/><b>{t.gp}</b></span><span>Close<br/><b>{t.close}</b></span><span>Rev/Hr<br/><b>{t.rph}</b></span></article>)}</section></main>}
