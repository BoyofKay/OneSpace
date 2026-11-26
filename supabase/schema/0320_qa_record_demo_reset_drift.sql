-- 0320 (26 Nov 2026): record a QA change that was made without a schema file.
--
-- Found by comparing QA and Production function fingerprints on 26 Nov 2026:
-- QA's private.demo_reset(text) (demo couple Omar & Lina, used by the
-- screenshot and UI-audit robots) was edited directly in QA after 22 Nov:
--   * demo profiles accept the current terms version 2026-11-22;
--   * Omar's surprise "Lina's birthday" occasion lives in his personal space
--     (space_id null, private_space_id = Omar), as the personal/shared model
--     of ADR 2026-11-20 requires for "Only me" items.
-- This file reproduces exactly that edit on top of the Production definition,
-- using private.patch_function (0245), which fails if a fragment is missing.
-- QA already has it: running it there again fails harmlessly with
-- "Fragment 1 not found", so it is for Production (at the next go-live) only.
--
-- 16 other QA functions differed only by Windows line endings (same logic),
-- and qa_dispatch_due_account_deletions differs only by the project URL, as
-- intended. No action needed for those.

select private.patch_function('private.demo_reset(text)'::regprocedure, array[
$a$terms_version = '2026-11-16'$a$,
$b$terms_version = '2026-11-22'$b$,
$a$occasion_plans (space_id, created_by, title, occasion_on$a$,
$b$occasion_plans (space_id, private_space_id, created_by, title, occasion_on$b$,
$a$values (sp, o, 'Lina''s birthday', d + 19$a$,
$b$values (null, o, o, 'Lina''s birthday', d + 19$b$
]);
