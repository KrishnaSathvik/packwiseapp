# Trip-type contract audit — Product Experience V2, Task 3

Date: 2026-09-14 · Source of truth: design Section 8.1 (`docs/plans/2026-09-04-product-experience-v2-design.md`) · Enforced by: `shared/rules/trip-types.json`, `scripts/trip_type_contracts.py`, `TripTypeCompositionTests`

This table maps every known `TripType` to its approved typed needs, its unselected suggested activities, and its explicit non-implications. It becomes executable policy in Task 3. Task 3 does not change any packing list. It only defines the semantic layer that Task 4 composes.

## 1. Approved contract (verbatim from design 8.1)

| Trip type | Needs | Suggested activities (unselected, non-causal) | Non-implications (prose) |
| --- | --- | --- | --- |
| `vacation` | `leisureGeneralTravel` | sightseeing, walking, niceDinner, shopping | Beach/swim, formal/work, nightlife, or a second baseline |
| `cityBreak` | `urbanWalking`, `cityDayUse` | sightseeing, walking, museums, niceDinner, shopping, nightlife | Business/work, checked capacity, or automatic activity selection |
| `beach` | `beachSwim`, `sunExposure` | swimming, beachDays, snorkeling, boatTrip | Vacation baseline, nightlife, or duplicated everyday clothing |
| `business` | `workContext`, `formalPresentation` | work, niceDinner, walking | Leisure, nightlife, or larger luggage capacity |
| `outdoor` | `outdoorDayUse` | hiking, wildlife, walking, running | Camping, overnight/technical gear, or backpack ownership |
| `roadTrip` | `roadTravelComfort` | sightseeing, walking | Larger luggage capacity, a physical bag, camping, or outdoor activity |
| `weddingEvent` | `formalEvent` | niceDinner | Business/work devices, nightlife, or a vacation baseline |
| `skiSnow` | `snowSport`, `coldActivityExposure` | — | A duplicate generic Outdoor contract, camping, or technical gear beyond the approved snow candidates |
| `festival` | `festivalAttendance` | — | Nightlife, camping, substance use, or larger luggage capacity |
| `visitingFamily` | `hostVisit` | sightseeing, walking | Family party structure, children, caregiving items, or duplicated Vacation context |
| `other` | — | — | Any deterministic packing inference from the label or arbitrary text |

The 14-need `PackingNeed` vocabulary is closed and identical in Swift and the shared rules. No need belongs to more than one trip type today. The resolver still merges a shared need into one normalized need that keeps every provenance fact.

## 2. Mechanical non-implications

The prose column stays verbatim in `nonImplications`. Only phrases that name something the vocabulary can check exactly become machine-checked exclusions. Validation requires every exclusion to be disjoint from the type's own needs and suggestions, and the tests assert that no contract contributes an excluded need or suggests an excluded activity.

| Trip type | `excludedNeeds` | `excludedActivities` | Prose phrase each exclusion comes from |
| --- | --- | --- | --- |
| `vacation` | beachSwim, sunExposure, workContext, formalPresentation, formalEvent | swimming, beachDays, work, nightlife | beach/swim; formal/work; nightlife |
| `cityBreak` | workContext, formalPresentation | work | Business/work |
| `beach` | leisureGeneralTravel | nightlife | Vacation baseline; nightlife |
| `business` | leisureGeneralTravel | nightlife | Leisure; nightlife |
| `outdoor` | — | camping | Camping |
| `roadTrip` | outdoorDayUse | camping | outdoor activity (as a need); camping |
| `weddingEvent` | workContext, leisureGeneralTravel | work, nightlife | Business/work devices; vacation baseline; nightlife |
| `skiSnow` | outdoorDayUse | camping | duplicate generic Outdoor contract; camping |
| `festival` | — | nightlife, camping | Nightlife; camping |
| `visitingFamily` | leisureGeneralTravel | — | duplicated Vacation context |
| `other` | every need (enforced: `other` has no needs) | every activity (enforced: no suggestions) | any deterministic inference |

Left as prose only, because nothing in the need or activity vocabulary names them: luggage capacity, a physical bag, backpack ownership, technical gear, overnight gear, substance use, party structure, children and caregiving, duplicated clothing baselines, and automatic activity selection. Luggage belongs to Task 5, party and children to Task 6, and clothing baselines to Task 4's single quantity pass. Automatic activity selection is a UI rule; see finding F-1.

## 3. Need → candidate mapping (the one new decision)

Trip types no longer own item lists. A central map in `trip-types.json` (`needs[].candidates`) names the canonical candidates for each need. For Task 3 it is a lossless partition of today's per-type lists, so a single-type trip gets exactly the items it gets today. Each candidate sits under the need whose bounded meaning (design 8.1) describes it:

| Need | Candidates | Previously in |
| --- | --- | --- |
| `leisureGeneralTravel` | electronics.headphones, travel_comfort.book | vacation |
| `urbanWalking` | activities.daypack | cityBreak |
| `cityDayUse` | essentials.sunglasses | cityBreak |
| `beachSwim` | clothing.swimsuit, clothing.coverup, footwear.sandals, activities.beach_towel, clothing.shorts | beach |
| `sunExposure` | toiletries.sunscreen, clothing.hat_sun | beach |
| `workContext` | electronics.laptop, electronics.laptop_charger | business |
| `formalPresentation` | clothing.dress_shirt, clothing.blazer, footwear.dress_shoes | business |
| `outdoorDayUse` | activities.daypack, hydration.water_bottle, toiletries.insect_repellent, health.blister_pads, health.first_aid | outdoor |
| `roadTravelComfort` | miscellaneous.car_charger, miscellaneous.car_snacks, essentials.snacks | roadTrip |
| `formalEvent` | clothing.formal_outfit, footwear.dress_shoes, miscellaneous.wedding_card | weddingEvent |
| `snowSport` | activities.ski_goggles, activities.ski_gloves | skiSnow |
| `coldActivityExposure` | clothing.winter_coat, clothing.gloves, clothing.beanie, clothing.thermal_top, footwear.boots | skiSnow |
| `festivalAttendance` | activities.festival_earplugs, electronics.power_bank, toiletries.sunscreen, essentials.hand_sanitizer | festival |
| `hostVisit` | miscellaneous.gift | visitingFamily |

Every old candidate appears under exactly one of its type's needs, and every mapped candidate came from that type. The union of a type's need candidates therefore equals its old list. The same canonical ID may serve several needs (sunscreen, daypack, dress shoes). Candidate identity stays the existing recommendation key, so Task 4's single pass sees each ID once. The split inside a type (for example daypack under `urbanWalking`, sunglasses under `cityDayUse`) is reviewable provenance for Task 4. No row of the approved matrix changes.

## 4. Findings

- **F-1 — setup auto-selects suggested activities (pre-existing, owned by Task 8).** `TripSetupView.typeStep` does `draft.activities = Array(type.suggestedActivityIDs.prefix(2))` when a type is tapped and no activities are selected yet. That writes suggestions into the selection without an activity tap, which violates "suggested activity ≠ selected activity". Task 3 does no UI work. It pins the rule at the domain boundary: the contract resolver has no API that reads or writes a selection, and the engine gives suggestions no causal path.
- **F-2 — two suggestion sources (pre-existing, owned by Task 8).** Setup still reads the hardcoded `TripType.suggestedActivityIDs`, which differs from the approved suggestions (for example vacation today also suggests nightlife, running, museums, and work). The contract is now the approved source. Task 8 switches setup to it; until then the Swift list is documented as legacy UI data only.
