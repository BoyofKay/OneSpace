# OneSpace Production Google Play bundle — go-live 27 Nov 2026
Signed Android AAB for live.onespace.app and Production Supabase (Frankfurt).

- Source: main = approved-2026-11-27 (f9105c6, UAT round 2) + the A7 Arabic
  word fix (41264ce, unit-tested, owner retests in the next iteration) + book.
- Production database already has 0320–0324 (applied 27 Nov before this build).
- Signing: OneSpace Play upload key only. Version code = workflow run number (12).
- Owner uploads the AAB to Play Console by hand; nothing is published automatically.

---

# OneSpace Production Google Play upload bundle (2026-11-19)

Signed Android AAB for live.onespace.app and Production Supabase.
Code matches QA source (Gmail invitation formatting correction and
branded HTML invitation delivery) except for release marker text.

- Manual Google Play closed-testing upload only; no automated rollout
- Required signing: OneSpace Play upload key (never QA signing key)
- Required Firebase configuration and production environment verification
- Flutter analyzer and automated tests must pass
- Check App Bundle package ID, signing certificate and unique version code
- Email templates use original OneSpace mark and Two of Us. One Space
- Official store badges only when their validated product URLs are configured
- Production email sending remains authenticated and rate-limited

## Source correction
- Rebuild with fixed invitation popup scope and unique Arabic string keys.

## Test correction
- Use current store-availability wording in invitation email regression tests.
