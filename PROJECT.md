# Chasing Excellence Scorecards — Project Handoff

**Read this first if you are a new chat session picking up this project.**

- **Live:** https://scorecards.chasingexcellence.net (Netlify, auto-deploys `main`)
- **Repo:** `MortgageMark/chasing-excellence-scorecards`
- **Database:** Supabase project **DailyTimeTracker** (`vybypyeyzfgakenkotbw`), shared with the time tracker. All objects are prefixed `sc_`.
- **Owner:** Mark (non-technical; dictates by voice).

---

## How Mark wants to work (standing rules)

1. **Short replies.** Only say what he needs to know or do. No lists of fixes.
2. **Any SQL he must run: paste the full SQL in the reply** (in a code block) and say "Supabase → DailyTimeTracker → SQL Editor → paste → Run". Never just name a file.
3. **Deploy when work is done**: commit on the session's feature branch, push, open a PR, merge to `main` (Netlify deploys). He does not want to be asked each time.
4. Ask before building big new things only when the choice is genuinely his. Otherwise use judgment ("I trust your judgment").
5. Test before shipping (see Testing).

## The app

Single file `index.html` (vanilla JS + inline CSS, state object `S`, string-template `render()`), Supabase JS client `SB`, installable PWA (`manifest.json`, `sw.js` caches icons only — never `index.html`). `netlify.toml` stamps a build id into the version string shown under Settings.

```
index.html          the whole app
sw.js, manifest.json, icon-*.png, apple-touch-icon.png, favicon-32.png
ce-mark-gold.png, ce-mark-white.png    brand monograms (header/icons)
sql/00-NOTES.md     list of every SQL file — READ before touching the DB
sql/01..16          idempotent migrations (all applied through 16 once Mark has run it)
sql/99-rls-tests.sql  regression suite, rollback-only; run after policy/helper changes
```

### Brand
Navy `#102937` base (`--ink`), `--slate #163347`, `--raise #1C4259`, `--line #2A4A5E`, `--bone #EEF3F3`, `--muted #8FA6B3`, `--accent #48A0CE`, `--gold #D9A441`. League Spartan headings, Arial body. Text scaling via `--z` (Standard/Large/XL).

### What exists
- Multiple scorecards (shared templates: Life Balance, Sales & Marketing; plus user-made/copied private ones). Check-in periods: monthly / weekly / daily.
- Answers: done / not done / **N/A**. Tap = toggle; **swipe right = done, swipe left = N/A**.
- Optional longer-cycle items with due/late (`due_at`/`late_at`: weekly 1–7, monthly day, longer = month*100+day).
- Bottom nav: Check-in/Today · Score · History · Items · Settings. Home = Scorecards list + Settings. CE monogram in header.
- Today (daily) has a scrollable day strip, look chips (Clean / Sections / Time of day — **Clean is default**), hide-completed, score display.
- Items screen: collapsible sections, drag reorder, "show only what I'm using", **item edit screen** (✎ or the "Repeats…" line): icon, name, color, section, repeat/due/late, time of day; admin tools (make global, rename for everyone, save default order/fields); delete custom items.
- Per-item emoji icon, time of day, color (color needs SQL 16).
- Admins (`sc_admins`, `sc_is_admin()`) can promote items to the shared template and edit wording/defaults for everyone.
- Settings page: account, show-longer / due-only toggles, text size, time-of-day colors, open-this-device-to (start scorecard), change password, version / check for updates.
- Deep link `?s=<templateId>`; preferences in localStorage (`ces-*` keys).

### Not built yet (agreed next)
1. **Printable grid tracker** (weekly/monthly; items down the side, days across; tap cells; N/A mark; totals: best day, percentages, perfect days; print CSS).
2. **Month calendar** (tap a day to jump) — both behind buttons inside the **History** tab.
3. Stats (monthly rate, streaks, perfect days).
Explicitly skipped for now: goal-value counts, reminders, item start/end dates.

## Testing (do this before pushing)
- Node harness scripts that evaluate the app's `<script>` with stubs (copy the pattern used earlier; recreate if missing).
- Real browser: Playwright + Chromium are preinstalled (`require('playwright')`, `chromium.launch()`), good for screenshots and mouse/touch tests.
- SQL: validate against a throwaway local Postgres 16 before giving it to Mark.
- iOS notes: no `viewport-fit=cover`, opaque status bar, safe-area paddings. Bump the SW cache name only if cached asset names change.

## Database rules
- Everything `sc_`-prefixed. The tracker's `public.profiles` is NOT an auth user; this app has `sc_profiles`.
- After changing functions: end SQL with `notify pgrst, 'reload schema';`.
- Run `sql/99-rls-tests.sql` after any policy change; every row must say PASS.
- Online only, no IndexedDB (deliberate). Separate auth storageKey `ces-auth`.

## Git
Develop on the branch the session names (previously `claude/sales-marketing-scorecard-r0ks8h`). If its last PR is already merged, restart the branch from latest `main` before new work. Never reuse a merged PR.
