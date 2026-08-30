-- =====================================================================
-- Chasing Excellence Scorecards — 04 FIX: lock down function execution
--
-- BUG THIS FIXES (found in browser verification, 2026-08-29)
--
-- Postgres grants EXECUTE on every new function to PUBLIC by default, and
-- PostgREST exposes any function the `anon` role can execute. 02-rls.sql
-- only ADDED a grant to `authenticated`, which restricted nothing.
--
-- Result: anyone holding the publishable key — which is embedded in the
-- app and public by design — could call sc_find_user_by_email() without
-- signing in and learn whether any given address has an account, getting
-- back its auth.users uuid. An unauthenticated email-enumeration oracle.
-- Confirmed live against a real address before this fix.
--
-- Two layers, because either alone is one mistake away from the same hole:
--   1. revoke EXECUTE from public and anon, grant only to authenticated
--   2. an explicit auth.uid() guard inside the functions that read or
--      write anything sensitive, so a future stray GRANT still leaks nothing
--
-- Re-runnable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Revoke the default PUBLIC execute, then grant deliberately.
--    Covers every sc_ function, including any added later.
-- ---------------------------------------------------------------------
do $revoke$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'sc\_%'
  loop
    execute format('revoke all on function %s from public', f.sig);
    execute format('revoke all on function %s from anon', f.sig);
  end loop;
end $revoke$;

grant execute on function
  public.sc_owns_card(uuid),
  public.sc_can_edit(uuid),
  public.sc_can_view(uuid),
  public.sc_plan(),
  public.sc_has_tier(text),
  public.sc_knows_user(uuid),
  public.sc_bootstrap_profile(text),
  public.sc_roster_respond(uuid, boolean),
  public.sc_find_user_by_email(text)
to authenticated;

-- sc_touch_updated_at is a trigger function. It is invoked by the trigger,
-- which runs as the table owner, so no role needs EXECUTE on it directly.

-- ---------------------------------------------------------------------
-- 2. Guards inside the functions that matter.
-- ---------------------------------------------------------------------

-- The enumeration oracle. Signed-in callers only.
create or replace function public.sc_find_user_by_email(p_email text)
returns uuid
language sql stable security definer set search_path = public as $fn$
  select u.id from auth.users u
  where auth.uid() is not null
    and lower(u.email) = lower(p_email)
  limit 1;
$fn$;

-- Was reachable by anon and failed with a raw not-null constraint error.
create or replace function public.sc_bootstrap_profile(p_timezone text default null)
returns public.sc_profiles
language plpgsql security definer set search_path = public as $fn$
declare row public.sc_profiles;
begin
  if auth.uid() is null then
    raise exception 'sc_bootstrap_profile requires an authenticated session';
  end if;
  insert into public.sc_profiles (user_id, email, timezone)
  values (auth.uid(),
          lower((select email from auth.users where id = auth.uid())),
          coalesce(p_timezone, 'America/Chicago'))
  on conflict (user_id) do update
    set email = excluded.email, updated_at = now()
  returning * into row;
  return row;
end $fn$;

grant execute on function
  public.sc_find_user_by_email(text),
  public.sc_bootstrap_profile(text)
to authenticated;

-- ---------------------------------------------------------------------
-- Verify: anon must hold EXECUTE on nothing.
-- Expect zero rows.
-- ---------------------------------------------------------------------
select p.oid::regprocedure::text as still_reachable_by_anon
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname like 'sc\_%'
  and has_function_privilege('anon', p.oid, 'EXECUTE');
