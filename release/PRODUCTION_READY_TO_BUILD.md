# Explicit Production Android build request — 2026-11-18

- Artifact: signed Android App Bundle (.aab) for live.onespace.app
- Backend: OneSpace Production only
- Version name: 1.0.0 (workflow default)
- Tests: flutter analyze + flutter test + Firebase registration + signing/package checks
- Distribution: workflow artifact only; no automatic Play Console upload or release
- Purpose: rebuild the current main revision after QA hardening and security review
- Trigger: an explicit change to this file on main, never a routine source commit
