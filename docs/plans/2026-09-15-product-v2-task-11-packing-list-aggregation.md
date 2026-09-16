# Product Experience V2, Task 11 — Family Packing List aggregation, People and Status scopes

Date: 2026-09-15 · Branch: `product-v2-stage-a` · Baseline: `d680da0` (after Task 10)

## What changed

Presentation only. `PackingItemRecord`s, ownership, carrier, quantities, overrides, and persistence are untouched; the engine and goldens are unchanged (52/52).

### Architecture

```text
PackingItemRecord[]  →  PackingListItem[]  (one value per record, same id)
        ↓ PackingListAggregator.sections(items:party:order:query:)
PackingListSection[]  { category, rows: [PackingListPresentationRow], record-level counts }
        ↓
SwiftUI: PackingRow (real record) | PackingGroupRow (group) | PackingGroupDetailView (real records)
```

- `PackingListAggregation.swift` is pure and deterministic: one filter pass, one grouping dictionary per category, stable sorting; input order never changes the output (tested on 480 records, under 50 ms).
- `PackingListQuery` = People scope + optional Status + search + Hide packed. Every filter and the search apply to the **records** before aggregation, so a group is visible when any of its records matches and carries only the records that do.
- **Aggregation rule.** In the All scope of a party list, personal records that share a canonical ID and a category become one `PersonalItemGroup` when there are at least two of them. Shared records never join a group; custom rows without a canonical ID never group (a look-alike name is not an identity); custom rows with a canonical ID do. A single remaining record is an individual row, not a group of one.
- **Group model.** Canonical ID, category, display name, members in party order (record ID, traveler ID, label, quantity, packed, importance, complete), record IDs, traveler count, completed count, total quantity, strongest importance (read-only), completion, `progressText`, `travelerSummary`, `accessibilityLabel`. Never persisted; nothing writes to it.
- **Completion semantic:** record-level, the same as the section headers. A record is complete when `packedQuantity >= quantity`; a group is complete when every visible record is; progress is `complete / visible records`.

### Rows

```text
T-shirts                                 0 / 4
You ×4 · Maya ×4 · Ada ×6 · Child 2 ×4       >

Toothbrush                               2 / 4  !
4 personal                                   >

Sunscreen                     Shared ×2  !     (shared rows stay real rows: "Shared" or "Shared · Alex carries")
```

The leading glyph reports group state (empty / half / check) and is not a control; the row opens `PackingGroupDetailView`: a header with the category and "4 travelers · 2 of 4 packed", then one real `PackingRow` per traveler, titled by the traveler, with its own checkbox, swipe Pack / Not Needed / Delete, and a push to the real `ItemDetailView`. No "mark all packed"; nothing edits a group quantity.

### Scopes

```text
PEOPLE   ✓ All | You | Maya | Kids | Shared      (hidden entirely for solo)
STATUS   To pack 102 | Packed 5 | Important · Hide packed
```

Status is a toggle with nothing selected by default, so the duplicated All / All 81 is gone. Counts are underlying records in the current People scope and search. Selected chips carry a checkmark as well as the fill. At accessibility sizes the row names sit above the chips.

- Traveler scope shows that traveler's raw records with no owner caption (their own checklist). Kids and Shared show raw records. Labels come from `TripParty.label(for:)`: names, else You / Adult N / Child N; identity is the traveler ID.
- Search matches display name, canonical ID, the owner's or carrier's label, and "Shared"; never fuzzy.
- Hide packed removes packed records before aggregation, so a group whose other travelers are unpacked stays.
- Category sections and their order (`PackingCategory.displayOrder(international:tripTypes:)`) are unchanged; aggregation happens inside each.
- The floating Add button keeps a bottom content margin of its size plus its padding plus one spacing unit (`PackWiseSize.floatingControl`), so the last row scrolls clear of it.
- The Add sheet's "For" picker uses the same stable labels.

## Visible rows, before and after

| Fixture | Records | Rows in All | Groups |
| --- | --- | --- | --- |
| Family (You, Maya, Ada toddler, teen; beach vacation; engine-generated, test) | 103 | 42 | 24 (+18 single rows) |
| Same seed in Debug (`packingListFamily`) | 107 | one row per item | e.g. Keys 3 personal, T-shirts You ×9 · Maya ×9 · Ada ×16 · Child 2 ×9 |

Every record is reachable from exactly one row (tested).

## Tests

`PackingListAggregationTests` (28): four toothbrushes → one group over four records; T-shirt quantities preserved per traveler; shared umbrella stays a shared row apart from personal rows, with and without a carrier; same canonical ID in two categories does not merge; look-alike custom names never merge, custom rows with a canonical ID do; a single record is an individual row; names and positional fallbacks with stable IDs; People labels; search before aggregation; traveler search; To pack / Packed / Important with partial groups and unchanged record importance; Hide packed with mixed states; Shared scope; traveler scope; solo never aggregates and has no People; status counts from scoped records; category sections survive; accessibility labels (short for large groups); determinism and cost at 480 records; the generated family fixture; and four mutation tests on real records — one traveler's quantity, packing You's row, Not Needed for one traveler (one override, others untouched), and a category edit moving one record out of its group.

`M1LoopTests.task11ReferenceStatesAreAllCapturable` pins the eighteen Debug states.

## Evidence

`docs/device-evidence/product-v2/task11-packing-list-sheet.png`: solo; couple All; family All, You, Maya, Child 1, Shared; family middle and bottom; To pack, Packed, Important, Hide packed; item search, traveler search, no results; T-shirts and Toothbrush group sheets; family All and the T-shirts sheet at accessibility-large.

Reviewed: the All view reads as one packing plan — each item once, with who still needs it — and the traveler views read as personal checklists. Shared rows say "Shared" and keep quantity, reason, and importance. The bottom row clears the Add button. Accessibility-large has no wrapping labels and no clipped rows.

## Verification

- **iOS:** 589 tests in 37 suites pass.
- **Clean Debug build:** 0 Swift warnings; only the existing AppIntents metadata notice.
- **Engine audit:** `scripts/run_engine_audit.sh` passes; goldens 52/52 unchanged.
- **API preflight:** not run; no shared or generated artifact changed.

## Findings (not fixed)

- **F11-1.** Reason copy on multi-type trips: the family fixture's Shorts row reads "Useful for your other." because list copy passes the singular `TripRecord.tripType` (fail-safe `.other`) to `PackingReasonPresentation`. Already recorded as the Task 13 finding; unchanged here.
- **F11-2.** Two or more children collapse into one "Kids" scope (the frozen party-list rule). The brief's example lists each child; if that is wanted, `TripParty.listFilters()` and its test change together.
- **F11-3.** The section header count follows the visible records, like the rows, so with a Status or Hide packed active a header reads "0 / 8" rather than the category's full total. Consistent with "progress uses only the active scope"; flagging in case the full total is preferred there.
