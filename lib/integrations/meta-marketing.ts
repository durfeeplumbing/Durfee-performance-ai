import 'server-only';
import { createHash } from 'node:crypto';

export function metaMarketingConfigured(){return Boolean(process.env.META_AD_ACCOUNT_ID&&process.env.META_ACCESS_TOKEN&&process.env.META_PIXEL_ID);}
function hash(value:string){return createHash('sha256').update(value).digest('hex');}
export function metaUserData(input:{email?:string|null;phone?:string|null;fbclid?:string|null}){const email=String(input.email??'').trim().toLowerCase();const digits=String(input.phone??'').replace(/\D/g,'');const phone=digits.length===10?`1${digits}`:digits;return {em:email?[hash(email)]:undefined,ph:phone?[hash(phone)]:undefined,fbc:input.fbclid?`fb.1.${Math.floor(Date.now()/1000)}.${input.fbclid}`:undefined};}
export function metaConversionEnvelope(input:{eventName:string;eventTime:string;transactionId:string;value:number;currencyCode?:string;email?:string|null;phone?:string|null;fbclid?:string|null}){return {eventName:input.eventName,eventTime:input.eventTime,eventId:input.transactionId,value:Math.max(0,Number(input.value)||0),currency:input.currencyCode||'USD',userData:metaUserData(input)};}
