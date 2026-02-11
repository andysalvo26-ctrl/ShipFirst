#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_VERIFY_SCRIPT="${SCRIPT_DIR}/verify_interview_engine_contract.sh"

on_error() {
  local exit_code="$?"
  echo "verify_db_contract: failed (exit=${exit_code})" >&2
  exit "${exit_code}"
}
trap on_error ERR

if [[ -f "${ENGINE_VERIFY_SCRIPT}" ]]; then
  bash "${ENGINE_VERIFY_SCRIPT}"
else
  echo "warn: ${ENGINE_VERIFY_SCRIPT} not found; skipping interview engine behavior contract checks"
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "error: psql is required" >&2
  exit 1
fi

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "error: DATABASE_URL is required (export it or prefix the command)." >&2
  exit 1
fi

sanitize_db_url_for_pgpassword() {
  # If PGPASSWORD is provided, remove any inline password from DATABASE_URL so
  # special characters do not need URL-encoding inside the URI.
  # Example:
  #   postgresql://user:bad@chars@host:5432/db -> postgresql://user@host:5432/db
  sed -E 's#^(postgres(ql)?://[^:/@]+):[^@]*@#\1@#'
}

PSQL_DATABASE_URL="${DATABASE_URL}"
if [[ -n "${PGPASSWORD:-}" ]]; then
  PSQL_DATABASE_URL="$(printf '%s' "${DATABASE_URL}" | sanitize_db_url_for_pgpassword)"
elif [[ "${DATABASE_URL}" =~ ^postgres(ql)?://[^[:space:]]+:[^[:space:]]+@ ]]; then
  echo "warn: DATABASE_URL contains an inline password and PGPASSWORD is not set." >&2
  echo "warn: If auth fails, export PGPASSWORD and use a DATABASE_URL without password." >&2
fi

run_optional_supabase_diff() {
  if ! command -v supabase >/dev/null 2>&1; then
    echo "info: supabase CLI not found; skipping optional db diff"
    return 0
  fi

  if ! command -v docker >/dev/null 2>&1; then
    echo "warn: docker not found; skipping optional supabase db diff"
    return 0
  fi

  if ! docker info >/dev/null 2>&1; then
    echo "warn: docker is not running; skipping optional supabase db diff"
    return 0
  fi

  local diff_out diff_err
  diff_out="$(mktemp -t shipfirst_db_diff.XXXXXX.sql)"
  diff_err="$(mktemp -t shipfirst_db_diff.XXXXXX.err)"

  echo "info: running optional supabase db diff"
  if ! supabase db diff --schema public >"${diff_out}" 2>"${diff_err}"; then
    echo "warn: supabase db diff failed; continuing with psql contract checks"
    sed -n '1,40p' "${diff_err}" >&2 || true
  else
    echo "info: supabase db diff completed"
  fi

  rm -f "${diff_out}" "${diff_err}"
}

if command -v supabase >/dev/null 2>&1; then
  run_optional_supabase_diff
else
  echo "info: supabase CLI not found; skipping optional db diff"
fi

echo "info: running psql contract checks"
psql "${PSQL_DATABASE_URL}" -v ON_ERROR_STOP=1 <<'SQL'
do $$
declare
  missing text;
begin
  with required(table_name, column_name) as (
    values
      ('projects', 'id'),
      ('projects', 'owner_user_id'),
      ('projects', 'name'),
      ('intake_turns', 'project_id'),
      ('intake_turns', 'cycle_no'),
      ('intake_turns', 'turn_index'),
      ('intake_turns', 'raw_text'),
      ('decision_items', 'project_id'),
      ('decision_items', 'cycle_no'),
      ('decision_items', 'decision_key'),
      ('decision_items', 'claim'),
      ('decision_items', 'status'),
      ('decision_items', 'decision_state'),
      ('decision_items', 'evidence_refs'),
      ('decision_items', 'lock_state'),
      ('decision_items', 'has_conflict'),
      ('decision_items', 'conflict_key'),
      ('decision_items', 'confirmed_by_turn_id'),
      ('decision_items', 'hypothesis_rationale'),
      ('artifact_inputs', 'project_id'),
      ('artifact_inputs', 'cycle_no'),
      ('artifact_inputs', 'artifact_type'),
      ('artifact_inputs', 'artifact_ref'),
      ('artifact_inputs', 'ingest_state'),
      ('artifact_inputs', 'verification_state'),
      ('artifact_inputs', 'created_at'),
      ('artifact_inputs', 'updated_at'),
      ('interview_turn_state', 'project_id'),
      ('interview_turn_state', 'cycle_no'),
      ('interview_turn_state', 'turn_id'),
      ('interview_turn_state', 'posture_mode'),
      ('interview_turn_state', 'move_type'),
      ('interview_turn_state', 'burden_signal'),
      ('interview_turn_state', 'pace_signal'),
      ('interview_turn_state', 'transition_reason'),
      ('interview_turn_state', 'created_at'),
      ('artifact_ingest_runs', 'project_id'),
      ('artifact_ingest_runs', 'cycle_no'),
      ('artifact_ingest_runs', 'artifact_input_id'),
      ('artifact_ingest_runs', 'idempotency_key'),
      ('artifact_ingest_runs', 'canonical_url'),
      ('artifact_ingest_runs', 'ingestion_limits_version'),
      ('artifact_ingest_runs', 'brain_version'),
      ('artifact_ingest_runs', 'status'),
      ('artifact_ingest_runs', 'started_at'),
      ('artifact_ingest_runs', 'created_at'),
      ('artifact_pages', 'project_id'),
      ('artifact_pages', 'cycle_no'),
      ('artifact_pages', 'artifact_input_id'),
      ('artifact_pages', 'ingest_run_id'),
      ('artifact_pages', 'canonical_url'),
      ('artifact_pages', 'raw_text'),
      ('artifact_pages', 'created_at'),
      ('artifact_summaries', 'project_id'),
      ('artifact_summaries', 'cycle_no'),
      ('artifact_summaries', 'artifact_input_id'),
      ('artifact_summaries', 'ingest_run_id'),
      ('artifact_summaries', 'version_no'),
      ('artifact_summaries', 'summary_text'),
      ('artifact_summaries', 'created_at'),
      ('interview_checkpoints', 'project_id'),
      ('interview_checkpoints', 'cycle_no'),
      ('interview_checkpoints', 'checkpoint_type'),
      ('interview_checkpoints', 'checkpoint_key'),
      ('interview_checkpoints', 'status'),
      ('interview_checkpoints', 'created_turn_id'),
      ('interview_checkpoints', 'resolved_turn_id'),
      ('interview_checkpoints', 'payload'),
      ('interview_checkpoints', 'created_at'),
      ('interview_readiness_snapshots', 'project_id'),
      ('interview_readiness_snapshots', 'cycle_no'),
      ('interview_readiness_snapshots', 'turn_id'),
      ('interview_readiness_snapshots', 'readiness_score'),
      ('interview_readiness_snapshots', 'resolved_count'),
      ('interview_readiness_snapshots', 'total_count'),
      ('interview_readiness_snapshots', 'next_focus'),
      ('interview_readiness_snapshots', 'bucket_states'),
      ('interview_readiness_snapshots', 'created_at'),
      ('interview_semantic_entries', 'project_id'),
      ('interview_semantic_entries', 'cycle_no'),
      ('interview_semantic_entries', 'source_type'),
      ('interview_semantic_entries', 'source_text'),
      ('interview_semantic_entries', 'embedding'),
      ('interview_semantic_entries', 'embedding_model'),
      ('interview_semantic_entries', 'created_at'),
      ('generation_runs', 'project_id'),
      ('generation_runs', 'cycle_no'),
      ('generation_runs', 'stage'),
      ('generation_runs', 'status'),
      ('contract_versions', 'project_id'),
      ('contract_versions', 'cycle_no'),
      ('contract_versions', 'version_number'),
      ('contract_versions', 'status'),
      ('contract_versions', 'document_count'),
      ('contract_versions', 'artifact_fingerprint'),
      ('contract_docs', 'project_id'),
      ('contract_docs', 'contract_version_id'),
      ('contract_docs', 'role_id'),
      ('requirements', 'project_id'),
      ('requirements', 'contract_version_id'),
      ('requirements', 'contract_doc_id'),
      ('requirements', 'role_id'),
      ('requirements', 'requirement_index'),
      ('requirements', 'requirement_text'),
      ('requirements', 'trust_label'),
      ('provenance_links', 'project_id'),
      ('provenance_links', 'contract_version_id'),
      ('provenance_links', 'contract_doc_id'),
      ('provenance_links', 'requirement_id'),
      ('provenance_links', 'source_type'),
      ('provenance_links', 'pointer'),
      ('submission_artifacts', 'project_id'),
      ('submission_artifacts', 'contract_version_id'),
      ('submission_artifacts', 'user_id'),
      ('submission_artifacts', 'bucket'),
      ('submission_artifacts', 'storage_path'),
      ('submission_artifacts', 'manifest'),
      ('audit_events', 'project_id')
  ),
  missing_cols as (
    select r.table_name, r.column_name
    from required r
    left join information_schema.columns c
      on c.table_schema = 'public'
     and c.table_name = r.table_name
     and c.column_name = r.column_name
    where c.column_name is null
  )
  select string_agg(format('%s.%s', table_name, column_name), ', ')
  into missing
  from missing_cols;

  if missing is not null then
    raise exception 'Missing required columns: %', missing;
  end if;
end $$;

do $$
declare
  missing text;
begin
  with required(tablename) as (
    values
      ('projects'),
      ('intake_turns'),
      ('decision_items'),
      ('artifact_inputs'),
      ('interview_turn_state'),
      ('artifact_ingest_runs'),
      ('artifact_pages'),
      ('artifact_summaries'),
      ('interview_checkpoints'),
      ('interview_readiness_snapshots'),
      ('interview_semantic_entries'),
      ('generation_runs'),
      ('contract_versions'),
      ('contract_docs'),
      ('requirements'),
      ('provenance_links'),
      ('submission_artifacts'),
      ('audit_events')
  ),
  missing_tables as (
    select r.tablename
    from required r
    left join pg_tables t
      on t.schemaname = 'public'
     and t.tablename = r.tablename
    where t.tablename is null
  )
  select string_agg(tablename, ', ')
  into missing
  from missing_tables;

  if missing is not null then
    raise exception 'Missing required tables: %', missing;
  end if;
end $$;

do $$
declare
  missing text;
begin
  with required(tablename) as (
    values
      ('projects'),
      ('intake_turns'),
      ('decision_items'),
      ('artifact_inputs'),
      ('interview_turn_state'),
      ('artifact_ingest_runs'),
      ('artifact_pages'),
      ('artifact_summaries'),
      ('interview_checkpoints'),
      ('interview_readiness_snapshots'),
      ('interview_semantic_entries'),
      ('generation_runs'),
      ('contract_versions'),
      ('contract_docs'),
      ('requirements'),
      ('provenance_links'),
      ('submission_artifacts'),
      ('audit_events')
  ),
  bad as (
    select r.tablename
    from required r
    left join pg_tables t
      on t.schemaname = 'public'
     and t.tablename = r.tablename
    where coalesce(t.rowsecurity, false) is false
  )
  select string_agg(tablename, ', ')
  into missing
  from bad;

  if missing is not null then
    raise exception 'RLS is not enabled on: %', missing;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'user_owns_project'
  ) then
    raise exception 'Missing function public.user_owns_project(uuid)';
  end if;
end $$;

do $$
declare
  missing text;
begin
  with required(table_name, policy_name) as (
    values
      ('projects', 'projects_select_own'),
      ('projects', 'projects_insert_own'),
      ('projects', 'projects_update_own'),
      ('intake_turns', 'intake_turns_select_own'),
      ('intake_turns', 'intake_turns_insert_own'),
      ('decision_items', 'decision_items_select_own'),
      ('decision_items', 'decision_items_insert_own'),
      ('decision_items', 'decision_items_update_own'),
      ('artifact_inputs', 'artifact_inputs_select_own'),
      ('artifact_inputs', 'artifact_inputs_insert_own'),
      ('interview_turn_state', 'interview_turn_state_select_own'),
      ('artifact_ingest_runs', 'artifact_ingest_runs_select_own'),
      ('artifact_pages', 'artifact_pages_select_own'),
      ('artifact_summaries', 'artifact_summaries_select_own'),
      ('interview_checkpoints', 'interview_checkpoints_select_own'),
      ('interview_checkpoints', 'interview_checkpoints_insert_own'),
      ('interview_checkpoints', 'interview_checkpoints_update_own'),
      ('interview_readiness_snapshots', 'interview_readiness_snapshots_select_own'),
      ('interview_semantic_entries', 'interview_semantic_entries_select_own'),
      ('generation_runs', 'generation_runs_select_own'),
      ('contract_versions', 'contract_versions_select_own'),
      ('contract_docs', 'contract_docs_select_own'),
      ('requirements', 'requirements_select_own'),
      ('provenance_links', 'provenance_links_select_own'),
      ('submission_artifacts', 'submission_artifacts_select_own'),
      ('audit_events', 'audit_events_select_own')
  ),
  missing_policies as (
    select r.table_name, r.policy_name
    from required r
    left join pg_policies p
      on p.schemaname = 'public'
     and p.tablename = r.table_name
     and p.policyname = r.policy_name
    where p.policyname is null
  )
  select string_agg(format('%s.%s', table_name, policy_name), ', ')
  into missing
  from missing_policies;

  if missing is not null then
    raise exception 'Missing required policies: %', missing;
  end if;
end $$;

select 'verify_db_contract:ok' as result;
SQL

echo "verify_db_contract: passed"
