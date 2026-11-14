# R26 — Collaborative Scrapbook Studio

Require-Firebase-Config: true

Previous verified Android preview: 0.1.403. Upgrade safely over the
existing signed installation. Do not uninstall, clear application storage,
recreate partner accounts, or touch existing private data.

## This release includes
- Memories → Scrapbook Studio with four visually designed template previews:
  Love Letters, Our Adventures, Little Moments, Milestone Story.
- Create shared or private scrapbooks as regular RLS-protected Memories.
- Create up to 12 pages per scrapbook; each designed page has 2–3 photo slots,
  subtitle, title, highlight quote and a larger personal story section.
- Direct camera/gallery capture or reuse existing photos, with the same secure
  memory photo bucket. People/place/other tags and captions are edited in
  the linked Memory photo manager and remain searchable.
- Invite partner to contribute to shared scrapbook; invitation is delivered
  via existing OneSpace notification infrastructure and Firebase push.
  Partner must accept to obtain page edit access.
- Partner collaborative edits sync through Supabase realtime and use
  updated_at version checks to protect simultaneous edits.
- Each page can be exported as a high-resolution PNG to Android Pictures/OneSpace
  and passed through the Android native Share sheet. No broad storage access.
- Database migrations 0091/0092 and rollback-only RLS regression test 0014
  passed: uninvited editor denied, invited editor accepted, private view
  blocked, cross-memory photo rejection.
- New Dart widget/template unit tests and validation of existing Memories
  and Auth behavior.
- Preserve all R25 Firebase Android and server-side background notification
  configuration; REQUIRE its Android Google Services secret in every signed build.

## Known limits / acceptance tests
- PNG exports are one page at a time; not a stitched multi-page PDF or printed
  booklet. Native Android export should be tested on a real phone.
- Image loading and template layout on the two physical devices should be
  validated before claiming production-grade scrapbook output.
- An invitation to a shared scrapbook grants edit access only after acceptance;
  the shared scrapbook itself is visible to both partners by design.
- iOS native export is not included in this Android preview.
- Firebase push has one-phone physical confirmation; two-phone push visibility
  remains an open acceptance check.

## Gates
Full Flutter analysis and tests (including scrapbook templates), native Android
release compilation, same app ID com.onespace.onespace.preview, unchanged
preview signing certificate, validated Firebase Android registration and
verified published APK artifact. Publish exactly one controlled preview.

Trigger R26, November 14, 2026.

## Release workflow repair
Fixed YAML for required Firebase configuration, preserved the working Android signing and release jobs. Retry the exact verified R26 source.
