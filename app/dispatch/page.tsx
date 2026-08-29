const jobs = [
  ["8:00 AM", "No Heat", "Dennis", "High", "Assign best HVAC diagnostic tech"],
  ["10:00 AM", "Water Heater", "Yarmouth", "High", "Prioritize tank/tankless sales skill"],
  ["12:30 PM", "Leak Repair", "Barnstable", "Normal", "Minimize drive time"],
  ["2:00 PM", "Boiler Estimate", "Harwich", "High", "Match boiler conversion leader"]
];
export default function DispatchPage(){return <main style={{fontFamily:"system-ui",maxWidth:1200,margin:"auto",padding:32}}><h1>Smart Dispatch</h1><p>Rank assignments using skill, geography, availability, conversion and revenue productivity.</p><div style={{overflowX:"auto"}}><table style={{width:"100%",borderCollapse:"collapse",marginTop:24}}><thead><tr>{["Time","Call","Town","Opportunity","AI Recommendation"].map(x=><th key={x} style={{textAlign:"left",padding:12,borderBottom:"1px solid #ccc"}}>{x}</th>)}</tr></thead><tbody>{jobs.map((r,i)=><tr key={i}>{r.map(x=><td key={x} style={{padding:12,borderBottom:"1px solid #eee"}}>{x}</td>)}</tr>)}</tbody></table></div></main>}
