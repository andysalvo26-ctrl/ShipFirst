-- Drift safety for legacy public.decision_items."key" NOT NULL constraint.
-- Canonical schema uses decision_key, but some deployed schemas still enforce "key".
-- This migration keeps NOT NULL and ensures inserts succeed by setting a safe default.

create extension if not exists pgcrypto;

do $$
declare
  key_data_type text;
begin
  -- 1) Table guard.
  if to_regclass('public.decision_items') is null then
    raise notice 'Skipping decision_items.key safety migration: public.decision_items does not exist.';
    return;
  end if;

  -- 2) Column guard.
  select c.data_type
  into key_data_type
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'decision_items'
    and c.column_name = 'key';

  if key_data_type is null then
    raise notice 'Skipping decision_items.key safety migration: column "key" does not exist.';
    return;
  end if;

  -- 3/4) Text-like columns: set default + backfill null/empty.
  if key_data_type in ('text', 'character varying', 'character') then
    execute $sql$
      alter table public.decision_items
      alter column "key" set default gen_random_uuid()::text
    $sql$;

    execute $sql$
      update public.decision_items
      set "key" = gen_random_uuid()::text
      where "key" is null
         or btrim("key") = ''
    $sql$;

    return;
  end if;

  -- 5) UUID columns: set default + backfill nulls.
  if key_data_type = 'uuid' then
    execute $sql$
      alter table public.decision_items
      alter column "key" set default gen_random_uuid()
    $sql$;

    execute $sql$
      update public.decision_items
      set "key" = gen_random_uuid()
      where "key" is null
    $sql$;

    return;
  end if;

  raise notice 'Skipping decision_items.key safety migration: unsupported data_type=%', key_data_type;
end $$;
