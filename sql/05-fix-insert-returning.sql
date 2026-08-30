-- =====================================================================
-- Chasing Excellence Scorecards — 05 FIX: insert ... returning on
-- sc_user_scorecards
--
-- BUG THIS FIXES (found adopting a scorecard in the browser, 2026-08-29)
--
-- Creating a scorecard failed with
--   new row violates row-level security policy for table "sc_user_scorecards"
-- even though the INSERT itself was legal. Proven server-side: the same
-- INSERT succeeds without RETURNING and fails with it.
--
-- Cause: PostgREST always adds RETURNING, so the SELECT policy has to pass
-- on the brand-new row. That policy was `sc_can_view(id)`, and sc_can_view
-- is a STABLE function that looks the row up in sc_user_scorecards — the
-- very table being inserted into. A STABLE function runs on the snapshot
-- taken at the start of the statement, so the row it is being asked about
-- does not exist yet. It returns false and the insert is rejected.
--
-- Fix: give both policies a direct predicate on the row first.
-- `owner = auth.uid()` is evaluated against the NEW row itself with no
-- self-query, so it is true immediately; sc_can_view stays for the share
-- and roster cases, where the row is already committed.
--
-- The rule this establishes: an RLS policy on table X must never depend
-- SOLELY on a stable function that re-queries table X. Shares, rosters and
-- entries are unaffected — their helpers read a different table.
--
-- Re-runnable.
-- =====================================================================

drop policy if exists sc_cards_select on public.sc_user_scorecards;
create policy sc_cards_select on public.sc_user_scorecards
  for select to authenticated
  using (owner = auth.uid() or public.sc_can_view(id));

drop policy if exists sc_cards_update on public.sc_user_scorecards;
create policy sc_cards_update on public.sc_user_scorecards
  for update to authenticated
  using      (owner = auth.uid() or public.sc_can_edit(id))
  with check (owner = auth.uid() or public.sc_can_edit(id));

-- ---------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------
select policyname, cmd, qual, with_check
from pg_policies
where schemaname='public' and tablename='sc_user_scorecards'
order by policyname;
