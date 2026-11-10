-- =====================================================================
-- Chasing Excellence Scorecards — 19 Missed
--
-- An answer can now be "missed": acknowledged as not done, so it clears off the
-- checklist but still counts against the score (value_bool stays false).
-- Idempotent. Needs 01-18.
-- =====================================================================
alter table public.sc_entries
  add column if not exists missed boolean not null default false;

notify pgrst, 'reload schema';
