begin;

create extension if not exists pgcrypto;

create table if not exists public.interview_checkpoints (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  cycle_no integer not null check (cycle_no >= 1),
  checkpoint_type text not null,
  checkpoint_key text not null,
  status text not null check (status in ('pending', 'confirmed', 'rejected', 'skipped')),
  created_turn_id uuid not null references public.intake_turns(id) on delete cascade,
  resolved_turn_id uuid references public.intake_turns(id) on delete set null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc'::text, now()),
  resolved_at timestamptz,
  updated_at timestamptz not null default timezone('utc'::text, now()),
  unique (project_id, cycle_no, checkpoint_type, checkpoint_key)
);

create index if not exists interview_checkpoints_project_cycle_created_idx
  on public.interview_checkpoints(project_id, cycle_no, created_at desc);

create index if not exists interview_checkpoints_project_cycle_status_idx
  on public.interview_checkpoints(project_id, cycle_no, checkpoint_type, status);

alter table public.interview_checkpoints enable row level security;

drop policy if exists interview_checkpoints_select_own on public.interview_checkpoints;
create policy interview_checkpoints_select_own on public.interview_checkpoints
for select to authenticated
using (public.user_owns_project(project_id));

drop policy if exists interview_checkpoints_insert_own on public.interview_checkpoints;
create policy interview_checkpoints_insert_own on public.interview_checkpoints
for insert to authenticated
with check (public.user_owns_project(project_id));

drop policy if exists interview_checkpoints_update_own on public.interview_checkpoints;
create policy interview_checkpoints_update_own on public.interview_checkpoints
for update to authenticated
using (public.user_owns_project(project_id))
with check (public.user_owns_project(project_id));

commit;
