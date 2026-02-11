begin;

create extension if not exists pgcrypto;
create extension if not exists vector;

create table if not exists public.interview_readiness_snapshots (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  cycle_no integer not null check (cycle_no >= 1),
  turn_id uuid not null references public.intake_turns(id) on delete cascade,
  readiness_score numeric(5,2) not null check (readiness_score >= 0 and readiness_score <= 100),
  resolved_count integer not null default 0 check (resolved_count >= 0),
  total_count integer not null default 0 check (total_count >= 0),
  next_focus text not null,
  bucket_states jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default timezone('utc'::text, now())
);

create index if not exists interview_readiness_snapshots_project_cycle_created_idx
  on public.interview_readiness_snapshots(project_id, cycle_no, created_at desc);

create table if not exists public.interview_semantic_entries (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  cycle_no integer not null check (cycle_no >= 1),
  source_type text not null check (source_type in ('intake_turn', 'decision_item', 'artifact_summary')),
  source_id uuid,
  source_text text not null,
  embedding vector(1536),
  embedding_model text not null,
  brain_version text,
  provenance_refs text[] not null default '{}',
  created_at timestamptz not null default timezone('utc'::text, now()),
  unique (project_id, cycle_no, source_type, source_id, embedding_model)
);

create index if not exists interview_semantic_entries_project_cycle_created_idx
  on public.interview_semantic_entries(project_id, cycle_no, created_at desc);

alter table public.interview_readiness_snapshots enable row level security;
alter table public.interview_semantic_entries enable row level security;

drop policy if exists interview_readiness_snapshots_select_own on public.interview_readiness_snapshots;
create policy interview_readiness_snapshots_select_own on public.interview_readiness_snapshots
for select to authenticated
using (public.user_owns_project(project_id));

drop policy if exists interview_semantic_entries_select_own on public.interview_semantic_entries;
create policy interview_semantic_entries_select_own on public.interview_semantic_entries
for select to authenticated
using (public.user_owns_project(project_id));

commit;
