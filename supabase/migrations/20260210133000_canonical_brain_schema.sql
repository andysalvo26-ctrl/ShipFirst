create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc'::text, now());
  return new;
end;
$$;

create or replace function public.reject_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'append-only table: update/delete not allowed';
end;
$$;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'trust_label') then
    create type public.trust_label as enum ('USER_SAID', 'ASSUMED', 'UNKNOWN');
  end if;
end $$;

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null default 'Untitled Project',
  active_cycle_no integer not null default 1 check (active_cycle_no >= 1),
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now())
);

create table if not exists public.intake_turns (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  cycle_no integer not null check (cycle_no >= 1),
  actor_type text not null default 'USER' check (actor_type in ('USER','SYSTEM')),
  turn_index integer not null check (turn_index >= 1),
  raw_text text not null,
  created_at timestamptz not null default timezone('utc'::text, now()),
  unique (project_id, cycle_no, turn_index)
);

create table if not exists public.decision_items (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  cycle_no integer not null check (cycle_no >= 1),
  decision_key text not null,
  claim text not null,
  status public.trust_label not null,
  evidence_refs text[] not null default '{}',
  lock_state text not null default 'open' check (lock_state in ('open','locked')),
  locked_at timestamptz,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  unique (project_id, cycle_no, decision_key),
  constraint decision_items_evidence_nonempty_check check (coalesce(array_length(evidence_refs, 1), 0) > 0)
);

create table if not exists public.generation_runs (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  cycle_no integer not null check (cycle_no >= 1),
  stage text not null check (stage in ('DISCOVERY','EXTRACTION','AMBIGUITY','CONFIRMATION','ASSEMBLY','CONSISTENCY','COMMIT')),
  status text not null check (status in ('started','passed','failed')),
  details jsonb not null default '{}'::jsonb,
  run_identity text,
  input_fingerprint text,
  output_fingerprint text,
  version_tuple jsonb not null default '{}'::jsonb,
  correlation_ref text,
  attempt integer not null default 1,
  created_at timestamptz not null default timezone('utc'::text, now()),
  ended_at timestamptz
);

create table if not exists public.contract_versions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  cycle_no integer not null check (cycle_no >= 1),
  version_number integer not null check (version_number >= 1),
  status text not null default 'committed' check (status in ('committed')),
  document_count integer not null default 10 check (document_count = 10),
  version_tuple jsonb not null default '{}'::jsonb,
  artifact_fingerprint text not null default '',
  commit_idempotency_key text,
  parent_contract_version_id uuid references public.contract_versions(id) on delete set null,
  committed_at timestamptz not null default timezone('utc'::text, now()),
  created_at timestamptz not null default timezone('utc'::text, now()),
  unique (project_id, cycle_no, version_number)
);

create table if not exists public.contract_docs (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  cycle_no integer not null check (cycle_no >= 1),
  contract_version_id uuid not null references public.contract_versions(id) on delete cascade,
  role_id integer not null check (role_id between 1 and 10),
  title text not null,
  body text not null,
  is_complete boolean not null default false,
  word_count integer not null default 1 check (word_count > 0),
  builder_notes_count integer not null default 4 check (builder_notes_count between 3 and 6),
  created_at timestamptz not null default timezone('utc'::text, now()),
  unique (contract_version_id, role_id)
);

create table if not exists public.requirements (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  cycle_no integer not null check (cycle_no >= 1),
  contract_version_id uuid not null references public.contract_versions(id) on delete cascade,
  contract_doc_id uuid not null references public.contract_docs(id) on delete cascade,
  role_id integer not null check (role_id between 1 and 10),
  requirement_index integer not null check (requirement_index >= 0),
  requirement_text text not null,
  trust_label public.trust_label not null,
  status text not null default 'active' check (status in ('active')),
  acceptance_criteria text,
  success_measure text,
  priority_level text,
  created_at timestamptz not null default timezone('utc'::text, now()),
  unique (contract_doc_id, requirement_index)
);

create table if not exists public.provenance_links (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  cycle_no integer not null check (cycle_no >= 1),
  contract_version_id uuid not null references public.contract_versions(id) on delete cascade,
  contract_doc_id uuid not null references public.contract_docs(id) on delete cascade,
  requirement_id uuid not null references public.requirements(id) on delete cascade,
  source_type text not null check (source_type in ('INTAKE_TURN','DECISION_ITEM')),
  source_id text,
  pointer text not null,
  created_at timestamptz not null default timezone('utc'::text, now())
);

create table if not exists public.audit_events (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  cycle_no integer not null check (cycle_no >= 1),
  contract_version_id uuid references public.contract_versions(id) on delete set null,
  actor_type text not null check (actor_type in ('USER','SYSTEM','SERVICE')),
  actor_id uuid,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc'::text, now())
);

create table if not exists public.submission_artifacts (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  cycle_no integer not null check (cycle_no >= 1),
  contract_version_id uuid not null references public.contract_versions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  bucket text not null,
  storage_path text not null,
  manifest jsonb not null,
  submitted_at timestamptz not null default timezone('utc'::text, now()),
  created_at timestamptz not null default timezone('utc'::text, now()),
  unique (contract_version_id)
);

create index if not exists projects_owner_created_idx on public.projects(owner_user_id, created_at desc);
create index if not exists intake_turns_project_cycle_idx on public.intake_turns(project_id, cycle_no, turn_index);
create index if not exists decision_items_project_cycle_updated_idx on public.decision_items(project_id, cycle_no, updated_at desc);
create index if not exists generation_runs_project_cycle_stage_idx on public.generation_runs(project_id, cycle_no, stage, created_at desc);
alter table public.generation_runs
  add column if not exists run_identity text;

create unique index if not exists generation_runs_identity_unique_idx
  on public.generation_runs(project_id, cycle_no, stage, run_identity)
  where run_identity is not null;
create index if not exists contract_versions_project_cycle_created_idx on public.contract_versions(project_id, cycle_no, created_at desc);
create index if not exists contract_versions_project_cycle_fingerprint_idx on public.contract_versions(project_id, cycle_no, artifact_fingerprint);
create unique index if not exists contract_versions_commit_key_unique_idx
  on public.contract_versions(project_id, cycle_no, commit_idempotency_key)
  where commit_idempotency_key is not null;
create index if not exists contract_docs_version_role_idx on public.contract_docs(contract_version_id, role_id);
create index if not exists requirements_version_role_idx on public.requirements(contract_version_id, role_id, requirement_index);
create index if not exists provenance_links_requirement_idx on public.provenance_links(requirement_id);
create index if not exists audit_events_project_cycle_created_idx on public.audit_events(project_id, cycle_no, created_at desc);
create index if not exists submission_artifacts_project_cycle_created_idx on public.submission_artifacts(project_id, cycle_no, created_at desc);

-- Append-only enforcement and updated_at tracking.
drop trigger if exists projects_set_updated_at on public.projects;
create trigger projects_set_updated_at
before update on public.projects
for each row
execute function public.set_updated_at();

drop trigger if exists decision_items_set_updated_at on public.decision_items;
create trigger decision_items_set_updated_at
before update on public.decision_items
for each row
execute function public.set_updated_at();

drop trigger if exists intake_turns_append_only_update on public.intake_turns;
create trigger intake_turns_append_only_update
before update on public.intake_turns
for each row
execute function public.reject_mutation();

drop trigger if exists intake_turns_append_only_delete on public.intake_turns;
create trigger intake_turns_append_only_delete
before delete on public.intake_turns
for each row
execute function public.reject_mutation();

-- Contract versions are immutable once committed.
drop trigger if exists contract_versions_append_only_update on public.contract_versions;
create trigger contract_versions_append_only_update
before update on public.contract_versions
for each row
execute function public.reject_mutation();

drop trigger if exists contract_versions_append_only_delete on public.contract_versions;
create trigger contract_versions_append_only_delete
before delete on public.contract_versions
for each row
execute function public.reject_mutation();

alter table public.projects enable row level security;
alter table public.intake_turns enable row level security;
alter table public.decision_items enable row level security;
alter table public.generation_runs enable row level security;
alter table public.contract_versions enable row level security;
alter table public.contract_docs enable row level security;
alter table public.requirements enable row level security;
alter table public.provenance_links enable row level security;
alter table public.audit_events enable row level security;
alter table public.submission_artifacts enable row level security;

drop policy if exists projects_select_own on public.projects;
create policy projects_select_own on public.projects
for select to authenticated
using (owner_user_id = auth.uid());

drop policy if exists projects_insert_own on public.projects;
create policy projects_insert_own on public.projects
for insert to authenticated
with check (owner_user_id = auth.uid());

drop policy if exists projects_update_own on public.projects;
create policy projects_update_own on public.projects
for update to authenticated
using (owner_user_id = auth.uid())
with check (owner_user_id = auth.uid());

drop policy if exists intake_turns_select_own on public.intake_turns;
create policy intake_turns_select_own on public.intake_turns
for select to authenticated
using (exists (
  select 1 from public.projects p
  where p.id = intake_turns.project_id and p.owner_user_id = auth.uid()
));

drop policy if exists intake_turns_insert_own on public.intake_turns;
create policy intake_turns_insert_own on public.intake_turns
for insert to authenticated
with check (exists (
  select 1 from public.projects p
  where p.id = intake_turns.project_id and p.owner_user_id = auth.uid()
));

drop policy if exists decision_items_select_own on public.decision_items;
create policy decision_items_select_own on public.decision_items
for select to authenticated
using (exists (
  select 1 from public.projects p
  where p.id = decision_items.project_id and p.owner_user_id = auth.uid()
));

drop policy if exists decision_items_insert_own on public.decision_items;
create policy decision_items_insert_own on public.decision_items
for insert to authenticated
with check (exists (
  select 1 from public.projects p
  where p.id = decision_items.project_id and p.owner_user_id = auth.uid()
));

drop policy if exists decision_items_update_own on public.decision_items;
create policy decision_items_update_own on public.decision_items
for update to authenticated
using (exists (
  select 1 from public.projects p
  where p.id = decision_items.project_id and p.owner_user_id = auth.uid()
))
with check (exists (
  select 1 from public.projects p
  where p.id = decision_items.project_id and p.owner_user_id = auth.uid()
));

-- Server-written, client-selectable tables.
drop policy if exists generation_runs_select_own on public.generation_runs;
create policy generation_runs_select_own on public.generation_runs
for select to authenticated
using (exists (
  select 1 from public.projects p
  where p.id = generation_runs.project_id and p.owner_user_id = auth.uid()
));

drop policy if exists contract_versions_select_own on public.contract_versions;
create policy contract_versions_select_own on public.contract_versions
for select to authenticated
using (exists (
  select 1 from public.projects p
  where p.id = contract_versions.project_id and p.owner_user_id = auth.uid()
));

drop policy if exists contract_docs_select_own on public.contract_docs;
create policy contract_docs_select_own on public.contract_docs
for select to authenticated
using (exists (
  select 1 from public.projects p
  where p.id = contract_docs.project_id and p.owner_user_id = auth.uid()
));

drop policy if exists requirements_select_own on public.requirements;
create policy requirements_select_own on public.requirements
for select to authenticated
using (exists (
  select 1 from public.projects p
  where p.id = requirements.project_id and p.owner_user_id = auth.uid()
));

drop policy if exists provenance_links_select_own on public.provenance_links;
create policy provenance_links_select_own on public.provenance_links
for select to authenticated
using (exists (
  select 1 from public.projects p
  where p.id = provenance_links.project_id and p.owner_user_id = auth.uid()
));

drop policy if exists audit_events_select_own on public.audit_events;
create policy audit_events_select_own on public.audit_events
for select to authenticated
using (exists (
  select 1 from public.projects p
  where p.id = audit_events.project_id and p.owner_user_id = auth.uid()
));

drop policy if exists submission_artifacts_select_own on public.submission_artifacts;
create policy submission_artifacts_select_own on public.submission_artifacts
for select to authenticated
using (user_id = auth.uid());

insert into storage.buckets (id, name, public)
values ('shipfirst-submissions', 'shipfirst-submissions', false)
on conflict (id) do nothing;
