# Surfaced-input contract audit

| total | deterministic (tested) | untested | context-only | dead |
| --- | --- | --- | --- | --- |
| 54 | 42 | 9 | 3 | 0 |

## Dead — exposed, verified to do nothing (0)

_none_

## Context-only — surfaced/stored, no independent engine effect (3)

| kind | id | icon | fixtures |
| --- | --- | --- | --- |
| activity | `photography` | `camera.aperture` | _none_ |
| | | | Context-only since Task 8.1 (2026-09-15). rules.activities still lists camera, camera charger, and memory card, but every one requires the traveler's explicit bringingCamera device choice, which adds them by itself — so selecting photography changes nothing on its own (pinned by ActivityContractTests.photographyAddsACameraAndMemoryCard). Not offered as a suggested-activity chip; reachable via the free-text keyword "photo". |
| bagType | `roadTripLuggage` | `car` | _none_ |
| | | | Legacy-only since Product Experience V2 Task 15: not a V2 bag value. Every boundary normalizes it to the empty bag set (no luggage constraint) and never infers Road Trip; golden fixtures 18/28/29 that used it now carry bagTypes []. Before V2 it already changed no engine output (it applied no space constraint), and LuggageContext.resolve drops it from the bag set, so it is contextOnly, not deterministic. Still offered by the single-select setup and Me pickers until Task 8 replaces them. |
| tripType | `other` | `ellipsis.circle` | _none_ |
| | | | Other is the identity element of trip type: shared/rules/trip-types.json declares it with an explicit empty needs list (Product Experience V2 Task 3; previously an empty add), meaning "no additional trip-type-specific needs; activities, preferences and context carry the meaning". The lookup succeeds and deliberately contributes nothing, which is contextOnly rather than missing. Phase 5 earns that relabel with three checks rather than asserting it: the key exists with an empty add, other is the ONLY trip type with an empty add so the label cannot spread to a trip type that merely lost its rule, and an Other trip still produces a complete list whose every row is explained by base essentials, activities, weather or party. |

## Untested — deterministic, no golden fixture proves it (9)

| kind | id | icon | fixtures |
| --- | --- | --- | --- |
| contextChip | `bringingLaptop` | `laptopcomputer` | _none_ |
| | | | rules.contextChips['bringingLaptop'] adds electronics.laptop + electronics.laptop_charger per traveler; also mirrored by TravelerPreferences.usuallyBringLaptop for the self traveler. Not listed in ContextChip.partnerDifferences, so only the self traveler can toggle it from the extras step, but it is still stored on Traveler.chips like the rest of the non-trip-level chips. No golden fixture sets it; deterministic and currently untested. |
| contextChip | `dailyMedication` | `pills` | _none_ |
| | | | rules.contextChips['dailyMedication'] adds health.daily_medication + health.prescription_copy via PackingEngine.addTravelerSuggestions, keyed per traveler (Traveler.chips, toggled in the extras step's 'About you' field and mirrored by TravelerPreferences.alwaysBringMedication for the self traveler). No golden fixture's party rows or top-level chips ever set a ContextChip (verified by grep across shared/fixtures/golden/golden-fixtures.json); deterministic and currently untested. |
| contextChip | `getColdEasily` | `thermometer.snowflake` | _none_ |
| | | | rules.contextChips['getColdEasily'] adds clothing.light_sweater + clothing.light_jacket per traveler; exposed in ContextChip.partnerDifferences for the partner. No golden fixture sets it; deterministic and currently untested. |
| contextChip | `laundryAvailable` | `washer` | _none_ |
| | | | rules.contextChips['laundryAvailable'] adds toiletries.laundry_sheets. Trip-level (in ContextChip.tripLevel), but TripSetupView.extrasStep explicitly filters it out of the 'About this trip' chip field ('Laundry moved to the bag-and-style step as a three-way control; the boolean chip stays in the enum for old trips') — it is not user-toggleable in the current UI, only reachable via legacy trip data, the same 'real enum case, not currently reachable from a fresh trip' status the camping activity record above documents. No golden fixture sets it (fixtures exercise LaundryAccess instead, at 02/02b/03); deterministic and currently untested. |
| contextChip | `needFormalOutfit` | `sparkles` | _none_ |
| | | | rules.contextChips['needFormalOutfit'] adds clothing.formal_outfit + footwear.dress_shoes; CoverageResolver.needs also inserts .formal for this chip alongside business/weddingEvent trip types and work/niceDinner activities, and it is exposed in ContextChip.partnerDifferences for the partner. No golden fixture sets it; deterministic and currently untested. |
| contextChip | `runWhileTraveling` | `figure.run` | _none_ |
| | | | rules.contextChips['runWhileTraveling'] adds footwear.running_shoes, clothing.workout_top, and activities.running_belt; CoverageResolver.needs also inserts .running for this chip alongside the 'running' activity, so it can satisfy running-shoe coverage without the activity itself being selected. Not listed in ContextChip.partnerDifferences (self-only toggle). No golden fixture sets it; deterministic and currently untested. |
| contextChip | `travelingInternationally` | `airplane` | _none_ |
| | | | rules.contextChips['travelingInternationally'] adds documents.passport, electronics.travel_adapter, and essentials.cash. Trip-level (in ContextChip.tripLevel, shown under the extras step's 'About this trip' field), distinct from the separately-computed TripContext.isInternationalConfirmed path (which also adds documents.visa and international entry-requirement notes). Golden fixture 23 exercises isInternationalConfirmed by mismatching homeCountryCode against the destination's country, not by setting this chip; no fixture sets the chip itself. Deterministic and currently untested. |
| contextChip | `usuallyWorkOut` | `dumbbell` | _none_ |
| | | | rules.contextChips['usuallyWorkOut'] adds clothing.workout_top, clothing.workout_bottom, and footwear.running_shoes per traveler; also mirrored by TravelerPreferences.usuallyWorkOut for the self traveler and exposed in ContextChip.partnerDifferences for the partner. No golden fixture sets it; deterministic and currently untested. |
| contextChip | `wearContacts` | `eyeglasses` | _none_ |
| | | | rules.contextChips['wearContacts'] adds toiletries.contacts_solution, toiletries.contact_case, and health.eye_drops per traveler; also mirrored by TravelerPreferences.wearContacts for the self traveler and exposed in ContextChip.partnerDifferences for the partner. No golden fixture sets it; deterministic and currently untested. |
