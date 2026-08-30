insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('job-photos','job-photos',false,10485760,array['image/jpeg','image/png','image/webp','image/heic','image/heif'])
on conflict (id) do update set public=false,file_size_limit=10485760,allowed_mime_types=excluded.allowed_mime_types;

create policy "job staff upload job photos" on storage.objects for insert to authenticated with check (
 bucket_id='job-photos' and exists (
   select 1 from public.jobs j
   join public.users u on u.auth_user_id=auth.uid() and u.active=true
   where j.id::text=(storage.foldername(name))[1]
   and (u.role in ('owner','manager','csr_dispatch') or (u.role='technician' and j.technician_id=u.id))
 )
);
create policy "job staff read job photos" on storage.objects for select to authenticated using (
 bucket_id='job-photos' and exists (
   select 1 from public.jobs j
   join public.users u on u.auth_user_id=auth.uid() and u.active=true
   where j.id::text=(storage.foldername(name))[1]
   and (u.role in ('owner','manager','csr_dispatch','accounting') or (u.role='technician' and j.technician_id=u.id))
 )
);
