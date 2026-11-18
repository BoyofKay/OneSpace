# Supabase security hardening — 18 November 2026

Applied live to **OneSpace** mobile (`ugwrpeduzyzrujkizqfo`) and **OneSpace Production** website/founder (`letcgxbnblohhfyeuigz`).

## Verified changes
- Anonymous `public.log_client_error` RPC EXECUTE privilege removed, while authenticated diagnostics work.
- Unauthenticated `public.submit_public_support` remains operational; inputs and quotas are bounded, with global/per-email throttles serialized under an advisory transaction lock.
- Both RPC owners are dedicated NOLOGIN, NOBYPASSRLS roles with column-level permissions and RLS policies (no privileged `postgres` owner).
- Explicit RESTRICTIVE deny policies for `anon`/`authenticated` on internal-only RLS tables; no direct client read grants added.
- Private trigger handlers and six internal helper functions lose unnecessary client EXECUTE grants; existing triggers and privileged internal procedures continue to call them.
- Tests: anonymous support + authenticated error report both succeed within transactions rolled back; no test rows persist.
- Security advisor re-run: missing-policy informational lints 0 in both projects; 1 anonymous definer warning remaining by design, 20 authenticated definer warnings requiring per-object authorization audit.
- On the active mobile project the Auth security advisor also flags leaked-password protection, a Supabase Pro-enabled Auth dashboard setting. This requires updating Auth service configuration, not database RLS.
- `Give it up, Boy! beta version` is a separate legacy project and was not modified.

## About the remaining warnings
Supabase flags **any** deliberately exposed SECURITY DEFINER RPC, even when bounded by ownership checks. An unverified warning must not be marked closed or accepted solely because the function has an `auth.uid()` reference. The open task is a two-account, wrong-space/wrong-object IDOR regression suite against all 18 signed-in-only functions. Do **not** blindly revoke them or flip them to SECURITY INVOKER: doing so breaks core flows.

The one public-warning function handles signed-out support and now executes under a restricted, non-bypass role. It remains an intentional exception and deserves abuse/rate-limit monitoring.

## Apply / verify
- The following SQL is the source-controlled representation of the migrations already applied in Supabase. On a new clone run `supabase/schema/0139_security_least_privilege.sql` **after** earlier schema scripts.
- Run `supabase/tests/0028_security_least_privilege.sql` to check privilege invariants (read-only, transaction rolled back).
- Run Supabase Security Advisor and verify the same warning categories; do not interpret any linter count as a penetration test.

Reference: https://supabase.com/docs/guides/database/functions and https://supabase.com/docs/guides/database/postgres/row-level-security.
