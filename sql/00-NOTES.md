# Scorecards database — notes

**All applied to project `vybypyeyzfgakenkotbw` on 2026-08-29.** Every file is
idempotent — safe to re-run.

| File | What it does |
|---|---|
| `01-schema.sql` | 2 enums, 10 tables, indexes, `updated_at` triggers |
| `02-rls.sql` | 6 helper functions, policies on all 10 tables, 3 RPCs |
| `03-seed-life-balance.sql` | Life Balance template, 8 categories, 241 items, 53 defaults |
| `04-fix-function-grants.sql` | **Security fix.** Revokes the default PUBLIC execute on every `sc_` function |
| `05-fix-insert-returning.sql` | **Bug fix.** Lets an owner create a scorecard |
| `06-seed-sales-marketing.sql` | Sales & Marketing template (5 categories, 56 yes/no questions). Re-runnable; retires removed items |
| `07-weekly-checkins.sql` | `sc_templates.check_in_period`; entries may be dated a Monday (weekly) or the 1st (monthly). Sales & Marketing = weekly |
| `08-admin-global-items.sql` | `sc_admins`, `sc_is_admin()`, `sc_set_global()`: an admin can promote their own question into the shared template |
| `09-default-order.sql` | `sc_set_default_order()`: an admin saves a category's order as the template default |
| `99-rls-tests.sql` | 17-check regression suite. Rollback-only, safe against live data |

Run `99-rls-tests.sql` after any change to a policy or helper. Every row must
say PASS.


---

## Spec §8 → tables

| Spec name | Table | Notes |
|---|---|---|
| `scorecard_templates` | `sc_templates` | + `access_tier`, `slug` |
| `scorecard_categories` | `sc_categories` | + `code` (stable seed key) |
| `scorecard_library_items` | `sc_library_items` | `default_target` split into `default_target_value` (count mode) and `default_target_month` |
| `user_scorecards` | `sc_user_scorecards` | + `daily_threshold` |
| `user_scorecard_items` | `sc_user_scorecard_items` | + `category_id` |
| `scorecard_entries` | `sc_entries` | + denormalised `user_scorecard_id` |
| `scorecard_daily_log` | `sc_daily_log` | + denormalised `user_scorecard_id` |
| `scorecard_shares` | `sc_shares` | unchanged |
| `scorecard_rosters` | `sc_rosters` | + `status`, `member_label` |
| — | `sc_profiles` | new: one row per auth user, holds `timezone` + `plan` |

### Why the departures

- **`sc_` prefix on everything.** `public` already holds the time tracker's
  `profiles / channels / sessions / plans / dayplans`. Its `profiles` means
  "Mark vs Tamara" — an in-app persona, not an auth user — so it cannot be
  reused for `timezone` and `plan`.
- **`owner` not `user_id`** on owned tables, matching the time tracker's
  migrations exactly. `sc_profiles` keeps `user_id` because it *is* the PK.
- **uuid PKs, not text.** The tracker uses client-generated text ids because
  it is local-first. uuids give the same offline-safe client generation
  (`crypto.randomUUID()`) with a real type and real foreign keys.
- **`user_scorecard_id` duplicated onto entries and the daily log.** Every RLS
  check on those two tables becomes one indexed lookup instead of a join back
  through the item table. They are the hottest tables in the app.
- **`category_id` on user items.** Custom items have no library row to inherit
  a category from, and Check-in grouping becomes a single-table read.

---

## The due-cycle rule the app must implement

The prototype hardcodes closing months:

```js
q -> m%3===2 (Mar/Jun/Sep/Dec)   s -> Jun/Dec   a -> Dec
```

That is exactly the December pile-up spec §4 says to avoid. The schema stores
`target_month` per item instead, and the rule generalises:

```
daily | weekly | monthly   always due
quarterly                  (month - target_month) mod 3 = 0
semiannual                 (month - target_month) mod 6 = 0
annual                     month = target_month
```

With `target_month = 12` this reproduces the prototype byte for byte, so the
ported scoring engine can be verified against it before the spread is turned on.

**The seed deliberately leaves `default_target_month` null.** The app assigns
`target_month` at selection time, spreading long-cycle items across the year.
If it forgets to, the fallback is the prototype's December behaviour — i.e. the
bug. Worth an assertion in the adoption code.

---

## RLS shape

`sc_user_scorecards`' read policy needs `sc_shares`, and `sc_shares`' read
policy needs `sc_user_scorecards`. Written as plain subqueries that is
infinite recursion. All six helpers are `security definer`, which runs them
with RLS off and breaks the loop. They are the only unfiltered readers of
those tables.

| Mechanism | Grants | Consent |
|---|---|---|
| 6.1 share to view | `sc_can_view` | none — owner gives access away |
| 6.2 share to co-own | `sc_can_edit` | none — same |
| 6.3 roster | `sc_can_view` | **required** — roster owner is *taking* access, so nothing is visible until `status = 'accepted'` |

Without that last row anyone could type a stranger's email into a roster and
read their private Life Balance card.

**Registered users only.** Both `sc_shares.shared_with_user_id` and
`sc_rosters.member_user_id` are `not null`. The app resolves an address with
`sc_find_user_by_email()` and, on a miss, tells the owner the person has to
sign up first. Nothing sits pending in the database.

Members respond only through `sc_roster_respond()`. RLS cannot restrict which
*column* an update touches, so a member-facing update policy on `sc_rosters`
would let a member set themselves as `owner`.

---

## Two bugs found after the first apply

**Anonymous email enumeration** (`04`). Postgres grants EXECUTE on new
functions to PUBLIC, and PostgREST exposes anything `anon` can execute.
`02-rls.sql` only *added* a grant to `authenticated`, which restricted
nothing — so `sc_find_user_by_email()` was callable with no session, using the
publishable key that ships in the page, and returned a real `auth.users` uuid.
Fixed by revoking from `public`/`anon` and adding `auth.uid()` guards inside
the two functions that matter.

**Owners could not create a scorecard** (`05`). PostgREST always adds
RETURNING, so the SELECT policy has to pass on the brand-new row.
`sc_cards_select` was just `sc_can_view(id)`, and `sc_can_view` is STABLE and
looks the row up in `sc_user_scorecards` — the table being inserted into. A
STABLE function runs on the snapshot from the start of the statement, so the
new row is not there, the policy returns false, and the insert is rejected as
an RLS violation even though the INSERT itself was legal.

> **Rule this establishes:** an RLS policy on table X must never depend
> *solely* on a stable function that re-queries table X. Give it a direct
> predicate on the row first — here `owner = auth.uid() or sc_can_view(id)`.
> Shares, rosters, entries and items are unaffected; their helpers read a
> different table.

Both are covered by `99-rls-tests.sql` now.

## Known gaps

- **241 items, not the ~264 in spec §11.** The prototype's library is the
  source of truth here and it holds 241: Faith 27, Spouse 31, Family 34,
  Friends 15, Health 34, Self 30, Wealth 31, Work 39. The 53 first-run
  defaults all resolve cleanly, matching the spec's per-category table.
- **`sc_profiles.plan` is user-writable** under the current policy. Fine while
  every tier is free; revoke the column before charging.
- **Scoring stays client-side**, as in the prototype. Spec §11 requires shared
  and roster views to be live rather than snapshots, and RLS already lets a
  viewer read the rows they need to recompute. No materialised month scores.
