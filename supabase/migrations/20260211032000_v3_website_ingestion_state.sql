begin;

create extension if not exists pgcrypto;

create table if not exists public.artifact_ingest_runs (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  cycle_no integer not null check (cycle_no >= 1),
  artifact_input_id uuid not null references public.artifact_inputs(id) on delete cascade,
  idempotency_key text not null,
  canonical_url text not null,
  ingestion_limits_version text not null,
  brain_version text not null,
  status text not null check (status in ('pending', 'fetching', 'partial', 'complete', 'failed')),
  http_status integer,
  error_code text,
  error_message text,
  bytes_total bigint not null default 0 check (bytes_total >= 0),
  pages_fetched integer not null default 0 check (pages_fetched >= 0),
  source_hash text,
  started_at timestamptz not null default timezone('utc'::text, now()),
  ended_at timestamptz,
  created_at timestamptz not null default timezone('utc'::text, now()),
  unique (project_id, cycle_no, idempotency_key)
);

create index if not exists artifact_ingest_runs_project_cycle_created_idx
  on public.artifact_ingest_runs(project_id, cycle_no, created_at desc);
create index if not exists artifact_ingest_runs_artifact_input_created_idx
  on public.artifact_ingest_runs(artifact_input_id, created_at desc);

create table if not exists public.artifact_pages (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  cycle_no integer not null check (cycle_no >= 1),
  artifact_input_id uuid not null references public.artifact_inputs(id) on delete cascade,
  ingest_run_id uuid not null references public.artifact_ingest_runs(id) on delete cascade,
  url text not null,
  canonical_url text not null,
  depth integer not null default 0 check (depth >= 0),
  fetch_status text not null default 'fetched' check (fetch_status in ('fetched', 'skipped', 'failed')),
  content_type text,
  http_status integer,
  content_hash text,
  raw_text text not null,
  text_char_count integer not null default 0 check (text_char_count >= 0),
  created_at timestamptz not null default timezone('utc'::text, now()),
  unique (ingest_run_id, canonical_url)
);

create index if not exists artifact_pages_project_cycle_created_idx
  on public.artifact_pages(project_id, cycle_no, created_at desc);
create index if not exists artifact_pages_artifact_input_created_idx
  on public.artifact_pages(artifact_input_id, created_at desc);

create table if not exists public.artifact_summaries (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  cycle_no integer not null check (cycle_no >= 1),
  artifact_input_id uuid not null references public.artifact_inputs(id) on delete cascade,
  ingest_run_id uuid not null references public.artifact_ingest_runs(id) on delete cascade,
  version_no integer not null default 1 check (version_no >= 1),
  summary_text text not null,
  summary_confidence numeric(4,3),
  source_page_ids uuid[] not null default '{}',
  created_at timestamptz not null default timezone('utc'::text, now()),
  unique (project_id, cycle_no, artifact_input_id, version_no)
);

create index if not exists artifact_summaries_project_cycle_created_idx
  on public.artifact_summaries(project_id, cycle_no, created_at desc);
create index if not exists artifact_summaries_ingest_run_created_idx
  on public.artifact_summaries(ingest_run_id, created_at desc);

alter table public.artifact_ingest_runs enable row level security;
alter table public.artifact_pages enable row level security;
alter table public.artifact_summaries enable row level security;

drop policy if exists artifact_ingest_runs_select_own on public.artifact_ingest_runs;
create policy artifact_ingest_runs_select_own on public.artifact_ingest_runs
for select to authenticated
using (public.user_owns_project(project_id));

drop policy if exists artifact_pages_select_own on public.artifact_pages;
create policy artifact_pages_select_own on public.artifact_pages
for select to authenticated
using (public.user_owns_project(project_id));

drop policy if exists artifact_summaries_select_own on public.artifact_summaries;
create policy artifact_summaries_select_own on public.artifact_summaries
for select to authenticated
using (public.user_owns_project(project_id));

commit;
