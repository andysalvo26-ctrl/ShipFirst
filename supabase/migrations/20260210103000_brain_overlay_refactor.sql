-- Brain overlay refactor: enforce immutable contract versions, explicit issue records,
-- contradiction visibility, idempotent run identity, and submission audit linkage.

-- Contract versions: normalize to immutable committed snapshots.
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public' and table_name = 'contract_versions' and column_name = 'status'
  ) then
    update public.contract_versions
    set status = 'committed'
    where status is distinct from 'committed';

    alter table public.contract_versions
      alter column status set default 'committed';

    alter table public.contract_versions
      drop constraint if exists contract_versions_status_check;

    alter table public.contract_versions
      add constraint contract_versions_status_check
      check (status in ('committed'));
  end if;
end $$;

alter table public.contract_versions
  add column if not exists parent_contract_version_id uuid references public.contract_versions(id) on delete set null,
  add column if not exists version_tuple jsonb not null default '{}'::jsonb,
  add column if not exists artifact_fingerprint text not null default '',
  add column if not exists commit_idempotency_key text,
  add column if not exists committed_at timestamptz not null default timezone('utc'::text, now());

create index if not exists contract_versions_run_created_idx
  on public.contract_versions(run_id, created_at desc);

create index if not exists contract_versions_run_fingerprint_idx
  on public.contract_versions(run_id, artifact_fingerprint);

create unique index if not exists contract_versions_run_commit_key_idx
  on public.contract_versions(run_id, commit_idempotency_key)
  where commit_idempotency_key is not null;

-- Enforce immutability post-commit.
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

-- Generation run identity + tuple for idempotent stage traces.
alter table public.generation_runs
  add column if not exists run_identity text,
  add column if not exists version_tuple jsonb not null default '{}'::jsonb,
  add column if not exists correlation_ref text,
  add column if not exists attempt integer not null default 1;

update public.generation_runs
set run_identity = coalesce(run_identity, stage || ':' || coalesce(input_fingerprint, id::text));

with duplicate_identities as (
  select id,
         row_number() over (partition by run_id, stage, run_identity order by created_at, id) as rn
  from public.generation_runs
)
update public.generation_runs g
set run_identity = g.run_identity || ':' || g.id::text
where g.id in (
  select id from duplicate_identities where rn > 1
);

alter table public.generation_runs
  alter column run_identity set not null;

create unique index if not exists generation_runs_identity_unique_idx
  on public.generation_runs(run_id, stage, run_identity);

-- Contradictions are first-class and visible.
create table if not exists public.contradictions (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.runs(id) on delete cascade,
  contradiction_type text not null check (contradiction_type in ('scope','temporal','priority','policy','other')),
  conflicting_refs text[] not null default '{}',
  severity text not null check (severity in ('critical','major','minor')),
  resolution_state text not null default 'open' check (resolution_state in ('open','resolved','deferred')),
  summary text not null,
  created_at timestamptz not null default timezone('utc'::text, now()),
  resolved_at timestamptz
);

create index if not exists contradictions_run_open_idx
  on public.contradictions(run_id, severity, resolution_state);

-- Issue reports preserve block/warn decisions.
create table if not exists public.issue_reports (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.runs(id) on delete cascade,
  stage text not null,
  issue_type text not null,
  severity text not null check (severity in ('block','warn','info')),
  issue_ref text,
  message text not null,
  remediation_state text not null default 'open' check (remediation_state in ('open','resolved','accepted')),
  created_at timestamptz not null default timezone('utc'::text, now())
);

create index if not exists issue_reports_run_stage_idx
  on public.issue_reports(run_id, stage, severity, created_at desc);

-- Audit trail for critical transitions.
create table if not exists public.audit_events (
  id uuid primary key default gen_random_uuid(),
  run_id uuid references public.runs(id) on delete cascade,
  contract_version_id uuid references public.contract_versions(id) on delete set null,
  actor_type text not null check (actor_type in ('USER','SYSTEM','SERVICE')),
  actor_id uuid,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc'::text, now())
);

create index if not exists audit_events_run_created_idx
  on public.audit_events(run_id, created_at desc);

-- Contract doc integrity for budget and builder notes tracking.
alter table public.contract_docs
  add column if not exists word_count integer not null default 1,
  add column if not exists builder_notes_count integer not null default 4;

update public.contract_docs
set word_count = greatest(
  1,
  coalesce(array_length(regexp_split_to_array(trim(body), E'\\s+'), 1), 1)
)
where word_count <= 0;

update public.contract_docs
set builder_notes_count = 4
where builder_notes_count < 3 or builder_notes_count > 6;

alter table public.contract_docs
  drop constraint if exists contract_docs_word_count_positive_check;
alter table public.contract_docs
  add constraint contract_docs_word_count_positive_check
  check (word_count > 0);

alter table public.contract_docs
  drop constraint if exists contract_docs_builder_notes_count_check;
alter table public.contract_docs
  add constraint contract_docs_builder_notes_count_check
  check (builder_notes_count between 3 and 6);

-- Trust/provenance hardening.
update public.decision_items
set evidence_refs = array['run:legacy-backfill']
where coalesce(array_length(evidence_refs, 1), 0) = 0;

alter table public.decision_items
  drop constraint if exists decision_items_evidence_nonempty_check;
alter table public.decision_items
  add constraint decision_items_evidence_nonempty_check
  check (coalesce(array_length(evidence_refs, 1), 0) > 0);

update public.document_claims
set provenance_refs = array['run:legacy-backfill']
where coalesce(array_length(provenance_refs, 1), 0) = 0;

alter table public.document_claims
  drop constraint if exists document_claims_provenance_nonempty_check;
alter table public.document_claims
  add constraint document_claims_provenance_nonempty_check
  check (coalesce(array_length(provenance_refs, 1), 0) > 0);

-- Provenance pointers can target UUID-backed rows or logical keys.
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'provenance_links'
      and column_name = 'source_id'
      and data_type = 'uuid'
  ) then
    alter table public.provenance_links
      alter column source_id type text using source_id::text;
  end if;
end $$;

-- Submission linkage: one submission artifact per contract version.
alter table public.submissions
  drop constraint if exists submissions_run_id_key;

create unique index if not exists submissions_contract_version_unique_idx
  on public.submissions(contract_version_id);

create index if not exists submissions_run_created_idx
  on public.submissions(run_id, created_at desc);

-- RLS for new tables.
alter table public.contradictions enable row level security;
alter table public.issue_reports enable row level security;
alter table public.audit_events enable row level security;

drop policy if exists contradictions_select_own on public.contradictions;
create policy contradictions_select_own on public.contradictions
for select to authenticated
using (exists (select 1 from public.runs r where r.id = contradictions.run_id and r.user_id = auth.uid()));

drop policy if exists issue_reports_select_own on public.issue_reports;
create policy issue_reports_select_own on public.issue_reports
for select to authenticated
using (exists (select 1 from public.runs r where r.id = issue_reports.run_id and r.user_id = auth.uid()));

drop policy if exists audit_events_select_own on public.audit_events;
create policy audit_events_select_own on public.audit_events
for select to authenticated
using (exists (select 1 from public.runs r where r.id = audit_events.run_id and r.user_id = auth.uid()));
