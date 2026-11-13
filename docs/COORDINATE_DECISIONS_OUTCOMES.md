# OneSpace Coordinate — Decision & Outcome log

## Why this exists
Partners need a permanent record of why they selected a heater, registered for gymnastics, postponed a trip, or reopened an Activity. A status badge is not sufficient.

## Event model
- `activity_decisions`: append-only, server-attributed event log. No direct insert, update or delete privileges for signed-in clients.
- `record_activity_decision(activity_id, action, component_id, reason)`: authenticated, validated, atomic command to add an outcome and update the Activity stage together.
- Actions: chosen, purchased, delivered, registered, postponed, reopened, cancelled.
- Chosen requires a matching nonarchived Option in the same Activity.
- Purchase, delivery and registration reuse the last recorded chosen candidate when none is supplied.
- Reads inherit parent Activity visibility via RLS.
- Option name is resolved in the UI from the same Activity's visible components. Comments, notes and original research do not disappear on completion.
- Status revision trigger is kept, so the original stage and subsequent changes remain in the audit history.

## Current UI
- 'Choose this option' appears on the Option context menu; the Activity's Decision panel also offers a candidate picker.
- The latest outcome is visible with a reason, creator and local display of its server timestamp. Prior entries expand below.
- Everyday exploring/comparing statuses remain selectable from the compact toolbar. Decided, purchased, registered and completed actions use the new outcome log.

## Security invariants
- One authenticated shared-space partner can record an outcome on a shared Activity.
- Only a private Activity's creator can record its outcome.
- An arbitrary option from another Activity is rejected.
- Anonymous users cannot call the command or read the table.
- Do not modify/delete historical outcome events, or infer a joint vote from a single partner's like/dislike.
- No changes to legacy task/list/note records or partner accounts.

## Device acceptance cases
1. Partner A creates three options. A chooses option B with a reason.
2. Partner B sees chosen option, name and reason in the Decision panel.
3. B records a purchase, A records delivery; history shows all three, Activity ends completed.
4. Reopen and choose another option without losing prior decisions or discussion.
5. Attempt to select a component from a different Activity; database rejects it.
6. Private Activity is never writable by its nonowner partner.
7. Both users see the same outcome after reopening the Activity on their Android phones.
