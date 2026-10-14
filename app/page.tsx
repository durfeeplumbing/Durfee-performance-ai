import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/lib/session';
import { employeePermissions } from '@/lib/employee-access';
import { employeeHome } from '@/lib/access-navigation';

export default async function Home() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  redirect(employeeHome(user.role, await employeePermissions(user)));
}
