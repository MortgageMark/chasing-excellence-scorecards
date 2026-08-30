-- =====================================================================
-- Chasing Excellence Scorecards — 02 RLS  (PROPOSAL, NOT YET RUN)
--
-- Written against all three sharing mechanisms from the start (spec 6.x),
-- because retrofitting visibility means rewriting every policy.
--
-- WHY THE HELPER FUNCTIONS EXIST
-- sc_user_scorecards' SELECT policy needs to look at sc_shares, and
-- sc_shares' SELECT policy needs to look at sc_user_scorecards. Written
-- as plain subqueries that is infinite RLS recursion. Every helper below
-- is SECURITY DEFINER, so it runs as the function owner with RLS off and
-- the loop is broken. They are the only place that reads those tables
-- unfiltered — keep them narrow and keep them here.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------

create or replace function public.sc_owns_card(card uuid)
returns boolean language sql stable security definer set search_path = public as $fn$
  select exists (
    select 1 from public.sc_user_scorecards c
    where c.id = card and c.owner = auth.uid());
$fn$;

-- 6.2 co-own. Edit implies view.
create or replace function public.sc_can_edit(card uuid)
returns boolean language sql stable security definer set search_path = public as $fn$
  select public.sc_owns_card(card)
      or exists (
        select 1 from public.sc_shares s
        where s.user_scorecard_id = card
          and s.shared_with_user_id = auth.uid()
          and s.access = 'edit');
$fn$;

-- 6.1 share to view + 6.3 roster.
-- Roster clause: I see a card if its owner is an ACCEPTED member of a
-- roster I own for that card's template. Note this covers every card that
-- member holds on that template, including extra multi-instance copies.
create or replace function public.sc_can_view(card uuid)
returns boolean language sql stable security definer set search_path = public as $fn$
  select public.sc_owns_card(card)
      or exists (
        select 1 from public.sc_shares s
        where s.user_scorecard_id = card
          and s.shared_with_user_id = auth.uid())
      or exists (
        select 1
        from public.sc_user_scorecards c
        join public.sc_rosters r
          on r.template_id = c.template_id
         and r.member_user_id = c.owner
        where c.id = card
          and r.owner = auth.uid()
          and r.status = 'accepted');
$fn$;

-- Entitlements (spec 11). Everything is free today; the check is wired in
-- now so no read path has to be touched when it stops being free.
create or replace function public.sc_plan()
returns text language sql stable security definer set search_path = public as $fn$
  select coalesce((select plan from public.sc_profiles where user_id = auth.uid()), 'free');
$fn$;

create or replace function public.sc_has_tier(tier text)
returns boolean language sql stable security definer set search_path = public as $fn$
  select tier = 'free' or public.sc_plan() = 'pro';
$fn$;

-- Can I see this person's name at all? True when we are connected by a
-- share or an accepted roster in either direction. Keeps the roster and
-- "shared with me" lists from showing bare uuids without opening the
-- profile table to everyone.
create or replace function public.sc_knows_user(other uuid)
returns boolean language sql stable security definer set search_path = public as $fn$
  select other = auth.uid()
      or exists (
        select 1 from public.sc_shares s
        join public.sc_user_scorecards c on c.id = s.user_scorecard_id
        where (s.shared_with_user_id = auth.uid() and c.owner = other)
           or (s.shared_with_user_id = other and c.owner = auth.uid()))
      or exists (
        select 1 from public.sc_rosters r
        where r.status = 'accepted'
          and ((r.owner = auth.uid() and r.member_user_id = other)
            or (r.owner = other and r.member_user_id = auth.uid())));
$fn$;

grant execute on function
  public.sc_owns_card(uuid), public.sc_can_edit(uuid), public.sc_can_view(uuid),
  public.sc_plan(), public.sc_has_tier(text), public.sc_knows_user(uuid)
to authenticated;

-- ---------------------------------------------------------------------
-- Enable RLS everywhere
-- ---------------------------------------------------------------------
alter table public.sc_profiles             enable row level security;
alter table public.sc_templates            enable row level security;
alter table public.sc_categories           enable row level security;
alter table public.sc_library_items        enable row level security;
alter table public.sc_user_scorecards      enable row level security;
alter table public.sc_user_scorecard_items enable row level security;
alter table public.sc_entries              enable row level security;
alter table public.sc_daily_log            enable row level security;
alter table public.sc_shares               enable row level security;
alter table public.sc_rosters              enable row level security;

-- Table grants. Supabase's default privileges usually cover this, but being
-- explicit costs nothing and a missing grant looks exactly like a broken
-- policy. `anon` gets nothing: this app is signed-in only.
grant select on
  public.sc_templates, public.sc_categories, public.sc_library_items
to authenticated;

grant select, insert, update, delete on
  public.sc_profiles, public.sc_user_scorecards, public.sc_user_scorecard_items,
  public.sc_entries, public.sc_daily_log, public.sc_shares, public.sc_rosters
to authenticated;

-- Policies are dropped first so this file is re-runnable.

-- ---------------------------------------------------------------------
-- sc_profiles
-- ---------------------------------------------------------------------
drop policy if exists sc_profiles_select on public.sc_profiles;
create policy sc_profiles_select on public.sc_profiles
  for select to authenticated
  using (public.sc_knows_user(user_id));

drop policy if exists sc_profiles_insert on public.sc_profiles;
create policy sc_profiles_insert on public.sc_profiles
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists sc_profiles_update on public.sc_profiles;
create policy sc_profiles_update on public.sc_profiles
  for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
-- No delete policy: an account row goes away with the auth user.

-- NOTE: `plan` is user-writable under this policy. Acceptable while every
-- tier is free; before charging, move `plan` to its own table or revoke
-- column update (`revoke update (plan) on public.sc_profiles from authenticated`).

-- ---------------------------------------------------------------------
-- Template content — read-only to clients, seeded by SQL as postgres
-- (the service role and the SQL editor bypass RLS, so no write policies).
-- ---------------------------------------------------------------------
drop policy if exists sc_templates_select on public.sc_templates;
create policy sc_templates_select on public.sc_templates
  for select to authenticated
  using (is_published and public.sc_has_tier(access_tier));

drop policy if exists sc_categories_select on public.sc_categories;
create policy sc_categories_select on public.sc_categories
  for select to authenticated
  using (exists (
    select 1 from public.sc_templates t
    where t.id = template_id and t.is_published and public.sc_has_tier(t.access_tier)));

drop policy if exists sc_library_items_select on public.sc_library_items;
create policy sc_library_items_select on public.sc_library_items
  for select to authenticated
  using (exists (
    select 1 from public.sc_categories c
    join public.sc_templates t on t.id = c.template_id
    where c.id = category_id and t.is_published and public.sc_has_tier(t.access_tier)));

-- ---------------------------------------------------------------------
-- sc_user_scorecards
-- ---------------------------------------------------------------------
drop policy if exists sc_cards_select on public.sc_user_scorecards;
create policy sc_cards_select on public.sc_user_scorecards
  for select to authenticated
  using (public.sc_can_view(id));

drop policy if exists sc_cards_insert on public.sc_user_scorecards;
create policy sc_cards_insert on public.sc_user_scorecards
  for insert to authenticated
  with check (owner = auth.uid());

-- A co-owner may edit the card's settings but never reassign it.
drop policy if exists sc_cards_update on public.sc_user_scorecards;
create policy sc_cards_update on public.sc_user_scorecards
  for update to authenticated
  using (public.sc_can_edit(id))
  with check (public.sc_can_edit(id));

drop policy if exists sc_cards_delete on public.sc_user_scorecards;
create policy sc_cards_delete on public.sc_user_scorecards
  for delete to authenticated
  using (owner = auth.uid());

-- ---------------------------------------------------------------------
-- sc_user_scorecard_items
-- ---------------------------------------------------------------------
drop policy if exists sc_items_select on public.sc_user_scorecard_items;
create policy sc_items_select on public.sc_user_scorecard_items
  for select to authenticated
  using (public.sc_can_view(user_scorecard_id));

drop policy if exists sc_items_write on public.sc_user_scorecard_items;
create policy sc_items_write on public.sc_user_scorecard_items
  for all to authenticated
  using (public.sc_can_edit(user_scorecard_id))
  with check (public.sc_can_edit(user_scorecard_id));

-- ---------------------------------------------------------------------
-- sc_entries / sc_daily_log
-- Both carry user_scorecard_id so the check is one lookup, no join.
-- ---------------------------------------------------------------------
drop policy if exists sc_entries_select on public.sc_entries;
create policy sc_entries_select on public.sc_entries
  for select to authenticated
  using (public.sc_can_view(user_scorecard_id));

drop policy if exists sc_entries_write on public.sc_entries;
create policy sc_entries_write on public.sc_entries
  for all to authenticated
  using (public.sc_can_edit(user_scorecard_id))
  with check (public.sc_can_edit(user_scorecard_id));

drop policy if exists sc_daily_select on public.sc_daily_log;
create policy sc_daily_select on public.sc_daily_log
  for select to authenticated
  using (public.sc_can_view(user_scorecard_id));

drop policy if exists sc_daily_write on public.sc_daily_log;
create policy sc_daily_write on public.sc_daily_log
  for all to authenticated
  using (public.sc_can_edit(user_scorecard_id))
  with check (public.sc_can_edit(user_scorecard_id));

-- ---------------------------------------------------------------------
-- sc_shares
-- Only the card owner grants access. A recipient can see their own row
-- and delete it (leave), nothing else.
-- ---------------------------------------------------------------------
drop policy if exists sc_shares_select on public.sc_shares;
create policy sc_shares_select on public.sc_shares
  for select to authenticated
  using (public.sc_owns_card(user_scorecard_id) or shared_with_user_id = auth.uid());

drop policy if exists sc_shares_insert on public.sc_shares;
create policy sc_shares_insert on public.sc_shares
  for insert to authenticated
  with check (public.sc_owns_card(user_scorecard_id) and shared_by = auth.uid());

drop policy if exists sc_shares_update on public.sc_shares;
create policy sc_shares_update on public.sc_shares
  for update to authenticated
  using (public.sc_owns_card(user_scorecard_id))
  with check (public.sc_owns_card(user_scorecard_id));

drop policy if exists sc_shares_delete on public.sc_shares;
create policy sc_shares_delete on public.sc_shares
  for delete to authenticated
  using (public.sc_owns_card(user_scorecard_id) or shared_with_user_id = auth.uid());

-- ---------------------------------------------------------------------
-- sc_rosters
-- The roster owner controls membership; the member controls consent, and
-- only through sc_roster_respond() — RLS cannot restrict which COLUMN a
-- member updates, so an update policy for members would let them promote
-- themselves to owner.
-- ---------------------------------------------------------------------
drop policy if exists sc_rosters_select on public.sc_rosters;
create policy sc_rosters_select on public.sc_rosters
  for select to authenticated
  using (owner = auth.uid() or member_user_id = auth.uid());

drop policy if exists sc_rosters_insert on public.sc_rosters;
create policy sc_rosters_insert on public.sc_rosters
  for insert to authenticated
  with check (owner = auth.uid());

drop policy if exists sc_rosters_update on public.sc_rosters;
create policy sc_rosters_update on public.sc_rosters
  for update to authenticated
  using (owner = auth.uid()) with check (owner = auth.uid());

drop policy if exists sc_rosters_delete on public.sc_rosters;
create policy sc_rosters_delete on public.sc_rosters
  for delete to authenticated
  using (owner = auth.uid() or member_user_id = auth.uid());

-- =====================================================================
-- RPCs
-- =====================================================================

-- Called on every app boot. Creates the account row if missing and keeps
-- the email copy current so invites can find this person.
create or replace function public.sc_bootstrap_profile(p_timezone text default null)
returns public.sc_profiles
language plpgsql security definer set search_path = public as $fn$
declare row public.sc_profiles;
begin
  insert into public.sc_profiles (user_id, email, timezone)
  values (auth.uid(),
          lower((select email from auth.users where id = auth.uid())),
          coalesce(p_timezone, 'America/Chicago'))
  on conflict (user_id) do update
    set email = excluded.email, updated_at = now()
  returning * into row;
  return row;
end $fn$;

-- Roster consent. The only way a member's status changes.
create or replace function public.sc_roster_respond(p_roster uuid, p_accept boolean)
returns public.sc_rosters
language plpgsql security definer set search_path = public as $fn$
declare row public.sc_rosters;
begin
  update public.sc_rosters
     set status = case when p_accept then 'accepted' else 'declined' end,
         updated_at = now()
   where id = p_roster and member_user_id = auth.uid()
  returning * into row;
  if row.id is null then raise exception 'not a member of that roster'; end if;
  return row;
end $fn$;

-- Share by email without exposing auth.users. Returns null when there is no
-- account for that address, which is the app's cue to tell the owner the
-- person has to sign up first. This does confirm whether an address has an
-- account; that is the same signal Supabase's own auth endpoints give.
create or replace function public.sc_find_user_by_email(p_email text)
returns uuid
language sql stable security definer set search_path = public as $fn$
  select id from auth.users where lower(email) = lower(p_email) limit 1;
$fn$;

grant execute on function
  public.sc_bootstrap_profile(text),
  public.sc_roster_respond(uuid, boolean),
  public.sc_find_user_by_email(text)
to authenticated;
