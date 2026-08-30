# Chasing Excellence Scorecards — Project Handoff

**Read this first if you are a new chat session picking up this project.**

- **Live:** https://scorecards.chasingexcellence.net *(not deployed yet)*
- **Current release:** v2
- **Status:** binary mode working end to end, local only

---

## 1. Where everything is

| Thing | Where |
|---|---|
| Local clone | `C:\Users\markn\OneDrive\Desktop\Claude Folder\Scorecards` |
| GitHub | `https://github.com/MortgageMark/chasing-excellence-scorecards` |
| Host | Netlify, auto-deploy from `main` |
| Database | Supabase project `vybypyeyzfgakenkotbw` — **shared with Daily Time Tracker** |
| Local dev | `python -m http.server 8899 --directory Scorecards` |

```
index.html                       the entire app (264 KB, all CSS/JS inline)
manifest.json                    PWA manifest
sw.js                            service worker - icons only, never index.html
netlify.toml                     build command, cache headers, SPA rewrite
sql/00-NOTES.md                  READ THIS before touching the database
sql/01..05                       migrations, all applied, all idempotent
sql/99-rls-tests.sql             regression suite - run after any policy change
Chasing_Excellence_Scorecards_Spec_v2.md    the build spec
life-balance-scorecard-prototype.html       reference implementation
icon-*.png                       placeholder icons, swap when branding lands
```

---

## 2. The three rules

**The prototype is a reference implementation, not a mockup.** The scoring
engine, due-cycle logic, radar math, first-run defaults and the 241-item
library are already correct in it. Port them. Do not rebuild or redesign.

**The database is shared with the time tracker.** Every table, function and
type in this app is prefixed `sc_`. The tracker's `public.profiles` is an
in-app persona (Mark vs Tamara), *not* an auth user — this app has its own
`sc_profiles`, one row per login.

**Run `sql/99-rls-tests.sql` after any policy or helper change.** It is
rollback-only and safe against live data. Every row must say PASS. Two real
bugs shipped past code review and were caught only by running it — both are
written up in `sql/00-NOTES.md`.

---

## 3. What works

Binary mode, end to end: adopt a scorecard (241 items, 53 on), check in, score,
radar, history, edit items. Auth and PWA shell forked from the time tracker.

**"One login" means one Supabase account, not single sign-on.** Different
domains, so localStorage is not shared. The apps use different auth
`storageKey`s (`dtt-auth` vs `ces-auth`); you sign in on each separately.

**Online only, no IndexedDB.** Deliberate. A monthly check-in is not something
you do on a plane, and the tracker's sync engine carries a bug class (deletes
not propagating) this app does not need.

## 4. What does not exist yet

Following the spec's build order:

- Daily tracking and the Today screen (spec §5). The `⚡` toggle is absent from
  the Items screen rather than present and dead.
- Sharing UI (spec §6). The database and RLS are done and tested; there are no
  screens.
- Scale and count modes (spec §3.2, §3.3). The schema holds them already.
- Home / status board and Library screens (spec §9). Only needed once a second
  template exists.

## 5. Open decisions

Carried over from spec §12: brand hex codes and logo, per-item daily threshold
(fixed at 70%), the 7.0 positive-month line, and data export.
