-- ShipFirst Phase 1 launch hardening
-- Goals:
-- 1) Single ownership predicate: user_owns_project(project_id)
-- 2) Enforce project_id + owner ownership model without denormalized ownership fanout
-- 3) Repair schema drift (decision_items + contract_versions)
-- 4) Rebuild strict RLS with fail-closed behavior

begin;

create extension if not exists pgcrypto;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'trust_label') then
    create type public.trust_label as enum ('USER_SAID', 'ASSUMED', 'UNKNOWN');
  end if;
end $$;

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

create or replace function public.user_owns_project(p_project_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from public.projects p
    where p.id = p_project_id
      and p.owner_user_id = auth.uid()
  );
$$;

revoke all on function public.user_owns_project(uuid) from public;
grant execute on function public.user_owns_project(uuid) to authenticated;

-- Ensure projects.owner_user_id exists and is protected.
alter table public.projects add column if not exists owner_user_id uuid;

do $$
begin
  if to_regclass('public.submission_artifacts') is not null then
    update public.projects p
    set owner_user_id = (
      select sa.user_id
      from public.submission_artifacts sa
      where sa.project_id = p.id
        and sa.user_id is not null
      order by sa.created_at desc
      limit 1
    )
    where p.owner_user_id is null
      and exists (
        select 1
        from public.submission_artifacts sa2
        where sa2.project_id = p.id
          and sa2.user_id is not null
      );
  end if;

  if to_regclass('public.audit_events') is not null then
    update public.projects p
    set owner_user_id = (
      select ae.actor_id
      from public.audit_events ae
      where ae.project_id = p.id
        and ae.actor_type = 'USER'
        and ae.actor_id is not null
      order by ae.created_at desc
      limit 1
    )
    where p.owner_user_id is null
      and exists (
        select 1
        from public.audit_events ae2
        where ae2.project_id = p.id
          and ae2.actor_type = 'USER'
          and ae2.actor_id is not null
      );
  end if;
end $$;

alter table public.projects alter column owner_user_id set default auth.uid();

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.projects'::regclass
      and conname = 'projects_owner_user_id_fkey'
  ) then
    alter table public.projects
      add constraint projects_owner_user_id_fkey
      foreign key (owner_user_id) references auth.users(id) on delete cascade not valid;
  end if;
end $$;

do $$
declare
  owner_null_count bigint;
begin
  select count(*) into owner_null_count
  from public.projects
  where owner_user_id is null;

  if owner_null_count = 0 then
    alter table public.projects alter column owner_user_id set not null;
  else
    raise notice 'projects.owner_user_id still has % NULL rows; keeping nullable for legacy rows', owner_null_count;
    if not exists (
      select 1
      from pg_constraint
      where conrelid = 'public.projects'::regclass
        and conname = 'projects_owner_user_id_not_null_check'
    ) then
      alter table public.projects
        add constraint projects_owner_user_id_not_null_check
        check (owner_user_id is not null) not valid;
    end if;
  end if;
end $$;
create index if not exists projects_owner_user_id_idx on public.projects(owner_user_id);

create or replace function public.enforce_project_owner_user_id()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    if new.owner_user_id is null then
      new.owner_user_id := auth.uid();
    end if;
    if auth.uid() is not null and new.owner_user_id is distinct from auth.uid() then
      raise exception 'owner_user_id spoofing denied';
    end if;
  elsif tg_op = 'UPDATE' then
    if new.owner_user_id is distinct from old.owner_user_id then
      raise exception 'owner_user_id is immutable';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists projects_enforce_owner_user_id on public.projects;
create trigger projects_enforce_owner_user_id
before insert or update on public.projects
for each row
execute function public.enforce_project_owner_user_id();

-- Every customer-path control-plane table must carry project_id.
do $$
declare
  t text;
  tables text[] := array[
    'intake_turns',
    'decision_items',
    'generation_runs',
    'contract_versions',
    'contract_docs',
    'requirements',
    'provenance_links',
    'submission_artifacts',
    'audit_events'
  ];
begin
  foreach t in array tables loop
    execute format('alter table public.%I add column if not exists project_id uuid', t);
  end loop;
end $$;

-- Backfill project_id from existing relationships where possible.
update public.contract_docs d
set project_id = v.project_id
from public.contract_versions v
where d.contract_version_id = v.id
  and d.project_id is null;

update public.requirements r
set project_id = d.project_id
from public.contract_docs d
where r.contract_doc_id = d.id
  and r.project_id is null;

update public.requirements r
set project_id = v.project_id
from public.contract_versions v
where r.contract_version_id = v.id
  and r.project_id is null;

update public.provenance_links p
set project_id = r.project_id
from public.requirements r
where p.requirement_id = r.id
  and p.project_id is null;

update public.provenance_links p
set project_id = d.project_id
from public.contract_docs d
where p.contract_doc_id = d.id
  and p.project_id is null;

update public.provenance_links p
set project_id = v.project_id
from public.contract_versions v
where p.contract_version_id = v.id
  and p.project_id is null;

update public.submission_artifacts s
set project_id = v.project_id
from public.contract_versions v
where s.contract_version_id = v.id
  and s.project_id is null;

update public.audit_events a
set project_id = v.project_id
from public.contract_versions v
where a.contract_version_id = v.id
  and a.project_id is null;

-- Fail closed if required project_id cannot be inferred.
do $$
declare
  t text;
  c bigint;
  has_not_null_check boolean;
  tables text[] := array[
    'intake_turns',
    'decision_items',
    'generation_runs',
    'contract_versions',
    'contract_docs',
    'requirements',
    'provenance_links',
    'submission_artifacts',
    'audit_events'
  ];
begin
  foreach t in array tables loop
    execute format('select count(*) from public.%I where project_id is null', t) into c;
    if c = 0 then
      execute format('alter table public.%I alter column project_id set not null', t);
    else
      raise notice '%.project_id has % NULL rows; keeping nullable for legacy rows', t, c;
      select exists (
        select 1
        from pg_constraint
        where conrelid = ('public.' || t)::regclass
          and conname = t || '_project_id_not_null_check'
      ) into has_not_null_check;

      if not has_not_null_check then
        execute format(
          'alter table public.%I add constraint %I check (project_id is not null) not valid',
          t,
          t || '_project_id_not_null_check'
        );
      end if;
    end if;
  end loop;
end $$;

-- Ensure project_id FK exists on each project-scoped table.
do $$
declare
  t text;
  has_fk boolean;
  tables text[] := array[
    'intake_turns',
    'decision_items',
    'generation_runs',
    'contract_versions',
    'contract_docs',
    'requirements',
    'provenance_links',
    'submission_artifacts',
    'audit_events'
  ];
begin
  foreach t in array tables loop
    select exists (
      select 1
      from pg_constraint c
      join pg_attribute a
        on a.attrelid = c.conrelid
       and a.attnum = any(c.conkey)
      where c.conrelid = ('public.' || t)::regclass
        and c.confrelid = 'public.projects'::regclass
        and c.contype = 'f'
        and a.attname = 'project_id'
    ) into has_fk;

    if not has_fk then
      execute format(
        'alter table public.%I add constraint %I foreign key (project_id) references public.projects(id) on delete cascade not valid',
        t,
        t || '_project_id_fkey'
      );
    end if;
  end loop;
end $$;

-- decision_items drift repair and canonicalization.
alter table public.decision_items add column if not exists decision_key text;
alter table public.decision_items add column if not exists claim text;
alter table public.decision_items add column if not exists evidence_refs text[];
alter table public.decision_items add column if not exists lock_state text;
alter table public.decision_items add column if not exists created_at timestamptz default timezone('utc'::text, now());
alter table public.decision_items add column if not exists updated_at timestamptz default timezone('utc'::text, now());
alter table public.decision_items add column if not exists locked_at timestamptz;

do $$
declare
  status_udt text;
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'decision_items'
      and column_name = 'status'
      and column_default is not null
  ) then
    alter table public.decision_items
      alter column status drop default;
  end if;

  select udt_name
  into status_udt
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'decision_items'
    and column_name = 'status';

  if status_udt is null then
    alter table public.decision_items add column status public.trust_label;
  elsif status_udt <> 'trust_label' then
    alter table public.decision_items
      alter column status type public.trust_label
      using (
        case upper(coalesce(status::text, ''))
          when 'USER_SAID' then 'USER_SAID'::public.trust_label
          when 'ASSUMED' then 'ASSUMED'::public.trust_label
          when 'UNKNOWN' then 'UNKNOWN'::public.trust_label
          else 'UNKNOWN'::public.trust_label
        end
      );
  end if;

  alter table public.decision_items
    alter column status set default 'UNKNOWN'::public.trust_label;
end $$;

do $$
declare
  lock_state_udt text;
  c record;
begin
  for c in
    select conname
    from pg_constraint
    where conrelid = 'public.decision_items'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%lock_state%'
  loop
    execute format('alter table public.decision_items drop constraint if exists %I', c.conname);
  end loop;

  select udt_name
  into lock_state_udt
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'decision_items'
    and column_name = 'lock_state';

  if lock_state_udt is not null and lock_state_udt not in ('text', 'varchar', 'bpchar') then
    if exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'decision_items'
        and column_name = 'lock_state'
        and column_default is not null
    ) then
      alter table public.decision_items
        alter column lock_state drop default;
    end if;

    alter table public.decision_items
      alter column lock_state type text
      using lock_state::text;
  end if;

  alter table public.decision_items
    alter column lock_state set default 'open';
end $$;

update public.decision_items
set decision_key = 'legacy_decision_' || substr(id::text, 1, 8)
where decision_key is null
   or btrim(decision_key) = '';

with ranked as (
  select ctid, row_number() over (
    partition by project_id, cycle_no, decision_key
    order by created_at asc nulls last, id asc
  ) as rn
  from public.decision_items
)
update public.decision_items d
set decision_key = d.decision_key || '_' || ranked.rn
from ranked
where d.ctid = ranked.ctid
  and ranked.rn > 1;

update public.decision_items
set claim = 'Legacy claim requiring clarification.'
where claim is null
   or btrim(claim) = '';

update public.decision_items
set status = 'UNKNOWN'::public.trust_label
where status is null;

update public.decision_items
set evidence_refs = array['legacy:missing_evidence']::text[]
where evidence_refs is null
   or coalesce(array_length(evidence_refs, 1), 0) = 0;

update public.decision_items
set lock_state = case upper(coalesce(lock_state::text, ''))
  when 'OPEN' then 'open'
  when 'LOCKED' then 'locked'
  else 'open'
end;

update public.decision_items
set updated_at = timezone('utc'::text, now())
where updated_at is null;

update public.decision_items
set created_at = updated_at
where created_at is null;

alter table public.decision_items alter column decision_key set not null;
alter table public.decision_items alter column claim set not null;
alter table public.decision_items alter column status set not null;
alter table public.decision_items alter column evidence_refs set not null;
alter table public.decision_items alter column lock_state set not null;
alter table public.decision_items alter column updated_at set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.decision_items'::regclass
      and conname = 'decision_items_lock_state_check'
  ) then
    alter table public.decision_items
      add constraint decision_items_lock_state_check
      check (lock_state in ('open', 'locked'));
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.decision_items'::regclass
      and conname = 'decision_items_evidence_nonempty_check'
  ) then
    alter table public.decision_items
      add constraint decision_items_evidence_nonempty_check
      check (coalesce(array_length(evidence_refs, 1), 0) > 0);
  end if;
end $$;

create unique index if not exists decision_items_project_cycle_decision_key_uidx
  on public.decision_items(project_id, cycle_no, decision_key);

-- contract_versions drift repair.
alter table public.contract_versions add column if not exists created_at timestamptz default timezone('utc'::text, now());
alter table public.contract_versions add column if not exists version_number integer;
alter table public.contract_versions add column if not exists status text default 'committed';
alter table public.contract_versions add column if not exists document_count integer default 10;
alter table public.contract_versions add column if not exists committed_at timestamptz default timezone('utc'::text, now());
alter table public.contract_versions add column if not exists artifact_fingerprint text default '';

do $$
declare
  status_udt text;
  c record;
begin
  for c in
    select conname
    from pg_constraint
    where conrelid = 'public.contract_versions'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%status%'
  loop
    execute format('alter table public.contract_versions drop constraint if exists %I', c.conname);
  end loop;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'contract_versions'
      and column_name = 'status'
      and column_default is not null
  ) then
    alter table public.contract_versions
      alter column status drop default;
  end if;

  select udt_name
  into status_udt
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'contract_versions'
    and column_name = 'status';

  if status_udt is not null and status_udt not in ('text', 'varchar', 'bpchar') then
    alter table public.contract_versions
      alter column status type text
      using status::text;
  end if;

  alter table public.contract_versions
    alter column status set default 'committed';
end $$;

with ranked as (
  select id,
         row_number() over (
           partition by project_id, cycle_no
           order by created_at asc nulls last, id asc
         ) as rn
  from public.contract_versions
)
update public.contract_versions cv
set version_number = ranked.rn
from ranked
where cv.id = ranked.id
  and cv.version_number is distinct from ranked.rn;

update public.contract_versions
set status = case upper(coalesce(status::text, ''))
  when 'COMMITTED' then 'committed'
  when 'COMMIT' then 'committed'
  when 'FINAL' then 'committed'
  else 'committed'
end;

update public.contract_versions
set document_count = 10
where document_count is null;

update public.contract_versions
set committed_at = created_at
where committed_at is null;

update public.contract_versions
set artifact_fingerprint = ''
where artifact_fingerprint is null;

alter table public.contract_versions alter column version_number set not null;
alter table public.contract_versions alter column status set not null;
alter table public.contract_versions alter column document_count set not null;
alter table public.contract_versions alter column committed_at set not null;
alter table public.contract_versions alter column artifact_fingerprint set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.contract_versions'::regclass
      and conname = 'contract_versions_version_number_check'
  ) then
    alter table public.contract_versions
      add constraint contract_versions_version_number_check
      check (version_number >= 1);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.contract_versions'::regclass
      and conname = 'contract_versions_status_check'
  ) then
    alter table public.contract_versions
      add constraint contract_versions_status_check
      check (status in ('committed'));
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.contract_versions'::regclass
      and conname = 'contract_versions_document_count_check'
  ) then
    alter table public.contract_versions
      add constraint contract_versions_document_count_check
      check (document_count = 10);
  end if;
end $$;

create unique index if not exists contract_versions_project_cycle_version_uidx
  on public.contract_versions(project_id, cycle_no, version_number);

alter table public.contract_versions add column if not exists version_tuple jsonb default '{}'::jsonb;
alter table public.contract_versions add column if not exists commit_idempotency_key text;
alter table public.contract_versions add column if not exists parent_contract_version_id uuid;

update public.contract_versions
set version_tuple = '{}'::jsonb
where version_tuple is null;

alter table public.contract_versions alter column version_tuple set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.contract_versions'::regclass
      and conname = 'contract_versions_parent_contract_version_id_fkey'
  ) then
    alter table public.contract_versions
      add constraint contract_versions_parent_contract_version_id_fkey
      foreign key (parent_contract_version_id)
      references public.contract_versions(id) on delete set null not valid;
  end if;
end $$;

do $$
declare
  duplicate_commit_key_groups bigint;
begin
  select count(*) into duplicate_commit_key_groups
  from (
    select 1
    from public.contract_versions
    where commit_idempotency_key is not null
    group by project_id, cycle_no, commit_idempotency_key
    having count(*) > 1
  ) dup;

  if duplicate_commit_key_groups = 0 then
    create unique index if not exists contract_versions_commit_key_unique_idx
      on public.contract_versions(project_id, cycle_no, commit_idempotency_key)
      where commit_idempotency_key is not null;
  else
    raise notice 'Skipping contract_versions_commit_key_unique_idx due to % duplicate key groups', duplicate_commit_key_groups;
  end if;
end $$;

-- generation_runs contract expected by Edge Functions
alter table public.generation_runs add column if not exists stage text;
alter table public.generation_runs add column if not exists status text;
alter table public.generation_runs add column if not exists details jsonb default '{}'::jsonb;
alter table public.generation_runs add column if not exists run_identity text;
alter table public.generation_runs add column if not exists input_fingerprint text;
alter table public.generation_runs add column if not exists output_fingerprint text;
alter table public.generation_runs add column if not exists version_tuple jsonb default '{}'::jsonb;
alter table public.generation_runs add column if not exists correlation_ref text;
alter table public.generation_runs add column if not exists attempt integer default 1;
alter table public.generation_runs add column if not exists created_at timestamptz default timezone('utc'::text, now());
alter table public.generation_runs add column if not exists ended_at timestamptz;

do $$
declare
  stage_udt text;
  status_udt text;
  c record;
begin
  for c in
    select conname
    from pg_constraint
    where conrelid = 'public.generation_runs'::regclass
      and contype = 'c'
      and (
        pg_get_constraintdef(oid) ilike '%status%'
        or pg_get_constraintdef(oid) ilike '%stage%'
      )
  loop
    execute format('alter table public.generation_runs drop constraint if exists %I', c.conname);
  end loop;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'generation_runs'
      and column_name = 'stage'
      and column_default is not null
  ) then
    alter table public.generation_runs
      alter column stage drop default;
  end if;

  select udt_name
  into stage_udt
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'generation_runs'
    and column_name = 'stage';

  if stage_udt is not null and stage_udt not in ('text', 'varchar', 'bpchar') then
    alter table public.generation_runs
      alter column stage type text
      using stage::text;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'generation_runs'
      and column_name = 'status'
      and column_default is not null
  ) then
    alter table public.generation_runs
      alter column status drop default;
  end if;

  select udt_name
  into status_udt
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'generation_runs'
    and column_name = 'status';

  if status_udt is not null and status_udt not in ('text', 'varchar', 'bpchar') then
    alter table public.generation_runs
      alter column status type text
      using status::text;
  end if;

  alter table public.generation_runs alter column stage set default 'DISCOVERY';
  alter table public.generation_runs alter column status set default 'started';
end $$;

update public.generation_runs
set stage = case upper(coalesce(stage::text, ''))
      when 'DISCOVERY' then 'DISCOVERY'
      when 'EXTRACTION' then 'EXTRACTION'
      when 'AMBIGUITY' then 'AMBIGUITY'
      when 'CONFIRMATION' then 'CONFIRMATION'
      when 'ASSEMBLY' then 'ASSEMBLY'
      when 'CONSISTENCY' then 'CONSISTENCY'
      when 'COMMIT' then 'COMMIT'
      else 'DISCOVERY'
    end,
    status = case upper(coalesce(status::text, ''))
      when 'STARTED' then 'started'
      when 'RUNNING' then 'started'
      when 'IN_PROGRESS' then 'started'
      when 'OPEN' then 'started'
      when 'PASSED' then 'passed'
      when 'SUCCESS' then 'passed'
      when 'SUCCEEDED' then 'passed'
      when 'COMPLETED' then 'passed'
      when 'DONE' then 'passed'
      when 'FAILED' then 'failed'
      when 'FAIL' then 'failed'
      when 'ERROR' then 'failed'
      when 'FAILURE' then 'failed'
      else 'started'
    end,
    details = coalesce(details, '{}'::jsonb),
    version_tuple = coalesce(version_tuple, '{}'::jsonb),
    attempt = coalesce(attempt, 1),
    created_at = coalesce(created_at, timezone('utc'::text, now()));

alter table public.generation_runs alter column stage set not null;
alter table public.generation_runs alter column status set not null;
alter table public.generation_runs alter column details set not null;
alter table public.generation_runs alter column version_tuple set not null;
alter table public.generation_runs alter column attempt set not null;
alter table public.generation_runs alter column created_at set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.generation_runs'::regclass
      and conname = 'generation_runs_stage_check'
  ) then
    alter table public.generation_runs
      add constraint generation_runs_stage_check
      check (stage in ('DISCOVERY','EXTRACTION','AMBIGUITY','CONFIRMATION','ASSEMBLY','CONSISTENCY','COMMIT'));
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.generation_runs'::regclass
      and conname = 'generation_runs_status_check'
  ) then
    alter table public.generation_runs
      add constraint generation_runs_status_check
      check (status in ('started','passed','failed'));
  end if;
end $$;

create index if not exists generation_runs_project_cycle_stage_idx
  on public.generation_runs(project_id, cycle_no, stage, created_at desc);

do $$
declare
  duplicate_run_identity_groups bigint;
begin
  select count(*) into duplicate_run_identity_groups
  from (
    select 1
    from public.generation_runs
    where run_identity is not null
    group by project_id, cycle_no, stage, run_identity
    having count(*) > 1
  ) dup;

  if duplicate_run_identity_groups = 0 then
    create unique index if not exists generation_runs_identity_unique_idx
      on public.generation_runs(project_id, cycle_no, stage, run_identity)
      where run_identity is not null;
  else
    raise notice 'Skipping generation_runs_identity_unique_idx due to % duplicate key groups', duplicate_run_identity_groups;
  end if;
end $$;

-- contract_docs columns required by submit/generate
alter table public.contract_docs add column if not exists word_count integer default 1;
alter table public.contract_docs add column if not exists builder_notes_count integer default 4;
alter table public.contract_docs add column if not exists is_complete boolean default false;
alter table public.contract_docs add column if not exists created_at timestamptz default timezone('utc'::text, now());

update public.contract_docs
set word_count = coalesce(nullif(word_count, 0), 1),
    builder_notes_count = coalesce(builder_notes_count, 4),
    is_complete = coalesce(is_complete, false),
    created_at = coalesce(created_at, timezone('utc'::text, now()));

alter table public.contract_docs alter column word_count set not null;
alter table public.contract_docs alter column builder_notes_count set not null;
alter table public.contract_docs alter column is_complete set not null;
alter table public.contract_docs alter column created_at set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.contract_docs'::regclass
      and conname = 'contract_docs_role_id_check'
  ) then
    alter table public.contract_docs
      add constraint contract_docs_role_id_check
      check (role_id between 1 and 10);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.contract_docs'::regclass
      and conname = 'contract_docs_word_count_check'
  ) then
    alter table public.contract_docs
      add constraint contract_docs_word_count_check
      check (word_count > 0);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.contract_docs'::regclass
      and conname = 'contract_docs_builder_notes_count_check'
  ) then
    alter table public.contract_docs
      add constraint contract_docs_builder_notes_count_check
      check (builder_notes_count between 3 and 6);
  end if;
end $$;

do $$
declare
  duplicate_doc_role_groups bigint;
begin
  select count(*) into duplicate_doc_role_groups
  from (
    select 1
    from public.contract_docs
    group by contract_version_id, role_id
    having count(*) > 1
  ) dup;

  if duplicate_doc_role_groups = 0 then
    create unique index if not exists contract_docs_version_role_idx
      on public.contract_docs(contract_version_id, role_id);
  else
    raise notice 'Skipping contract_docs_version_role_idx due to % duplicate key groups', duplicate_doc_role_groups;
  end if;
end $$;

do $$
declare
  duplicate_doc_role_groups bigint;
begin
  select count(*) into duplicate_doc_role_groups
  from (
    select 1
    from public.contract_docs
    group by contract_version_id, role_id
    having count(*) > 1
  ) dup;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.contract_docs'::regclass
      and conname = 'contract_docs_contract_version_role_unique'
  ) then
    if duplicate_doc_role_groups = 0 then
      alter table public.contract_docs
        add constraint contract_docs_contract_version_role_unique
        unique (contract_version_id, role_id);
    else
      raise notice 'Skipping contract_docs_contract_version_role_unique due to % duplicate key groups', duplicate_doc_role_groups;
    end if;
  end if;
end $$;

-- requirements columns required by submit/generate
alter table public.requirements add column if not exists requirement_index integer;
alter table public.requirements add column if not exists requirement_text text;
alter table public.requirements add column if not exists trust_label public.trust_label;
alter table public.requirements add column if not exists status text default 'active';
alter table public.requirements add column if not exists created_at timestamptz default timezone('utc'::text, now());

do $$
declare
  status_udt text;
  trust_udt text;
  c record;
begin
  for c in
    select conname
    from pg_constraint
    where conrelid = 'public.requirements'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%status%'
  loop
    execute format('alter table public.requirements drop constraint if exists %I', c.conname);
  end loop;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'requirements'
      and column_name = 'status'
      and column_default is not null
  ) then
    alter table public.requirements
      alter column status drop default;
  end if;

  select udt_name
  into status_udt
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'requirements'
    and column_name = 'status';

  if status_udt is not null and status_udt not in ('text', 'varchar', 'bpchar') then
    alter table public.requirements
      alter column status type text
      using status::text;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'requirements'
      and column_name = 'trust_label'
      and column_default is not null
  ) then
    alter table public.requirements
      alter column trust_label drop default;
  end if;

  select udt_name
  into trust_udt
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'requirements'
    and column_name = 'trust_label';

  if trust_udt is not null and trust_udt <> 'trust_label' then
    alter table public.requirements
      alter column trust_label type public.trust_label
      using (
        case upper(coalesce(trust_label::text, ''))
          when 'USER_SAID' then 'USER_SAID'::public.trust_label
          when 'ASSUMED' then 'ASSUMED'::public.trust_label
          when 'UNKNOWN' then 'UNKNOWN'::public.trust_label
          else 'UNKNOWN'::public.trust_label
        end
      );
  end if;

  alter table public.requirements
    alter column trust_label set default 'UNKNOWN'::public.trust_label;

  alter table public.requirements
    alter column status set default 'active';
end $$;

update public.requirements
set requirement_index = coalesce(requirement_index, 0),
    requirement_text = coalesce(nullif(btrim(requirement_text), ''), 'Unspecified requirement.'),
    trust_label = coalesce(trust_label, 'UNKNOWN'::public.trust_label),
    status = case upper(coalesce(status::text, ''))
      when 'ACTIVE' then 'active'
      when 'OPEN' then 'active'
      else 'active'
    end,
    created_at = coalesce(created_at, timezone('utc'::text, now()));

alter table public.requirements alter column requirement_index set not null;
alter table public.requirements alter column requirement_text set not null;
alter table public.requirements alter column trust_label set not null;
alter table public.requirements alter column status set not null;
alter table public.requirements alter column created_at set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.requirements'::regclass
      and conname = 'requirements_status_check'
  ) then
    alter table public.requirements
      add constraint requirements_status_check
      check (status in ('active'));
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.requirements'::regclass
      and conname = 'requirements_role_id_check'
  ) then
    alter table public.requirements
      add constraint requirements_role_id_check
      check (role_id between 1 and 10);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.requirements'::regclass
      and conname = 'requirements_requirement_index_check'
  ) then
    alter table public.requirements
      add constraint requirements_requirement_index_check
      check (requirement_index >= 0);
  end if;
end $$;

do $$
declare
  duplicate_requirement_groups bigint;
begin
  select count(*) into duplicate_requirement_groups
  from (
    select 1
    from public.requirements
    group by contract_doc_id, requirement_index
    having count(*) > 1
  ) dup;

  if duplicate_requirement_groups = 0 then
    create unique index if not exists requirements_doc_requirement_index_uidx
      on public.requirements(contract_doc_id, requirement_index);
  else
    raise notice 'Skipping requirements_doc_requirement_index_uidx due to % duplicate key groups', duplicate_requirement_groups;
  end if;
end $$;

do $$
declare
  duplicate_requirement_groups bigint;
begin
  select count(*) into duplicate_requirement_groups
  from (
    select 1
    from public.requirements
    group by contract_doc_id, requirement_index
    having count(*) > 1
  ) dup;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.requirements'::regclass
      and conname = 'requirements_contract_doc_requirement_index_unique'
  ) then
    if duplicate_requirement_groups = 0 then
      alter table public.requirements
        add constraint requirements_contract_doc_requirement_index_unique
        unique (contract_doc_id, requirement_index);
    else
      raise notice 'Skipping requirements_contract_doc_requirement_index_unique due to % duplicate key groups', duplicate_requirement_groups;
    end if;
  end if;
end $$;

create index if not exists requirements_version_role_idx
  on public.requirements(contract_version_id, role_id, requirement_index);

-- provenance_links columns required by submit/generate
alter table public.provenance_links add column if not exists source_type text;
alter table public.provenance_links add column if not exists source_id text;
alter table public.provenance_links add column if not exists pointer text;
alter table public.provenance_links add column if not exists created_at timestamptz default timezone('utc'::text, now());

do $$
declare
  source_type_udt text;
  c record;
begin
  for c in
    select conname
    from pg_constraint
    where conrelid = 'public.provenance_links'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%source_type%'
  loop
    execute format('alter table public.provenance_links drop constraint if exists %I', c.conname);
  end loop;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'provenance_links'
      and column_name = 'source_type'
      and column_default is not null
  ) then
    alter table public.provenance_links
      alter column source_type drop default;
  end if;

  select udt_name
  into source_type_udt
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'provenance_links'
    and column_name = 'source_type';

  if source_type_udt is not null and source_type_udt not in ('text', 'varchar', 'bpchar') then
    alter table public.provenance_links
      alter column source_type type text
      using source_type::text;
  end if;
end $$;

update public.provenance_links
set source_type = case upper(coalesce(source_type::text, ''))
      when 'INTAKE_TURN' then 'INTAKE_TURN'
      when 'DECISION_ITEM' then 'DECISION_ITEM'
      else 'INTAKE_TURN'
    end,
    pointer = coalesce(nullif(btrim(pointer), ''), 'legacy:missing_pointer'),
    created_at = coalesce(created_at, timezone('utc'::text, now()));

alter table public.provenance_links alter column source_type set not null;
alter table public.provenance_links alter column pointer set not null;
alter table public.provenance_links alter column created_at set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.provenance_links'::regclass
      and conname = 'provenance_links_source_type_check'
  ) then
    alter table public.provenance_links
      add constraint provenance_links_source_type_check
      check (source_type in ('INTAKE_TURN','DECISION_ITEM'));
  end if;
end $$;

create index if not exists provenance_links_requirement_idx
  on public.provenance_links(requirement_id);

-- submission_artifacts contract expected by submit-run
alter table public.submission_artifacts add column if not exists user_id uuid;
alter table public.submission_artifacts add column if not exists bucket text;
alter table public.submission_artifacts add column if not exists storage_path text;
alter table public.submission_artifacts add column if not exists manifest jsonb;
alter table public.submission_artifacts add column if not exists submitted_at timestamptz default timezone('utc'::text, now());
alter table public.submission_artifacts add column if not exists created_at timestamptz default timezone('utc'::text, now());

update public.submission_artifacts sa
set user_id = p.owner_user_id
from public.projects p
where sa.project_id = p.id
  and sa.user_id is null;

update public.submission_artifacts
set bucket = coalesce(nullif(btrim(bucket), ''), 'shipfirst-submissions'),
    storage_path = coalesce(nullif(btrim(storage_path), ''), 'legacy/missing-path.zip'),
    manifest = coalesce(manifest, '{}'::jsonb),
    submitted_at = coalesce(submitted_at, timezone('utc'::text, now())),
    created_at = coalesce(created_at, timezone('utc'::text, now()));

do $$
declare
  submission_user_null_count bigint;
begin
  select count(*) into submission_user_null_count
  from public.submission_artifacts
  where user_id is null;

  if submission_user_null_count = 0 then
    alter table public.submission_artifacts alter column user_id set not null;
  else
    raise notice 'submission_artifacts.user_id has % NULL rows; keeping nullable for legacy rows', submission_user_null_count;
    if not exists (
      select 1
      from pg_constraint
      where conrelid = 'public.submission_artifacts'::regclass
        and conname = 'submission_artifacts_user_id_not_null_check'
    ) then
      alter table public.submission_artifacts
        add constraint submission_artifacts_user_id_not_null_check
        check (user_id is not null) not valid;
    end if;
  end if;
end $$;

alter table public.submission_artifacts alter column bucket set not null;
alter table public.submission_artifacts alter column storage_path set not null;
alter table public.submission_artifacts alter column manifest set not null;
alter table public.submission_artifacts alter column submitted_at set not null;
alter table public.submission_artifacts alter column created_at set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.submission_artifacts'::regclass
      and conname = 'submission_artifacts_user_id_fkey'
  ) then
    alter table public.submission_artifacts
      add constraint submission_artifacts_user_id_fkey
      foreign key (user_id) references auth.users(id) on delete cascade not valid;
  end if;
end $$;

do $$
declare
  duplicate_submission_groups bigint;
begin
  select count(*) into duplicate_submission_groups
  from (
    select 1
    from public.submission_artifacts
    group by contract_version_id
    having count(*) > 1
  ) dup;

  if duplicate_submission_groups = 0 then
    create unique index if not exists submission_artifacts_contract_version_uidx
      on public.submission_artifacts(contract_version_id);
  else
    raise notice 'Skipping submission_artifacts_contract_version_uidx due to % duplicate key groups', duplicate_submission_groups;
  end if;
end $$;

do $$
declare
  duplicate_submission_groups bigint;
begin
  select count(*) into duplicate_submission_groups
  from (
    select 1
    from public.submission_artifacts
    group by contract_version_id
    having count(*) > 1
  ) dup;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.submission_artifacts'::regclass
      and conname = 'submission_artifacts_contract_version_unique'
  ) then
    if duplicate_submission_groups = 0 then
      alter table public.submission_artifacts
        add constraint submission_artifacts_contract_version_unique
        unique (contract_version_id);
    else
      raise notice 'Skipping submission_artifacts_contract_version_unique due to % duplicate key groups', duplicate_submission_groups;
    end if;
  end if;
end $$;

create index if not exists submission_artifacts_project_cycle_created_idx
  on public.submission_artifacts(project_id, cycle_no, created_at desc);

-- audit_events required columns
alter table public.audit_events add column if not exists actor_type text;
alter table public.audit_events add column if not exists actor_id uuid;
alter table public.audit_events add column if not exists event_type text;
alter table public.audit_events add column if not exists payload jsonb default '{}'::jsonb;
alter table public.audit_events add column if not exists created_at timestamptz default timezone('utc'::text, now());

do $$
declare
  actor_type_udt text;
  c record;
begin
  for c in
    select conname
    from pg_constraint
    where conrelid = 'public.audit_events'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%actor_type%'
  loop
    execute format('alter table public.audit_events drop constraint if exists %I', c.conname);
  end loop;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'audit_events'
      and column_name = 'actor_type'
      and column_default is not null
  ) then
    alter table public.audit_events
      alter column actor_type drop default;
  end if;

  select udt_name
  into actor_type_udt
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'audit_events'
    and column_name = 'actor_type';

  if actor_type_udt is not null and actor_type_udt not in ('text', 'varchar', 'bpchar') then
    alter table public.audit_events
      alter column actor_type type text
      using actor_type::text;
  end if;
end $$;

update public.audit_events
set actor_type = case upper(coalesce(actor_type::text, ''))
      when 'USER' then 'USER'
      when 'SYSTEM' then 'SYSTEM'
      when 'SERVICE' then 'SERVICE'
      else 'SYSTEM'
    end,
    event_type = coalesce(nullif(btrim(event_type), ''), 'legacy.event'),
    payload = coalesce(payload, '{}'::jsonb),
    created_at = coalesce(created_at, timezone('utc'::text, now()));

alter table public.audit_events alter column actor_type set not null;
alter table public.audit_events alter column event_type set not null;
alter table public.audit_events alter column payload set not null;
alter table public.audit_events alter column created_at set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.audit_events'::regclass
      and conname = 'audit_events_actor_type_check'
  ) then
    alter table public.audit_events
      add constraint audit_events_actor_type_check
      check (actor_type in ('USER','SYSTEM','SERVICE'));
  end if;
end $$;

create index if not exists audit_events_project_cycle_created_idx
  on public.audit_events(project_id, cycle_no, created_at desc);

-- Append-only + timestamp triggers.
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

-- Strict RLS reset.
alter table public.projects enable row level security;
alter table public.intake_turns enable row level security;
alter table public.decision_items enable row level security;
alter table public.generation_runs enable row level security;
alter table public.contract_versions enable row level security;
alter table public.contract_docs enable row level security;
alter table public.requirements enable row level security;
alter table public.provenance_links enable row level security;
alter table public.submission_artifacts enable row level security;
alter table public.audit_events enable row level security;

do $$
declare
  p record;
begin
  for p in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'projects',
        'intake_turns',
        'decision_items',
        'generation_runs',
        'contract_versions',
        'contract_docs',
        'requirements',
        'provenance_links',
        'submission_artifacts',
        'audit_events'
      )
  loop
    execute format('drop policy if exists %I on %I.%I', p.policyname, p.schemaname, p.tablename);
  end loop;
end $$;

create policy projects_select_own on public.projects
for select to authenticated
using (owner_user_id = auth.uid());

create policy projects_insert_own on public.projects
for insert to authenticated
with check (owner_user_id = auth.uid());

create policy projects_update_own on public.projects
for update to authenticated
using (owner_user_id = auth.uid())
with check (owner_user_id = auth.uid());

create policy intake_turns_select_own on public.intake_turns
for select to authenticated
using (public.user_owns_project(project_id));

create policy intake_turns_insert_own on public.intake_turns
for insert to authenticated
with check (public.user_owns_project(project_id));

create policy decision_items_select_own on public.decision_items
for select to authenticated
using (public.user_owns_project(project_id));

create policy decision_items_insert_own on public.decision_items
for insert to authenticated
with check (public.user_owns_project(project_id));

create policy decision_items_update_own on public.decision_items
for update to authenticated
using (public.user_owns_project(project_id))
with check (public.user_owns_project(project_id));

create policy generation_runs_select_own on public.generation_runs
for select to authenticated
using (public.user_owns_project(project_id));

create policy contract_versions_select_own on public.contract_versions
for select to authenticated
using (public.user_owns_project(project_id));

create policy contract_docs_select_own on public.contract_docs
for select to authenticated
using (public.user_owns_project(project_id));

create policy requirements_select_own on public.requirements
for select to authenticated
using (public.user_owns_project(project_id));

create policy provenance_links_select_own on public.provenance_links
for select to authenticated
using (public.user_owns_project(project_id));

create policy submission_artifacts_select_own on public.submission_artifacts
for select to authenticated
using (public.user_owns_project(project_id));

create policy audit_events_select_own on public.audit_events
for select to authenticated
using (public.user_owns_project(project_id));

insert into storage.buckets (id, name, public)
values ('shipfirst-submissions', 'shipfirst-submissions', false)
on conflict (id) do update
set public = excluded.public;

commit;
