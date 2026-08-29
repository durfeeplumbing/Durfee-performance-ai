import type { SessionUser } from './auth';

/**
 * Authentication provider boundary.
 * Production deployment must replace this with a verified server-side session
 * from the selected identity provider. Never trust role/user values supplied
 * by browser form fields, query parameters or unsigned cookies.
 */
export async function getCurrentUser():Promise<SessionUser|null>{
  return null;
}

export async function requireCurrentUser(){
  const user=await getCurrentUser();
  if(!user)throw new Error('Authentication provider is not configured');
  return user;
}
