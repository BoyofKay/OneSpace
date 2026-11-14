# R21 — OneSpace Core Trust and Connections Android Test Preview

Baseline install: R20 preview-0.1.398. **Upgrade in place: never uninstall, clear app data or re-create user accounts.**
Release type: controlled two-partner Android preview, NOT production.

## Included in this candidate
- R21 migration 0077: safely moved the four old standalone tasks under one shared **Old checklist** as subitems, preserving original rows and statuses for recovery. New list UI hides archived/migrated parent task records.
- Checklist flow: create a named checklist, expand and add subitems, per-person completion state for shared lists (separate checkmarks per cycle), narrow task-scoped realtime queries, and assigned-partner completion restrictions. Recurrence advanced settings are NOT part of this preview.
- R21 migration 0078: task-scoped per-person check history with RLS update restrictions; searchable people/place/other tags on Memory photos.
- Memories: fixed R16 insert column privileges; camera-first Daily Selfie or gallery, explicit shared/private selection, photo tags, text/tag search, in-memory photo gallery camera capture. Existing shared memories remain editable by both partners.
- Android Contacts: explicit native contact picker, controlled permission prompt only on import, company/role/website, duplicate-detection preview with private default, Android Save to Contacts, Android vCard external-share intake. iOS Contacts extension remains unimplemented.
- R21 migration 0079: retired unused old Lists/shopping tables and template RPC after verifying they contained zero records. Today Explore legacy Lists tile removed; existing home-snapshot count keys retained as zero for old preview compatibility.
- Safe SQL privacy regressions for shared/private checklists, partner checkboxes, and memory insertion passed and rolled back.

## Not claimed complete
- Real-device tests of Android Contacts provider permissions, NFC/URI-specific vCards, camera permissions and 2-account biometric flow.
- Flutter Quill Notes 2.0, dedicated reminders, push notifications, unified sign-in, next generation scrapbook composer, advanced recurrent schedule and occasions.
- Supabase leaked-password protection (separate Auth setting) and RLS audit of public.record_activity_decision remain open.
- The existing R20 APK still has an outdated Lists UI until upgraded.

## Publication gate
Trigger one signed reproducible optimized test preview APK only after committed-lockfile dependency validation, Flutter 3.50 analysis/tests, Android native Kotlin/Gradle build, fixed preview signing identity and package ID verification. Preserve the package id com.onespace.onespace.preview. Publish the verified artifact to GitHub Releases and retain the workflow artifact. A failing build must not be published.

Safety: do not delete pairings, users, saved documents, trips, check-ins, or live memories. Do not perform a server region migration. Test upgrades in place on both Android phones.

Trigger: R21 controlled Android preview after SQL and Flutter checks, November 14, 2026.
