# R81 — usage statistics and a Complaint topic (QA build)

Require-Firebase-Config: true

QA app (package onespace.qa, "OneSpace QA"), QA backend. Install as an in-place update over the previous QA build.

## Included since R80
- Usage statistics (decision D78): session length, tabs and screens opened, notification taps — event names and times only,
  never content. On by default; Settings → Privacy → "Share usage statistics" switches it off.
- Support: new "Complaint" topic in Contact us (signed in and from the sign-in screen).

## Database (applied to QA and Production)
- 0137_app_usage_events (private.app_events + log_app_events, 180-day cleanup job).
- 0138_support_complaint_kind.

## Verification
- "Verify OneSpace iteration" (flutter analyze + flutter test) passed on branch r81-usage-complaints, 17 Nov 2026.
- Database function tested in QA: valid events stored, bad names/dates/values rejected, anonymous callers refused.
