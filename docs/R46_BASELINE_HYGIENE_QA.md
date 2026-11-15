# R46 — Baseline hygiene (decided items only)

Branch: `r46-baseline-hygiene` · Date: 15 Nov 2026 · Decisions recorded in the OneSpace claude.ai Project ("OneSpace_Working_Baseline").

## What changed

| # | Change | Where |
|---|---|---|
| 1 | Migration history repaired: schema files 0095–0105 (R30–R44) were live but missing from Supabase's migration log. They are now registered (pointing to their source files). No SQL was re-run. | Supabase `supabase_migrations` |
| 2 | **Automatic love gestures retired** (decision #1). The 5-minute sender job is unscheduled; schedules and consent are switched off; personal gestures no longer carry an automatic trigger; app users can no longer create schedules. Past automated gestures stay in history. | `0107_r46_retire_automatic_gestures.sql`, Settings, Profile, A little love |
| 3 | **Shared Goals removed from the app** (decision #2): Connect hub link, Today shortcut, global search section and screen removed. The `goals` table and its single record are kept untouched (no data deleted). | `lib/` |
| 4 | Tagline set to the approved brand line **"As a couple, we have One Space"** (startup screen, Today; English in both languages as previously approved). | `main.dart`, `onespace_strings.dart` |
| 5 | Stale copy removed: Connect no longer says daily selfies are "planned"; World no longer promises "more of our wider world". | `section_hubs.dart` |
| 6 | Developer performance panel moved out of the Profile list into a small "Troubleshooting" link under Sign out. | `profile_settings_screen.dart` |
| 7 | Meeting counter: a "last time we met" date of today shows **Today** (yesterday shows **Yesterday**) instead of "Coming up". | `shared_space_screen.dart` |

Already compliant, no change needed: Activity chat bubbles show initials only (decision #7).

## Deliberately NOT in R46
Everything that needs a design decision (Today redesign, filters/history icons, creation flow, share-in Inbox, relationship model) waits for the UX Redesign Specification. The dead "urgent" branch for to-dos in Needs attention will be removed when Needs attention is rebuilt in R47.

## Two-phone test script (after installing the R46 APK)

1. Open **Settings → Affection & notifications**. Expect only **My love gestures**; no "Thoughtful little rituals".
2. Open **Profile → Schedule & days off**. Expect working days, work hours, bedtime and wake-up; **no** "Allow scheduled gestures" switch. Change a time, save, reopen: the value is kept.
3. **A little love → Settings → Create my own gesture.** Expect name, message and theme only (no "automatic trigger"). Save it; send that type to your partner; the partner receives it.
4. Edit an existing personal gesture; it saves without error.
5. **Connect** tab: no "Shared goals" entry, and no "Daily selfies… are planned" sentence.
6. **World** tab: text reads "People & contacts live in Remember."
7. **⋮ → Search our space:** search for any word; there is no "Goal" filter or result type; other results still open correctly.
8. **Today:** tagline reads "As a couple, we have One Space". In Settings → Our relationship, set *Last time we met* to today → Today shows **Today**; set it to yesterday → **Yesterday**; set 10 days ago → **10 days ago**. Clear it afterwards if you wish.
9. Restart the app (cold start): the splash shows "As a couple, we have One Space".
10. **Profile:** no "App performance" row in the list; a small **Troubleshooting** link appears under Sign out and opens the timings.
11. Wait past a morning/after-work/bedtime moment: **no automatic gesture arrives** for either partner.
