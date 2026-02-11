-- Interview engine pre-implementation state support.
-- Purpose: add minimum representational support for posture/burden/artifact verification
-- and explicit hypothesis confirmation linkage, without implementing full engine logic.

begin;

create table if not exists public.artifact_inputs (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  cycle_no integer not null check (cycle_no >= 1),
  artifact_type text not null check (artifact_type in ('website', 'brand_page', 'uploaded_doc', 'other')),
  artifact_ref text not null,
  ingest_state text not null default 'pending' check (ingest_state in ('pending', 'partial', 'complete', 'failed')),
  summary_text text,
  verification_state text not null default 'unverified' check (verification_state in ('unverified', 'user_confirmed', 'user_corrected')),
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  unique (project_id, cycle_no, artifact_type, artifact_ref)
);

create index if not exists artifact_inputs_project_cycle_created_idx
  on public.artifact_inputs(project_id, cycle_no, created_at desc);

create table if not exists public.interview_turn_state (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  cycle_no integer not null check (cycle_no >= 1),
  turn_id uuid not null references public.intake_turns(id) on delete cascade,
  posture_mode text not null check (posture_mode in ('Exploration', 'Artifact Grounding', 'Verification', 'Extraction', 'Alignment Checkpoint', 'Recovery')),
  move_type text not null,
  burden_signal text not null default 'medium' check (burden_signal in ('low', 'medium', 'high')),
  pace_signal text not null default 'opening' check (pace_signal in ('opening', 'narrowing', 'reopening')),
  transition_reason text not null default 'unspecified',
  created_at timestamptz not null default timezone('utc'::text, now())
);

create index if not exists interview_turn_state_project_cycle_turn_idx
  on public.interview_turn_state(project_id, cycle_no, created_at desc);

alter table public.decision_items
  add column if not exists confirmed_by_turn_id uuid references public.intake_turns(id) on delete set null;

alter table public.decision_items
  add column if not exists hypothesis_rationale text;

create index if not exists decision_items_confirmed_by_turn_idx
  on public.decision_items(confirmed_by_turn_id);

alter table public.artifact_inputs enable row level security;
alter table public.interview_turn_state enable row level security;

drop policy if exists artifact_inputs_select_own on public.artifact_inputs;
drop policy if exists artifact_inputs_insert_own on public.artifact_inputs;
drop policy if exists interview_turn_state_select_own on public.interview_turn_state;

create policy artifact_inputs_select_own on public.artifact_inputs
for select to authenticated
using (public.user_owns_project(project_id));

create policy artifact_inputs_insert_own on public.artifact_inputs
for insert to authenticated
with check (
  public.user_owns_project(project_id)
  and verification_state = 'unverified'
  and ingest_state = 'pending'
  and summary_text is null
);

create policy interview_turn_state_select_own on public.interview_turn_state
for select to authenticated
using (public.user_owns_project(project_id));

do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'set_updated_at'
  ) then
    drop trigger if exists artifact_inputs_set_updated_at on public.artifact_inputs;
    create trigger artifact_inputs_set_updated_at
    before update on public.artifact_inputs
    for each row
    execute function public.set_updated_at();
  end if;
end $$;

commit;
