-- =====================================================================
-- Chasing Excellence Scorecards — 07 Weekly check-ins
--
-- Lets a template be scored weekly instead of monthly.
--   1. sc_templates.check_in_period  ('monthly' default | 'weekly')
--   2. sc_entries.period_start may now be a Monday (weekly entries) as well
--      as the 1st of a month (monthly entries, and the monthly / quarterly /
--      6-month / yearly items on a weekly card).
--   3. sc_entries.credit_week: which week a monthly/quarterly/yearly "yes" is
--      credited to (it counts once, in the week it was ticked).
--   4. sc_library_items.short_label: the short checklist text shown in the app,
--      separate from the full question.
--   5. Sales & Marketing switches to weekly. Life Balance stays monthly.
--
-- Idempotent. Run this before (or after) 06 — order does not matter.
-- =====================================================================

alter table public.sc_templates
  add column if not exists check_in_period text not null default 'monthly';

alter table public.sc_templates drop constraint if exists sc_templates_check_in_period_chk;
alter table public.sc_templates
  add constraint sc_templates_check_in_period_chk
  check (check_in_period in ('monthly', 'weekly'));

alter table public.sc_entries drop constraint if exists sc_entries_month_start;
alter table public.sc_entries drop constraint if exists sc_entries_period_start;
alter table public.sc_entries
  add constraint sc_entries_period_start
  check (extract(day from period_start) = 1 or extract(isodow from period_start) = 1);

alter table public.sc_entries add column if not exists credit_week date;
alter table public.sc_library_items add column if not exists short_label text;

update public.sc_templates set check_in_period = 'weekly', updated_at = now()
where slug = 'sales-marketing';

-- Verify: life-balance monthly, sales-marketing weekly
select slug, check_in_period from public.sc_templates order by sort_order;
