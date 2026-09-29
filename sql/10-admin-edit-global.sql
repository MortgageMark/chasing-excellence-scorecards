-- =====================================================================
-- Chasing Excellence Scorecards — 10 Admin: edit a question for everyone
--
-- sc_edit_global(item, text) changes the wording of a shared template question
-- for every user. The item must be a template question on the admin's own card.
-- The text becomes the checklist text (short_label). If the full question was
-- identical to it, the full question is updated too, so they stay in step.
-- The admin's own personal rename, if any, is cleared so they see the shared text.
--
-- Admin only. Idempotent.
-- =====================================================================

create or replace function public.sc_edit_global(p_item uuid, p_text text)
returns void language plpgsql security definer set search_path = public as $fn$
declare u public.sc_user_scorecard_items%rowtype;
begin
  if auth.uid() is null or not public.sc_is_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_text is null or btrim(p_text) = '' then
    raise exception 'text is empty' using errcode = '22023';
  end if;

  select i.* into u
  from public.sc_user_scorecard_items i
  join public.sc_user_scorecards c on c.id = i.user_scorecard_id
  where i.id = p_item and c.owner = auth.uid() and i.library_item_id is not null;
  if not found then
    raise exception 'template item not found' using errcode = 'P0002';
  end if;

  update public.sc_library_items
     set label = case when label = coalesce(short_label, label) then btrim(p_text) else label end,
         short_label = btrim(p_text),
         updated_at = now()
   where id = u.library_item_id;

  update public.sc_user_scorecard_items
     set renamed_label = null, updated_at = now()
   where id = u.id;
end
$fn$;

revoke execute on function public.sc_edit_global(uuid, text) from public, anon;
grant  execute on function public.sc_edit_global(uuid, text) to authenticated;
