# Product Experience V2, Task 8 — trip setup redesign

Date: 2026-09-15 · Branch: `product-v2-stage-a` · Baseline: `9eb664a` (Task 7.2)

## What changed

- **Nine steps, one shell.**
  - Steps: Destination, Dates, Travelers, Trip types, Activities, Bags, Style + laundry, Preferences, Review.
  - `TripSetupShell` provides native Cancel/Back, a progress track, "Step n of 9", a 28pt title with helper text, scrollable content, and a primary action pinned to the bottom safe area.
  - There is no top-right Next.
- **`TripDraft`** (`TripSetupDraft.swift`) holds `tripTypes` and `bagTypes` as sets and owns every selection rule, so the rules are testable without UI:
  - at least one trip type is required;
  - bags are the four physical bags, and an empty selection means not sure yet;
  - activities change only on a tap.
- **`MultiSelectionCard` / `TripSetupSelectionGrid`** is one multi-select primitive for trip types, activities, bags, and Me's default bags.
  - The checkbox square, accent wash, border, and selected trait are color-independent.
  - Cards show two tiles per row and collapse to rows at accessibility text sizes.
- **Activities.**
  - Suggestions are the stable union of the selected trip-type contracts. The legacy `TripType.suggestedActivityIDs` list is deleted.
  - Setup no longer auto-selects suggestions, and no longer re-reads notes or custom text into activities at save.
- **Travelers.**
  - Family counts **Other adults** and **Children**; Group counts **Other adults** (at least one).
  - Each person besides You gets a traveler card (name; for adults, Devices, differences, and a note; for children, age and needs). Only teens get Devices.
  - `TripParty.label(for:)` (You / Adult 1 / Child 1, names win) and `travelerCountSummary` ("You + 1 adult, 2 children") are presentation-only.
  - Drafts carry traveler IDs, so edits reuse identities.
- **Device choices** are traveler-scoped signals:
  - `bringingPhone` and `bringingTablet` (new, in `base.json` `traveler_device_chips`, kept out of the API chip vocabulary);
  - `bringingLaptop` (existing).
  - `phoneOwnership` accepts `bringingPhone` from a companion; `electronics.tablet` requires `bringingTablet`.
  - A device signal can never become trip context.
- **Repository.**
  - `apply` and `attach` take trip-type and bag sets.
  - One bag reconciliation keeps a record per selected bag and preserves identity.
  - The Task 1 one-bag guard is removed (Task 5 owns multi-bag semantics).
  - The compat scalars never pick a primary.
- **Me.** "Default bags" is the same four-bag multi-select (`setPreferredBagTypes`), replacing the single-select picker.
- **Review** has separate wrapping sections for trip types, travelers, activities, bags ("Not sure yet"), packing style, laundry, and preferences.

## Evidence

- `TripSetupDraftTests` (10 tests) covers:
  - nine-step order;
  - multi-bag prefill;
  - legacy-empty bags;
  - multi-type and multi-bag round trip;
  - family ID reuse;
  - non-causal suggestions and byte-stable activities;
  - labels and counts;
  - companion device signals reaching the engine;
  - review summaries;
  - preference groups.
- Full suite: 514 tests pass. Clean Debug build: 0 Swift warnings. Goldens: 52/52 unchanged.
- Shared validation, Python tests (121), and API preflight (141) pass. Generated API artifacts changed only by two reason codes.
- Contact sheet: `docs/device-evidence/product-v2/task8-setup-contact-sheet.png`, captured on the iPhone 17 Pro simulator with `-PackWiseScreen`.
  - Systemic fix found: two-column cards broke words mid-word. The primitive gained a tile layout.

## Deviations and findings

- **Checkpoint V skipped.** The whole-product contact sheet was not run before Task 8, on explicit instruction to proceed directly. The setup flow was captured and reviewed as one flow instead.
- **Destination step unchanged apart from the shell.** Its redesign is Task 9.
- **No free-text note in setup**, same as before. An existing trip's note is kept.
- **Fixed-size fonts don't scale.** Design-system fonts have fixed sizes, so only the system text fields scale with Dynamic Type. This existed before Task 8.
- **Primary interim devices remain.** The primary traveler's headphones, power bank, and camera are still the Task 7.2 interim carryover. You have no device card.
