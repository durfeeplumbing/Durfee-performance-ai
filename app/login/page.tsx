import { login } from './actions';

export default async function LoginPage({searchParams}:{searchParams:Promise<{error?:string}>}){
  const params=await searchParams;
  return <main style={{maxWidth:460,margin:'8vh auto',padding:28}}><article style={{padding:32,borderRadius:16,boxShadow:'0 12px 40px rgba(20,40,70,.1)'}}><h1>Durfee Performance AI</h1><p>Employee Portal</p>{params.error&&<p role="alert">Unable to sign in. Check your email and password.</p>}<form action={login} style={{display:'grid',gap:14}}><label>Email<input name="email" type="email" autoComplete="email" required style={{display:'block',width:'100%',padding:12,marginTop:6}}/></label><label>Password<input name="password" type="password" autoComplete="current-password" required style={{display:'block',width:'100%',padding:12,marginTop:6}}/></label><button type="submit" style={{padding:13,cursor:'pointer'}}>Sign in</button></form><p style={{fontSize:13,opacity:.7}}>Access is limited to authorized employees.</p></article></main>
}
