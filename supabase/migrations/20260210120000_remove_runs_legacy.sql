-- Align legacy local schema with canonical project/cycle model.
-- Production already uses projects + cycle_no; this removes accidental local dependencies on public.runs.

drop table if exists public.runs cascade;
