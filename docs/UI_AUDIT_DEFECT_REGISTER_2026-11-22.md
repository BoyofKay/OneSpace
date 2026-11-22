# UI audit defect register (run #4, 2026-11-22)

Source: GitHub Actions run 45040948697 ("UI audit robot"), branch `claude/project-thread-gwl96u`, QA backend, demo couple Omar & Lina.
106 photos per shape. Reviewed: phone, phone-landscape, foldable-open, tablet-landscape (all variants in the logs, English and big-text photos viewed).
Not reviewed by eye: tablet (portrait) and small-phone photos (artifacts are on the run page until 2026-12-06).
Contact sheets: `*-en.jpg`, `phone-bigtext.jpg` next to this file.

Priorities: P0 blocks use, P1 major function broken or hidden, P2 visible defect with workaround, P3 polish.

| # | Pri | Shape / variant | Screen | Actual | Expected | Likely code |
|---|---|---|---|---|---|---|
| 1 | P1 | phone-landscape, all | Sign in | Form cut off below the password field; Sign in button off screen, keyboard covers the rest | Form scrolls; button reachable | sign-in screen (needs scroll view / portrait lock on phones) |
| 2 | P1 | phone-landscape, tablet-landscape, foldable-open, all variants | Quick add sheet | Sheet overflows by 419 px (phone landscape), 436 px with big text, 167–207 px on foldable/tablet; yellow-black stripe, second row of options cut off | Whole sheet visible or scrollable | `lib/features/quick_add/quick_add_sheet.dart` (no `isScrollControlled`, no scroll) |
| 3 | P1 | tablet, tablet-landscape | Every screen | App squeezed into a 720 dp strip in the middle, rest blank; navigation rail never shows | Use the width: rail + wider content / two panels | `TabletFrame` in `lib/main.dart` |
| 4 | P1 | phone-landscape | Today and all tabs | Only a thin band of content is visible between the header and the bottom bar | Phones locked to portrait (Step 1 plan) | `lib/main.dart` orientation setup |
| 5 | P2 | phone, en-bigtext | Quick add sheet | Labels clipped ("Reminde", "Somethi"), small overflow (0.5 px) | Labels wrap or tiles grow | `quick_add_sheet.dart` grid tile size |
| 6 | P2 | all shapes and variants | Appearance & themes | Theme preview cards overflow (9.9 px, 20 px in landscape, 33–46 px big text): yellow stripes | Cards fit their content | appearance screen theme preview card |
| 7 | P2 | phone, en-bigtext | A little love | Gesture tiles overflow by 17 px (14 tiles), stripes under each label | Tiles fit the bigger text | love / gestures grid tile |
| 8 | P2 | phone, en-bigtext | Bottom navigation bar | Labels break mid-word ("Rememb/er", "Coordina/te") | Shorter labels or icon-only selected label | home shell `NavigationBar` |
| 9 | P2 | phone | Calendar | "Add event" button covers the "Nothing scheduled for this date" text | Extra bottom padding under the list | calendar screen |
| 10 | P2 | phone, en-bigtext | Add note | Formatting toolbar labels squashed ("Headi/ng"), icons labelled "Und…", "Hig…" | Toolbar scrolls sideways | note editor toolbar |
| 11 | P3 | all, ar | App start | Flutter warns locale `ar` is not supported by all localization delegates | All delegates support Arabic | `localizationsDelegates` in `lib/main.dart` (likely Quill) |
| 12 | ? | all | Notifications, Calendar, Notes, Occasions, Trip detail, To-do (some shapes) | Photo shows only a loading spinner | Content | Probably the robot photographed too early (it waits a fixed time). Recheck with a longer wait before calling it a defect |

## Not tested
Real devices, real keyboard (simulated as a 45% bottom inset), iOS, Android system back/rotation behaviour, partner (Lina) view, any write actions (robot only opens forms, never saves).
