# Product Experience V2, Task 10 — Every non-empty category on Trip Detail

Date: 2026-09-15 · Branch: `product-v2-stage-a` · Baseline: `90e6b6c` (Task 9.2)

## What changed

- **No cap.** The Packing block on Trip Detail renders every category that has at least one item. The `prefix(5)` and the "N more categories" row are gone; the page scrolls. `See All` still opens the complete Packing List, and tapping a row still opens the list scoped to that category.
- **Ordering.** `PackingCategory.displayOrder(international:tripTypes:)` is the one authority both Trip Detail and the Packing List call. It derives Outdoor from the trip's whole type set (`tripTypes.contains(.outdoor)`), so a Beach + Outdoor trip orders as outdoor; the singular compatibility accessor denied that. International comes from `trip.isInternational` (Task 9.2). No ordering table lives in a view.
- **Pure presentation.** `TripDetailCategoryOverview.summaries(of:order:)` returns the `CategorySummary` rows (category, packed, total) in display order and nothing for an empty category. No placeholder rows.
- **Row.** Icon, title, packed / total, bar, chevron, as before, with a 44pt minimum height. At accessibility sizes the count and bar drop under the title instead of squeezing it to one clipped word.
- **Debug capture.** `tripDetailAllCategories`, `…Middle`, and `…Scrolled` seed a Chicago family trip with an item in every category and open the page at its top, centre, and bottom: `simctl` cannot scroll, so `DebugPreviewScreen.initialScrollAnchor` feeds a Debug-only `defaultScrollAnchor` on the Trip Detail scroll view (compiled out of Release with the rest of the harness). The seed uses fresh drafts; reusing the main trip's drafts moved its rows here because item IDs are unique across the store.

## Category count

| | Before | After |
| --- | --- | --- |
| Rows on the all-categories trip | 5 + "6 more categories" | 11 |
| Rows on the reference Chicago trip (5 categories) | 5 | 5 |

## Tests (`M1LoopTests`)

| Test | Proves |
| --- | --- |
| `tripDetailShowsEveryNonEmptyCategoryInDisplayOrder` | all eleven non-empty → all eleven, in display order, not insertion order, with the right counts |
| `tripDetailHidesEmptyCategoriesWithoutPlaceholders` | mixed → only non-empty, in order; nothing → nothing |
| `categoryOrderDerivesOutdoorFromTheTripTypeSet` | `[.beach, .outdoor]` orders as outdoor; `[.beach]` does not; `[]` is the canonical order |
| `task10ReferenceStatesAreAllCapturable` | the three all-categories states and the scoped list are capturable, with the right anchors |

Category navigation tests are unchanged.

## Evidence

`docs/device-evidence/product-v2/task10-all-categories-sheet.png`: top, centre, and bottom of Trip Detail at standard and accessibility-large, plus the Packing List opened scoped to Toiletries (category navigation destination).

Checked in the captures:

- All eleven rows visible across the standard captures, in the order Essentials, Documents, Clothing, Kids, Footwear, Toiletries, Electronics, Health, Activities, Travel Comfort, Miscellaneous.
- Accessibility-large: the centre capture shows Essentials → Kids and the bottom capture Footwear → Miscellaneous; no row clips, no icon/title collision, the count and bar sit under the title, the weather copy wraps.
- Hero, progress card, Weather, Packing Impact, and Packing scroll in order; the Apple Maps attribution is unobscured; the status bar returns to dark glyphs once the white content is under it.

## Semantic diff

Presentation only. Goldens 52/52 unchanged (1717 rows, zero changes in any column). No engine, quantity, eligibility, sharing, luggage, trip-type, weather, trace, or user-authority code changed.

## Verification

- **iOS:** 560 tests in 36 suites pass.
- **Clean Debug build:** 0 Swift warnings; only the existing AppIntents metadata notice.
- **Engine audit:** `scripts/run_engine_audit.sh` passes.
- **API preflight:** not run; no shared or generated artifact changed.
