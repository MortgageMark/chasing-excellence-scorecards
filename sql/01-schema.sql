-- =====================================================================
-- Chasing Excellence Scorecards — 01 SCHEMA  (PROPOSAL, NOT YET RUN)
--
-- Target: the EXISTING Daily Time Tracker Supabase project
--         (ref vybypyeyzfgakenkotbw) so one login serves both apps.
--
-- Everything here is prefixed `sc_` because `public` already holds the
-- time tracker's profiles / channels / sessions / plans / dayplans.
-- `public.profiles` in that app means "Mark vs Tamara", NOT an auth user,
-- so this app cannot reuse it and adds `sc_profiles` instead.
--
-- Conventions inherited from the time tracker's migrations:
--   owner uuid not null default auth.uid() references auth.users(id)
--   snake_case, created_at / updated_at timestamptz, guarded statements.
-- Departure: uuid primary keys instead of text. The client still supplies
-- them (crypto.randomUUID()) so offline creation works.
--
-- Run order: 01-schema.sql -> 02-rls.sql -> 03-seed-life-balance.sql
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Enums. Structural values only. `list` is deliberately NOT reserved
-- (spec 3.4). Softer policy values are text + check so they can change
-- without ALTER TYPE.
-- ---------------------------------------------------------------------
do $enum$ begin
  create type sc_scoring_mode as enum ('binary','scale','count');
exception when duplicate_object then null; end $enum$;

do $enum$ begin
  create type sc_frequency as enum
    ('daily','weekly','monthly','quarterly','semiannual','annual');
exception when duplicate_object then null; end $enum$;

-- ---------------------------------------------------------------------
-- updated_at trigger
-- ---------------------------------------------------------------------
create or replace function public.sc_touch_updated_at()
returns trigger language plpgsql as $fn$
begin new.updated_at = now(); return new; end $fn$;

-- =====================================================================
-- ACCOUNT
-- =====================================================================

-- One row per auth user. Holds the things spec 11 puts "on the profile":
-- timezone (daily-log day boundaries) and plan (entitlements).
-- Created by the app on first load — deliberately NOT a trigger on
-- auth.users, because a failing trigger there would break signup for the
-- time tracker too.
create table if not exists public.sc_profiles (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  email        text,                       -- lowercased copy; powers share-by-email
  display_name text,
  timezone     text not null default 'America/Chicago',
  plan         text not null default 'free' check (plan in ('free','pro')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create unique index if not exists sc_profiles_email_idx
  on public.sc_profiles (lower(email)) where email is not null;

-- =====================================================================
-- TEMPLATE CONTENT  (global, read-only to clients, seeded by SQL)
-- =====================================================================

create table if not exists public.sc_templates (
  id                    uuid primary key default gen_random_uuid(),
  slug                  text not null unique,           -- 'life-balance'
  name                  text not null,
  description           text,
  score_label           text not null default 'Score',  -- 'Balance'
  scoring_mode          sc_scoring_mode not null default 'binary',
  allows_multi_instance boolean not null default false,
  is_published          boolean not null default false,
  access_tier           text not null default 'free' check (access_tier in ('free','pro')),
  organization_id       uuid,                           -- null = platform template
  sort_order            integer not null default 0,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create table if not exists public.sc_categories (
  id          uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.sc_templates(id) on delete cascade,
  code        text not null,              -- 'faith' — matches the prototype's cat ids
  name        text not null,              -- 'Faith'
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (template_id, code)
);

-- `code` is a slug of the original label and is the seed's idempotency key,
-- so a later typo fix in `label` updates the row instead of duplicating it.
create table if not exists public.sc_library_items (
  id                   uuid primary key default gen_random_uuid(),
  category_id          uuid not null references public.sc_categories(id) on delete cascade,
  code                 text not null,
  label                text not null,
  default_frequency    sc_frequency not null default 'monthly',
  default_target_value integer,           -- count mode only (spec 3.3)
  default_target_month smallint check (default_target_month between 1 and 12),
  is_default_on        boolean not null default false,   -- first-run 53 (spec 11)
  is_active            boolean not null default true,    -- retire without deleting
  sort_order           integer not null default 0,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  unique (category_id, code)
);
create index if not exists sc_library_items_cat_idx
  on public.sc_library_items (category_id, sort_order);

-- =====================================================================
-- USER DATA
-- =====================================================================

create table if not exists public.sc_user_scorecards (
  id              uuid primary key default gen_random_uuid(),
  owner           uuid not null default auth.uid() references auth.users(id) on delete cascade,
  template_id     uuid not null references public.sc_templates(id) on delete restrict,
  label           text,                    -- multi-instance subject (spec 7)
  checkin_cadence text not null default 'monthly'
                    check (checkin_cadence in ('weekly','monthly')),
  -- spec 12 leaves the daily threshold open; per-card covers both futures.
  daily_threshold numeric(4,3) not null default 0.700
                    check (daily_threshold > 0 and daily_threshold <= 1),
  started_at      date not null default current_date,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists sc_user_scorecards_owner_idx
  on public.sc_user_scorecards (owner, is_active);
create index if not exists sc_user_scorecards_template_idx
  on public.sc_user_scorecards (template_id, owner);

-- One row per item the user can see on a card: library items they kept,
-- library items they dropped (is_selected false), and their own additions.
--   library_item_id null   -> custom item, label lives in custom_label
--   renamed_label not null -> user override of the library label
-- Effective label = coalesce(renamed_label, custom_label, library.label)
--
-- Departure from spec 8: category_id is stored here too. Custom items have
-- no library row to inherit a category from, and it makes the Check-in
-- screen's grouping a single-table read.
create table if not exists public.sc_user_scorecard_items (
  id                uuid primary key default gen_random_uuid(),
  user_scorecard_id uuid not null references public.sc_user_scorecards(id) on delete cascade,
  library_item_id   uuid references public.sc_library_items(id) on delete set null,
  category_id       uuid not null references public.sc_categories(id) on delete restrict,
  custom_label      text,
  renamed_label     text,
  frequency         sc_frequency not null,
  target_month      smallint check (target_month between 1 and 12),  -- long-cycle closing month
  target_value      integer,                                          -- count mode
  is_selected       boolean not null default true,
  track_daily       boolean not null default false,
  sort_order        integer not null default 0,
  added_at          timestamptz not null default now(),
  removed_at        timestamptz,           -- soft delete; history must survive
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint sc_item_has_a_label check (library_item_id is not null or custom_label is not null)
);
create unique index if not exists sc_user_items_one_per_library_item
  on public.sc_user_scorecard_items (user_scorecard_id, library_item_id)
  where library_item_id is not null and removed_at is null;
create index if not exists sc_user_items_card_idx
  on public.sc_user_scorecard_items (user_scorecard_id, category_id, sort_order);
create index if not exists sc_user_items_daily_idx
  on public.sc_user_scorecard_items (user_scorecard_id)
  where track_daily and removed_at is null;

-- One row per item per month. period_start is always the 1st.
-- user_scorecard_id is denormalised so every RLS check is one lookup
-- instead of a join through the item table.
create table if not exists public.sc_entries (
  id                     uuid primary key default gen_random_uuid(),
  user_scorecard_id      uuid not null references public.sc_user_scorecards(id) on delete cascade,
  user_scorecard_item_id uuid not null references public.sc_user_scorecard_items(id) on delete cascade,
  period_start           date not null,
  value_bool             boolean,
  value_int              integer check (value_int >= 0),
  value_scale            smallint check (value_scale between 1 and 5),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  constraint sc_entries_month_start check (extract(day from period_start) = 1),
  constraint sc_entries_single_value
    check (num_nonnulls(value_bool, value_int, value_scale) <= 1),
  unique (user_scorecard_item_id, period_start)
);
create index if not exists sc_entries_card_period_idx
  on public.sc_entries (user_scorecard_id, period_start);

-- Opt-in daily tracking (spec 5). At month end the item counts as complete
-- when the day count clears sc_user_scorecards.daily_threshold.
create table if not exists public.sc_daily_log (
  id                     uuid primary key default gen_random_uuid(),
  user_scorecard_id      uuid not null references public.sc_user_scorecards(id) on delete cascade,
  user_scorecard_item_id uuid not null references public.sc_user_scorecard_items(id) on delete cascade,
  log_date               date not null,        -- in the profile's timezone
  completed              boolean not null default true,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  unique (user_scorecard_item_id, log_date)
);
create index if not exists sc_daily_log_card_date_idx
  on public.sc_daily_log (user_scorecard_id, log_date);

-- =====================================================================
-- SHARING  (spec 6)
-- =====================================================================

-- 6.1 share to view + 6.2 share to co-own. Same table, different `access`.
-- The card owner is giving access away, so no consent from the recipient
-- is required. Registered users only: the app resolves an address to a uuid
-- with sc_find_user_by_email() and refuses when there is no account yet.
create table if not exists public.sc_shares (
  id                  uuid primary key default gen_random_uuid(),
  user_scorecard_id   uuid not null references public.sc_user_scorecards(id) on delete cascade,
  shared_by           uuid not null default auth.uid() references auth.users(id) on delete cascade,
  shared_with_user_id uuid not null references auth.users(id) on delete cascade,
  access              text not null default 'view' check (access in ('view','edit')),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (user_scorecard_id, shared_with_user_id)
);
create index if not exists sc_shares_recipient_idx
  on public.sc_shares (shared_with_user_id);

-- 6.3 roster: same template, separate private cards, one aggregated viewer.
-- Unlike a share this is the viewer TAKING access, so it requires the
-- member to accept. Only status='accepted' grants visibility.
create table if not exists public.sc_rosters (
  id             uuid primary key default gen_random_uuid(),
  owner          uuid not null default auth.uid() references auth.users(id) on delete cascade,
  template_id    uuid not null references public.sc_templates(id) on delete cascade,
  member_user_id uuid not null references auth.users(id) on delete cascade,
  member_label   text,                    -- what the roster owner calls them
  status         text not null default 'pending'
                   check (status in ('pending','accepted','declined')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (owner, template_id, member_user_id)
);
create index if not exists sc_rosters_member_lookup_idx
  on public.sc_rosters (member_user_id, status);

-- =====================================================================
-- updated_at triggers
-- =====================================================================
do $trg$
declare t text;
begin
  foreach t in array array[
    'sc_profiles','sc_templates','sc_categories','sc_library_items',
    'sc_user_scorecards','sc_user_scorecard_items','sc_entries',
    'sc_daily_log','sc_shares','sc_rosters'
  ] loop
    execute format('drop trigger if exists %I on public.%I', t||'_touch', t);
    execute format(
      'create trigger %I before update on public.%I
         for each row execute function public.sc_touch_updated_at()',
      t||'_touch', t);
  end loop;
end $trg$;
