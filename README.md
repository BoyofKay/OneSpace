# OneSpace

**Two of us, One Space.** A private Flutter app for couples — living together or apart — that keeps the shared life in one place.

- Website: **https://onespace.live** (English + Arabic). Website source: public repo [BoyofKay/onespace-app](https://github.com/BoyofKay/onespace-app).
- Latest Android preview: **0.1.444** (R80, 17 Nov 2026) on [GitHub Releases](../../releases). iPhone: waiting for the Apple Developer account (TestFlight, see `docs/IOS_SETUP.md`).

**Continuing this project (any assistant): read [docs/DECISION_LOG.md](docs/DECISION_LOG.md) first.** It is the single source of truth for decisions, the working agreement and the iteration plan.

## What the app does (as built at R80)

Five tabs, fixed (D50): **Today · Remember · Coordinate · Connect · Me**

| Tab | What is in it |
|---|---|
| **Today** | The couple's dashboard: hero with how you live (together/apart), two clocks and weather when apart, next good time to talk, last/next time together; Since you were away; Needs your attention; next 7 days; shortcuts; Quick add. Opens instantly from a saved copy, one server call. |
| **Remember** | Shared calendar (month/week/day, special dates, public holidays, one-way export to the phone calendar) · To-do lists and checklists · Reminders (me / partner / both, repeat, quiet hours) · Notes (rich text, links, backlinks) · Our places (been there / bucket list, OpenStreetMap) · Counters (the day itself vs its anniversary, linked dates) · Contact cards (import / save to phone) · Occasions & gifts (budget, gift ideas, preparation timeline). |
| **Coordinate** | Activities (options with prices/specs, both partners' reactions, conversation with @mentions, voice notes and photos, decision record, change log) · Trips (flight options compared, stays, itinerary, packing, private travel documents). |
| **Connect** | Letters (sealed until a date) · A little love (manual gestures and private self-reminders — automatic gestures are retired, D1) · Daily check-ins · Shared experiences (movies, shows, music, books, games; mutual picks, both ratings) · Memories (stories, daily selfie together, scrapbook studio with 20+ designs, PDF). |
| **Me** | Profile and partner, settings (relationship, theme, schedule, holidays, weather), language and currency, help & support (FAQ, contact, report a problem with screenshot), download my data, delete my account. |

Across the app: Shared vs Only me on every item, "Create from this" with linked items both ways, share-in from any app (shops, streaming, Google Flights, Maps, text with dates, photos/PDF) with an "Items to sort" tray, push notifications that say who did what (in the recipient's language), English and Arabic (RTL) per person, nine themes, biometric app lock. Voice commands exist in code but are hidden (D55).

## Architecture

| Part | Detail |
|---|---|
| App | Flutter (stable 3.50), `material_ui`, `supabase_flutter`, `flutter_quill`, `flutter_map`, Firebase Messaging (push only). Code in `lib/features/<area>/`, shared building blocks in `lib/core/`, themes in `lib/theme/`, Arabic phrases in `lib/l10n/phrases_ar.dart` (UI text goes through `tt()`). |
| Backend | Supabase project `ugwrpeduzyzrujkizqfo` (Seoul). Every table has RLS; the app uses only the publishable key. Schema history: `supabase/schema/0001…0133` (each change is a numbered file **and** a recorded migration). |
| Edge functions (app) | `onespace-push-delivery` (push via FCM), `onespace-account-purge` (account deletion). Source in `supabase/functions/`. |
| Edge functions (website) | `founder-join`, `founder-confirm`, `founder-admin`, `founder-unsubscribe`, `site-contact` — the Founder waitlist and website forms. They use their own `private.founder_*` tables and do not touch app tables. Source: `backend/founders/` in the website repo. |
| Demo data | Fictional couple Omar (Toronto) & Lina (London) in their own space, for website and store screens only (`private.demo_*`, migrations 0132–0133, D70). |

## Workflows (GitHub Actions)

| Workflow | When |
|---|---|
| Verify OneSpace iteration | Every iteration branch: `flutter analyze` + tests. |
| Build and publish OneSpace APK | Only when `release/READY_TO_BUILD.md` changes on `main` (or manual). Signed preview, install as an in-place update — never uninstall. |
| iOS build | Unsigned compile check until the Apple account exists. |
| Database backup | Scheduled backup (needs the backup secrets). |
| Screenshot robot | Runs from the website repo (`app-screens` workflow) against this code: `integration_test/screenshots_test.dart`, `tools/screenshots/`. |

## Develop

```
flutter pub get
flutter analyze
flutter test
```

Android preview package: `com.onespace.onespace.preview` (development signing key under `tools/dev-signing/`, never for production). Install new previews over the old one.

## Documents

- `docs/DECISION_LOG.md` — decisions D1–D76, working agreement, iteration plan (start here).
- `docs/HANDBOOK_R45.md` — how the app worked at R45 (older; the decision log records what changed since).
- `docs/R46_*` … `docs/R78_QA.md` — per-iteration notes and two-phone test scripts.
- `docs/R74_SETUP.md` — owner setup steps (Google/Apple sign-in, backups). `docs/IOS_SETUP.md` — iPhone checklist.
- `website/` — **archived** first version of the website (16 Nov). The live site is built from the public repo `onespace-app`; do not edit here.
