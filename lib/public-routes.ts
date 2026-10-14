/** Routes whose own token or login flow supplies authentication. */
export function isPublicPage(pathname: string): boolean {
  if (pathname === '/login' || pathname === '/unauthorized' || pathname === '/auth/callback') return true;
  return pathname.startsWith('/approve/') || pathname.startsWith('/join/');
}
