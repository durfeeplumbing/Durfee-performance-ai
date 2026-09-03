import Link from 'next/link';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { requireCurrentUser } from '@/lib/session';

function dayKey(d:Date){return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`}
function relationName(value:any){const row=Array.isArray(value)?value[0]:value;return row?.name??null}
function relationAddress(value:any){const row=Array.isArray(value)?value[0]:value;return row?.service_address??null}
function durationHours(job:any){if(!job.scheduled_start||!job.scheduled_end)return 0;return Math.max(0,(new Date(job.scheduled_end).getTime()-new Date(job.scheduled_start).getTime())/3600000)}
function hasOverlap(job:any,rows:any[]){if(job.staged||!job.technician_id||!job.scheduled_start||!job.scheduled_end)return false;const start=new Date(job.scheduled_start).getTime(),end=new Date(job.scheduled_end).getTime();return rows.some(other=>other.id!==job.id&&!other.staged&&other.technician_id===job.technician_id&&other.scheduled_start&&other.scheduled_end&&new Date(other.scheduled_start).getTime()<end&&new Date(other.scheduled_end).getTime()>start)}

export default async function SchedulePage({searchParams}:{searchParams:Promise<{week?:string;tech?:string}>}){
  await requireCurrentUser();
  const sp=await searchParams;
  const anchor=sp.week&&/^\d{4}-\d{2}-\d{2}$/.test(sp.week)?new Date(`${sp.week}T12:00:00`):new Date();
  const start=new Date(anchor);start.setDate(start.getDate()-start.getDay());start.setHours(0,0,0,0);
  const end=new Date(start);end.setDate(end.getDate()+7);
  const prev=new Date(start);prev.setDate(prev.getDate()-7);
  const next=new Date(start);next.setDate(next.getDate()+7);
  const days=Array.from({length:7},(_,i)=>{const d=new Date(start);d.setDate(d.getDate()+i);return d});
  const supabase=await createSupabaseServerClient();
  const [{data:nativeData,error:nativeError},{data:techs}]=await Promise.all([
    supabase.from('jobs').select('id,status,service_type,service_summary,scheduled_start,scheduled_end,technician_id,customers(name,service_address),users(name)').gte('scheduled_start',start.toISOString()).lt('scheduled_start',end.toISOString()).order('scheduled_start'),
    supabase.from('users').select('id,name').eq('role','technician').eq('active',true).order('name')
  ]);
  const nativeRows:any[]=nativeError?[]:(nativeData??[]);
  const {data:stagedData,error:stagedError}=nativeRows.length===0?await supabase.rpc('service_titan_schedule_fallback',{p_start:start.toISOString(),p_end:end.toISOString()}):{data:null,error:null};
  const stagedRows:any[]=(stagedData??[]).map((r:any)=>({id:`st-${r.appointment_id}`,staged:true,external_job_id:r.job_external_id,job_number:r.job_number,status:r.appointment_status||r.job_status,service_type:'ServiceTitan Job',service_summary:r.summary,scheduled_start:r.scheduled_start,scheduled_end:r.scheduled_end,technician_id:null,customers:{name:r.customer_name,service_address:r.service_address},users:null,total:r.total}));
  const usingStaged=nativeRows.length===0&&stagedRows.length>0;
  const allRows=usingStaged?stagedRows:nativeRows;
  const rows=sp.tech&&!usingStaged?allRows.filter(j=>j.technician_id===sp.tech):allRows;
  const today=dayKey(new Date());
  const unassigned=usingStaged?[]:allRows.filter(j=>!j.technician_id);
  const conflicts=usingStaged?[]:allRows.filter(j=>hasOverlap(j,allRows));
  const weekHours=allRows.reduce((sum,j)=>sum+durationHours(j),0);
  const filterSuffix=sp.tech&&!usingStaged?`&tech=${encodeURIComponent(sp.tech)}`:'';

  return <main style={{fontFamily:'system-ui',maxWidth:1500,margin:'auto',padding:28}}>
    <div style={{display:'flex',justifyContent:'space-between',alignItems:'center',gap:12,flexWrap:'wrap'}}>
      <div><h1>Schedule Calendar</h1><p>Weekly calendar tied to Durfee Performance jobs, with a read-only ServiceTitan fallback during migration staging.</p></div>
      <p><Link href="/dispatch">Open Smart Dispatch →</Link> · <Link href="/dispatch/fleet-optimizer">Fleet Day Plan →</Link></p>
    </div>

    {usingStaged&&<section style={{padding:14,border:'1px solid #b8a76a',borderRadius:12,background:'#fffbea',margin:'16px 0'}}><b>ServiceTitan staging schedule</b><div>The native Durfee Performance job table is still empty, so this calendar is showing ServiceTitan appointments for this week. Dispatch edits remain in ServiceTitan until migration is activated.</div></section>}
    {stagedError&&nativeRows.length===0&&<p role="alert">ServiceTitan staged schedule could not be loaded.</p>}

    <section style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(180px,1fr))',gap:10,margin:'18px 0'}}>
      <div style={{border:'1px solid #ddd',borderRadius:14,padding:14}}><small>Scheduled jobs</small><div style={{fontSize:28,fontWeight:800}}>{allRows.length}</div></div>
      <div style={{border:unassigned.length?'2px solid #a65b00':'1px solid #ddd',borderRadius:14,padding:14}}><small>Unassigned</small><div style={{fontSize:28,fontWeight:800}}>{usingStaged?'—':unassigned.length}</div></div>
      <div style={{border:conflicts.length?'2px solid #b00020':'1px solid #ddd',borderRadius:14,padding:14}}><small>Conflict flags</small><div style={{fontSize:28,fontWeight:800}}>{usingStaged?'—':conflicts.length}</div></div>
      <div style={{border:'1px solid #ddd',borderRadius:14,padding:14}}><small>Booked hours</small><div style={{fontSize:28,fontWeight:800}}>{weekHours.toFixed(1)}</div></div>
    </section>

    {!usingStaged&&<form method="get" style={{display:'flex',gap:8,alignItems:'center',flexWrap:'wrap',margin:'14px 0'}}><input type="hidden" name="week" value={dayKey(start)}/><label htmlFor="tech"><b>Technician:</b></label><select id="tech" name="tech" defaultValue={sp.tech??''}><option value="">All technicians</option>{(techs??[]).map((t:any)=><option key={t.id} value={t.id}>{t.name}</option>)}</select><button type="submit">Filter</button>{sp.tech&&<Link href={`/schedule?week=${dayKey(start)}`}>Clear filter</Link>}</form>}

    <div style={{display:'flex',justifyContent:'space-between',alignItems:'center',margin:'20px 0',gap:10}}><Link href={`/schedule?week=${dayKey(prev)}${filterSuffix}`}>← Previous week</Link><b>{start.toLocaleDateString(undefined,{month:'long',day:'numeric'})} – {new Date(end.getTime()-86400000).toLocaleDateString(undefined,{month:'long',day:'numeric',year:'numeric'})}</b><Link href={`/schedule?week=${dayKey(next)}${filterSuffix}`}>Next week →</Link></div>

    {nativeError&&<p role="alert">Native schedule could not be loaded.</p>}
    {!usingStaged&&(unassigned.length>0||conflicts.length>0)&&<section style={{border:'2px solid #222',borderRadius:14,padding:14,marginBottom:16}}><h2 style={{marginTop:0}}>Dispatcher Attention</h2>{unassigned.length>0&&<p><b>{unassigned.length} scheduled job{unassigned.length===1?'':'s'} without a technician.</b></p>}{conflicts.length>0&&<p><b>{conflicts.length} job{conflicts.length===1?'':'s'} overlap another appointment for the same technician.</b></p>}</section>}

    <div style={{display:'grid',gridTemplateColumns:'repeat(7,minmax(190px,1fr))',gap:8,overflowX:'auto',paddingBottom:10}}>
      {days.map(d=>{const key=dayKey(d),jobs=rows.filter(j=>j.scheduled_start&&dayKey(new Date(j.scheduled_start))===key),hours=jobs.reduce((sum,j)=>sum+durationHours(j),0),dayConflicts=jobs.filter(j=>hasOverlap(j,allRows)).length;return <section key={key} style={{minWidth:190,border:key===today?'2px solid #111':'1px solid #ddd',borderRadius:14,padding:10,minHeight:430,background:key===today?'#fafafa':'white'}}><header style={{borderBottom:'1px solid #ddd',paddingBottom:8,marginBottom:8}}><b>{d.toLocaleDateString(undefined,{weekday:'short'})}</b><div style={{fontSize:22,fontWeight:800}}>{d.getDate()}</div><small>{jobs.length} jobs · {hours.toFixed(1)} booked hrs{dayConflicts?` · ${dayConflicts} conflicts`:''}</small></header>{jobs.map(j=>{const conflict=hasOverlap(j,allRows);const card=<><b>{new Date(j.scheduled_start).toLocaleTimeString([],{hour:'numeric',minute:'2-digit'})}{j.scheduled_end?`–${new Date(j.scheduled_end).toLocaleTimeString([],{hour:'numeric',minute:'2-digit'})}`:''}</b><div style={{fontWeight:700,marginTop:4}}>{relationName(j.customers)||'Customer'}</div><small>{j.service_type||'Service'} · {j.staged?'ServiceTitan':relationName(j.users)||'UNASSIGNED'}</small><small style={{display:'block'}}>{relationAddress(j.customers)||''}</small><small style={{display:'block'}}>{j.status}{conflict?' · SCHEDULE CONFLICT':''}</small>{j.service_summary&&<small style={{display:'block',marginTop:4}}>{j.service_summary}</small>}</>;return j.staged?<div key={j.id} style={{border:'1px solid #ddd',borderRadius:10,padding:9,margin:'8px 0'}}>{card}</div>:<Link key={j.id} href={`/jobs/${j.id}`} style={{display:'block',textDecoration:'none',color:'inherit',border:conflict?'2px solid #b00020':!j.technician_id?'2px solid #a65b00':'1px solid #ddd',borderRadius:10,padding:9,margin:'8px 0'}}>{card}</Link>})}{!jobs.length&&<small>Open capacity</small>}</section>})}
    </div>

    <h2 style={{marginTop:26}}>Week at a Glance</h2>
    <div style={{overflowX:'auto'}}><table style={{width:'100%',borderCollapse:'collapse'}}><thead><tr>{['Day / Window','Source / Technician','Customer','Service','Address','Status','Load Check'].map(x=><th key={x} style={{textAlign:'left',padding:10,borderBottom:'1px solid #ccc'}}>{x}</th>)}</tr></thead><tbody>{rows.map(j=><tr key={j.id}><td style={{padding:10,borderBottom:'1px solid #eee'}}>{j.staged?new Date(j.scheduled_start).toLocaleString([], {weekday:'short',hour:'numeric',minute:'2-digit'}):<Link href={`/jobs/${j.id}`}>{new Date(j.scheduled_start).toLocaleString([], {weekday:'short',hour:'numeric',minute:'2-digit'})}</Link>}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{j.staged?'ServiceTitan':relationName(j.users)||'Unassigned'}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{relationName(j.customers)||'—'}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{j.service_type||'—'}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{relationAddress(j.customers)||'—'}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{j.status}</td><td style={{padding:10,borderBottom:'1px solid #eee'}}>{j.staged?'READ ONLY':hasOverlap(j,allRows)?'CONFLICT':!j.technician_id?'UNASSIGNED':'OK'}</td></tr>)}</tbody></table></div>
  </main>
}
