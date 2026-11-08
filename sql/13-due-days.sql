-- =====================================================================
-- Chasing Excellence Scorecards — 13 Due days
--
-- Adds an optional "due on" weekday to weekly items, so e.g. "Call Family" can
-- be due on the weekend instead of from Monday. Nothing else needs a column:
-- every other cadence follows the same simple defaults in the app
--   daily      due that day, late after it
--   weekly     due Monday (or the chosen day), late after Sunday
--   monthly    due the 1st, late after the last day of the month
--   quarterly  due the first day of the quarter, late after its last day
--   6-month    due Jan 1 / Jul 1, late after Jun 30 / Dec 31
--   yearly     due Jan 1, late after Dec 31
--
-- due_dow: 1 = Monday ... 7 = Sunday; 6 means "the weekend" (due Saturday, still
-- due Sunday). Null means the default (Monday).
-- Idempotent. Needs 01-12.
-- =====================================================================

alter table public.sc_library_items
  add column if not exists due_dow smallint check (due_dow between 1 and 7);
alter table public.sc_user_scorecard_items
  add column if not exists due_dow smallint check (due_dow between 1 and 7);

-- Sensible starting points for a few weekly items whose day is obvious.
-- Everything else keeps the default (due Monday, late after Sunday).
update public.sc_library_items set due_dow = 7 where code in ('attend-church', 'family-meeting');
update public.sc_library_items set due_dow = 6 where code in ('call-family-dad-mom-siblings', 'family-activity');
update public.sc_library_items set due_dow = 5
  where code in ('weekly-business-review') or code like 'did-you-send-your-friday-weekend-warrior%';
update public.sc_library_items set due_dow = 1
  where code like 'did-you-email-your-realtors-the-monday-marketing-email%';

-- The two functions that copy items now carry the due day with them.
create or replace function public.sc_set_global(p_item uuid, p_on boolean)
returns uuid language plpgsql security definer set search_path = public as $fn$
declare
  u   public.sc_user_scorecard_items%rowtype;
  lib public.sc_library_items%rowtype;
  new_id uuid;
begin
  if auth.uid() is null or not public.sc_is_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;

  select i.* into u
  from public.sc_user_scorecard_items i
  join public.sc_user_scorecards c on c.id = i.user_scorecard_id
  where i.id = p_item and c.owner = auth.uid();
  if not found then
    raise exception 'item not found' using errcode = 'P0002';
  end if;

  if p_on then
    if u.library_item_id is not null then
      update public.sc_library_items set is_active = true, updated_at = now()
      where id = u.library_item_id;
      return u.library_item_id;
    end if;
    insert into public.sc_library_items
      (category_id, code, label, short_label, default_frequency,
       default_target_month, due_dow, is_default_on, sort_order)
    select u.category_id, 'custom-' || substr(gen_random_uuid()::text, 1, 8),
           u.custom_label, u.custom_label, u.frequency, u.target_month, u.due_dow, true,
           coalesce((select max(sort_order) + 1 from public.sc_library_items
                     where category_id = u.category_id), 0)
    returning id into new_id;
    update public.sc_user_scorecard_items
      set library_item_id = new_id, custom_label = null, updated_at = now()
    where id = u.id;
    return new_id;
  else
    if u.library_item_id is null then return null; end if;
    select * into lib from public.sc_library_items where id = u.library_item_id;
    -- Retire it for everyone; keep it on the admin's own card as a custom item.
    update public.sc_library_items set is_active = false, updated_at = now()
    where id = lib.id;
    update public.sc_user_scorecard_items
      set custom_label = coalesce(u.renamed_label, lib.short_label, lib.label),
          due_dow = coalesce(u.due_dow, lib.due_dow),
          renamed_label = null, library_item_id = null, updated_at = now()
    where id = u.id;
    return null;
  end if;
end
$fn$;

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
     default_target_month, due_dow, is_default_on, sort_order)
  select nc.id, l.code,
         coalesce(u.renamed_label, l.label),
         coalesce(u.renamed_label, l.short_label, l.label),
         coalesce(u.frequency, l.default_frequency),
         l.default_target_value,
         coalesce(u.target_month, l.default_target_month),
         coalesce(u.due_dow, l.due_dow),
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
      (category_id, code, label, short_label, default_frequency, default_target_month, due_dow, is_default_on, sort_order)
    select nc.id, 'custom-' || substr(gen_random_uuid()::text, 1, 8), u.custom_label, u.custom_label,
           u.frequency, u.target_month, u.due_dow, u.is_selected, u.sort_order
    from public.sc_user_scorecard_items u
    join public.sc_categories oc on oc.id = u.category_id
    join public.sc_categories nc on nc.template_id = tid and nc.code = oc.code
    where u.user_scorecard_id = card and u.library_item_id is null
      and u.removed_at is null and u.custom_label is not null;
  end if;
  return tid;
end
$fn$;

-- Make everything callable straight away.
notify pgrst, 'reload schema';
