-- Afaq: new Supabase project setup. Run in SQL Editor.
-- Frontend must use these table names and Supabase Auth.
begin;

create table public.afaq_workspaces (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id),
  name text not null,
  created_at timestamptz not null default now()
);
create table public.afaq_members (
  workspace_id uuid not null references public.afaq_workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'viewer' check (role in ('manager','viewer')),
  primary key (workspace_id,user_id)
);

create function public.afaq_access(w uuid, editing boolean default false)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.afaq_workspaces x
    where x.id = w and x.owner_id = (select auth.uid())
  ) or exists (
    select 1 from public.afaq_members m
    where m.workspace_id = w and m.user_id = (select auth.uid())
      and (not editing or m.role = 'manager')
  );
$$;
revoke all on function public.afaq_access(uuid,boolean) from public;
grant execute on function public.afaq_access(uuid,boolean) to authenticated;

create table public.afaq_employees (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.afaq_workspaces(id),
  name text not null,
  nationality text,
  job_title text,
  work_location text,
  phone text,
  start_date date,
  status text not null default 'active' check (status in ('active','inactive','terminated')),
  base_salary numeric(12,2) not null default 0 check (base_salary >= 0),
  notes text,
  created_at timestamptz not null default now(),
  unique (workspace_id,id)
);
create table public.afaq_documents (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.afaq_workspaces(id),
  employee_id uuid not null,
  document_type text not null check (document_type in ('identity','residency','passport','photo','other')),
  document_number text,
  expires_on date,
  storage_path text,
  notes text,
  created_at timestamptz not null default now(),
  foreign key (workspace_id,employee_id) references public.afaq_employees(workspace_id,id)
);
create table public.afaq_attendance (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.afaq_workspaces(id),
  employee_id uuid not null,
  work_date date not null,
  status text not null check (status in ('present','absent','leave','late','holiday')),
  check_in timestamptz,
  check_out timestamptz,
  overtime_hours numeric(6,2) not null default 0 check (overtime_hours >= 0),
  overtime_rate numeric(12,2) not null default 0 check (overtime_rate >= 0),
  work_location text,
  daily_work text,
  notes text,
  unique (workspace_id,employee_id,work_date),
  check (check_out is null or check_in is null or check_out >= check_in),
  foreign key (workspace_id,employee_id) references public.afaq_employees(workspace_id,id)
);
create table public.afaq_advances (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.afaq_workspaces(id),
  employee_id uuid not null,
  advance_date date not null,
  amount numeric(12,2) not null check (amount > 0),
  repaid_amount numeric(12,2) not null default 0,
  notes text,
  check (repaid_amount >= 0 and repaid_amount <= amount),
  foreign key (workspace_id,employee_id) references public.afaq_employees(workspace_id,id)
);
create table public.afaq_payroll (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.afaq_workspaces(id),
  employee_id uuid not null,
  period_month date not null check (extract(day from period_month) = 1),
  base_salary numeric(12,2) not null default 0 check (base_salary >= 0),
  overtime_amount numeric(12,2) not null default 0 check (overtime_amount >= 0),
  allowances numeric(12,2) not null default 0 check (allowances >= 0),
  deductions numeric(12,2) not null default 0 check (deductions >= 0),
  advance_deduction numeric(12,2) not null default 0 check (advance_deduction >= 0),
  net_salary numeric(12,2) generated always as
    (base_salary + overtime_amount + allowances - deductions - advance_deduction) stored,
  paid_on date,
  notes text,
  unique (workspace_id,employee_id,period_month),
  foreign key (workspace_id,employee_id) references public.afaq_employees(workspace_id,id)
);
create table public.afaq_tasks (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.afaq_workspaces(id),
  employee_id uuid,
  title text not null,
  details text,
  work_location text,
  due_date date,
  status text not null default 'pending' check (status in ('pending','in_progress','done','cancelled')),
  created_at timestamptz not null default now(),
  foreign key (workspace_id,employee_id) references public.afaq_employees(workspace_id,id)
);

alter table public.afaq_workspaces enable row level security;
alter table public.afaq_members enable row level security;
create policy afaq_workspace_read on public.afaq_workspaces
  for select to authenticated using (public.afaq_access(id));
create policy afaq_workspace_create on public.afaq_workspaces
  for insert to authenticated with check (owner_id = (select auth.uid()));
create policy afaq_workspace_update on public.afaq_workspaces
  for update to authenticated using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));
create policy afaq_members_read on public.afaq_members
  for select to authenticated using (public.afaq_access(workspace_id));
create policy afaq_members_manage on public.afaq_members
  for all to authenticated
  using (exists (select 1 from public.afaq_workspaces w where w.id = workspace_id and w.owner_id = (select auth.uid())))
  with check (exists (select 1 from public.afaq_workspaces w where w.id = workspace_id and w.owner_id = (select auth.uid())));

do $$
declare t text;
begin
  foreach t in array array['afaq_employees','afaq_documents','afaq_attendance','afaq_advances','afaq_payroll','afaq_tasks'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create index on public.%I (workspace_id)', t);
    execute format('create policy afaq_read on public.%I for select to authenticated using (public.afaq_access(workspace_id))', t);
    execute format('create policy afaq_write on public.%I for all to authenticated using (public.afaq_access(workspace_id,true)) with check (public.afaq_access(workspace_id,true))', t);
    execute format('revoke all on public.%I from anon',t);
    execute format('grant select, insert, update, delete on public.%I to authenticated',t);
  end loop;
end;
$$;
revoke all on public.afaq_workspaces,public.afaq_members from anon;
grant select,insert,update on public.afaq_workspaces to authenticated;
grant select,insert,update,delete on public.afaq_members to authenticated;

-- Private files: path must be WORKSPACE_UUID/EMPLOYEE_UUID/filename.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('afaq-private','afaq-private',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf']);

create function public.afaq_file_access(path text, editing boolean default false)
returns boolean language sql stable set search_path = ''
as $$
  select exists (
    select 1 from public.afaq_workspaces w
    where w.id::text = (storage.foldername(path))[1]
    and public.afaq_access(w.id, editing)
  );
$$;
revoke all on function public.afaq_file_access(text,boolean) from public;
grant execute on function public.afaq_file_access(text,boolean) to authenticated;
create policy afaq_files_read on storage.objects for select to authenticated
  using (bucket_id = 'afaq-private' and public.afaq_file_access(name));
create policy afaq_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'afaq-private' and public.afaq_file_access(name,true));
create policy afaq_files_update on storage.objects for update to authenticated
  using (bucket_id = 'afaq-private' and public.afaq_file_access(name,true))
  with check (bucket_id = 'afaq-private' and public.afaq_file_access(name,true));
create policy afaq_files_delete on storage.objects for delete to authenticated
  using (bucket_id = 'afaq-private' and public.afaq_file_access(name,true));

commit;
