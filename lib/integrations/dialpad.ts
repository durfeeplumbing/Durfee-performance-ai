import 'server-only';
import { createHmac, timingSafeEqual } from 'node:crypto';

const baseUrl='https://dialpad.com/api/v2';

function apiKey(){
  const value=process.env.DIALPAD_API_KEY?.trim();
  if(!value)throw new Error('Dialpad is not connected. Add DIALPAD_API_KEY to the deployment environment.');
  return value;
}

export function dialpadConnected(){return Boolean(process.env.DIALPAD_API_KEY?.trim());}

export async function dialpadRequest(path:string,init:RequestInit={}){
  const response=await fetch(`${baseUrl}${path}`,{
    ...init,
    headers:{Authorization:`Bearer ${apiKey()}`,'Content-Type':'application/json',Accept:'application/json',...(init.headers||{})},
    cache:'no-store',
  });
  const text=await response.text();
  let data:any=null;
  if(text){try{data=JSON.parse(text);}catch{data={raw:text};}}
  if(!response.ok)throw new Error(`Dialpad ${response.status}: ${data?.message||data?.error||text||'request failed'}`);
  return data;
}

export async function findDialpadUserByEmail(email:string){
  const data=await dialpadRequest(`/users?email=${encodeURIComponent(email)}`);
  const items=Array.isArray(data?.items)?data.items:Array.isArray(data)?data:[];
  return items.find((item:any)=>String(item?.email||'').toLowerCase()===email.toLowerCase())||items[0]||null;
}

export async function initiateDialpadCall(args:{email:string;phoneNumber:string;customerId:string;jobId?:string|null}){
  const user=await findDialpadUserByEmail(args.email);
  if(!user?.id)throw new Error(`No active Dialpad user matched ${args.email}. The Durfee user email should match the Dialpad user email.`);
  return dialpadRequest('/call',{method:'POST',body:JSON.stringify({
    user_id:Number(user.id),
    phone_number:args.phoneNumber,
    custom_data:JSON.stringify({source:'durfee-performance-ai',customerId:args.customerId,jobId:args.jobId||null}),
  })});
}

export async function sendDialpadSms(args:{email:string;to:string;text:string}){
  const user=await findDialpadUserByEmail(args.email);
  if(!user?.id)throw new Error(`No active Dialpad user matched ${args.email}. The Durfee user email should match the Dialpad user email.`);
  return dialpadRequest('/sms',{method:'POST',body:JSON.stringify({user_id:Number(user.id),to_numbers:[args.to],text:args.text})});
}

function decodeBase64Url(value:string){return Buffer.from(value.replace(/-/g,'+').replace(/_/g,'/'),'base64');}

export function verifyDialpadWebhookJwt(token:string){
  const secret=process.env.DIALPAD_WEBHOOK_SECRET?.trim();
  if(!secret)throw new Error('DIALPAD_WEBHOOK_SECRET is not configured');
  const parts=token.trim().split('.');
  if(parts.length!==3)throw new Error('Invalid Dialpad webhook token');
  const [header,payload,signature]=parts;
  const parsedHeader=JSON.parse(decodeBase64Url(header).toString('utf8'));
  if(parsedHeader?.alg!=='HS256')throw new Error('Unsupported Dialpad webhook signature algorithm');
  const expected=createHmac('sha256',secret).update(`${header}.${payload}`).digest();
  const actual=decodeBase64Url(signature);
  if(actual.length!==expected.length||!timingSafeEqual(actual,expected))throw new Error('Invalid Dialpad webhook signature');
  return JSON.parse(decodeBase64Url(payload).toString('utf8')) as Record<string,any>;
}

export function extractDialpadWebhookToken(raw:string){
  const value=raw.trim();
  if(!value)throw new Error('Empty Dialpad webhook body');
  if(!value.startsWith('{')&&!value.startsWith('[')&&value.split('.').length===3)return value;
  const parsed=JSON.parse(value);
  const token=typeof parsed==='string'?parsed:parsed?.jwt||parsed?.token||parsed?.data;
  if(typeof token!=='string'||token.split('.').length!==3)throw new Error('Dialpad webhook JWT missing');
  return token;
}

export function dialpadProviderEventId(payload:Record<string,any>){
  const id=payload.call_id??payload.sms_id??payload.message_id??payload.id??payload.event_id;
  if(id==null)return null;
  const type=payload.call_id!=null?'call':(payload.sms_id!=null||payload.message_id!=null?'sms':'event');
  return `${type}:${String(id)}`;
}
