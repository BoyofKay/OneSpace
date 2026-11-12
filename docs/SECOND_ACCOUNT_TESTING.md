# Two-account pairing acceptance test (OneSpace Preview)

This is a **development-only** test. Keep actual personal/sensitive data out of the shared space until the feature passes end-to-end acceptance testing.

## Create a temporary partner account through Supabase Auth (not SQL)

Project: `ugwrpeduzyzrujkizqfo`

1. Open [Supabase Authentication → Users](https://supabase.com/dashboard/project/ugwrpeduzyzrujkizqfo/auth/users).
2. Select **Add user → Create new user**.
3. Use the non-deliverable test address `onespace.qa.partner.20261112@example.invalid`.
4. Set a **unique, strong password**, stored privately by the tester.
5. Check **Auto Confirm User** and select **Create user**.

This creates a real Supabase Auth identity using the official admin interface,
while **preserving email verification for all ordinary registrations**.
Never insert fake users directly into `public.profiles`: a profile alone cannot authenticate.
Do not turn off confirmation globally for this test.

Because the address has no inbox, **forgot-password and confirmation emails cannot work for this account**. Use a real email alias for those tests.

## Test on one Android phone

1. Sign in using the first account that already owns the shared space.
2. Open **Home → Create invitation code**. The code appears on screen and is copied to the clipboard.
3. Open **Sign out**.
4. Sign in as the temporary partner account using its private password.
5. Under **Home → Join your partner**, tap **Paste invitation code**, then **Join space**. Do not create a second space.
6. Confirm that the home screen shows **2 of 2 members** and both display names.
7. Open **Plans**, create a shared task, then sign out and sign back in as the first user.
8. Confirm the task is present under Plans. Complete it, switch back to the test user, and confirm the new status is visible.
9. Try reusing the invitation from a third test account later. It must be rejected.
10. In normal testing, generating a replacement code must make the old code unusable; revoking a pending invitation must also invalidate it.

## Acceptance criteria

- [ ] Both test identities can sign in independently, restoring the correct account session.
- [ ] Each profile is separate, but both accounts share the same space.
- [ ] The second account can accept exactly one valid invitation.
- [ ] Both accounts see each other's **display names**, but not private credentials.
- [ ] Shared tasks survive sign-out, reopening, and account switching.
- [ ] An outsider cannot view or change space data.
- [ ] Revoked, expired and reused invitations are rejected.

The database SQL regressions are already passing. This test verifies **actual app behavior**, not merely SQL permissions.

## Cleanup and caution

The dummy email cannot receive recovery emails. Its password must not be shared in a repository, issue, or chat. An accepted test user has genuine access to that shared space, so do not pair it with sensitive real-life data.

Before deleting a paired test user, review linked shared records and deletion rules. The current beta does **not** yet implement a safe self-service unlink or account deletion process; deleting a user without considering linked task/invitation data may be blocked by foreign-key constraints. Cleanup is a separate acceptance task.

## Privacy, assignment and editing acceptance

- [ ] With account A, create a Shared task and assign it to account B.
- [ ] Sign in as B. Confirm it appears and displays B as the assignee.
- [ ] As B, edit its title, priority or target date, then complete it.
- [ ] Sign back into A and verify the edits and completion survived account switching.
- [ ] As A, create a Private task. Sign into B and verify it does **not** appear under All visible, Shared or Private. Home's private-task count must not include A's task.
- [ ] Switch back to A and verify that only A can see and edit the Private task.
- [ ] The task editor must not offer a visibility switch for an existing task.
- [ ] Check Home's open shared, assigned-to-me, my private, and completed shared counts.

The role-based SQL privacy regression in `supabase/tests/0003_task_privacy_and_assignment.sql` passed on the live database within a rolled-back transaction. Physical app acceptance remains separate.
