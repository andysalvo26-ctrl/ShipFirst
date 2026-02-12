begin;

create extension if not exists pgcrypto;
create extension if not exists vector;

create table if not exists public.kodos_v3_slots (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  cycle_no integer not null check (cycle_no >= 1),
  slot_key text not null,
  slot_value text not null,
  status public.trust_label not null default 'UNKNOWN',
  confidence numeric(4,3) not null default 0.500 check (confidence >= 0 and confidence <= 1),
  evidence_refs text[] not null default '{}',
  confirmed_by_turn_id uuid references public.intake_turns(id) on delete set null,
  source text not null default 'system' check (source in ('user', 'system', 'domain_kit')),
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  unique (project_id, cycle_no, slot_key)
);

create index if not exists kodos_v3_slots_project_cycle_updated_idx
  on public.kodos_v3_slots(project_id, cycle_no, updated_at desc);
create index if not exists kodos_v3_slots_project_cycle_status_idx
  on public.kodos_v3_slots(project_id, cycle_no, status, updated_at desc);

create table if not exists public.kodos_v3_slot_events (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  cycle_no integer not null check (cycle_no >= 1),
  slot_id uuid not null references public.kodos_v3_slots(id) on delete cascade,
  event_type text not null check (event_type in ('created', 'updated', 'confirmed', 'deferred', 'conflicted')),
  previous_status public.trust_label,
  new_status public.trust_label not null,
  value_snapshot text not null,
  evidence_refs text[] not null default '{}',
  actor_type text not null check (actor_type in ('USER','SYSTEM','SERVICE')),
  actor_turn_id uuid references public.intake_turns(id) on delete set null,
  created_at timestamptz not null default timezone('utc'::text, now())
);

create index if not exists kodos_v3_slot_events_project_cycle_created_idx
  on public.kodos_v3_slot_events(project_id, cycle_no, created_at desc);

create table if not exists public.kodos_v3_memory_chunks (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  cycle_no integer not null check (cycle_no >= 1),
  source_type text not null check (source_type in ('intake_turn', 'decision_item', 'artifact_summary', 'slot', 'domain_kit')),
  source_id text not null,
  chunk_text text not null,
  trust_label public.trust_label not null default 'ASSUMED',
  embedding vector(1536),
  embedding_model text not null default 'text-embedding-3-small',
  provenance_refs text[] not null default '{}',
  metadata jsonb not null default '{}'::jsonb,
  source_hash text,
  created_at timestamptz not null default timezone('utc'::text, now()),
  unique (project_id, cycle_no, source_type, source_id, embedding_model, source_hash)
);

create index if not exists kodos_v3_memory_chunks_project_cycle_created_idx
  on public.kodos_v3_memory_chunks(project_id, cycle_no, created_at desc);
create index if not exists kodos_v3_memory_chunks_project_cycle_source_idx
  on public.kodos_v3_memory_chunks(project_id, cycle_no, source_type, created_at desc);
create index if not exists kodos_v3_memory_chunks_embedding_hnsw_idx
  on public.kodos_v3_memory_chunks using hnsw (embedding vector_cosine_ops);

create table if not exists public.kodos_v3_domain_kits (
  id uuid primary key default gen_random_uuid(),
  domain_key text not null unique,
  title text not null,
  summary text not null,
  defaults jsonb not null default '{}'::jsonb,
  checklist jsonb not null default '[]'::jsonb,
  embedding vector(1536),
  embedding_model text not null default 'text-embedding-3-small',
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now())
);

create table if not exists public.kodos_v3_doc_strength_snapshots (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  cycle_no integer not null check (cycle_no >= 1),
  contract_version_id uuid references public.contract_versions(id) on delete set null,
  role_id integer not null check (role_id between 1 and 10),
  strength_score numeric(5,2) not null check (strength_score >= 0 and strength_score <= 100),
  quality_tier text not null check (quality_tier in ('mvp', 'solid', 'strong')),
  unresolved_count integer not null default 0 check (unresolved_count >= 0),
  provenance_density numeric(4,3) not null default 0 check (provenance_density >= 0 and provenance_density <= 1),
  notes jsonb not null default '[]'::jsonb,
  generated_by text not null check (generated_by in ('next-turn', 'commit-contract', 'manual')),
  created_at timestamptz not null default timezone('utc'::text, now())
);

create index if not exists kodos_v3_doc_strength_snapshots_project_cycle_created_idx
  on public.kodos_v3_doc_strength_snapshots(project_id, cycle_no, created_at desc);
create index if not exists kodos_v3_doc_strength_snapshots_project_cycle_role_idx
  on public.kodos_v3_doc_strength_snapshots(project_id, cycle_no, role_id, created_at desc);

create table if not exists public.kodos_v3_retrieval_runs (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  cycle_no integer not null check (cycle_no >= 1),
  purpose text not null check (purpose in ('question_planning', 'doc_generation', 'doc_strength')),
  query_text text not null,
  top_k integer not null default 8 check (top_k >= 1 and top_k <= 50),
  results jsonb not null default '[]'::jsonb,
  latency_ms integer,
  created_at timestamptz not null default timezone('utc'::text, now())
);

create index if not exists kodos_v3_retrieval_runs_project_cycle_created_idx
  on public.kodos_v3_retrieval_runs(project_id, cycle_no, created_at desc);

alter table public.kodos_v3_slots enable row level security;
alter table public.kodos_v3_slot_events enable row level security;
alter table public.kodos_v3_memory_chunks enable row level security;
alter table public.kodos_v3_domain_kits enable row level security;
alter table public.kodos_v3_doc_strength_snapshots enable row level security;
alter table public.kodos_v3_retrieval_runs enable row level security;

drop policy if exists kodos_v3_slots_select_own on public.kodos_v3_slots;
create policy kodos_v3_slots_select_own on public.kodos_v3_slots
for select to authenticated
using (public.user_owns_project(project_id));

drop policy if exists kodos_v3_slot_events_select_own on public.kodos_v3_slot_events;
create policy kodos_v3_slot_events_select_own on public.kodos_v3_slot_events
for select to authenticated
using (public.user_owns_project(project_id));

drop policy if exists kodos_v3_memory_chunks_select_own on public.kodos_v3_memory_chunks;
create policy kodos_v3_memory_chunks_select_own on public.kodos_v3_memory_chunks
for select to authenticated
using (public.user_owns_project(project_id));

drop policy if exists kodos_v3_doc_strength_snapshots_select_own on public.kodos_v3_doc_strength_snapshots;
create policy kodos_v3_doc_strength_snapshots_select_own on public.kodos_v3_doc_strength_snapshots
for select to authenticated
using (public.user_owns_project(project_id));

drop policy if exists kodos_v3_retrieval_runs_select_own on public.kodos_v3_retrieval_runs;
create policy kodos_v3_retrieval_runs_select_own on public.kodos_v3_retrieval_runs
for select to authenticated
using (public.user_owns_project(project_id));

drop policy if exists kodos_v3_domain_kits_select_authenticated on public.kodos_v3_domain_kits;
create policy kodos_v3_domain_kits_select_authenticated on public.kodos_v3_domain_kits
for select to authenticated
using (true);

do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'set_updated_at'
  ) then
    drop trigger if exists kodos_v3_slots_set_updated_at on public.kodos_v3_slots;
    create trigger kodos_v3_slots_set_updated_at
    before update on public.kodos_v3_slots
    for each row
    execute function public.set_updated_at();

    drop trigger if exists kodos_v3_domain_kits_set_updated_at on public.kodos_v3_domain_kits;
    create trigger kodos_v3_domain_kits_set_updated_at
    before update on public.kodos_v3_domain_kits
    for each row
    execute function public.set_updated_at();
  end if;
end $$;

insert into public.kodos_v3_domain_kits (domain_key, title, summary, defaults, checklist)
values
  (
    'generic_app',
    'General App Starter',
    'Baseline planning kit for broad app ideas when domain-specific intent is weak.',
    '{"primary_outcome":"capture leads or requests","launch_capabilities":["onboarding","core browse flow"],"monetization_path":"later"}'::jsonb,
    '["Confirm core user outcome","Confirm one or two launch capabilities","Confirm payment timing"]'::jsonb
  ),
  (
    'commerce_books',
    'Book Commerce Starter',
    'Starter assumptions for selling books online with simple catalog, discovery, and purchase flow.',
    '{"primary_outcome":"browse and buy books","launch_capabilities":["catalog categories","search and filters","cart and checkout"],"monetization_path":"payments_required","payments_provider":"stripe"}'::jsonb,
    '["Catalog structure (categories, metadata)","Search and browse behavior","Checkout and payment readiness","Order status communication"]'::jsonb
  ),
  (
    'service_booking',
    'Service Booking Starter',
    'Starter assumptions for appointment and service booking flows.',
    '{"primary_outcome":"book a service","launch_capabilities":["availability","booking form","reminders"],"monetization_path":"payments_optional"}'::jsonb,
    '["Service types","Scheduling rules","Payment timing","Post-booking communication"]'::jsonb
  )
on conflict (domain_key) do update
set
  title = excluded.title,
  summary = excluded.summary,
  defaults = excluded.defaults,
  checklist = excluded.checklist,
  updated_at = timezone('utc'::text, now());

commit;
