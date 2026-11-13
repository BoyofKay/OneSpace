# OneSpace World — Contacts from Coordinate

**One Life. Two Places. One Space.**

This first World directory is intentionally a **read-only index**, not a second independently editable address book.

## Behavior
- World now contains a **Saved contacts** entry.
- Only contacts from the signed-in partner's RLS-visible Activities appear.
- Contacts are retrieved on demand with a bounded query (up to 200 recent entries), ordered by most recently created.
- Search matches the contact card title, original Activity title, named person, phone number, email address, physical address and working hours.
- Cards present the same tap-to-call, email and map actions as Coordinate. Calls/emails are never sent automatically.
- Each card links back to its **original Activity** for editing, discussion, evidence and audit history.
- Data is not cloned or migrated into a duplicate table. Existing per-Activity privacy and editing-history rules continue to govern access.

## Deferred
- A full World person/contact master record with multiple associated Activities, deduplication and explicit relationship roles (family, school, doctor, etc).
- Contact import/export and native address-book integration (requires explicit permission and privacy considerations).
- Pagination when the contact index grows beyond the first 200 RLS-visible entries.
- Bilingual World/Contact labels and advanced date handling.

## Acceptance
- Create a shared Activity with a Contact component; it appears in the World index on both authorized accounts.
- Create a private Activity contact; unauthorized partner cannot see it.
- Search by phone, person's name, business title, or hours.
- Tap "From" to return to the original Activity with full collaboration context.
- RLS and app test validation are required before production.
