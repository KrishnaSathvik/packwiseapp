# Product Experience V2, Task 11.1 — One People scope per traveler, stable header progress

Date: 2026-09-16 · Branch: `product-v2-stage-a` · Baseline: `90cd28c` (Task 11) · Closes F11-2 and F11-3

## 1. One traveler, one scope

`TripParty.listFilters()` is now `All`, one `.traveler(id)` per traveler in party order, `Shared`. The `PartyListFilter.kids` case is deleted; nothing produced or consumed it outside the list. Labels are unchanged: names, else You / Adult N / Child N. A large party scrolls the chips; solo still hides the row. The All aggregation is untouched.

```text
All | You | Maya | Ada | Child 2 | Shared
```

Tests: `partyListFiltersGiveEveryTravelerTheirOwnScope` (two children → two scopes); `twoChildrenGetTwoDistinctScopesWithNameOrStableFallback` (named child uses the name, unnamed child falls back to Child 2, identity by ID); `aChildScopeShowsOnlyThatChildsRecords` (nothing from the other child, You, or Shared leaks in; raw records, no groups).

## 2. Header progress follows People only

A section's `completedCount / totalCount` now measures the whole category for the current People scope, computed before Status, search, and Hide packed. Those change which rows are visible, not what the header means. A section with no visible rows is omitted rather than shown with an empty body. Record-level completion is unchanged.

```text
People = All,   Clothing 3 / 8   — same under To pack, Packed, Important, Hide packed, search
People = Alex,  Clothing 1 / 2
People = Shared, no clothing → no section
```

Tests: `categoryHeaderProgressIsStableAcrossStatusSearchAndHidePacked` (six filter variations, plus the rows below still filtered), `aFilterThatHidesEveryRowHidesTheSectionRatherThanShowingAnEmptyHeader`, `changingPeopleChangesTheHeaderDenominator`.

## Evidence

`docs/device-evidence/product-v2/task11-1-people-progress-sheet.png`: family All with Ada and Child 2 as their own chips; Ada's scope; To pack with Clothing still 0 / 40; Hide packed with Toiletries still 3 / 11 over unpacked rows only; accessibility-large.

## Boundary and verification

No change to aggregation identity, grouping, persistence, quantities, owner/carrier, engine, sharing, eligibility, search matching, or mutations. Goldens 52/52 unchanged. iOS 594 tests in 37 suites pass; clean Debug build 0 Swift warnings; engine audit passes. API preflight not run; no shared artifact changed.
