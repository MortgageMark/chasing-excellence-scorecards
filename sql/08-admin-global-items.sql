-- =====================================================================
-- Chasing Excellence Scorecards — 08 Admins and "add to the global template"
--
-- Lets an admin promote a question they added on their own Items screen into
-- the shared template, so every user gets it (and later, every new card).
--
--   sc_admins            who is an admin. RLS on, no policies, no grants: the
--                        browser can neither read nor write it, so nobody can
--                        make themselves an admin from the app.
--   sc_is_admin()        true for a signed-in admin. The app uses it to decide
--                        whether to show the Global toggle.
--   sc_set_global(...)   the only way in. Checks admin, and that the item is on
--                        the caller's own card, then creates (or retires) the
--                        shared library row.
--
-- Idempotent. Add another admin by adding a row to sc_admins from the SQL
-- editor (see the insert below).
-- =====================================================================

create table if not exists public.sc_admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.sc_admins enable row level security;
revoke all on public.sc_admins from public, anon, authenticated;

insert into public.sc_admins (user_id)
select id from auth.users where lower(email) = 'mark@mortgagemark.com'
on conflict (user_id) do nothing;

create or replace function public.sc_is_admin()
returns boolean language sql stable security definer set search_path = public as $fn$
  select auth.uid() is not null
     and exists (select 1 from public.sc_admins where user_id = auth.uid());
$fn$;

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
       default_target_month, is_default_on, sort_order)
    select u.category_id, 'custom-' || substr(gen_random_uuid()::text, 1, 8),
           u.custom_label, u.custom_label, u.frequency, u.target_month, true,
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
          renamed_label = null, library_item_id = null, updated_at = now()
    where id = u.id;
    return null;
  end if;
end
$fn$;

revoke execute on function public.sc_is_admin()               from public, anon;
revoke execute on function public.sc_set_global(uuid, boolean) from public, anon;
grant  execute on function public.sc_is_admin()               to authenticated;
grant  execute on function public.sc_set_global(uuid, boolean) to authenticated;

-- Verify: your account should be listed
select u.email from public.sc_admins a join auth.users u on u.id = a.user_id;
