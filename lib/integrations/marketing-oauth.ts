import 'server-only';
import crypto from 'node:crypto';

export type MarketingProvider='google_ads'|'meta_ads';

function secret(){
  const value=process.env.MARKETING_OAUTH_SECRET?.trim();
  if(!value||value.length<32)throw new Error('MARKETING_OAUTH_SECRET is not configured');
  return value;
}
function key(label:string){return crypto.createHash('sha256').update(`${label}:${secret()}`).digest()}
export function encryptMarketingToken(value:string){
  const iv=crypto.randomBytes(12);const cipher=crypto.createCipheriv('aes-256-gcm',key('token'),iv);
  const encrypted=Buffer.concat([cipher.update(value,'utf8'),cipher.final()]);const tag=cipher.getAuthTag();
  return ['v1',iv.toString('base64url'),tag.toString('base64url'),encrypted.toString('base64url')].join('.');
}
export function decryptMarketingToken(value:string){
  const [version,ivRaw,tagRaw,dataRaw]=value.split('.');if(version!=='v1'||!ivRaw||!tagRaw||!dataRaw)throw new Error('Invalid encrypted token');
  const decipher=crypto.createDecipheriv('aes-256-gcm',key('token'),Buffer.from(ivRaw,'base64url'));decipher.setAuthTag(Buffer.from(tagRaw,'base64url'));
  return Buffer.concat([decipher.update(Buffer.from(dataRaw,'base64url')),decipher.final()]).toString('utf8');
}
export function makeMarketingOAuthState(provider:MarketingProvider,userId:string){
  const payload=Buffer.from(JSON.stringify({provider,userId,issuedAt:Date.now(),nonce:crypto.randomBytes(16).toString('base64url')})).toString('base64url');
  const sig=crypto.createHmac('sha256',key('state')).update(payload).digest('base64url');return `${payload}.${sig}`;
}
export function verifyMarketingOAuthState(state:string,provider:MarketingProvider,userId:string){
  const [payload,sig]=state.split('.');if(!payload||!sig)throw new Error('Invalid OAuth state');
  const expected=crypto.createHmac('sha256',key('state')).update(payload).digest();const actual=Buffer.from(sig,'base64url');
  if(actual.length!==expected.length||!crypto.timingSafeEqual(actual,expected))throw new Error('Invalid OAuth state');
  const parsed=JSON.parse(Buffer.from(payload,'base64url').toString('utf8')) as {provider:string,userId:string,issuedAt:number};
  if(parsed.provider!==provider||parsed.userId!==userId||Date.now()-parsed.issuedAt>10*60*1000)throw new Error('Expired OAuth state');
}
export function marketingBaseUrl(){return (process.env.APP_BASE_URL||'https://durfee-performance-ai.vercel.app').replace(/\/$/,'')}
export function marketingOAuthReadiness(){return {
  secret:Boolean(process.env.MARKETING_OAUTH_SECRET?.trim()),
  googleClient:Boolean(process.env.GOOGLE_ADS_OAUTH_CLIENT_ID?.trim()&&process.env.GOOGLE_ADS_OAUTH_CLIENT_SECRET?.trim()),
  googleDeveloperToken:Boolean(process.env.GOOGLE_ADS_DEVELOPER_TOKEN?.trim()),
  metaClient:Boolean(process.env.META_ADS_APP_ID?.trim()&&process.env.META_ADS_APP_SECRET?.trim()),
};}
