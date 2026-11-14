# R26 — Two-device Scrapbook Studio Acceptance

Scope: Android preview built from R26 marker, upgrading over 0.1.403.
Do not uninstall or clear app data. Both partners keep their existing accounts.

## Creation & template gallery
1. Remember your current version and photograph the Memories home screen.
2. Open **Connect → Memories → Scrapbook Studio**.
3. Preview each of the four real designed layouts: Love Letters, Our Adventures,
   Little Moments and Milestone Story. All thumbnails should fit without
   clipped text or image placeholders escaping their artwork.
4. Create a **private** scrapbook. Confirm it appears only on its creator's
   phone and does not appear in the partner's Memories list.
5. Create a **shared** scrapbook. Confirm its name is visible on the second
   phone, but editing remains disabled until an invitation is accepted.

## Partner collaboration + native push
6. On the first phone, tap **Invite**. Background the second phone.
   Expect the generic OneSpace push. Open it through Notifications and
   accept the invitation. If push does not appear, check the in-app feed;
   record whether the issue is transport vs UI.
7. On the second phone, add another scrapbook page, write a new quote,
   and add a photo. Verify the first phone sees the updated design.
8. Check that a contributor cannot edit a **private** scrapbook or a
   **shared** scrapbook before accepting the invitation.
9. Open the same page on both phones, save a change on one, then attempt
   saving an older version on the other: it should show a conflict rather
   than silently overwriting the first edit.

## Photo slots, metadata & PNG
10. Add photo 1 via Android camera and photo 2 via Gallery. Try using an
    existing scrapbook photo for a third slot (where available).
11. Expand **Photo library & searchable tags**. Add people, location,
    other tags and captions. Search Memories by a unique tag and confirm
    the scrapbook is found.
12. Change template on a populated page; existing photos and writing
    must remain associated with the same page.
13. Tap **Export this page as PNG**. Verify a high-resolution PNG appears
    in Android **Pictures/OneSpace**, with correctly rendered photos and
    text. Confirm the native Android share sheet opens.
14. Confirm none of these actions affected existing To-do Checklists,
    Reminders, Notes, or Firebase message delivery.

## Backend acceptance
- Rollback SQL regression: `supabase/tests/0014_r26_collaborative_scrapbooks.sql`
- Private memory cannot be viewed by partner.
- Partner cannot edit pages before invitation acceptance.
- Accepted partner can create and edit pages.
- Photo slot references cannot point to another scrapbook's photo.
- Inviting the partner produces one in-app notification and FCM outbox item.
- R26 release must keep the exact `com.onespace.onespace.preview` package
  and existing signing identity; install **over** 0.1.403.

## Open issues to document rather than guess
- A push received on only one of the phones is not yet a verified two-device
  delivery result. Record which phone/recipient, notification state,
  whether the app was force-stopped and Android notification permission.
- PNG export is Android-only and one page at a time, not a bound PDF book.
- Signed photo previews require a network connection. Offline scrapbook
  caching is not claimed in this release.
