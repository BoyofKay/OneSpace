# Coordinate — Contact information component

**Two of Us. One Space**

The reusable **Contact Information** component belongs to either the whole Activity or one specific Option (for instance, gymnastics provider B). It can be added through the Activity add menu or an Option context menu.

## Structured fields
- Card title (e.g., Gym B admissions)
- Person to contact (optional)
- Telephone number (optional), including international dialling codes
- Email address (optional)
- Physical address (optional)
- Working hours and time zone if known (free text; do not infer open-now status)
- Notes (optional)

The user must fill at least one contact detail. Phone and email inputs are validated; long fields are bounded to fit within the existing component payload limit. Unknown payload fields survive edits.

## Actions
- **Phone** opens the device dialer; does not place a call.
- **Email** opens the local email composer; does not send mail.
- **Address** opens the existing external Google Maps search flow. It does not request GPS permission.
- Missing fields do not show fake actions.
- On devices without a compatible dialer/email client, the field can be copied.

## Integration
- Contact cards render in readable form without redundant type headings, while retaining original creator and time.
- They can be discussed, edited, reacted to, and audited using the existing Activity component workflow.
- Option-attached contacts contribute common rows (person, phone, email, address, working hours, notes) to the side-by-side comparison.
- Existing RLS and append-only revision history continue to apply; no contact directory or account-level sharing has been created.
- Current email and phone controls are manual, not synced with Google Contacts or a CRM.

## Acceptance tests
- An Activity can hold a standalone contact.
- Gym A and Gym B can hold different named contacts and working hours.
- Comparison aligns those fields and marks unknown values clearly.
- Phone/email/map interactions open their system handlers, without sending or calling automatically.
- Invalid contacts are rejected without destroying an existing saved component.
- Two-partner sync, narrow-screen layout and external-action availability remain device-level acceptance checks.
