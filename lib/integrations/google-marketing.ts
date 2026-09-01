import 'server-only';
import { createHash } from 'node:crypto';

export function googleMarketingConfigured(){return Boolean(process.env.GOOGLE_ADS_CUSTOMER_ID&&process.env.GOOGLE_ADS_DEVELOPER_TOKEN&&process.env.GOOGLE_ADS_REFRESH_TOKEN);}
export function normalizeEmail(value:string|null|undefined){return String(value??'').trim().toLowerCase();}
export function normalizePhone(value:string|null|undefined){const digits=String(value??'').replace(/\D/g,'');if(!digits)return '';return digits.length===10?`+1${digits}`:digits.startsWith('1')&&digits.length===11?`+${digits}`:`+${digits}`;}
export function sha256(value:string){return createHash('sha256').update(value).digest('hex');}
export function googleLeadIdentifiers(input:{email?:string|null;phone?:string|null}){const result:{hashedEmail?:string;hashedPhone?:string}={};const email=normalizeEmail(input.email);const phone=normalizePhone(input.phone);if(email)result.hashedEmail=sha256(email);if(phone)result.hashedPhone=sha256(phone);return result;}
export function googleConversionEnvelope(input:{transactionId:string;eventTime:string;value:number;currencyCode?:string;gclid?:string|null;gbraid?:string|null;wbraid?:string|null;email?:string|null;phone?:string|null}){return {transactionId:input.transactionId,eventTime:input.eventTime,value:Math.max(0,Number(input.value)||0),currencyCode:input.currencyCode||'USD',clickIdentifiers:{gclid:input.gclid||undefined,gbraid:input.gbraid||undefined,wbraid:input.wbraid||undefined},userIdentifiers:googleLeadIdentifiers(input)};}
