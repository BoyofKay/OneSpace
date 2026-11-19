# OneSpace Production Android Google Play upload bundle (2026-11-19)

Build a signed Android App Bundle (.aab), package live.onespace.app, for
OneSpace Production Supabase. Source matches the QA code initiated by commit
7ac1070d6e5e4fe8b5117720f35b3f221906d921; only release marker text differs.

Contents:
- Invitation UX improvements and safer same-code resend
- Shared invitation landing links and app intake
- Password-manager autofill and email recovery from Profile
- No database schema changes

Security/release conditions:
- Fail if upload signing secrets or production Firebase configuration are absent
- Flutter analyzer and tests must pass
- Verify package ID and upload-key signature
- Generate .aab for manual upload to Google Play closed testing
- Do not automatically publish in Google Play or alter production accounts
- iOS archives from the QA marker are UNSIGNED and cannot go to TestFlight
