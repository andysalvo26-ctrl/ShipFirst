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

create table if not exists public.runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  status text not null default 'draft' check (status in ('draft','generated','submitted')),
  current_stage text not null default 'DISCOVERY' check (current_stage in ('DISCOVERY','EXTRACTION','AMBIGUITY','CONFIRMATION','ASSEMBLY','CONSISTENCY','COMMIT','SUBMITTED')),
  latest_contract_version_id uuid,
  latest_submission_path text,
  brain_version text,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  submitted_at timestamptz
);

create table if not exists public.intake_turns (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.runs(id) on delete cascade,
  actor_type text not null default 'USER' check (actor_type in ('USER','SYSTEM')),
  turn_index integer not null,
  raw_text text not null,
  created_at timestamptz not null default timezone('utc'::text, now()),
  unique (run_id, turn_index)
);

create table if not exists public.decision_items (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.runs(id) on delete cascade,
  decision_key text not null,
  claim text not null,
  status public.trust_label not null,
  evidence_refs text[] not null default '{}',
  lock_state text not null default 'open' check (lock_state in ('open','locked')),
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  unique (run_id, decision_key)
);

create table if not exists public.generation_runs (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.runs(id) on delete cascade,
  stage text not null check (stage in ('DISCOVERY','EXTRACTION','AMBIGUITY','CONFIRMATION','ASSEMBLY','CONSISTENCY','COMMIT')),
  status text not null check (status in ('started','passed','failed')),
  details jsonb not null default '{}'::jsonb,
  input_fingerprint text,
  output_fingerprint text,
  created_at timestamptz not null default timezone('utc'::text, now()),
  ended_at timestamptz
);

create table if not exists public.run_gates (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.runs(id) on delete cascade,
  gate_name text not null,
  gate_status text not null check (gate_status in ('pass','warn','fail')),
  message text,
  created_at timestamptz not null default timezone('utc'::text, now())
);

create table if not exists public.contract_versions (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.runs(id) on delete cascade,
  version_number integer not null,
  status text not null default 'draft' check (status in ('draft','validated','submitted')),
  document_count integer not null default 0,
  submission_bundle_path text,
  submission_manifest jsonb,
  created_at timestamptz not null default timezone('utc'::text, now()),
  unique (run_id, version_number)
);

create table if not exists public.contract_docs (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.runs(id) on delete cascade,
  contract_version_id uuid not null references public.contract_versions(id) on delete cascade,
  role_id integer not null check (role_id between 1 and 10),
  title text not null,
  body text not null,
  is_complete boolean not null default false,
  created_at timestamptz not null default timezone('utc'::text, now()),
  unique (contract_version_id, role_id)
);

create table if not exists public.document_claims (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.runs(id) on delete cascade,
  contract_version_id uuid not null references public.contract_versions(id) on delete cascade,
  contract_doc_id uuid not null references public.contract_docs(id) on delete cascade,
  role_id integer not null check (role_id between 1 and 10),
  claim_index integer not null,
  claim_text text not null,
  trust_label public.trust_label not null,
  provenance_refs text[] not null default '{}',
  created_at timestamptz not null default timezone('utc'::text, now()),
  unique (contract_doc_id, claim_index)
);

create table if not exists public.provenance_links (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.runs(id) on delete cascade,
  contract_version_id uuid not null references public.contract_versions(id) on delete cascade,
  contract_doc_id uuid not null references public.contract_docs(id) on delete cascade,
  claim_id uuid not null references public.document_claims(id) on delete cascade,
  source_type text not null check (source_type in ('INTAKE_TURN','DECISION_ITEM')),
  source_id uuid,
  pointer text not null,
  created_at timestamptz not null default timezone('utc'::text, now())
);

create table if not exists public.submissions (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null unique references public.runs(id) on delete cascade,
  contract_version_id uuid not null references public.contract_versions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  bucket text not null,
  path text not null,
  manifest jsonb not null,
  created_at timestamptz not null default timezone('utc'::text, now())
);

create index if not exists runs_user_created_idx on public.runs(user_id, created_at desc);
create index if not exists intake_turns_run_idx on public.intake_turns(run_id, turn_index);
create index if not exists decision_items_run_updated_idx on public.decision_items(run_id, updated_at desc);
create index if not exists contract_docs_version_role_idx on public.contract_docs(contract_version_id, role_id);
create index if not exists document_claims_version_role_idx on public.document_claims(contract_version_id, role_id, claim_index);
create index if not exists provenance_links_claim_idx on public.provenance_links(claim_id);

alter table public.runs add constraint runs_latest_contract_version_fkey
  foreign key (latest_contract_version_id) references public.contract_versions(id) on delete set null;

create trigger runs_set_updated_at
before update on public.runs
for each row
execute function public.set_updated_at();

create trigger decision_items_set_updated_at
before update on public.decision_items
for each row
execute function public.set_updated_at();

create trigger intake_turns_append_only_update
before update on public.intake_turns
for each row
execute function public.reject_mutation();

create trigger intake_turns_append_only_delete
before delete on public.intake_turns
for each row
execute function public.reject_mutation();

alter table public.runs enable row level security;
alter table public.intake_turns enable row level security;
alter table public.decision_items enable row level security;
alter table public.generation_runs enable row level security;
alter table public.run_gates enable row level security;
alter table public.contract_versions enable row level security;
alter table public.contract_docs enable row level security;
alter table public.document_claims enable row level security;
alter table public.provenance_links enable row level security;
alter table public.submissions enable row level security;

drop policy if exists runs_select_own on public.runs;
create policy runs_select_own on public.runs
for select to authenticated
using (user_id = auth.uid());

drop policy if exists runs_insert_own on public.runs;
create policy runs_insert_own on public.runs
for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists runs_update_own on public.runs;
create policy runs_update_own on public.runs
for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists intake_turns_select_own on public.intake_turns;
create policy intake_turns_select_own on public.intake_turns
for select to authenticated
using (exists (select 1 from public.runs r where r.id = intake_turns.run_id and r.user_id = auth.uid()));

drop policy if exists intake_turns_insert_own on public.intake_turns;
create policy intake_turns_insert_own on public.intake_turns
for insert to authenticated
with check (exists (select 1 from public.runs r where r.id = intake_turns.run_id and r.user_id = auth.uid()));

drop policy if exists decision_items_select_own on public.decision_items;
create policy decision_items_select_own on public.decision_items
for select to authenticated
using (exists (select 1 from public.runs r where r.id = decision_items.run_id and r.user_id = auth.uid()));

drop policy if exists decision_items_insert_own on public.decision_items;
create policy decision_items_insert_own on public.decision_items
for insert to authenticated
with check (exists (select 1 from public.runs r where r.id = decision_items.run_id and r.user_id = auth.uid()));

drop policy if exists decision_items_update_own on public.decision_items;
create policy decision_items_update_own on public.decision_items
for update to authenticated
using (exists (select 1 from public.runs r where r.id = decision_items.run_id and r.user_id = auth.uid()))
with check (exists (select 1 from public.runs r where r.id = decision_items.run_id and r.user_id = auth.uid()));

drop policy if exists generation_runs_select_own on public.generation_runs;
create policy generation_runs_select_own on public.generation_runs
for select to authenticated
using (exists (select 1 from public.runs r where r.id = generation_runs.run_id and r.user_id = auth.uid()));

drop policy if exists run_gates_select_own on public.run_gates;
create policy run_gates_select_own on public.run_gates
for select to authenticated
using (exists (select 1 from public.runs r where r.id = run_gates.run_id and r.user_id = auth.uid()));

drop policy if exists contract_versions_select_own on public.contract_versions;
create policy contract_versions_select_own on public.contract_versions
for select to authenticated
using (exists (select 1 from public.runs r where r.id = contract_versions.run_id and r.user_id = auth.uid()));

drop policy if exists contract_docs_select_own on public.contract_docs;
create policy contract_docs_select_own on public.contract_docs
for select to authenticated
using (exists (select 1 from public.runs r where r.id = contract_docs.run_id and r.user_id = auth.uid()));

drop policy if exists document_claims_select_own on public.document_claims;
create policy document_claims_select_own on public.document_claims
for select to authenticated
using (exists (select 1 from public.runs r where r.id = document_claims.run_id and r.user_id = auth.uid()));

drop policy if exists provenance_links_select_own on public.provenance_links;
create policy provenance_links_select_own on public.provenance_links
for select to authenticated
using (exists (select 1 from public.runs r where r.id = provenance_links.run_id and r.user_id = auth.uid()));

drop policy if exists submissions_select_own on public.submissions;
create policy submissions_select_own on public.submissions
for select to authenticated
using (user_id = auth.uid());

insert into storage.buckets (id, name, public)
values ('shipfirst-submissions', 'shipfirst-submissions', false)
on conflict (id) do nothing;

drop policy if exists storage_read_own_submission_bundle on storage.objects;
create policy storage_read_own_submission_bundle
on storage.objects
for select to authenticated
using (
  bucket_id = 'shipfirst-submissions'
  and (storage.foldername(name))[1] = auth.uid()::text
);
