-- =====================================================================
-- Chasing Excellence Scorecards — 11 Life Balance becomes a weekly check-in
--
-- Same setting Sales & Marketing uses (sql/07). Requires 07 to have been run.
-- Life Balance then gets the week picker (W40: Sep 28 – Oct 4), percentages,
-- yes/applicable counts per section, and an optional monthly / quarterly /
-- 6-month / yearly section — exactly like Sales & Marketing.
--
-- NOTE: check-ins already recorded under the old monthly check-in are dated the
-- 1st of a month, so they will not appear as weekly answers. Nothing is deleted.
-- To go back to monthly:  update public.sc_templates set check_in_period =
-- 'monthly' where slug = 'life-balance';
--
-- Idempotent.
-- =====================================================================

update public.sc_templates set check_in_period = 'weekly', updated_at = now()
where slug = 'life-balance';

-- Verify: both templates weekly
select slug, check_in_period from public.sc_templates order by sort_order;
