import Link from 'next/link';

export default async function UnauthorizedPage({searchParams}:{searchParams:Promise<{permission?:string}>}){
  const {permission}=await searchParams;
  return <main style={{maxWidth:620,margin:'10vh auto',padding:32,fontFamily:'system-ui'}}><article style={{border:'1px solid #ddd',borderRadius:16,padding:28}}><h1>Access restricted</h1><p>Your account does not currently have permission to open that area.</p>{permission&&<p><small>Required permission: <code>{permission}</code></small></p>}<p><Link href="/dashboard">Return to dashboard</Link> or contact an owner/authorized manager if you need access.</p></article></main>;
}
