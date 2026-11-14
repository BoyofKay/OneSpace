# R45 — Shared Experience conversation lifecycle and permission gates

## Implemented
- Author can edit, retract and restore individual comments; partner can read
  active comments but cannot edit them or see retracted text, even from a direct
  Data API query. Author can opt to show *their own* retracted comments.
- Each comment has an immutable creator, server-updated concurrency timestamp,
  and server-recorded created/edited/retracted/restored events with actor,
  changed field names and time. **No comment body** enters the audit log.
- Conversation has local multiword search across comments, including author's
  own retracted comments only when opted in.
- New comments can insert an @partner mention; the existing comment-send
  notification remains responsible for delivery. Editing does not send alerts.
- No hard-delete, no removal of legacy tasks/checklists, and no data reset.

## Deployment order
1. Apply migration 0106 before installing new APK. This adds a new nullable-
   compatibility timestamp (with default), one column update grant,
   author/privacy-safe SELECT policy and a comment-scoped audit kind.
2. Run rollback-only SQL test 0027 as *authenticated* partner and author;
   ensure visible active, invisible retracted, unauthorized update rejected,
   history/restore safe and no personal comment bodies in audit.
3. Run Flutter analyzer and full tests, including checklist legacy expansion.
4. Build one signed preview APK only after green CI. Install on both existing
   phones without signing, package or account data changes.

## Remaining product-wide consistency work
- Attachment/photo and nested component edit/restore coverage.
- More granular search across child items, archived opt-in and permission
  boundaries, plus additional module text mentions with server routing.
- Manual screenshot contrast checks across all palettes/light-dark and
  image overlays, and both-device notification tap/recipient checks.
