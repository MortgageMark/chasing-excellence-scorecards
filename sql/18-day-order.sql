-- =====================================================================
-- Chasing Excellence Scorecards — 18 Day order
--
-- Order of an item inside its time of day (Morning / Afternoon / Evening / Anytime),
-- across sections. Used by the "Time of day" sort on Items and by the Today screen.
-- Idempotent. Needs 01-17.
-- =====================================================================
alter table public.sc_user_scorecard_items
  add column if not exists day_order integer;

notify pgrst, 'reload schema';
