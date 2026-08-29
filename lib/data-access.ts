import type { SessionUser } from './auth';
import { requirePermission } from './auth';

export type DataScope={userId:string;role:SessionUser['role'];scope:'all'|'department'|'self'|'assigned'};

export function jobReadScope(user:SessionUser):DataScope{
  if(user.role==='owner')return{userId:user.id,role:user.role,scope:'all'};
  if(user.role==='manager'||user.role==='accounting')return{userId:user.id,role:user.role,scope:'department'};
  if(user.role==='technician')return{userId:user.id,role:user.role,scope:'assigned'};
  return{userId:user.id,role:user.role,scope:'department'};
}

export function authorizeFinancialReports(user:SessionUser){
  if(user.role==='owner')return user;
  return requirePermission(user,'financial.reports.read');
}

export function authorizeDispatch(user:SessionUser){return requirePermission(user,'dispatch.manage')}
export function authorizePricebookRead(user:SessionUser){return requirePermission(user,'pricebook.read')}
