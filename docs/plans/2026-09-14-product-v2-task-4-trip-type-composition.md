# Product Experience V2, Task 4 — compose every selected trip type

Date: 2026-09-14 · Branch: `product-v2-stage-a` · Semantic baseline: `4f55101` · Trace decision: [2026-09-14-product-v2-task-4-trace-authority.md](2026-09-14-product-v2-task-4-trace-authority.md)

## Commits

| Commit | Scope |
| --- | --- |
| `dfd6e4f` | One trace authority: structured provenance on the draft, `recommendationTraceRaw` as its encoding, provenance in the golden ledger and report tool |
| `c11926a` | Engine composes the full `tripTypes` set; singular trip-type authority removed; 10 combination fixtures |
| docs | This record, plan checkboxes, implementation status |

## What changed in the engine

- `PackingEngine.ruleSuggestions` resolves `context.tripTypes` through `TripTypeContractResolver.normalizedNeeds`.
  - Each need's central candidates join the single `collected` suggestion map, in the same pass as base essentials, activities, preferences, and weather.
  - An item several types contribute is one suggestion with one `RecommendationProvenance.tripType(_)` fact per type.
  - Its reason argument names every source in stable order (`TripType.reasonPhrase`: "beach", "vacation and beach", "vacation, city break, and beach"). A single type's copy is unchanged.
  - Candidates, eligibility, coverage, quantities, constraints, sharing, and reconciliation still run once, unchanged.
- Singular trip-type authority is gone from engine and domain code.
  - `TripContextSnapshot` and `CoverageContext` carry `Set<TripType>`, and `CoverageResolver.needs` checks membership (beach, formal, snow hands) over the full set.
  - The Task 3 item-list bridge (`TripTypeRule`, `rules.tripTypes`) is deleted.
  - **`TripContext.tripType` no longer exists**, so no engine path can regain a primary type without a compile error.
  - The weather/context signature already used the stable sets (Task 15).
- No quantity policy, coverage rule, constraint, or deduper was added.

## Remaining singular readers (all non-engine)

| Reader | Why it may remain | Owner |
| --- | --- | --- |
| `TripSetupView` single-select `draft.tripType`, and `TripRepository.createTrip`/`apply` singular params | setup UI still selects one type | Task 8 |
| `PackingListView.swift:416` and `TripDetailView.swift:511` read `TripRecord.tripType == .outdoor` for category display order | presentation order only | Task 10 |
| `PackingListView.swift:682, 835` pass `TripRecord.tripType` to `PackingReasonPresentation.inclusionReason` for `trip_type.generic` | presentation copy only; a multi-type trip would render the fail-safe "other" there | Task 13 |
| `TripRecord.tripType` accessor | serves the UI readers above | Tasks 8/10/13 |
| All `bagType` readers (engine, snapshot, quantities) | luggage semantics | Task 5 |

No shipped screen can create a multi-type trip until Task 8, so the list-copy fail-safe can't show today.

## Combination fixtures — manual review

Each fixture was also recorded once per member type alone, in the identical context (temporary fixtures, since removed), and diffed. All have `activities: []`, so suggested activities cannot contribute.

| Fixture | Items | Members alone | Trip-type items (all carry their type's provenance) |
| --- | --- | --- | --- |
| `39` vacation-beach-maui | 32 | beach 30, vacation 28 | beach_towel, coverup, hat_sun, shorts, swimsuit, headphones, sandals, sunscreen, book |
| `40` vacation-citybreak-barcelona | 30 | cityBreak 28, vacation 28 | daypack, headphones, sunglasses, book |
| `41` vacation-citybreak-beach-barcelona | 36 | beach 33, cityBreak 28, vacation 29 | beach_towel, daypack, coverup, hat_sun, shorts, swimsuit, headphones, sunglasses, sandals, sunscreen, book |
| `42` business-citybreak-newyork | 28 | business 26, cityBreak 23 | daypack, blazer, dress_shirt, laptop, laptop_charger, sunglasses, dress_shoes |
| `43` business-vacation-chicago | 31 | business 29, vacation 26 | blazer, dress_shirt, headphones, laptop, laptop_charger, dress_shoes, book |
| `44` roadtrip-outdoor-yellowstone | 25 | outdoor 25, roadTrip 21 | daypack, blister_pads, water_bottle, insect_repellent |
| `45` outdoor-skisnow-aspen | 33 | outdoor 31, skiSnow 28 | daypack, ski_gloves, ski_goggles, beanie, thermal_top, winter_coat, boots, blister_pads, first_aid, water_bottle, insect_repellent |
| `46` vacation-wedding-lisbon | 30 | vacation 27, weddingEvent 28 | formal_outfit, headphones, dress_shoes, wedding_card, book |
| `47` festival-citybreak-austin | 27 | cityBreak 23, festival 25 | daypack, festival_earplugs, power_bank, hand_sanitizer, sunglasses, sunscreen |
| `48` visitingfamily-vacation-boston | 24 | vacation 23, visitingFamily 22 | headphones, gift, book |

Across all ten:

- **Duplicate recommendation keys:** 0.
- **Items added beyond the union of the members alone:** 0.
- **Baseline clothing** (T-shirts, underwear, socks, pants, sleepwear) **and base essentials:** identical to every member alone except one existing policy (next list).

Reviewed differences, all existing policy rather than composition artifacts:

- **`42` T-shirts 4 (City Break alone 5).** The evidence shows `appearanceOffsetUses: 1`: the existing formal-top offset reacting to Business's dress shirt. That equals Business alone. No trip-type-count multiplier exists.
- **`45` `clothing.gloves` suppressed** (Outdoor alone keeps it). The one coverage pass covers `hand_protection.cold` with ski gloves, exactly as Ski/Snow alone already does. The combination also suppresses `light_jacket` (covered by `light_sweater`), as both members do alone. Winter coat, beanie, and boots carry both Ski/Snow and snow-weather facts.
- **`44` road-comfort items** (car charger, car snacks, snacks) **and first aid are trimmed** by the light carry-on constraint, exactly as they are with Road Trip alone. Road Trip does not loosen capacity. `roadTripNeverChangesLuggageCapacity` proves identical trims and quantities with and without Road Trip for personal-item, carry-on, and checked bags.
- **`39` and `45` show multi-source provenance with weather:** sunscreen, sun hat, and shorts carry Beach plus hot/UV weather facts, and Ski/Snow items carry snow weather. Weather supplies the row's higher-tier reason, and the trip-type fact is kept.

## Tests (`TripTypeEngineCompositionTests`, 15)

- **Composition:** all ten combinations keep every member's candidates (present, or suppressed or trimmed by the single pass) with that type's provenance; no fact names an unselected type; no duplicate keys.
- **Shared item:** Beach plus Festival sunscreen is one row with both type facts and the reason "beach and festival".
- **Copy:** a single type's reason is unchanged, and the three-type phrase renders as one list.
- **Quantities:** baseline clothing and essentials are identical for Vacation, Vacation plus Beach, and Vacation plus Beach plus City Break.
- **Determinism:** output, trace, and signature are identical across insertion orders.
- **Specific combinations:** Business plus City Break keeps formal and urban needs (dress shoes, laptop, daypack; coverage needs formal and everyday walking) with no leisure inference. Road Trip never changes luggage capacity. Outdoor plus Ski/Snow reuses the one coverage pass.
- **Suggestions:** City Break suggestions contribute nothing until selected, and explicit Sightseeing adds its own fact to the daypack.
- **User authority:** Not Needed stays suppressed when a new type contributes the same item. Manual quantity, custom item, and packed state survive a trip-type change, and additions arrive through the diff, not a wholesale replace.
- **Weather boundary:** trip types never manufacture weather (the weather-driven item set is identical to Other for Outdoor, Ski/Snow, Beach, and all three together), and Outdoor plus precise rain composes both facts.
- **Legacy luggage:** road-trip luggage never creates Road Trip behavior.

`RecommendationProvenanceTests` (6) cover the persisted multi-source trace.

## Semantic golden diff

- **Existing 38 vs `4f55101`** (`--ignore-trace-field provenance`, which that baseline predates): 1441 unchanged; zero added, removed, quantity, trace, coverage, or constraint changes.
- **Existing 38 vs `dfd6e4f`** (provenance included): 1441 unchanged, zero changes.
- **New:** 10 fixtures, reviewed above.

## Verification

- **iOS:** 430 tests / 28 suites, all passing.
- **Clean Debug build:** 0 Swift warnings.
- **`scripts/run_engine_audit.sh`** on `c11926a`: all 6 steps pass. That covers `validate_shared`, 115 Python audit tests, 104 focused Swift tests, golden diff CLEAN for 48 fixtures, input audit, and trace audit `--strict` CLEAN.
- **API:** 141 tests pass; preflight green; generated artifacts current.

## Deviations from the plan text

- The plan's trace example is "walking shoes keep City Break/Sightseeing/Walking facts". Walking shoes are not a City Break candidate (they come from base and activity rules), so the equivalent assertion uses the daypack: City Break plus an explicitly selected Sightseeing.
- The plan places combination fixtures under `shared/fixtures/trips/`. Engine goldens live in `shared/fixtures/golden/golden-fixtures.json`, while `trips/` holds evaluation scenarios with `mustInclude` expectations, so the ten fixtures joined the golden ledger.
- The design lists a "Business + Vacation" combination the Task 4 instruction did not; it is included (fixture `43`, tests).
- `CoverageResolver.needs` still derives capability needs from trip types plus activities rather than from `PackingNeed` values directly. It now reads the full set, which is the behavior the plan requires, without a second resolver.

## Findings

- **List copy (Task 13):** `PackingReasonPresentation.inclusionReason` receives `TripRecord.tripType`, so a multi-type trip's `trip_type.generic` rows would render the fail-safe "other" in the list. The engine's own reason names every type correctly.
- **A shared item's multi-type reason** reads as one compound phrase ("Suggested for a beach and festival trip."). Its article follows the existing single-type template ("a outdoor trip" was already possible). Copy polish belongs to Task 13.
