# OneSpace QA — Invitation + password feedback (Nov 19, 2026)

## Source observations
QA screenshots from installed Android:
1. Profile > Change password: the **Update password** button was enabled with empty/incomplete inputs; there was no Cancel beside it.
2. Reset password message arrived as `Supabase Auth <noreply@mail.app.supabase.io>`, instead of OneSpace `support@onespace.live`.
3. Invite my partner: actions had uneven spacing/alignment. Resend sent email with no confirmation dialog.
4. Today invitation card repeated **Generate replacement code** and **Revoke invitation** controls already in the invitation full page. Refresh status was left aligned.
5. Tapping invitation email link opened a website instead of opening the installed app.

## Changes completed in QA mobile
- Valid-change-only Update button; Cancel beside Update. Password validation tests.
- Same-code email resend requires confirmation with displayed recipient and preserved expiry.
- Responsive invitation buttons arranged in evenly spaced row; replacement/revoke controls separated inside subpage.
- Removed replacement/revoke from Today; centered Refresh status.
- Verified Android HTTPS App Link intent for **QA-only** path `/qa-invite/`. Production path `/app-invite/` must NOT be claimed by QA app.
- Deep-link parser/tests updated to isolate QA vs Production.
- QA invitation backend email updated to use `https://onespace.live/qa-invite/?code=...`.

## Website changes
- Published `.well-known/assetlinks.json` with observed stable QA signing fingerprint for `onespace.qa`; deployed `.nojekyll` to serve association route from GitHub Pages.
- Published `qa-invite/index.html` as a lightweight *mobile-app handoff only*, no web sign-up.
- Corrected the existing invitation landing's CSP image rule that previously blocked the OneSpace logo.
- Production mobile app/backends not modified. The public website invitation fallback/association files **were** changed.

## Pending external configuration / real-world checks
- Supabase Auth must be configured with custom SMTP sender `OneSpace <support@onespace.live>` in **QA** (and HTML recovery email template installed). Existing invitation email provider does not control Supabase Auth. Details in `docs/QA_AUTH_SENDER_BRANDING_2026-11-19.md`. Do not claim this sender is fixed until tested.
- An uninstalled QA app cannot be installed from the public store because QA distribution is separate. Store badge must not link to Production or an unverified listing; the QA fallback instead explains to use the QA test installer.
- Real Android Chrome/Gmail and device Settings > Opening links verification required for app links, because repository and package checks do not establish OS-level real-world behavior.
- iOS Universal Link association/signing is not part of this Android QA iteration.

## QA acceptance
1. Update disabled initially; stays disabled for missing current, too-short new, mismatch, or same password.
2. Valid change enables button; Cancel returns to Profile without change.
3. Reset email still works securely, while sender branding remains pending SMTP configuration.
4. Tap Resend: confirmation dialog; Cancel sends nothing, Confirm sends same code and expiry.
5. Today no longer duplicates Replace/Revoke, Refresh centered.
6. Buttons spaced and aligned; QR and manual code still work.
7. QA recipient opens `/qa-invite/` and launches installed `onespace.qa` directly; absent app sees only mobile install instructions, no web signup.
8. With both QA and Production apps installed, Production `/app-invite/` must never open QA; security still validates recipient verified email.
9. No Production Android build or Production backend deployment.
