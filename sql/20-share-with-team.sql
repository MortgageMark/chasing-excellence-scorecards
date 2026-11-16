-- =====================================================================
-- Chasing Excellence Scorecards — 20 Share a scorecard with someone
--
-- Lets you make a scorecard, share it with a person (by the email they
-- signed up with) and watch their progress. Three access levels:
--   view : can see the scorecard, history and score, but not change anything
--   log  : view + can tick their answers (what a team member needs)
--   edit : log + can change the items and settings (co-owner)
-- The owner always has everything and sees the person's answers live.
-- Shared people can now also read the scorecard's template, sections and
-- items (before, only the owner could). Idempotent. Needs 01-19.
-- =====================================================================

-- widen the allowed access levels
do $m$
declare c text;
begin
  for c in select conname from pg_constraint
           where conrelid = 'public.sc_shares'::regclass and contype = 'c'
             and pg_get_constraintdef(oid) ilike '%access%' loop
    execute format('alter table public.sc_shares drop constraint %I', c);
  end loop;
end $m$;
alter table public.sc_shares
  add constraint sc_shares_access_check check (access in ('view', 'log', 'edit'));

-- may this person tick answers on the card?
create or replace function public.sc_can_log(card uuid)
returns boolean language sql stable security definer set search_path = public as $fn$
  select public.sc_owns_card(card)
      or exists (
        select 1 from public.sc_shares s
        where s.user_scorecard_id = card
          and s.shared_with_user_id = auth.uid()
          and s.access in ('log', 'edit'));
$fn$;

-- can this person see the template because a card on it is shared with them?
create or replace function public.sc_can_see_template(tid uuid)
returns boolean language sql stable security definer set search_path = public as $fn$
  select exists (
    select 1 from public.sc_user_scorecards c
    where c.template_id = tid and public.sc_can_view(c.id));
$fn$;

grant execute on function public.sc_can_log(uuid), public.sc_can_see_template(uuid) to authenticated;

-- answers: owner, 'log' and 'edit' people can write
drop policy if exists sc_entries_write on public.sc_entries;
create policy sc_entries_write on public.sc_entries
  for all to authenticated
  using (public.sc_can_log(user_scorecard_id))
  with check (public.sc_can_log(user_scorecard_id));

drop policy if exists sc_daily_write on public.sc_daily_log;
create policy sc_daily_write on public.sc_daily_log
  for all to authenticated
  using (public.sc_can_log(user_scorecard_id))
  with check (public.sc_can_log(user_scorecard_id));

-- template / sections / items readable by people the card is shared with
drop policy if exists sc_templates_select on public.sc_templates;
create policy sc_templates_select on public.sc_templates
  for select to authenticated
  using ((owner is null and is_published and public.sc_has_tier(access_tier))
         or owner = auth.uid()
         or public.sc_can_see_template(id));

drop policy if exists sc_categories_select on public.sc_categories;
create policy sc_categories_select on public.sc_categories
  for select to authenticated
  using (exists (
    select 1 from public.sc_templates t
    where t.id = template_id
      and ((t.owner is null and t.is_published and public.sc_has_tier(t.access_tier))
           or t.owner = auth.uid()
           or public.sc_can_see_template(t.id))));

drop policy if exists sc_library_items_select on public.sc_library_items;
create policy sc_library_items_select on public.sc_library_items
  for select to authenticated
  using (exists (
    select 1 from public.sc_categories c
    join public.sc_templates t on t.id = c.template_id
    where c.id = category_id
      and ((t.owner is null and t.is_published and public.sc_has_tier(t.access_tier))
           or t.owner = auth.uid()
           or public.sc_can_see_template(t.id))));

notify pgrst, 'reload schema';
