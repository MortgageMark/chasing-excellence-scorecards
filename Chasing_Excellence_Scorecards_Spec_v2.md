# Chasing Excellence Scorecards — Build Spec v2

**Platform:** Chasing Excellence Scorecards
**First release:** Life Balance Scorecard
**Date:** August 2026
**Supersedes:** v1 spec

---

## 1. What this is

A template engine for recurring self-assessment. A template defines categories and a library of suggested items. A user adopts a template, selects the items that apply, optionally renames them and changes their frequency, then records progress each period and gets a score per category plus an overall score.

**Life Balance is the first instance, not the product.** Marketing, Culture, Company, Boss, Money Matters, Blueprint for Life, Activity Tracker and others follow using the same engine. Adding a scorecard must be a content task — write the items, load them — never a development task.

Ship Life Balance first. Everything else waits for real usage data.

---

## 2. Naming and hosting

| Layer | Name |
|---|---|
| Platform | Chasing Excellence Scorecards |
| Instance | Life Balance Scorecard, Marketing Scorecard, etc. |

Subdomain of `chasingexcellence.net`. Existing `dailytimetracker.com` stays live and should eventually alias into the same umbrella.

**Stack:** mirror the Daily Time Tracker — new GitHub repo, new Netlify site, **same Supabase project**. One login serves both tools. Installable PWA with its own manifest, service worker, and a visibly distinct icon.

**Palette:** navy ground `#0D1620`, surface `#16212D`, primary blue `#4C9BE0`, teal `#3FA88F` for auto-computed values, coral `#E0705F` for low scores, gold `#E0A93F` for streaks only. Awaiting official brand hex codes. The time tracker should take a different accent in the same shell — siblings, not twins.

---

## 3. Scoring modes

Every template declares a `scoring_mode`. This is the single most important structural decision in the build — all four must exist in the schema even though only three ship in v1.

### 3.1 Binary — v1
Checkbox. Complete or not.
*Life Balance, Marketing, Culture, Boss, Money Matters, Blueprint for Life*

```
category_score = completed_and_due / selected_and_due
```

### 3.2 Scale — v1
1–5 rating per item. Assesses something external rather than the user's own behavior, so per-item frequency cycles generally don't apply — the whole card is rated once per period.
*Company Scorecard: "How competitive is our pricing?"*

```
category_score = sum(ratings) / (5 × item_count)
```

### 3.3 Count — v1
Integer against a target.
*Activity Tracker: calls, voicemails, review requests, leads*

```
item_score = min(actual / target, 1)
category_score = mean(item_scores)
```

Needs its own entry screen: steppers or number pad, running weekly total, previous period visible for context. Tapping checkboxes is wrong for numbers.

### 3.4 List — CUT

Free-text named entries with an open/closed state were considered and **cut**. The mode spanned periods (ask in August, resolve in October), broke the period-scoring model, and needed its own screen.

Practical consequence: on the Activity Tracker, "ask for Google reviews" is a **count** — how many you asked for this period. You lose the names and the strike-through, not the metric. Track the names wherever you track them today.

Do not reserve an enum value. If it comes back later it will need a rethink, not a slot.

### 3.5 Rules common to all modes

**Denominator is what the user selected, not the full library.** Eight of eight selected items is 100%.

**Categories weight equally.** Score each category, then average the categories. The source spreadsheet summed all 124 items into one number, which meant Faith (21 items) moved the total nearly three times as hard as Friends (8) — a user could neglect friendships entirely and still score 90%, in a tool about balance.

**Empty categories are excluded, not zeroed.**

**No minimums.** A user may select zero items in a category. Valid state, no error, no failure styling.

**Display is 1–10, one decimal.** Store the percentage. Always show raw counts alongside — "8.0 (4 of 5)".

---

## 4. Frequency and due cycles

Values: `daily`, `weekly`, `monthly`, `quarterly`, `semiannual`, `annual`

**The scoring period is always the calendar month.** Users may set a weekly reminder cadence, but that only changes how often they're nudged to update the month in progress. If scoring windows varied by user, scores wouldn't be comparable across a roster and the sharing views would be meaningless.

**Only items due in the period count.** Quarterly, semiannual, and annual items sit visible but greyed out and excluded from the denominator until their closing month, where they go live. Users assign a target month when selecting long-cycle items; default to an automatic spread so items don't pile up in December.

This fixes a bug in the source spreadsheet: "Attend Church Retreat" is annual but appears in every monthly column, so it reads as a miss eleven months a year and permanently caps Faith below 100%.

**Frequency is user-editable per item.** The template's value is a suggestion. A user can make "Call Core Friends" weekly instead of monthly.

---

## 5. Daily tracking (binary mode)

Opt-in per item, not global. Health alone has ~25 daily items; nobody sustains 30 taps a day.

A user flags a handful of items to track daily. Those get a Today screen — end of day, not throughout. Underneath, each logged day is recorded; at month end the item counts as complete if the user hit the threshold (default 70% of days, ~22 of 31).

The monthly checkbox stays binary, so everything downstream is unchanged. On the Check-in screen these items display as auto-computed with a day count rather than a tappable box.

This is what makes streaks real rather than approximated, and it powers the encouragement prompt: after a streak threshold, offer one unselected library item from that category. Always optional, never auto-add, remember dismissals.

Completed items on the Today screen: user chooses Leave, Bottom, or Hide. Hidden items return the next day automatically.

---

## 6. Sharing

Do not build a coach role. Build generic per-scorecard sharing; the coach dashboard falls out of it. **Three distinct mechanisms:**

### 6.1 Share to view
Owner shares a scorecard with another registered user. Viewer sees scores, trends, radar, history. Viewer cannot edit check-ins.
*Client shares Life Balance with coach. Employee shares with boss.*

### 6.2 Share to co-own
Multiple users edit one scorecard. A single set of entries — "did we send the newsletter" is one fact about the team, not three.
*Marketing Scorecard shared with two marketing staff.*

### 6.3 Roster
Same template, separate private instances, aggregated for one viewer. Each person's entries are invisible to peers, visible to the roster owner.
*Team Member Scorecard: eight people, eight private cards, one comparison view.*

**Row-level security policies must be written against all three from the start.** Retrofitting visibility rules means rewriting and re-testing every policy in the database.

---

## 7. Multi-instance

A template can be adopted more than once by the same user, each instance carrying a subject label.
*Referral Partner Scorecard, one per agent. Team Member Scorecard, one per employee.*

One nullable `label` field on the user's scorecard record. Trivial now, a rebuild later.

---

## 8. Data model

```
scorecard_templates
  id, slug, name, description, score_label
  scoring_mode           -- 'binary' | 'scale' | 'count'
  allows_multi_instance, is_published, organization_id

scorecard_categories
  id, template_id, name, sort_order
  (categories need not have equal item counts)

scorecard_library_items
  id, category_id, label, default_frequency, default_target
  is_default_on, sort_order

user_scorecards
  id, user_id, template_id
  label                  -- multi-instance subject, nullable
  checkin_cadence, started_at, is_active

user_scorecard_items
  id, user_scorecard_id, library_item_id (nullable)
  custom_label, renamed_label      -- user overrides
  frequency, target_month, target_value
  is_selected, track_daily, sort_order
  added_at, removed_at             -- soft delete; history must survive

scorecard_entries
  id, user_scorecard_item_id, period_start
  value_bool | value_int | value_scale    -- by mode
  updated_at

scorecard_daily_log
  id, user_scorecard_item_id, log_date, completed

scorecard_shares
  id, user_scorecard_id, shared_with_user_id
  access                 -- 'view' | 'edit'
  created_at

scorecard_rosters              [roster view]
  id, owner_user_id, template_id, member_user_id
```

RLS on every user table. Soft deletes throughout — when a user drops or renames an item, historical scores must stay intact.

---

## 9. Screens

**Home** — status board of adopted scorecards, each with score, mini radar, and check-in state. Sorted so what needs attention floats up. Skipped entirely when the user has only one scorecard.

**Scorecard tabs** — Today (only if items are flagged) · Check-in · [Score label] · History · Items

- **Check-in** — grouped by category, only items due this period, live scoring
- **Score tab** — radar with the perfect circle ghosted behind, each spoke labeled with name, score and raw count; category list below
- **History** — overall trend line, summary stats (average, best, lowest, months at 7.0+), most improved and biggest slide, per-category sparklines with monthly values, month-by-month radar grid, streaks
- **Items** — select, deselect, rename, change frequency, reorder, flag for daily tracking, add custom, select all / clear all per category, reset to template

**Library** — browse and adopt templates

---

## 10. Build order

1. Supabase tables and RLS policies in the existing project
2. Auth and PWA shell forked from the time tracker
3. Binary mode end to end: setup, check-in, scoring, radar, history
4. Seed the Life Balance library (~264 items, 8 categories)
5. Daily tracking and streaks
6. Sharing: view, then co-own, then roster
7. Scale and count modes
8. Deploy, install, test on device
9. **Ship Life Balance. Get real users. Then write more libraries.**

Phase two: coach roster dashboard, encouragement engine refinements.

---

## 11. Decisions made

**Backfill is unrestricted.** Nothing ever locks. Users edit any period at any time. No lock flags, no grace windows, no close job.

One consequence to build around: historical scores are mutable, so any shared or roster view is a **live query, not a snapshot**. Don't cache month scores as immutable rows — recompute, or cache with invalidation on entry write.

**Notifications: email first, push if cheap.** A monthly "it's the first" email is the primary channel and works everywhere. Web push is a bonus — iOS supports it only for PWAs installed to the home screen, with real limits. Not worth blocking on.

**Timezone: default America/Chicago, per-user override.** Stored on the profile, used for daily log day boundaries.

**Entitlements: free now, structured for paid.** Build the tables and the check from the start — a `plan` on the profile and an `access_tier` on each template, with everything set to free today. Wiring an entitlement check into a live app later means touching every read path.

**First-run defaults (Life Balance).** 53 items pre-selected across 8 categories, chosen for broad applicability rather than completeness. Full library remains available; users add from there.

| Category | Default count |
|---|---|
| Faith | 6 |
| Family: Spouse | 7 |
| Family | 7 |
| Friends | 5 |
| Health | 8 |
| Self | 6 |
| Wealth | 7 |
| Work | 7 |

Marked `is_default_on` in `scorecard_library_items`. Implemented in the prototype — see its `DEFAULTS` map for the exact list.

---

## 12. Still open

- Brand hex codes and logo file
- Subdomain name
- Per-item daily threshold — fixed at 70% of days for everyone; may want to be user-settable
- Positive vs. negative month threshold (currently 7.0)
- Data export for users who want their history out
