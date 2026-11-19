# OneSpace QA — archive retention and space safety slice 2 (2026-11-19)

Require-Firebase-Config: true

Branch: qa/lifecycle-first-slice-20261119
Android QA only: onespace.qa. Production remains untouched.

Included:
- All earlier invitation and password subpages, verified-recipient pairing
- My Space > My Archives for encrypted app-private automatic archive copies
- Explicit Save archive to Downloads, Android native checksum readback
- Automatic app-private copy DOES NOT trigger server deletion
- User external download acknowledgement + 30-day archive expiry
- Secure private archive registry and recipient-checking download endpoint
- Hourly archive-only Storage cleanup service with service-secret protection
- Read-only space-separation preflight; legacy destructive account deletion
  temporarily disabled in QA until exports and private vault pass validation
- Unit tests for explicit-download-only purge and 30-day retention

Safety: no actual partner separation, no shared-data deletion, no archive
generation (archive registry currently empty), and no Production changes.
Run locked dependencies, Flutter analyze, tests, QA APK signing/package checks.
