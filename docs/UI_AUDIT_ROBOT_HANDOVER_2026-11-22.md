# UI audit robot: handover (2026-11-22)

This note lets any Claude session pick up the tablet, foldable and landscape UI audit work.
Read it together with `docs/DECISION_LOG.md`.

## Why this exists

Amr ran the app in Android Studio's resizable emulator and found it breaks in landscape, on
tablets and on open foldables: the lock screen is cut off, Today cards are huge, Quick add is
clipped, forms hide behind the keyboard, and the bottom bar is cramped. He asked for:

1. An assessment of adaptive layout (two panels on tablets and open foldables) and a
   portrait-only lock on phones. The recommendation is below.
2. A UI audit run by a robot on GitHub, not by computer-use on his PC (that would use too
   much Claude quota).

Rules still apply: QA only, no Production, and no QA build until Amr says.

## The robot

| Part | File |
|---|---|
| Test that drives the app and takes the photos | `integration_test/ui_audit_test.dart` |
| GitHub workflow (manual) | `.github/workflows/ui-audit.yml`, named "UI audit robot (tablet, foldable, landscape)" |
| Demo couple seed fix (QA) | `supabase/schema/0319_qa_demo_seed_personal_occasion.sql` |

How it works:

- It runs the real app (QA backend, `--dart-define=ONESPACE_ENV=qa`) as a **Linux desktop
  program** under `xvfb`. There is no Android emulator. The old store-screenshot robot
  (`screenshots.yml`) used a software emulator that ran at about 4 frames a second and went
  offline mid-run, so it never finished.
- It resizes the app window to six shapes in dp: `phone` 393×852, `small-phone` 360×640,
  `phone-landscape` 852×393, `foldable-open` 690×841, `tablet` 800×1280 and
  `tablet-landscape` 1280×800.
- It takes each shape in four variants: `en`, `ar`, `en-dark` and `en-bigtext` (text ×1.6).
  It also takes forms with the keyboard up, simulated as a bottom inset of 45%.
- It signs in as the fictional demo couple **Omar & Lina** (`demo.omar@example.com`, password
  in the `DEMO_PASSWORD` repo secret). It photographs the sign-in screen, the 5 tabs, Quick add
  and its Reminder/To-do/Event/Note forms, Notifications, Calendar, To-do lists, Reminders,
  Notes, Occasions, Trips, Counters, Places, Love, Letters and Appearance, plus one activity,
  one trip and one occasion detail.
- `audit_log.txt` lists every photo (`SHOT …`), every Flutter layout error per screen
  (`ERROR <shape>__<variant>__: A RenderFlex overflowed …`) and anything the robot could not
  find (`MISSING …`).
- The workflow first resets the demo space once (job `plan`, best effort). Then it runs one
  parallel job per shape, about 9 to 10 minutes each. Photos are in the run's
  `ui-audit-<shape>` artifacts, kept 14 days. Files are named `<shape>__<variant>__<NN_screen>.png`.

### Running it

Actions → "UI audit robot (tablet, foldable, landscape)" → Run workflow. You can narrow the
`shapes` and `variants` inputs. From a Claude session, use GitHub MCP `actions_run_trigger`
with `workflow_id: ui-audit.yml`. A branch name as `ref` runs that branch's version of the
robot; the workflow file must also exist on `main`, which it does since PR #143.

### Running it locally (Linux)

```bash
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
  libsecret-1-dev gnome-keyring dbus-x11 xvfb
flutter pub get --enforce-lockfile
DEMO_PASSWORD=... AUDIT_OUT=/tmp/ui_audit AUDIT_SHAPES=phone,tablet AUDIT_VARIANTS=en \
dbus-run-session -- bash -c 'echo -n x | gnome-keyring-daemon --unlock --components=secrets >/dev/null;
  xvfb-run -a -s "-screen 0 1920x1440x24" flutter test integration_test/ui_audit_test.dart \
    -d linux --dart-define=ONESPACE_ENV=qa'
```

Pitfalls already solved:

- Without an unlocked keyring, `flutter_secure_storage` aborts the app with `LibsecretError`.
  The test shows only "did not complete".
- `debugDefaultTargetPlatformOverride = android` is set only **after** Supabase has started.
  Setting it earlier makes the app run the Android-only install check and hang.
- The root layer is in physical pixels, so `toImage` takes the physical size.
- Without `DEMO_PASSWORD`, only signed-out screens are photographed.

To review, make contact sheets with ImageMagick, for example
`montage -label '%t' -geometry 300x650+4+4 -tile 7x phone__en__*.png sheet.png`.

## Status at handover (2026-11-22, 15:55 UTC)

- PR #143 (robot) is merged. Follow-up commits are on branch `claude/project-thread-gwl96u`
  and **not merged yet**:
  - `0ae8a64`: workflow keeps going if the demo reset fails
  - `5a44462`: robot gets past the Terms screen; adds migration file 0319
- Run #2 (`45038757149`) completed all 6 shapes (324 photos), but it is **not a valid audit**:
  - The demo space was empty, because `private.demo_reset` failed. It inserted a *private*
    occasion inside the *shared* space, which `private.occasion_validate_budget_link` rejects.
    **Fixed in QA on 2026-11-22 with Amr's OK** (0319 applied: the occasion is now in Omar's
    private space, and the demo accounts get Terms version 2026-11-22).
  - The robot never reached the home tabs. The demo accounts were on the 2026-11-16 Terms and
    the app's `termsVersion` is 2026-11-22, so the app stopped at the Terms screen. The test now
    photographs that screen, calls `accept_terms` and signs in again.
- A phone-only check run on the branch was started around 15:48 UTC to confirm the home tabs
  are now reached.

### Next steps

1. Check the phone-only run: the log should have no `MISSING tab` lines and should include
   `01_home` and `01_today` photos.
2. If it's good, run the full workflow on the branch with all shapes and variants.
3. Review the contact sheets and write the defect register (P0 to P3, shape, variant, screen,
   expected vs actual, likely code location). Deliver it to Amr in plain language.
4. Open a PR for the branch commits (robot follow-ups + 0319 file) so `main` matches QA.

### Defects already confirmed from photos

| # | Pri | Where | What |
|---|---|---|---|
| 1 | P1 | Sign-in, `phone-landscape` | The form is cut off below the password field, and the keyboard covers everything (Amr's emulator showed the same) |
| 2 | P1 | Every screen, `tablet`/`tablet-landscape` | The app is squeezed into a 720 dp strip in the middle (`TabletFrame` in `lib/main.dart`). It also tells the app the screen is 720 wide, so the existing `NavigationRail` (which needs ≥900×620) can never appear |
| 3 | P2 | Appearance & themes, all shapes | Theme preview cards show yellow "BOTTOM OVERFLOWED BY 9.9 PIXELS" stripes (13 px and 33–36 px with big text) |
| 4 | P2 | Calendar, phone | The "Add event" button covers the "Nothing scheduled for this date" text and the line below it |
| 5 | P3 | Arabic | Flutter warns that locale `ar` is not supported by all localization delegates (probably the Quill or an SDK delegate) |

## Adaptive layout assessment (agreed direction, not built yet)

- Android 16 with targetSdk 36 (Flutter 3.50) **ignores orientation locks** on screens whose
  smallest width is at least 600 dp (tablets, open foldables). The temporary opt-out goes away
  when targeting Android 17. So locking to portrait can only cover phones.
- **Step 1** (a few days): lock phones (shortestSide < 600) to portrait in Dart; remove or
  rework `TabletFrame` so the rail shows on wide screens; make the Today "Our space" grid
  adaptive (it's fixed at 3 columns with aspect 1.05 in `lib/features/spaces/shared_space_screen.dart`);
  make the Quick add sheet scrollable and scroll-controlled (`lib/features/quick_add/quick_add_sheet.dart`);
  keep forms visible above the keyboard.
- **Step 2** (1 to 2 weeks): two panels (list + detail) on tablets and open foldables for
  Notes, To-do, Reminders, Calendar, Occasions and Trips; show add/edit forms as centred
  dialogs on wide screens.
- iOS: the same robot idea can run on GitHub macOS runners (iPhone + iPad simulators). Mac
  minutes count 10× on a private repo. Do it after iOS PR #134 lands.

### Update 16:00 UTC
- Phone-only check run `45040291124` passed: 30 photos and no `MISSING` lines, so the home tabs
  are reached now.
- Full run #4 started at about 16:00 UTC on branch `claude/project-thread-gwl96u` with all
  shapes and variants, using the fixed demo seed. Its result is next step 3 above. Find it under
  Actions → UI audit robot.
- PR #144 holds the branch commits and this note.
