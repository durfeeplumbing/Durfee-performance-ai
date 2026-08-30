create table if not exists public.job_notes (
 id uuid primary key default gen_random_uuid(),
 job_id uuid not null references public.jobs(id) on delete cascade,
 author_user_id uuid not null references public.users(id),
 note_type text not null default 'work' check (note_type in ('work','diagnostic','customer','internal','completion')),
 note text not null check (length(trim(note)) > 0),
 created_at timestamptz not null default now()
);
create index if not exists job_notes_job_created_idx on public.job_notes(job_id,created_at desc);
alter table public.job_notes enable row level security;
create policy "authenticated read job notes" on public.job_notes for select to authenticated using (private.current_employee_role() in ('owner','manager','csr_dispatch','technician','accounting'));
create policy "field staff add job notes" on public.job_notes for insert to authenticated with check (author_user_id=(select id from public.users where auth_user_id=auth.uid() and active=true limit 1) and (private.current_employee_role() in ('owner','manager','csr_dispatch') or (private.current_employee_role()='technician' and exists(select 1 from public.jobs j where j.id=job_id and j.technician_id=author_user_id))));

create table if not exists public.job_attachments (
 id uuid primary key default gen_random_uuid(),
 job_id uuid not null references public.jobs(id) on delete cascade,
 uploaded_by uuid not null references public.users(id),
 attachment_type text not null default 'photo' check (attachment_type in ('photo','document')),
 storage_path text not null,
 caption text,
 created_at timestamptz not null default now()
);
create index if not exists job_attachments_job_created_idx on public.job_attachments(job_id,created_at desc);
alter table public.job_attachments enable row level security;
create policy "authenticated read job attachments" on public.job_attachments for select to authenticated using (private.current_employee_role() in ('owner','manager','csr_dispatch','technician','accounting'));
create policy "field staff add job attachments" on public.job_attachments for insert to authenticated with check (uploaded_by=(select id from public.users where auth_user_id=auth.uid() and active=true limit 1) and (private.current_employee_role() in ('owner','manager','csr_dispatch') or (private.current_employee_role()='technician' and exists(select 1 from public.jobs j where j.id=job_id and j.technician_id=uploaded_by))));
