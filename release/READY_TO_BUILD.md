# R80 — counters fix and theme cards (demo couple, screenshot robot)

Require-Firebase-Config: true

Previous signed preview: R78 (0.1.443).
Preserve the existing com.onespace.onespace.preview Android package,
same signing certificate, Firebase config, biometrics, all account and
partner pairing data, checklists, notes, memories and user documents.
INSTALL AS AN IN-PLACE UPDATE only. Never uninstall or clear data.

## Included since R78
- Counters: the reunion counter is correct in every "living apart" mode.
- Appearance: theme preview cards are taller and no longer overflow on narrower phones.
- Developer only (not in the user experience): fictional demo couple support for the website screenshots, screenshot/clip robot test target.

## Database
- 0132_demo_couple, 0133_demo_couple_global (demo accounts only; no change for real users).

## Verification
- "Verify OneSpace iteration" passed on the R80 branches; screenshots robot ran the full app on an emulator (core, together, themes, video sets) on 16–17 Nov.
