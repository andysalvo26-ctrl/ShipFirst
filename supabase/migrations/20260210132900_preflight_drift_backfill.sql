-- Preflight drift backfill.
-- Purpose: make canonical migrations safe on remote DBs where tables already exist
-- with partial/legacy column sets. This migration is additive-only.
--
-- Rules:
-- - Only add missing columns on existing tables.
-- - Do not drop/rename/alter existing columns here.
-- - Keep types strict when obvious; otherwise permissive (text/jsonb/timestamptz).
-- - Do not enforce NOT NULL/constraints here (canonical/hardening migrations handle that).

-- projects: required by canonical indexes, policies, iOS run listing, edge ownership checks.
do $$
begin
  if to_regclass('public.projects') is not null then
    alter table public.projects add column if not exists owner_user_id uuid;
    alter table public.projects add column if not exists name text;
    alter table public.projects add column if not exists active_cycle_no integer;
    alter table public.projects add column if not exists created_at timestamptz;
    alter table public.projects add column if not exists updated_at timestamptz;
  end if;
end $$;

-- intake_turns: required by client writes, edge reads, canonical indexes.
do $$
begin
  if to_regclass('public.intake_turns') is not null then
    alter table public.intake_turns add column if not exists project_id uuid;
    alter table public.intake_turns add column if not exists cycle_no integer;
    alter table public.intake_turns add column if not exists actor_type text;
    alter table public.intake_turns add column if not exists turn_index integer;
    alter table public.intake_turns add column if not exists raw_text text;
    alter table public.intake_turns add column if not exists created_at timestamptz;
  end if;
end $$;

-- decision_items: required by client upsert/select, edge reads/inserts, canonical indexes.
do $$
begin
  if to_regclass('public.decision_items') is not null then
    alter table public.decision_items add column if not exists project_id uuid;
    alter table public.decision_items add column if not exists cycle_no integer;
    alter table public.decision_items add column if not exists decision_key text;
    alter table public.decision_items add column if not exists claim text;
    -- Status intentionally text in preflight; canonical/hardening migrations can tighten to enum.
    alter table public.decision_items add column if not exists status text;
    alter table public.decision_items add column if not exists evidence_refs text[];
    alter table public.decision_items add column if not exists lock_state text;
    alter table public.decision_items add column if not exists locked_at timestamptz;
    alter table public.decision_items add column if not exists created_at timestamptz;
    alter table public.decision_items add column if not exists updated_at timestamptz;
  end if;
end $$;

-- generation_runs: required by canonical indexes and generate-docs stage logging.
do $$
begin
  if to_regclass('public.generation_runs') is not null then
    alter table public.generation_runs add column if not exists project_id uuid;
    alter table public.generation_runs add column if not exists cycle_no integer;
    alter table public.generation_runs add column if not exists stage text;
    alter table public.generation_runs add column if not exists status text;
    alter table public.generation_runs add column if not exists details jsonb;
    alter table public.generation_runs add column if not exists run_identity text;
    alter table public.generation_runs add column if not exists input_fingerprint text;
    alter table public.generation_runs add column if not exists output_fingerprint text;
    alter table public.generation_runs add column if not exists version_tuple jsonb;
    alter table public.generation_runs add column if not exists correlation_ref text;
    alter table public.generation_runs add column if not exists attempt integer;
    alter table public.generation_runs add column if not exists created_at timestamptz;
    alter table public.generation_runs add column if not exists ended_at timestamptz;
  end if;
end $$;

-- contract_versions: required by iOS queries, edge generate/submit, canonical indexes.
do $$
begin
  if to_regclass('public.contract_versions') is not null then
    alter table public.contract_versions add column if not exists project_id uuid;
    alter table public.contract_versions add column if not exists cycle_no integer;
    alter table public.contract_versions add column if not exists version_number integer;
    alter table public.contract_versions add column if not exists status text;
    alter table public.contract_versions add column if not exists document_count integer;
    alter table public.contract_versions add column if not exists version_tuple jsonb;
    alter table public.contract_versions add column if not exists artifact_fingerprint text;
    alter table public.contract_versions add column if not exists commit_idempotency_key text;
    alter table public.contract_versions add column if not exists parent_contract_version_id uuid;
    alter table public.contract_versions add column if not exists committed_at timestamptz;
    alter table public.contract_versions add column if not exists created_at timestamptz;
  end if;
end $$;

-- contract_docs: required by review and submit paths, canonical indexes.
do $$
begin
  if to_regclass('public.contract_docs') is not null then
    alter table public.contract_docs add column if not exists project_id uuid;
    alter table public.contract_docs add column if not exists cycle_no integer;
    alter table public.contract_docs add column if not exists contract_version_id uuid;
    alter table public.contract_docs add column if not exists role_id integer;
    alter table public.contract_docs add column if not exists title text;
    alter table public.contract_docs add column if not exists body text;
    alter table public.contract_docs add column if not exists is_complete boolean;
    alter table public.contract_docs add column if not exists word_count integer;
    alter table public.contract_docs add column if not exists builder_notes_count integer;
    alter table public.contract_docs add column if not exists created_at timestamptz;
  end if;
end $$;

-- requirements: required by review and submit paths, canonical indexes.
do $$
begin
  if to_regclass('public.requirements') is not null then
    alter table public.requirements add column if not exists project_id uuid;
    alter table public.requirements add column if not exists cycle_no integer;
    alter table public.requirements add column if not exists contract_version_id uuid;
    alter table public.requirements add column if not exists contract_doc_id uuid;
    alter table public.requirements add column if not exists role_id integer;
    alter table public.requirements add column if not exists requirement_index integer;
    alter table public.requirements add column if not exists requirement_text text;
    -- trust_label intentionally permissive here to avoid enum drift failures pre-canonical.
    alter table public.requirements add column if not exists trust_label text;
    alter table public.requirements add column if not exists status text;
    alter table public.requirements add column if not exists acceptance_criteria text;
    alter table public.requirements add column if not exists success_measure text;
    alter table public.requirements add column if not exists priority_level text;
    alter table public.requirements add column if not exists created_at timestamptz;
  end if;
end $$;

-- provenance_links: required by review/submit and canonical indexes.
do $$
begin
  if to_regclass('public.provenance_links') is not null then
    alter table public.provenance_links add column if not exists project_id uuid;
    alter table public.provenance_links add column if not exists cycle_no integer;
    alter table public.provenance_links add column if not exists contract_version_id uuid;
    alter table public.provenance_links add column if not exists contract_doc_id uuid;
    alter table public.provenance_links add column if not exists requirement_id uuid;
    alter table public.provenance_links add column if not exists source_type text;
    alter table public.provenance_links add column if not exists source_id text;
    alter table public.provenance_links add column if not exists pointer text;
    alter table public.provenance_links add column if not exists created_at timestamptz;
  end if;
end $$;

-- submission_artifacts: required by submit function and runs listing.
do $$
begin
  if to_regclass('public.submission_artifacts') is not null then
    alter table public.submission_artifacts add column if not exists project_id uuid;
    alter table public.submission_artifacts add column if not exists cycle_no integer;
    alter table public.submission_artifacts add column if not exists contract_version_id uuid;
    alter table public.submission_artifacts add column if not exists user_id uuid;
    alter table public.submission_artifacts add column if not exists bucket text;
    alter table public.submission_artifacts add column if not exists storage_path text;
    alter table public.submission_artifacts add column if not exists manifest jsonb;
    alter table public.submission_artifacts add column if not exists submitted_at timestamptz;
    alter table public.submission_artifacts add column if not exists created_at timestamptz;
  end if;
end $$;

-- audit_events: required by canonical indexes and edge audit inserts.
do $$
begin
  if to_regclass('public.audit_events') is not null then
    alter table public.audit_events add column if not exists project_id uuid;
    alter table public.audit_events add column if not exists cycle_no integer;
    alter table public.audit_events add column if not exists contract_version_id uuid;
    alter table public.audit_events add column if not exists actor_type text;
    alter table public.audit_events add column if not exists actor_id uuid;
    alter table public.audit_events add column if not exists event_type text;
    alter table public.audit_events add column if not exists payload jsonb;
    alter table public.audit_events add column if not exists created_at timestamptz;
  end if;
end $$;
