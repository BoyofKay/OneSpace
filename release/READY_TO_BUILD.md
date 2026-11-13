# R12–R17 — OneSpace consolidated Android private preview

Iteration: R12–R17 — Hardened, verified source and one signed Android APK
Previous confirmed APK: preview-0.1.395

## Included functionality
- R12: standalone contacts, Activity-linked contact-card navigation, collapsible editing and history, daily check-in readability, Letters and gesture improvements.
- R13: Shared Experiences (movies, shows, music, books, games), comments, ratings, suggestions and shared planning.
- R14: Trips & Journeys, itinerary, private/shared visibility, partner conversations and currency-aware estimated expenses.
- R15: private PDF/image travel documents, native Android picker, signed previews and archive/restore.
- R16: Android share-sheet intake, saved comparison links/options, Occasion & Surprise planner with budgeting and lead times, selfie and collage memory layouts.
- R17: four Material 3 palettes, Light/Dark/Follow Phone, quiet optional seasonal banners, adaptive tablet/phone navigation, US/EG public-holiday overlays plus fixed Saudi civic dates, birthdays/anniversaries/special occasions with honoree and privacy.

## Quality gate
Verified R12–R17 source at commit 99f950ac3d167736cc88901cf688518d8d1299c7:
https://github.com/BoyofKay/OneSpace/actions/runs/43451478578
- Committed dependency lockfile: passed.
- Flutter analyzer: passed.
- Flutter test suite: passed.
- Two analyzer blockers found in the first run were fixed before verification.
- Non-destructive database migrations through 0071 deployed; two accounts, two memberships and the shared space preserved.

## Release instructions
Trigger exactly one optimized signed preview APK using the repository release workflow. Do not change package ID `com.onespace.onespace.preview`, signing certificate, or user data. Confirm signing fingerprint, artifact availability and GitHub Release URL if permitted. GitHub Release authorization errors must never cause a rebuild or loss of the verified APK. This remains a PRIVATE TEST PREVIEW, not a public production launch.

The physical two-phone acceptance checklist, including upgrade without uninstall, night/day themes, privacy, holiday calendar, trips and documents, remains mandatory after APK delivery.

Trigger: consolidated verified iteration R12–R17, November 13, 2026.
