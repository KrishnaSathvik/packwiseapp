# Product Experience V2, Task 12 — One dedicated category selector for Add and Edit

Date: 2026-09-16 · Branch: `product-v2-stage-a` · Baseline: `8937273` (Task 11.1)

## Architecture

`CategorySelectorView.swift` holds everything:

- **`CategorySelection`** — the pure contract: `options` is `PackingCategory.displayOrder(international: false, outdoor: false)` (the one ordering authority, no selector table); `isSelected`, `accessibilityValue`.
- **`CategorySelectorView(selection: Binding<PackingCategory>)`** — "Choose Category": plain rows with the design system's icon badge, name, and an accent checkmark, 44pt minimum, wrapping names, `isSelected` trait plus a "Selected" value for VoiceOver. Choosing writes the binding and pops.
- **`CategoryRowLabel`** — the "Category · Toiletries ›" row both hosts show; stacks at accessibility sizes.
- **`AddItemDraft`** — what Add Item holds until Save (name, quantity, category, owner, important). Choosing a category changes the draft only; the item exists only after Save; Cancel creates nothing.
- **`ItemCategoryEdit.apply(_:to:)`** — the one write for a chosen category on an existing record: the category column and `updatedAt`, nothing else.

Navigation is owned by the hosts, not the sheet. Add Item pushes inside its own sheet stack (`AddItemRoute.category`); Item Detail asks its host through `onChooseCategory`, and both hosts — the item sheet and the group sheet — push `ItemDetailRoute.category(recordID)` on a path-bound stack and register the destination. The menu Picker and the Add-only list are gone; there is one selector. The keyboard is dismissed before the push.

The Add sheet body moved into `AddItemSheet`, driven by a binding: presenting a sheet and mutating its draft in the same transaction had rendered stale state.

## Authority

Regeneration refreshes a record through `PackingItemRecord.apply(_:)`, which never writes the category, and quantity proposals skip user-modified rows, so a chosen category stands with no new override mechanism. Pinned in `CategorySelectorTests`:

| Test | Proves |
| --- | --- |
| `aUserChosenCategorySurvivesRegeneration` | generated shirts → Miscellaneous → edit trip and accept every proposal → same record, still Miscellaneous, no duplicate row |
| `manualQuantityAndCategoryBothSurviveRegeneration` | quantity 11 + Travel Comfort both survive |
| `packedStateSurvivesACategoryChangeAndRegeneration` | packed toothbrush moved to Health stays packed |
| `ownerAndCarrierAreUntouchedByACategoryChange` | owner, carrier, ownership unchanged on a personal and a shared record |
| `aCustomItemsCategorySurvivesARelaunch` | file-backed store, reopened: a custom Kite moved to Kids stays; regeneration leaves it |
| `editingOneTravelersCategoryMovesOnlyThatRecordOutOfItsGroup` | Maya's shirts → Miscellaneous: the Clothing group is You + Child 1, Maya's row sits under Miscellaneous |

Plus the selector contract: every category once in canonical order; the current one and only it selected; choosing updates the Add draft and nothing else; leaving without choosing keeps the prior category. Task 11's aggregation and mutation tests are unchanged and still pass.

## Evidence

`docs/device-evidence/product-v2/task12-category-selector-sheet.png`: Add Item with the Category row; Choose Category with Clothing checked; with Toiletries checked; Add Item after choosing Toiletries (Save enabled); Item Detail's Category row; Choose Category pushed from Item Detail; Item Detail after a move to Miscellaneous; the family list after Maya's T-shirts moved (group 0 / 3 over You · Ada · Child 2, Maya's row under Miscellaneous, Clothing header 0 / 39); the chooser at accessibility-large from both hosts.

## Boundary and verification

No change to recommendation generation, category assignment of new recommendations, trip types, luggage, eligibility, sharing, quantities, weather, or the trace. Goldens 52/52 unchanged. iOS 605 tests in 38 suites pass; clean Debug build 0 Swift warnings; engine audit passes. API preflight not run; no shared artifact changed.

## Findings (not fixed)

- **F12-1.** Item Detail writes the chosen category to the live record the moment a row is chosen, exactly as its quantity stepper and pack buttons already do. That is the sheet's existing save model, kept deliberately; there is no draft/commit step to add a category to.
- **F12-2.** The `For` picker still renders as a menu. Left as the brief asked; it uses the stable labels.
