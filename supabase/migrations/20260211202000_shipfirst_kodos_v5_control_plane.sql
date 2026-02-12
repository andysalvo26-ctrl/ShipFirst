begin;

create table if not exists public.kodos_v5_question_traces (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  cycle_no integer not null check (cycle_no >= 1),
  turn_id uuid references public.intake_turns(id) on delete set null,
  slot_key text not null,
  question_text text not null,
  options jsonb not null default '[]'::jsonb,
  why_question text not null,
  understanding_level text not null check (understanding_level in ('needs_basics', 'good_draft_ready', 'strong_builder_ready')),
  understanding_summary text not null,
  retrieval_refs text[] not null default '{}',
  retrieval_count integer not null default 0 check (retrieval_count >= 0),
  created_at timestamptz not null default timezone('utc'::text, now())
);

create index if not exists kodos_v5_question_traces_project_cycle_created_idx
  on public.kodos_v5_question_traces(project_id, cycle_no, created_at desc);

alter table public.kodos_v5_question_traces enable row level security;

drop policy if exists kodos_v5_question_traces_select_own on public.kodos_v5_question_traces;
create policy kodos_v5_question_traces_select_own on public.kodos_v5_question_traces
for select to authenticated
using (public.user_owns_project(project_id));

create or replace function public.kodos_v5_match_memory_chunks(
  p_project_id uuid,
  p_cycle_no integer,
  p_query_embedding vector(1536),
  p_match_count integer default 8
)
returns table (
  source_type text,
  source_id text,
  chunk_text text,
  trust_label public.trust_label,
  provenance_refs text[],
  metadata jsonb,
  similarity real
)
language sql
stable
as $$
  select
    m.source_type,
    m.source_id,
    m.chunk_text,
    m.trust_label,
    m.provenance_refs,
    m.metadata,
    (1 - (m.embedding <=> p_query_embedding))::real as similarity
  from public.kodos_v3_memory_chunks m
  where m.project_id = p_project_id
    and m.cycle_no = p_cycle_no
    and m.embedding is not null
  order by m.embedding <=> p_query_embedding
  limit greatest(1, least(coalesce(p_match_count, 8), 20));
$$;

grant execute on function public.kodos_v5_match_memory_chunks(uuid, integer, vector, integer) to authenticated;
grant execute on function public.kodos_v5_match_memory_chunks(uuid, integer, vector, integer) to service_role;

commit;
