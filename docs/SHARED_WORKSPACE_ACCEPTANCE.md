# OneSpace — Shared Workspace Slice (Preview QA)

## Delivered in this iteration

| Capability | Database | App | Tests |
| --- | --- | --- | --- |
| Shared/private lists | `lists` with member/owner RLS | Lists tab; type and privacy at creation | SQL visibility tests |
| Shopping and checklists | `list_items`, inherited parent privacy | Add, edit, quantities, units, check off, remove, restore, bulk clear | SQL isolation + Dart validation |
| Archived lists | `archived_at` | Archive, show archived, restore | DB constraints |
| Shared/private notes | `notes`, member/owner RLS | Notes tab, create/edit, pin, archive/restore | SQL privacy + Dart validation |
| Concurrent note editing | Monotonic `updated_at` trigger | Conditional updates block stale saves | SQL concurrency regression |
| Home dashboard | RLS-filtered reads | Task summary and counts for lists and notes; quick links | RLS baseline + existing task summary tests |
| English and Arabic | Existing profile locale | New screens translated, RTL inherited | Translation-key parity test |

The entire iteration is designed as **remote persistent data**. Creating an item on one account should make it visible to the other account if and only if it was created as **Shared**.

## Two-account acceptance checklist

Use your first account and the test partner account. Do not put important private information in test content.

- [ ] Account A opens Lists, creates **Shopping** named "Weekly groceries", visibility **Shared**.
- [ ] A adds "Milk", quantity 2, unit "litres", plus a second item without a unit.
- [ ] Account B opens Lists and sees the same list and items.
- [ ] B checks Milk; A sees it checked after opening the list again (and eventually via live updates when both devices are open).
- [ ] A chooses **Clear completed items**. B does not see them in the active list, but they are visible through **Show removed items**.
- [ ] B restores Milk. Both can see it again.
- [ ] A creates a **Private** checklist. B cannot see the list or its child items.
- [ ] A archives and restores a list; the items remain intact.
- [ ] A creates a **Shared** note and B edits it; A sees B's changes.
- [ ] If A and B both open the same note, B saves first and A tries to save a stale copy: A sees a conflict warning rather than silently overwriting B.
- [ ] A creates a **Private** note. B cannot see it, including in Home totals.
- [ ] A pins and unpins a note, then archives and restores it.
- [ ] Check Home counts for shopping lists, checklists and notes; counts should reflect only content visible to the current user.
- [ ] Change one account to Arabic in More. Lists/Notes and Home should be right-to-left; the other account's language remains independent.
- [ ] Account A and B retain their previous Tasks and pairing after updating the preview APK.

## Privacy and architectural decisions

- Data is shared by **space membership** with Row Level Security, not by client-side hiding.
- List and note visibility is immutable after creation to avoid unintended private/shared transitions.
- All child items inherit the parent list's access control.
- Removal/archiving is recoverable; hard DELETE is not granted to normal client users.
- Server-side timestamps are authoritative. For notes, conditional updates reject a save if another partner has already changed the record.
- Concurrent **list item** edits currently use last-write-wins; note conflicts are protected.
- No notifications, offline edit queue, file/photo attachments, rich-text formatting, or third-party sharing exist in this slice.
- Account deletion, unpairing, retention decisions, security hardening and production signing still require work before public distribution.

## Regression tests

- `supabase/tests/0004_lists_notes_rls.sql`: shared membership vs private content.
- `supabase/tests/0005_notes_concurrent_edit.sql`: rejecting stale note edits.
- `test/lists_notes_validation_test.dart`: bilingual input and numeric/text limits.
- `test/onespace_localization_test.dart`: English/Arabic key parity.

## Backlog after this iteration

The next high-value verticals are a shared calendar with timezone-aware occasions and reminders, milestones/countdowns, memories/attachments, share inbox and cross-app sharing, then privacy and consent workflows including unlinking/account deletion. Include full Arabic accessibility and offline behavior in each vertical.
