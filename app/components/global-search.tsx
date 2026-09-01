'use client';

import Link from 'next/link';
import { useEffect, useMemo, useRef, useState } from 'react';

type SearchResult={category:string;title:string;subtitle:string;href:string;sort_rank:number};

export default function GlobalSearch(){
  const [query,setQuery]=useState('');
  const [results,setResults]=useState<SearchResult[]>([]);
  const [loading,setLoading]=useState(false);
  const [open,setOpen]=useState(false);
  const inputRef=useRef<HTMLInputElement>(null);
  const boxRef=useRef<HTMLDivElement>(null);

  useEffect(()=>{const handler=(event:KeyboardEvent)=>{if((event.metaKey||event.ctrlKey)&&event.key.toLowerCase()==='k'){event.preventDefault();inputRef.current?.focus();setOpen(true);}if(event.key==='Escape'){setOpen(false);inputRef.current?.blur();}};window.addEventListener('keydown',handler);return()=>window.removeEventListener('keydown',handler);},[]);
  useEffect(()=>{const handler=(event:MouseEvent)=>{if(boxRef.current&&!boxRef.current.contains(event.target as Node))setOpen(false);};document.addEventListener('mousedown',handler);return()=>document.removeEventListener('mousedown',handler);},[]);
  useEffect(()=>{const q=query.trim();if(q.length<2){setResults([]);setLoading(false);return;}setLoading(true);const controller=new AbortController();const timer=setTimeout(async()=>{try{const response=await fetch(`/api/search?q=${encodeURIComponent(q)}`,{signal:controller.signal,cache:'no-store'});const payload=await response.json();setResults(response.ok?(payload.results??[]):[]);setOpen(true);}catch(error){if((error as Error).name!=='AbortError')setResults([]);}finally{setLoading(false);}},180);return()=>{clearTimeout(timer);controller.abort();};},[query]);
  const groups=useMemo(()=>{const map=new Map<string,SearchResult[]>();for(const result of results){const group=map.get(result.category)??[];group.push(result);map.set(result.category,group);}return [...map.entries()];},[results]);

  return <div ref={boxRef} style={{position:'relative',width:'min(760px,100%)'}}>
    <div style={{display:'flex',alignItems:'center',gap:10,background:'#fff',border:'1px solid #d7dce2',borderRadius:12,padding:'0 12px',boxShadow:'0 2px 8px rgba(15,23,42,.05)'}}>
      <span aria-hidden="true" style={{fontSize:18,opacity:.6}}>⌕</span>
      <input ref={inputRef} value={query} onChange={e=>setQuery(e.target.value)} onFocus={()=>setOpen(true)} placeholder="Search customers, jobs, invoices, parts, POs, calls…" aria-label="Search Durfee Performance AI" style={{width:'100%',border:0,outline:'none',padding:'12px 0',fontSize:15,background:'transparent'}}/>
      <kbd style={{fontSize:11,border:'1px solid #d7dce2',borderRadius:6,padding:'3px 6px',background:'#f8fafc',whiteSpace:'nowrap'}}>⌘ K</kbd>
    </div>
    {open&&query.trim().length>=2&&<div style={{position:'absolute',zIndex:1000,top:'calc(100% + 8px)',left:0,right:0,maxHeight:'70vh',overflowY:'auto',background:'#fff',border:'1px solid #d7dce2',borderRadius:14,boxShadow:'0 18px 50px rgba(15,23,42,.18)',padding:8}}>
      {loading&&<div style={{padding:18,color:'#64748b'}}>Searching across Durfee Performance AI…</div>}
      {!loading&&!results.length&&<div style={{padding:18}}><b>No matches found</b><div style={{marginTop:4,color:'#64748b',fontSize:13}}>Try a customer name, phone number, address, job type, invoice ID, SKU, barcode, PO number, employee, call note, or review.</div></div>}
      {!loading&&groups.map(([category,items])=><section key={category} style={{padding:'6px 0'}}><div style={{padding:'7px 10px 5px',fontSize:11,fontWeight:800,letterSpacing:'.08em',textTransform:'uppercase',color:'#64748b'}}>{category}</div>{items.map((item,index)=><Link key={`${category}-${item.href}-${index}`} href={item.href} onClick={()=>setOpen(false)} style={{display:'block',textDecoration:'none',color:'inherit',padding:'10px 12px',borderRadius:10}}><div style={{display:'flex',justifyContent:'space-between',gap:12,alignItems:'baseline'}}><b style={{fontSize:14}}>{item.title}</b><span style={{fontSize:11,color:'#64748b',whiteSpace:'nowrap'}}>{category}</span></div>{item.subtitle&&<div style={{fontSize:12,color:'#64748b',marginTop:3,overflow:'hidden',textOverflow:'ellipsis',whiteSpace:'nowrap'}}>{item.subtitle}</div>}</Link>)}</section>)}
      {!loading&&results.length>0&&<div style={{padding:'8px 10px',borderTop:'1px solid #eef2f7',fontSize:12,color:'#64748b'}}>Results are grouped by category and only include areas your account can access.</div>}
    </div>}
  </div>;
}
