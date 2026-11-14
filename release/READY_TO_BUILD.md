# R23 — Notes 2.0, Advanced Recurring Checklists & Occasion Shopping Lab

Previous verified preview: 0.1.400. Controlled Android test release.
Upgrade over installed preview. **Never uninstall, clear app data, or reset existing accounts.**

## Included
- Genuine OneSpace Notes 2.0 WYSIWYG editing with pinned Flutter Quill 11.6.0, formatted headings/lists/bold/italic/links, plain search text plus structured Delta JSON, existing note image attachments, shared/private RLS and optimistic edit conflict protection. Previous plain text notes remain readable.
- Occasion Planner now stores merchant, product URL, purchase price, expected delivery, retailer review rating, own preference score (1–5), order/shipping/return status, order number and optional tracking link.
- Interactive Occasion gift-combination selection with estimated total, budget comparison and late-delivery warnings; save proposed combinations and revisit/edit individual items before buying. No invented exchange rates; separate-currency items excluded from total.
- Advanced checklist schedules: weekday/weekend/selected weekdays/workdays, every N days/weeks, month days, configurable US federal holidays/personal days off/excluded dates, optional IANA timezone per checklist, per-person independent checked state per occurrence.
- Database schema migrations 0084–0086 applied and verified. No existing user records reset.
- Test suite extended for advanced recurrence; rollback-only SQL privacy regression passed for structured notes and private gift-combination selections.
- Existing R22 Reminders and notification deep links, R21 Android Contacts and Memories retained.

## Verification
- Flutter dependency lock committed and checked; full Flutter analyze/test suite green before triggering this build (GitHub run 43605304275).
- Publication only if exact commit passes Flutter analysis/tests again, Android Kotlin/Gradle compilation, correct signed preview certificate and unchanged package com.onespace.onespace.preview.
- One APK from this release marker.

## Still outstanding (not claimed delivered)
- Firebase Cloud Messaging, device push delivery and credential setup; reminders currently in-app.
- Full template-driven collaborative Scrapbook Studio (current photo memory tagging and gallery continue).
- Comprehensive Trips planning/search/offline encrypted itinerary/document experience.
- Shared Experiences richer metadata, Games external invitation, AI productivity companion, voice/Siri commands and hands-free spoken checklist.
- Thoughtful A Little Love sender-private suggestions replacing autonomous sending.
- True native iOS contact share extension, real-device testing, server relocation (deferred), and additional deeper system hardening.
- Automated order sync with Amazon/Walmart is NOT implemented; tracking is user-supplied only.

## Device acceptance recommendations
Test Notes 2.0 create/edit/read-only/shared/conflict, Occasions 3 competing gift options and proposed lists, purchase/returns, recurrence near weekend/holiday, partner checkmark separation, and biometric sign-in. All should preserve real records.

Trigger: R23 signed Android test preview, 2026-11-14.
