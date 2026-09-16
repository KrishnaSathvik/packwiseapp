# Product Experience V2 — Checkpoint V visual reference

Run after Task 8 (delayed, 2026-09-15), before Task 9. Commit: Task 8.1 (see `docs/plans/2026-09-15-product-v2-task-8-1-setup-closure.md`).

## Capture

- **Simulator:** iPhone 17 Pro, iOS 26.3 runtime, iOS Simulator SDK 26.2. Light appearance (the app is light-only).
- **Harness:** Debug-only `-PackWiseScreen <state>` (`DebugPreviewScene`). `M1LoopTests.checkpointVReferenceStatesAreAllCapturable` pins the required states.
- **Text sizes:** `large` (standard) and `accessibility-large`, set with `xcrun simctl ui <sim> content_size`.
- **Commands:** `scripts/capture_ios_screens.sh <dir> <states…>`, or the same `simctl launch`/`io screenshot` loop per size; sheets assembled with PIL.

| Sheet | States |
| --- | --- |
| `checkpoint-v-setup-standard.png` | setupDestination, setupDates, setupTravelers (solo), setupTravelersFamilyDetails (family expanded), setupTravelersGroup (group expanded), setupTripTypes, setupActivities, setupBags, setupStyleLaundry, setupPreferences (About you), setupReview |
| `checkpoint-v-setup-accessibility.png` | the same eleven at accessibility-large |
| `checkpoint-v-product-context.png` | onboarding ×3, tripsHome, tripDetail, packingList (solo), packingListFamily (current state), addItem, itemDetailSheet, me — context only |

## Review: setup as one flow

With titles covered, the nine steps share:

- Back/Cancel position, the progress track, and the "Step n of 9" line;
- title baseline, helper spacing, and horizontal margins;
- white background and card geometry;
- tiles for each step's main multi-select decision and round rows for single-select;
- chips for attributes inside a step;
- the accent-wash selected state with a color-independent glyph;
- icon tiles and the pinned bottom CTA.

Systemic issues found and fixed in shared primitives:

| Issue | Where | Fix |
| --- | --- | --- |
| Fixed point-size type did not scale | every screen | `PackWiseFont` roles anchored to Dynamic Type text styles at their sheet sizes; `PackWiseIconBadge` and the row-divider inset scale with it; selection glyphs use `selectionGlyph` |
| Weekday headers broke mid-word and day circles crowded at accessibility sizes | Dates (`PackWiseDateRangePicker`) | Grid and weekday row capped at `.xxxLarge`; one-line headers; cell height scales. The month title and summary still scale |
| Your devices as large tiles beside chip attributes | About you | Your device choices use the chip treatment companions use; the implicit phone is an informational row |
| Traveler name shown twice | traveler cards | Structural heading (Adult 1, Child 1) with a labeled Name field |

At accessibility-large:

- **Holds:** no clipped CTA, no nav or progress overlap, no horizontal overflow, and no mid-word breaks. Grids collapse to single-column rows, review sections wrap, and traveler and device cards stay readable.

## Context screens (not fixed here)

- **Onboarding (Task 9).** Page 1 is a full-bleed photo while pages 2–3 are white sheets with a different CTA/dots rhythm. Its fixed-size fonts remain.
- **Heroes (Task 9/10).** The Trip Detail hero and Trips Home cards use a different hero type treatment than setup Review's.
- **Family Packing List (Task 11).** Flat per-traveler duplicates (Keys ×3, Phone ×3) and two filter-chip rows that clip ("Impo…").
- **Me (later).** "I usually bring a laptop" duplicates the About you laptop device choice. Reconcile when Me gains the device model.
