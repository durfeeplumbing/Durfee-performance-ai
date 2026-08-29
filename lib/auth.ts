import { can, type Role } from './roles';

export type SessionUser={id:string;email:string;name:string;role:Role;active:boolean};

export function requireActiveUser(user:SessionUser|null|undefined):SessionUser{
  if(!user)throw new Error('Authentication required');
  if(!user.active)throw new Error('User account is inactive');
  return user;
}

export function requirePermission(user:SessionUser|null|undefined,permission:string):SessionUser{
  const active=requireActiveUser(user);
  if(!can(active.role,permission))throw new Error('Permission denied');
  return active;
}

export function requireRole(user:SessionUser|null|undefined,allowed:Role[]):SessionUser{
  const active=requireActiveUser(user);
  if(!allowed.includes(active.role))throw new Error('Role not authorized');
  return active;
}
