> Superseded by [R12–R17 consolidated plan](PLANNED_R12_R17_BUNDLE.md). Keep this older plan for history only; it does not trigger a build.

# Planned private preview — R12 through R16 (NOT AN APK BUILD TRIGGER)

## Release intent
Consolidate all committed source since the last verified APK preview-0.1.395 into exactly one signed, upgrade-installable Android preview.

Current readiness: source and database additions staged; static checks performed; **Flutter analyzer, test suite, Android compilation, APK signing and device acceptance pending**.

## Included
- R12 contact cards, Daily Check-In refinements, Letters/gesture pools.
- R13 Shared Experiences, ratings, discussions, Today agenda.
- R14 Trips & Journeys, itinerary, currency-aware estimates and realtime.
- R15 private travel documents (PDF/images), authorized signed previews, native picker.
- R16 Android share-sheet intake for external links/text with Coordinate comparison options; Occasions & Surprises planner with budgets/lead time; daily selfie gallery and scrapbook presets.
- Release publish job avoids repeat attempts after permissions failure; signed APK retained as Actions artifact.

## Before the ONE build
1. Run a single `flutter pub get --enforce-lockfile` and `flutter analyze --no-fatal-infos` plus `flutter test` when build capability is available.
2. Resolve failures in source first; keep `pubspec.lock` and signing key stable.
3. Confirm DB migrations 0058–0069 are applied and existing two accounts/memberships/space/content unchanged.
4. Verify Android native share intent and document picker compile.
5. Test SQL/RLS access boundaries with both independent app accounts if possible.
6. Only then update `release/READY_TO_BUILD.md` **once** (this is the one APK trigger), with a fully reviewed, consolidated release note.
7. Verify APK signed certificate and package ID match the installed preview; user upgrades without uninstall.
8. Install on both Android test phones, then run [full acceptance checklist](../docs/CONSOLIDATED_PREVIEW_R12_R16_QA.md).
9. Do not advertise a public launch; iOS testing and several external/background integrations remain separate.

## Guardrails
- Never reset/delete auth accounts, space memberships, or saved records.
- Don't run Actions verification repeatedly for individual commits.
- Don't modify `release/READY_TO_BUILD.md` until explicitly ready for the build.
- If GitHub Releases returns HTTP 403, retrieve verified APK from the completed build's Artifacts instead of wasting retries.
