const metrics = [
  ["Revenue Today", "$0", "Connect ServiceTitan"],
  ["Gross Profit", "—", "Target ≥ 50%"],
  ["Average Ticket", "$0", "Live after sync"],
  ["Booked Calls", "0", "CSR feed pending"],
];

export default function Home() {
  return (
    <main style={{fontFamily:"system-ui",maxWidth:1200,margin:"0 auto",padding:32}}>
      <p style={{fontWeight:700,letterSpacing:1}}>DURFEE PERFORMANCE AI</p>
      <h1>Owner Command Center</h1>
      <p>Profitability, people, dispatch and growth — one operating view.</p>
      <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(210px,1fr))",gap:16,marginTop:32}}>
        {metrics.map(([label,value,note]) => <article key={label} style={{border:"1px solid #ddd",borderRadius:16,padding:20}}><small>{label}</small><h2>{value}</h2><p>{note}</p></article>)}
      </section>
      <section style={{marginTop:36}}>
        <h2>AI Operations Queue</h2>
        <ul>
          <li>Flag jobs projected below the configured gross-profit floor.</li>
          <li>Recommend dispatch assignments using skill, geography, capacity and revenue opportunity.</li>
          <li>Surface unbilled time/material and invoice exceptions before day close.</li>
          <li>Coach technicians and CSRs from measurable outcomes and approved operating standards.</li>
        </ul>
      </section>
    </main>
  );
}
