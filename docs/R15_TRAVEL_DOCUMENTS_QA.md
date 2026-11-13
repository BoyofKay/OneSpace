# R15 — Private Travel Documents & Attachments

## Product scope (committed to source, migrations deployed)
- Attach PDF boarding passes, tickets, itineraries, receipts and scanned document images to any trip; optionally associate each file with a specific itinerary item.
- Android system document picker (`ACTION_OPEN_DOCUMENT`) and iOS system document picker (`UIDocumentPickerViewController`) use an existing Flutter platform channel. No new Flutter package or lockfile change.
- 10 MB maximum per file; only PDF, JPEG, PNG and WebP; validate file signatures on the Flutter side, not filename extension alone.
- Private Supabase Storage bucket `onespace-trip-documents` and metadata `trip_attachments`, with RLS matching the parent trip visibility.
- Paths are trip UUID / uploader UUID / random document UUID + validated extension. No public bucket, predictable filename paths or permanent public URLs.
- Files are opened through user-authenticated, 90-second signed URLs. Photos preview in a zoomable dialog; PDFs open through the device's external document viewer/browser.
- Add, relabel, categorize, associate to an itinerary item, archive and restore. **No irreversible file deletion** on normal user actions; failed metadata inserts may roll back only the requesting uploader's unreferenced file.
- Shared-trip new document notices route directly to the corresponding trip; no notification for private trips. Realtime metadata stream keeps document lists synchronized across devices.
- Global search includes document titles and routes the result to its authorized trip.

## Data-preservation contract
- Existing auth accounts, household pairing, activities, check-ins, documents, memories and previous trips are untouched.
- Database migrations 0065/0066 only add a bucket, table, helper function, policies, notification category and realtime publication.
- Existing R14 trip data remains valid; there is no forced backfill.
- Soft archival preserves metadata and the original binary for restoration.

## Security acceptance tests
1. Account A uploads a boarding-pass PDF under a shared trip; account B can see metadata and open the document using a short-lived signed link.
2. Account A attaches an image scan under a private trip; account B must not see the trip, document title, image, or storage bytes, including through Global Search.
3. Account B tries to use a known `object_path` for account A's private trip; signed URL generation must be denied.
4. Owner attempts an out-of-trip or forged `object_path` INSERT: database/storage policies must reject it.
5. Partner cannot edit `file_name`, `object_path`, `trip_id`, `created_by` or `mime_type` via API.
6. Archive and restore on either phone changes visibility; bytes are retained and files become viewable again after restore.
7. The owner cannot delete a registered document directly in Storage; only an orphaned own upload is removable for rollback.
8. A PDF larger than 10 MB, unsupported MIME/signature, empty file or interrupted upload produces an actionable error, with no partial document metadata.
9. A document linked to an itinerary item appears with the correct label; a removed item can still be recovered using the trip history.
10. Both devices receive a shared-document notification when appropriate; private documents never notify the other user.
11. Test Android device PIN/biometric flows and both device profiles to ensure no signed file URL is stored in permanent preferences.
12. Test iOS UIScene document picker and PDF viewing independently: native platform code is committed, but a macOS/Xcode compile and actual iOS device test are **still required**.

## Engineering status and limitations
- SQL migrations have been applied successfully and storage bucket verified private; RLS enabled.
- Static delimiter/source integrity checks performed for touched Dart, Swift and Kotlin files.
- Dart unit tests for file signatures, size limits and path restrictions have been added but **not run**.
- Flutter analyzer, Kotlin compile, Swift compile, Android APK build and two-phone acceptance **not performed** in this iteration.
- GitHub Actions quota is exhausted. No workflow dispatch, no CI marker change, no Actions retry and **no APK build triggered** by R15.
- Before release: run Flutter analyze/test, Android signed preview, verify iOS via Xcode and manual file/document/privacy testing.
- This feature does not automatically parse flight PNRs or extract itinerary fields from uploaded PDFs; it stores and previews files.
