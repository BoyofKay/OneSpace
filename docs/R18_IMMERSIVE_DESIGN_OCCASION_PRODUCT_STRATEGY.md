# OneSpace R18 — Immersive Design & Connected Occasion Intelligence

**Status (Nov 13, 2026): R18 source and additive migration 0072 committed/applied. Verify-only workflow 43460884916 passed locked dependencies, Flutter analysis, and the full automated test suite. No new APK triggered. Physical-device contrast, usability and two-phone acceptance are still pending.**

## 1. Product truth
OneSpace is **one relationship workspace**, not a collection of forms. Core journey:

`Discover / Receive inspiration → Compare → Discuss → Decide → Plan → Reserve budget → Purchase → Celebrate → Remember`

Each state should preserve continuity: what prompted the idea, what the two partners thought, the final decision, budget impact, receipts, lead-time preparation, and eventually the memory. Links are the system's connective tissue.

The product must feel intimate without assuming gender roles, imposing a type of relationship, automatically revealing private surprises, or inferring emotional states from sparse data.

## 2. Original user-approved theme concepts (R18 source restored)
| Concept | Intended mood | Primary treatment | Surface |
|---|---|---|---|
| Midnight Blue | cinematic, premium, immersive | near-black navy, luminous azure and dimensional gradients | deep-navy panels |
| Monochrome | sophisticated, minimal, bold | high-contrast charcoal / ivory, disciplined accent use | graphite panels |
| Clean Light | modern, professional, effortless | cool whites, soft blue and accessible outlines | airy layered white |
| Soft Rose | warm, personal, gentle | rose, plum, soft blush, elegant typography | warm blush panels |

There are **four named design concepts** plus separate Light / Dark / Follow Phone controls; this avoids choosing six arbitrary themes just to maximize count. Existing local preferences are migrated non-destructively from prior palette names.

The theme selector shows a miniature OneSpace composition instead of single-color circles. Every selected concept must be recognizable at five levels: atmosphere, typography, navigation, surfaces, and contextual action affordances.

## 3. Seasonal means a whole experience
App-wide tokens now style the Scaffold atmosphere, background pattern, AppBar, navigation bar/rail, cards, chip states, modal bottom sheets, dialogs, menus, snack bars, inputs, buttons and status accents. They use semantic color contrast, not merely a banner on Today.

Seasonal choices in source: Valentine's, spring, Halloween, winter, Eid, birthday, anniversary, Thanksgiving, Christmas, New Year, Automatic and Off.

- *Automatic fixed-date* overlays currently include Valentine's, spring, Halloween, U.S. Thanksgiving, Christmas and New Year. These are decorative windows, not legal holiday declarations.
- Eid appearances are manual until official lunar dates are available; no date is guessed. Birthday and anniversary appearances can be selected manually **or activated automatically** from the signed-in user's RLS-authorized Occasion records after app unlock. Context is cleared on sign-out and never synchronized to the other device.
- Seasonal vector motifs are subtle: petals, stars, moon shapes, snowflakes and hearts. Never overwhelm user text, especially for dark-mode, accessibility large text, or reduced-motion settings.
- Persist a theme locally per device; each partner can have a different experience.
- Official country holidays, personal occasions, workplace time off and decorative seasons are separate concepts and must not silently change each other.

### Visual design debt to pay down next
1. Full phone screenshots across all five tabs and both auth states for each concept and holiday.
2. Responsive text-scale testing (1x–2x) in calendar, chat, planning, budgets, memories, documents and dialogs.
3. Contrast measurements of all semantic text/background combinations; accessible color must not depend on decorative gradients.
4. Rich but purposeful imagery: user-owned memory cover art, context-specific illustrations, reliable remote image preview, not random stock shots.
5. Consistent motion grammar: route transition, expand/collapse, action confirmation and sheet entrance, respecting reduced motion.
6. Story-driven hero cards in Memories, Connect, and upcoming milestones using actual available content only.

References:
- Flutter Material 3 component theming: https://docs.flutter.dev/release/breaking-changes/material-3-default
- Apple HIG semantic color: https://developer.apple.com/design/human-interface-guidelines/color
- Material 3 expressive hierarchy: https://developer.android.com/design/ui/wear/guides/get-started/levels-expression
- Apple materials / hierarchy: https://developer.apple.com/design/human-interface-guidelines/materials

## 4. Actual Occasion budget lifecycle (R18 source implemented)
The R16 budget was a number and its steps were tasks. That was **not** budgeting.

R18 adds independent `occasion_budget_items`, with:
- wishlist idea, shortlisted option, reserved item, purchased item, skipped item;
- title, quantity, estimated unit price, actual unit price, currency, notes and source URL;
- linked Coordinate Activity and option IDs when imported;
- soft-removable / reversible status and transaction history;
- live aggregate summary (budget, reservations, actual spending, wishlist).

### Money logic
`Committed = Reserved estimate × quantity + Purchased actual (or estimate if actual missing) × quantity`

`Available = Total occasion budget − Committed`

Wishlist and shortlisted ideas do not deduct money. Moving an item to Reserved deducts its estimate. Marking Purchased replaces the reservation with actual spending. **Overspending remains negative and visible.** Unknown prices generate an explicit warning. Other currencies never get invisibly converted or deducted into the budget.

The reference model is the difference between *planned, available, and overspent* emphasized by YNAB. References:
https://support.ynab.com/en_us/focused-views-a-guide-BksnNYqLh
https://support.ynab.com/en_us/overspending-in-ynab-a-guide-ryWoxEyi?mobile-help=true

### Interactivity
- **Add wish** starts in Wishlist; it has no budget impact.
- **Reserve** moves a wish or shortlisted option to Planned, immediately affecting available budget.
- **Mark purchased** opens actual-price capture and changes status to Purchased.
- **Undo purchase** moves back to Planned without deleting history.
- **From Activity** imports an existing Coordinate comparison option.
- An **Activity option card** now has **Send to occasion plan**: select the private/shared destination, link source IDs, copy current data, reserve cost and write an automatic planning log entry.
- A private Activity cannot be linked into a shared occasion. RLS and a database trigger both enforce authorization. A linked source must be from the same space.
- Existing preparation steps remain a separate checklist, not silently transformed into purchases.

### Contextual intelligence implemented
Simple local, explainable rule engine surfaces actions when:
- the occasion is close and nothing is reserved or purchased;
- the budget is overcommitted;
- some committed items have no price;
- costs span unconverted currencies;
- wishlist choices have not been reserved;
- the plan has no items or no budget.

Each insight leads to an action (open shopping, import from Activity, or edit plan). **No third-party AI inference or private-data model calls.**

## 5. Product intelligence we SHOULD build next (R&D, not delivered)
**A. Surprise Studio / Gift Path**
Relationship-safe private planning with a wish inbox, recipient preference signals explicitly shared by that person, vendor links, gift arrival timeline, confirmation and “reveal” moment. Privacy is per item and per workspace.

**B. Decision → Purchase automation**
When an Activity is marked “chosen,” show a contextual optional action: “Reserve for birthday / anniversary / trip,” carrying selected option, partner opinions, price, linked source and known delivery deadline. No silent purchase or AI extraction.

**C. Shopping intelligence**
Compare captured options side by side (price, merchant, specs, vote, warranty, delivery ETA), suggest what *information is missing*, and highlight duplicates. Do **not** invent prices/availability, scrape external vendors without permission, or assume currencies are interchangeable.

**D. True savings pot**
A separate actual-funds ledger for money set aside, deposits and withdrawals. Distinguish *budget target*, *funds actually saved*, *planned reservation*, and *actual paid*. This is NOT implemented by R18: don't claim a running savings balance until recorded deposits exist.

**E. Occasion timeline and dependency graph**
“Choose gift” → “Place order” → “Expected delivery” → “Wrap” → “Celebrate”; lead-time risk reminders, timezone-aware notifications, and optional handoff to partner. Connect Calendar, Coordinate, Tasks, Travel and Memories without duplicating objects.

**F. Celebration into Memories**
After the event, offer a private/shared “Capture the moment” route that copies no private planning surprises unless the owner explicitly chooses to reveal them.

**G. Smart, consensual assistance**
Optional recommendations from user-authorized data only, transparent reasons, quick edit/undo, strong privacy safeguards and zero external model calls unless the person explicitly opts in.

## 6. Business intelligence and product KPI framework
These are **proposed metrics**, not a claim that analytics instrumentation already exists.

North Star: **shared-life outcomes completed together**, not screen taps or message counts.

Leading signals:
- inspiration-to-Coordinate conversion;
- comparison-to-decision rate;
- chosen-Activity-option-to-Occasion-plan flow completion;
- plans with a trustworthy budget and linked items;
- celebrations planned with appropriate lead time;
- partner collaboration and explicit consent rate;
- notification → useful action (not notification quantity);
- budget overruns acknowledged and resolved;
- incomplete purchases with missing actual amount;
- reported privacy violations and permission-denial correctness.

Guardrails:
- never send raw private notes, gift descriptions, intimate messages, locations, photos or partner identifiers into product analytics;
- aggregate event counts on device first; explicit opt-in for telemetry;
- allow exporting/deleting analytics;
- keep private surprises out of shared badges, search and global counters.

## 7. Architecture rules
- One object can be referenced from another; avoid duplicating data as a new independent copy.
- When snapshots are necessary for audit or purchase history, keep immutable origin IDs and the timestamp of copied values.
- Row-level security protects each family/partner boundary; UI hiding alone is insufficient.
- Mutations are idempotent where retries are possible. Preserve existing account sessions, pairing, activities and memories.
- Use bounded queries and stale-response guards on high-frequency lists.
- Never run a new release build because a source-only feature was committed.

## 8. R18 acceptance and caveats
Source has been committed and migration 0072 applied; no new release. Verify-only run https://github.com/BoyofKay/OneSpace/actions/runs/43460884916 passed Flutter analysis and tests; it is not a new APK or phone acceptance.
Before a future APK:
1. Run Flutter analyze and all widget/unit tests.
2. Validate theme appearance over all screens and modal surfaces in Light, Dark and Follow Phone, including RTL/large text.
3. Test all seasonal choices and graceful suppression when Off.
4. Create occasion budget 500 USD, add Wishlist 200, Reserve 100, Purchase actual 90: available must be 410 USD.
5. Confirm foreign-currency rows are not silently deducted.
6. On phone A make a private gift plan and link a private Activity option; phone B must see nothing about either object, even through known IDs or logs.
7. Attempt linking private Activity to shared occasion: database must reject.
8. Confirm shared Activity option can link to shared occasion, with provenance and history and without mutating original Activity.
9. Confirm both existing test accounts/memberships and pre-existing content are preserved.
10. Only after acceptance, produce a single consolidated test APK. The R12–R17 APK remains a frozen testing baseline.

**Do not confuse static source checks with compiled, tested or polished UI.**
