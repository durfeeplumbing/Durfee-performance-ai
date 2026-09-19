/** Routes whose own token or login flow supplies authentication. */
export function isPublicPage(pathname: string): boolean {
  if (pathname === '/login' || pathname === '/unauthorized') return true;
  return pathname.startsWith('/approve/') || pathname.startsWith('/join/');
}
