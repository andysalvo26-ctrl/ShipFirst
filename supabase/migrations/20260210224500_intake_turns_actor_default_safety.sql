-- Drift safety for legacy intake_turns.actor column.
-- Canonical schema uses intake_turns.actor_type, but some environments still enforce
-- NOT NULL on intake_turns.actor. Keep NOT NULL and set a safe USER default.

do $$
declare
  actor_udt text;
  actor_data_type text;
begin
  if to_regclass('public.intake_turns') is null then
    return;
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'intake_turns'
      and column_name = 'actor'
  ) then
    return;
  end if;

  select c.udt_name, c.data_type
  into actor_udt, actor_data_type
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'intake_turns'
    and c.column_name = 'actor';

  if actor_udt in ('text', 'varchar', 'bpchar')
     or actor_data_type in ('text', 'character varying', 'character') then
    execute 'alter table public.intake_turns alter column actor set default ''USER''';
    execute 'update public.intake_turns set actor = ''USER'' where actor is null';
    return;
  end if;

  if exists (
    select 1
    from pg_type t
    join pg_enum e on e.enumtypid = t.oid
    where t.typname = actor_udt
      and e.enumlabel = 'USER'
  ) then
    execute 'alter table public.intake_turns alter column actor set default ''USER''';
    execute 'update public.intake_turns set actor = ''USER'' where actor is null';
    return;
  end if;

  if exists (
    select 1
    from pg_type t
    join pg_enum e on e.enumtypid = t.oid
    where t.typname = actor_udt
      and e.enumlabel = 'user'
  ) then
    execute 'alter table public.intake_turns alter column actor set default ''user''';
    execute 'update public.intake_turns set actor = ''user'' where actor is null';
  end if;
end $$;
