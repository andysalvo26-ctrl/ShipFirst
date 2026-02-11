begin;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'decision_state') then
    create type public.decision_state as enum ('PROPOSED', 'CONFIRMED');
  end if;
end $$;

alter table public.decision_items
  add column if not exists decision_state public.decision_state;

update public.decision_items
set decision_state = case
  when lower(coalesce(lock_state::text, 'open')) = 'locked' then 'CONFIRMED'::public.decision_state
  else 'PROPOSED'::public.decision_state
end
where decision_state is null;

alter table public.decision_items
  alter column decision_state set default 'PROPOSED'::public.decision_state;

alter table public.decision_items
  alter column decision_state set not null;

alter table public.decision_items
  add column if not exists has_conflict boolean not null default false;

alter table public.decision_items
  add column if not exists conflict_key text;

create index if not exists decision_items_project_cycle_state_idx
  on public.decision_items(project_id, cycle_no, decision_state, updated_at desc);

create index if not exists decision_items_project_cycle_conflict_idx
  on public.decision_items(project_id, cycle_no, has_conflict, updated_at desc);

commit;
