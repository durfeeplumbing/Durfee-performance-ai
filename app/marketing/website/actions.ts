'use server';
import { requireCurrentUser } from '@/lib/session';
import { syncWebsiteCalls } from '@/lib/marketing/servicetitan-report';
import { revalidatePath } from 'next/cache';
export async function refreshWebsiteCalls(){const user=await requireCurrentUser();if(!['owner','marketing'].includes(user.role))throw new Error('Permission denied');await syncWebsiteCalls();revalidatePath('/marketing/website');}
