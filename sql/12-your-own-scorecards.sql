-- =====================================================================
-- Chasing Excellence Scorecards — 12 Your own scorecards
--
-- Lets any signed-in user make their own scorecard, either brand new or as a
-- copy of one they can see (their current selections, renames and order come
-- with the copy), and choose how often it is checked in: daily, weekly or
-- monthly.
--
--   sc_templates.owner      null = shared template; set = private to that user
--   sc_create_template      new blank scorecard with starting sections
--   sc_copy_template        copy of an existing scorecard
--   sc_add_category         add a section to one of your scorecards
--   sc_rename_template      rename one of your scorecards
--   sc_delete_template      delete one of your scorecards (and its check-ins)
--
-- Your own scorecards are invisible to everyone else. Idempotent.
-- Requires 01-11 (07 for the check-in setting).
-- =====================================================================

alter table public.sc_templates
  add column if not exists owner uuid references auth.users(id) on delete cascade;
create index if not exists sc_templates_owner_idx on public.sc_templates (owner);

-- Daily check-ins are dated by day, so entries are no longer limited to Mondays / 1sts.
alter table public.sc_templates drop constraint if exists sc_templates_check_in_period_chk;
alter table public.sc_templates
  add constraint sc_templates_check_in_period_chk
  check (check_in_period in ('monthly', 'weekly', 'daily'));
alter table public.sc_entries drop constraint if exists sc_entries_period_start;
alter table public.sc_entries drop constraint if exists sc_entries_month_start;

-- Shared templates are visible to everyone (as before); private ones only to their owner.
drop policy if exists sc_templates_select on public.sc_templates;
create policy sc_templates_select on public.sc_templates
  for select to authenticated
  using ((owner is null and is_published and public.sc_has_tier(access_tier))
         or owner = auth.uid());

drop policy if exists sc_categories_select on public.sc_categories;
create policy sc_categories_select on public.sc_categories
  for select to authenticated
  using (exists (
    select 1 from public.sc_templates t
    where t.id = template_id
      and ((t.owner is null and t.is_published and public.sc_has_tier(t.access_tier))
           or t.owner = auth.uid())));

drop policy if exists sc_library_items_select on public.sc_library_items;
create policy sc_library_items_select on public.sc_library_items
  for select to authenticated
  using (exists (
    select 1 from public.sc_categories c
    join public.sc_templates t on t.id = c.template_id
    where c.id = category_id
      and ((t.owner is null and t.is_published and public.sc_has_tier(t.access_tier))
           or t.owner = auth.uid())));

-- ---------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------
create or replace function public._sc_new_template(p_name text, p_period text, p_label text, p_desc text)
returns uuid language plpgsql security definer set search_path = public as $fn$
declare nm text := btrim(coalesce(p_name, '')); new_id uuid;
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '42501'; end if;
  if nm = '' or char_length(nm) > 80 then raise exception 'name must be 1-80 characters' using errcode = '22023'; end if;
  if p_period not in ('daily', 'weekly', 'monthly') then raise exception 'bad check-in period' using errcode = '22023'; end if;
  if (select count(*) from public.sc_templates where owner = auth.uid()) >= 25 then
    raise exception 'limit of 25 scorecards reached' using errcode = '54000';
  end if;
  insert into public.sc_templates
    (slug, name, description, score_label, scoring_mode, allows_multi_instance,
     is_published, access_tier, sort_order, check_in_period, owner)
  values ('u-' || replace(gen_random_uuid()::text, '-', ''), nm, p_desc, coalesce(p_label, 'Score'),
          'binary', false, true, 'free', 1000, p_period, auth.uid())
  returning id into new_id;
  return new_id;
end
$fn$;
revoke execute on function public._sc_new_template(text, text, text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- new blank scorecard
-- ---------------------------------------------------------------------
create or replace function public.sc_create_template(p_name text, p_period text, p_sections text[])
returns uuid language plpgsql security definer set search_path = public as $fn$
declare tid uuid; s text; n integer := 0;
begin
  tid := public._sc_new_template(p_name, p_period, 'Score', 'Your own scorecard.');
  foreach s in array coalesce(p_sections, array[]::text[]) loop
    s := btrim(s);
    if s <> '' then
      insert into public.sc_categories (template_id, code, name, sort_order)
      values (tid, 'sec-' || substr(gen_random_uuid()::text, 1, 8), left(s, 60), n);
      n := n + 1;
    end if;
  end loop;
  return tid;
end
$fn$;

-- ---------------------------------------------------------------------
-- copy of an existing scorecard
-- ---------------------------------------------------------------------
create or replace function public.sc_copy_template(p_source uuid, p_name text, p_period text)
returns uuid language plpgsql security definer set search_path = public as $fn$
declare src public.sc_templates%rowtype; tid uuid; card uuid;
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '42501'; end if;
  select * into src from public.sc_templates t
  where t.id = p_source
    and ((t.owner is null and t.is_published and public.sc_has_tier(t.access_tier)) or t.owner = auth.uid());
  if not found then raise exception 'scorecard not found' using errcode = 'P0002'; end if;

  tid := public._sc_new_template(p_name, p_period, src.score_label, src.description);

  insert into public.sc_categories (template_id, code, name, sort_order)
  select tid, c.code, c.name, c.sort_order from public.sc_categories c where c.template_id = p_source;

  select id into card from public.sc_user_scorecards
  where template_id = p_source and owner = auth.uid() and is_active
  order by created_at limit 1;

  -- every active question of the source, carrying over this user's own settings if they have a card
  insert into public.sc_library_items
    (category_id, code, label, short_label, default_frequency, default_target_value,
     default_target_month, is_default_on, sort_order)
  select nc.id, l.code,
         coalesce(u.renamed_label, l.label),
         coalesce(u.renamed_label, l.short_label, l.label),
         coalesce(u.frequency, l.default_frequency),
         l.default_target_value,
         coalesce(u.target_month, l.default_target_month),
         coalesce(u.is_selected, l.is_default_on),
         coalesce(u.sort_order, l.sort_order)
  from public.sc_library_items l
  join public.sc_categories oc on oc.id = l.category_id and oc.template_id = p_source
  join public.sc_categories nc on nc.template_id = tid and nc.code = oc.code
  left join public.sc_user_scorecard_items u
         on u.library_item_id = l.id and u.user_scorecard_id = card and u.removed_at is null
  where l.is_active;

  -- the user's own added items come along too
  if card is not null then
    insert into public.sc_library_items
      (category_id, code, label, short_label, default_frequency, default_target_month, is_default_on, sort_order)
    select nc.id, 'custom-' || substr(gen_random_uuid()::text, 1, 8), u.custom_label, u.custom_label,
           u.frequency, u.target_month, u.is_selected, u.sort_order
    from public.sc_user_scorecard_items u
    join public.sc_categories oc on oc.id = u.category_id
    join public.sc_categories nc on nc.template_id = tid and nc.code = oc.code
    where u.user_scorecard_id = card and u.library_item_id is null
      and u.removed_at is null and u.custom_label is not null;
  end if;
  return tid;
end
$fn$;

-- ---------------------------------------------------------------------
-- manage your own
-- ---------------------------------------------------------------------
create or replace function public.sc_add_category(p_template uuid, p_name text)
returns uuid language plpgsql security definer set search_path = public as $fn$
declare nm text := btrim(coalesce(p_name, '')); new_id uuid;
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '42501'; end if;
  if nm = '' or char_length(nm) > 60 then raise exception 'name must be 1-60 characters' using errcode = '22023'; end if;
  if not exists (select 1 from public.sc_templates where id = p_template and owner = auth.uid()) then
    raise exception 'not your scorecard' using errcode = '42501';
  end if;
  insert into public.sc_categories (template_id, code, name, sort_order)
  values (p_template, 'sec-' || substr(gen_random_uuid()::text, 1, 8), nm,
          coalesce((select max(sort_order) + 1 from public.sc_categories where template_id = p_template), 0))
  returning id into new_id;
  return new_id;
end
$fn$;

create or replace function public.sc_rename_template(p_id uuid, p_name text)
returns void language plpgsql security definer set search_path = public as $fn$
declare nm text := btrim(coalesce(p_name, ''));
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '42501'; end if;
  if nm = '' or char_length(nm) > 80 then raise exception 'name must be 1-80 characters' using errcode = '22023'; end if;
  update public.sc_templates set name = nm, updated_at = now() where id = p_id and owner = auth.uid();
  if not found then raise exception 'not your scorecard' using errcode = '42501'; end if;
end
$fn$;

create or replace function public.sc_delete_template(p_id uuid)
returns void language plpgsql security definer set search_path = public as $fn$
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '42501'; end if;
  if not exists (select 1 from public.sc_templates where id = p_id and owner = auth.uid()) then
    raise exception 'not your scorecard' using errcode = '42501';
  end if;
  delete from public.sc_user_scorecards where template_id = p_id and owner = auth.uid();
  delete from public.sc_templates where id = p_id and owner = auth.uid();
end
$fn$;

revoke execute on function public.sc_create_template(text, text, text[]) from public, anon;
revoke execute on function public.sc_copy_template(uuid, text, text)      from public, anon;
revoke execute on function public.sc_add_category(uuid, text)             from public, anon;
revoke execute on function public.sc_rename_template(uuid, text)          from public, anon;
revoke execute on function public.sc_delete_template(uuid)                from public, anon;
grant  execute on function public.sc_create_template(text, text, text[]) to authenticated;
grant  execute on function public.sc_copy_template(uuid, text, text)      to authenticated;
grant  execute on function public.sc_add_category(uuid, text)             to authenticated;
grant  execute on function public.sc_rename_template(uuid, text)          to authenticated;
grant  execute on function public.sc_delete_template(uuid)                to authenticated;
