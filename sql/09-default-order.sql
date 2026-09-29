-- =====================================================================
-- Chasing Excellence Scorecards — 09 Admin default order
--
-- sc_set_default_order(items) lets an admin save the order of one category, as
-- arranged on their own Items screen, as the default order of the shared
-- template. New scorecards (and "Reset this scorecard to the template") start in
-- that order. Users who already have a card keep their own order.
--
-- Admin only, and the items must be on the caller's own card.
-- Idempotent.
-- =====================================================================

create or replace function public.sc_set_default_order(p_items uuid[])
returns integer language plpgsql security definer set search_path = public as $fn$
declare n integer;
begin
  if auth.uid() is null or not public.sc_is_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;

  update public.sc_library_items l
     set sort_order = o.pos - 1, updated_at = now()
  from unnest(p_items) with ordinality as o(item_id, pos)
  join public.sc_user_scorecard_items i on i.id = o.item_id
  join public.sc_user_scorecards c on c.id = i.user_scorecard_id and c.owner = auth.uid()
  where l.id = i.library_item_id;
  get diagnostics n = row_count;
  return n;
end
$fn$;

revoke execute on function public.sc_set_default_order(uuid[]) from public, anon;
grant  execute on function public.sc_set_default_order(uuid[]) to authenticated;
