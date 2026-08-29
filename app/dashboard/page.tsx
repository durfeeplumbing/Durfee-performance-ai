const cards = [
  { label: "Revenue Today", value: "$18,640", detail: "Goal $20,000" },
  { label: "Gross Profit", value: "53.8%", detail: "Floor 50%" },
  { label: "Average Ticket", value: "$1,864", detail: "10 completed jobs" },
  { label: "Booking Rate", value: "86%", detail: "CSR team" },
  { label: "Unbilled Risk", value: "$1,275", detail: "3 jobs need review" },
  { label: "Callbacks", value: "1", detail: "Last 7 days" }
];

export default function DashboardPage() {
  return <main style={{fontFamily:"system-ui",maxWidth:1280,margin:"auto",padding:32}}>
    <header><p style={{fontWeight:800,letterSpacing:1}}>DURFEE PERFORMANCE AI</p><h1>Owner Command Center</h1><p>Daily operating health, profitability and exceptions.</p></header>
    <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(190px,1fr))",gap:16,margin:"28px 0"}}>
      {cards.map(c => <article key={c.label} style={{border:"1px solid #ddd",borderRadius:18,padding:20}}><small>{c.label}</small><h2>{c.value}</h2><p>{c.detail}</p></article>)}
    </section>
    <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(300px,1fr))",gap:20}}>
      <article style={{border:"1px solid #ddd",borderRadius:18,padding:22}}><h2>Needs Attention</h2><p>🔴 2 jobs below 50% GP</p><p>🟠 3 jobs have worked time above billed time</p><p>🟠 1 invoice is incomplete</p></article>
      <article style={{border:"1px solid #ddd",borderRadius:18,padding:22}}><h2>AI Operations</h2><p>Prioritize high-value calls for technicians with the strongest skill and close-rate match.</p><p>Review margin exceptions before invoices are finalized.</p><p>Coach from measurable trends, not one-off jobs.</p></article>
    </section>
  </main>;
}
