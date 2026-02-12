-- ShipFirst Kodos V6 intake rebuild foundation.
-- Additive, legacy-safe tables for a new intake surface that generates 3 customer docs.

create extension if not exists pgcrypto;
create extension if not exists vector with schema extensions;

create or replace function kodos_v6_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function kodos_v6_block_row_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'This table is append-only.' using errcode = '55000';
end;
$$;

create table if not exists kodos_v6_projects (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null,
  title text not null,
  idea_sentence text not null,
  website_url text,
  status text not null default 'active' check (status in ('active', 'archived')),
  readiness_state text not null default 'not_ready' check (readiness_state in ('not_ready', 'ready')),
  active_revision integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_kodos_v6_projects_owner_updated on kodos_v6_projects(owner_user_id, updated_at desc);

create trigger trg_kodos_v6_projects_touch_updated_at
before update on kodos_v6_projects
for each row
execute function kodos_v6_touch_updated_at();

create table if not exists kodos_v6_turns (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references kodos_v6_projects(id) on delete cascade,
  revision_no integer not null default 1,
  actor text not null check (actor in ('user', 'system')),
  message_text text not null,
  answer_kind text not null check (answer_kind in ('idea', 'option', 'free_text', 'system')),
  question_key text,
  selected_option_id text,
  created_at timestamptz not null default now()
);

create index if not exists idx_kodos_v6_turns_project_revision_created on kodos_v6_turns(project_id, revision_no, created_at);

create trigger trg_kodos_v6_turns_block_update
before update on kodos_v6_turns
for each row
execute function kodos_v6_block_row_mutation();

create trigger trg_kodos_v6_turns_block_delete
before delete on kodos_v6_turns
for each row
execute function kodos_v6_block_row_mutation();

create table if not exists kodos_v6_slot_states (
  project_id uuid not null references kodos_v6_projects(id) on delete cascade,
  revision_no integer not null default 1,
  slot_key text not null,
  slot_label text not null,
  slot_value text not null,
  slot_status text not null check (slot_status in ('missing', 'captured', 'assumed', 'confirmed')),
  confidence numeric(5,2) not null default 0,
  source_turn_id uuid references kodos_v6_turns(id),
  evidence jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(project_id, revision_no, slot_key)
);

create trigger trg_kodos_v6_slot_states_touch_updated_at
before update on kodos_v6_slot_states
for each row
execute function kodos_v6_touch_updated_at();

create table if not exists kodos_v6_question_events (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references kodos_v6_projects(id) on delete cascade,
  revision_no integer not null default 1,
  question_key text not null,
  question_text text not null,
  options jsonb not null default '[]'::jsonb,
  selected_option_id text,
  free_text text,
  asked_at timestamptz not null default now(),
  answered_at timestamptz
);

create index if not exists idx_kodos_v6_question_events_project_revision_asked on kodos_v6_question_events(project_id, revision_no, asked_at desc);

create table if not exists kodos_v6_memory_chunks (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references kodos_v6_projects(id) on delete cascade,
  revision_no integer not null default 1,
  source_table text not null,
  source_row_id uuid not null,
  source_hash text not null,
  chunk_text text not null,
  embedding vector(1536),
  model_version text not null default 'text-embedding-3-small',
  is_stale boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id, source_table, source_row_id, source_hash, model_version)
);

create index if not exists idx_kodos_v6_memory_chunks_project_revision_created on kodos_v6_memory_chunks(project_id, revision_no, created_at desc);
create index if not exists idx_kodos_v6_memory_chunks_embedding_ivf
  on kodos_v6_memory_chunks using ivfflat (embedding extensions.vector_cosine_ops)
  with (lists = 100);

create trigger trg_kodos_v6_memory_chunks_touch_updated_at
before update on kodos_v6_memory_chunks
for each row
execute function kodos_v6_touch_updated_at();

create table if not exists kodos_v6_brief_versions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references kodos_v6_projects(id) on delete cascade,
  revision_no integer not null default 1,
  version_no integer not null,
  generation_mode text not null check (generation_mode in ('fast', 'improve')),
  readiness_state text not null check (readiness_state in ('not_ready', 'ready')),
  source_snapshot jsonb not null default '{}'::jsonb,
  internal_build_contract jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(project_id, revision_no, version_no)
);

create table if not exists kodos_v6_brief_docs (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references kodos_v6_projects(id) on delete cascade,
  revision_no integer not null default 1,
  brief_version_id uuid not null references kodos_v6_brief_versions(id) on delete cascade,
  doc_key text not null check (doc_key in ('app_vision_brief', 'mvp_blueprint', 'owner_control_brief')),
  title text not null,
  body text not null,
  word_count integer not null,
  created_at timestamptz not null default now(),
  unique(brief_version_id, doc_key)
);

create index if not exists idx_kodos_v6_brief_docs_project_version on kodos_v6_brief_docs(project_id, brief_version_id, doc_key);

create trigger trg_kodos_v6_brief_versions_block_update
before update on kodos_v6_brief_versions
for each row
execute function kodos_v6_block_row_mutation();

create trigger trg_kodos_v6_brief_versions_block_delete
before delete on kodos_v6_brief_versions
for each row
execute function kodos_v6_block_row_mutation();

create trigger trg_kodos_v6_brief_docs_block_update
before update on kodos_v6_brief_docs
for each row
execute function kodos_v6_block_row_mutation();

create trigger trg_kodos_v6_brief_docs_block_delete
before delete on kodos_v6_brief_docs
for each row
execute function kodos_v6_block_row_mutation();

create table if not exists kodos_v6_audit_events (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references kodos_v6_projects(id) on delete cascade,
  revision_no integer,
  event_type text not null,
  actor text not null check (actor in ('user', 'system')),
  correlation_id text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_kodos_v6_audit_events_project_created on kodos_v6_audit_events(project_id, created_at desc);

create trigger trg_kodos_v6_audit_events_block_update
before update on kodos_v6_audit_events
for each row
execute function kodos_v6_block_row_mutation();

create trigger trg_kodos_v6_audit_events_block_delete
before delete on kodos_v6_audit_events
for each row
execute function kodos_v6_block_row_mutation();

create or replace function kodos_v6_user_owns_project(p_project_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from kodos_v6_projects p
    where p.id = p_project_id
      and p.owner_user_id = auth.uid()
  );
$$;

create or replace function kodos_v6_match_memory_chunks(
  p_project_id uuid,
  p_revision_no integer,
  p_query_embedding vector(1536),
  p_match_count integer default 6
)
returns table (
  id uuid,
  chunk_text text,
  source_table text,
  source_row_id uuid,
  metadata jsonb,
  similarity double precision
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select
    mc.id,
    mc.chunk_text,
    mc.source_table,
    mc.source_row_id,
    mc.metadata,
    1 - (mc.embedding <=> p_query_embedding) as similarity
  from kodos_v6_memory_chunks mc
  where mc.project_id = p_project_id
    and mc.revision_no = p_revision_no
    and mc.is_stale = false
    and mc.embedding is not null
  order by mc.embedding <=> p_query_embedding
  limit greatest(1, least(coalesce(p_match_count, 6), 20));
$$;

alter table kodos_v6_projects enable row level security;
alter table kodos_v6_turns enable row level security;
alter table kodos_v6_slot_states enable row level security;
alter table kodos_v6_question_events enable row level security;
alter table kodos_v6_memory_chunks enable row level security;
alter table kodos_v6_brief_versions enable row level security;
alter table kodos_v6_brief_docs enable row level security;
alter table kodos_v6_audit_events enable row level security;

-- Project ownership policies.
drop policy if exists kodos_v6_projects_select_own on kodos_v6_projects;
create policy kodos_v6_projects_select_own on kodos_v6_projects
for select to authenticated
using (owner_user_id = auth.uid());

drop policy if exists kodos_v6_projects_insert_own on kodos_v6_projects;
create policy kodos_v6_projects_insert_own on kodos_v6_projects
for insert to authenticated
with check (owner_user_id = auth.uid());

drop policy if exists kodos_v6_projects_update_own on kodos_v6_projects;
create policy kodos_v6_projects_update_own on kodos_v6_projects
for update to authenticated
using (owner_user_id = auth.uid())
with check (owner_user_id = auth.uid());

-- Intake policies.
drop policy if exists kodos_v6_turns_select_own on kodos_v6_turns;
create policy kodos_v6_turns_select_own on kodos_v6_turns
for select to authenticated
using (kodos_v6_user_owns_project(project_id));

drop policy if exists kodos_v6_turns_insert_own on kodos_v6_turns;
create policy kodos_v6_turns_insert_own on kodos_v6_turns
for insert to authenticated
with check (kodos_v6_user_owns_project(project_id));

drop policy if exists kodos_v6_slot_states_select_own on kodos_v6_slot_states;
create policy kodos_v6_slot_states_select_own on kodos_v6_slot_states
for select to authenticated
using (kodos_v6_user_owns_project(project_id));

drop policy if exists kodos_v6_question_events_select_own on kodos_v6_question_events;
create policy kodos_v6_question_events_select_own on kodos_v6_question_events
for select to authenticated
using (kodos_v6_user_owns_project(project_id));

drop policy if exists kodos_v6_memory_chunks_select_own on kodos_v6_memory_chunks;
create policy kodos_v6_memory_chunks_select_own on kodos_v6_memory_chunks
for select to authenticated
using (kodos_v6_user_owns_project(project_id));

-- Planning policies.
drop policy if exists kodos_v6_brief_versions_select_own on kodos_v6_brief_versions;
create policy kodos_v6_brief_versions_select_own on kodos_v6_brief_versions
for select to authenticated
using (kodos_v6_user_owns_project(project_id));

drop policy if exists kodos_v6_brief_docs_select_own on kodos_v6_brief_docs;
create policy kodos_v6_brief_docs_select_own on kodos_v6_brief_docs
for select to authenticated
using (kodos_v6_user_owns_project(project_id));

-- Ops policies.
drop policy if exists kodos_v6_audit_events_select_own on kodos_v6_audit_events;
create policy kodos_v6_audit_events_select_own on kodos_v6_audit_events
for select to authenticated
using (project_id is null or kodos_v6_user_owns_project(project_id));

grant execute on function kodos_v6_user_owns_project(uuid) to authenticated;
grant execute on function kodos_v6_match_memory_chunks(uuid, integer, vector, integer) to authenticated;
