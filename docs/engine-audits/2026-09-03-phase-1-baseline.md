# Phase 1 baseline — engine golden ledger, audits, and trace coverage

Closing evidence for Product Hardening Phase 1
(`docs/plans/2026-09-02-product-hardening-program.md`). Everything in this
file was regenerated or re-verified against the state at Phase 1's closing
commit (see the git log for the exact SHA the `docs: close engine hardening
phase 1` commit records). Reproduce the whole arc with:

```bash
scripts/run_engine_audit.sh
```

---

## 1. Fixture manifest — 27 fixtures, what each proves

Source of truth: `shared/fixtures/golden/golden-fixtures.json`'s `proves`
field per fixture (Task 1/3), run through `GoldenEngineTests.swift` against
`ios/PackWiseTests/Goldens/*.json` (27 files, 1011 total item rows).

| # | fixture | proves |
| --- | --- | --- |
| 01 | chicago-5d-city-balanced | Baseline sanity |
| 02 | tokyo-15d-light-laundry-possible | The current duration-formula bug |
| 02b | tokyo-15d-light-laundry-planned | Planned vs possible laundry (identical to 02 under V1; must diverge in Step 2) |
| 03 | tokyo-15d-light-laundry-none | Laundry matters |
| 04 | tokyo-15d-prepared-checked | Style and bag matter |
| 05 | tokyo-30d-light-laundry-planned | Plateau — within ±1 of 02b above the wash cycle |
| 06 | miami-5d-beach-personal-item | GATE A — must be unmistakably a beach trip |
| 07 | chicago-5d-business-checked | GATE B — must be unmistakably a business trip |
| 08 | running-sightseeing-footwear | Footwear substitution — one pair of shoes, not two |
| 09 | seattle-rain-layering | Weather layering without duplicate outerwear |
| 10 | one-day-trip | No duration overpacking |
| 11 | couple-5d-rain | Personal rain layers, shared umbrella ×1 |
| 12 | family-toddler-7d-seasonal | Age-aware without an inferred formula; far-future date exercises the seasonal-only weather path |
| 13 | override-survives-regeneration | Not Needed overrides survive regeneration |
| 14 | manual-quantity-survives-refresh | Manual quantity edits survive regeneration and weather refresh |
| 15 | minneapolis-6d-deep-winter | First genuinely cold full list: sub-freezing week fires coldRain, snowExposure, and shell layering together |
| 16 | minneapolis-7d-winter-family | Cold compounded with children: winter gear per traveler, care items beside snow layers, toddler bottoms under cold |
| 18 | reykjavik-64d-roadtrip-camping-seasonal | Plateau at an extreme duration, camping's absent activity rule, seasonal-layer choices on the seasonal-only weather path, all on one long road trip |
| 19 | phoenix-5d-city-walking-hot | Hot, dry city trip must not pull in cold-weather or rain gear |
| 20 | seattle-5d-vacation-rain-sufficiency | Rain gear sufficiency and duplication under sustained wet weather on a vacation (not city-break) trip type |
| 21 | aspen-5d-skisnow-checked-prepared-snow | Cold-category completeness for a dedicated ski/snow trip type, which has no ski-specific activity rule to lean on |
| 22 | chicago-5d-business-running-overlap | Formal business wear and fitness/running gear must coexist without either crowding out the other |
| 23 | cancun-7d-international-beach-personal-item | International beach trip in the smallest bag — documents, unmistakable beach identity, and compactness together |
| 24 | miami-6d-family-infant-no-needs | An infant with no declared needs must not trigger diaper/formula/stroller inference — contrast with fixture 12's toddler |
| 25 | chicago-5d-unknown-activity-cosplay | A genuinely unknown activity ID must degrade inertly — no crash, no invented items (diff against 01 isolates the effect) |
| 26 | seattle-5d-existing-rain-shell | A user-added rain shell already on the list before regeneration is recognized as covering the rain need, not duplicated (diff against 09 isolates the effect) |
| 27 | chicago-5d-custom-item-survives-regeneration | A genuinely off-catalog, user-added item survives regeneration unchanged via `isUserAdded`, distinct from fixture 14's `isUserModified` proxy (diff against 01 plus one custom item) |

17 fixtures (01 through 16, minus none) shipped before Task 3; fixtures 18–27
(10 more; note there is no "17" — the numbering has always had this gap) were
added by Task 3 to close specific gaps the original 17 didn't cover:
extreme duration/latitude, hot/dry climate, sustained rain sufficiency, a
dedicated ski/snow trip type, activity overlap, international-plus-beach,
infant-vs-toddler contrast, unknown-input degradation, and the two
existing-item/custom-item authority cases.

## 2. Schema gaps — what Task 1 added and why

Before Task 1, `GoldenItem` (`GoldenEngineTests.swift`) did not capture
`carrier` or `reasonArguments` — a golden diff could not tell you which
traveler was assigned to physically carry a shared item, nor whether a
reason template's *filled-in values* changed (e.g. rain-day counts) if the
rendered `reason` string happened to stay the same in some locale-independent
way. Task 1 added both fields, then a follow-up commit (`9de1e51`) tightened
the `carrier` test from "asserts non-empty" (which a hardcoded literal could
satisfy) to asserting it actually varies with routing, and clarified the
three-way `carrier` contract in a doc comment: `"primary"`/`"partner"`/etc.
for an assigned traveler, `"unassigned"` for shared items with nobody
assigned to carry them, and `"unknown"` for a dangling traveler reference —
never a raw UUID. This closed the schema gap that made
`scripts/report_engine_goldens.py`'s later semantic diff possible: without
`carrier` and `reasonArguments` as tracked fields, a regression in either
would have been invisible to any diff over the old schema.

## 3. Two-run determinism

Regenerating the goldens twice from the same fixtures and comparing:

```bash
TEST_RUNNER_PACKWISE_RECORD_GOLDENS=1 xcodebuild test \
    -project ios/PackWise.xcodeproj -scheme PackWise \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:PackWiseTests/GoldenEngineTests
# (repeat, capturing ios/PackWiseTests/Goldens/ between runs)
```

**Result: byte-identical across both runs, and byte-identical to the
committed HEAD state** (`git status --porcelain ios/PackWiseTests/Goldens/`
was empty after each of the two independent recordings; a per-file MD5
comparison of both runs' 27 output files also matched exactly). This was
run for real as part of closing this task, not assumed — the harness's
own documented determinism rules (frozen fixture dates, no `.now`
resolution, fixed mock weather, sorted items/signals, UUIDs and packing
state excluded from serialization) hold in practice, not just on paper.

## 4. Quantity properties (Task 4)

`ios/PackWiseTests/ClothingQuantityTests.swift` now asserts, across every
`ClothingNeedPolicy` in `ClothingNeedPolicy.all`:

- **Ordering never inverts** — `laundryOrderingNeverInvertsForSensitivePolicies`,
  `styleOrderingNeverInverts`, `bagOrderingNeverInverts`: tightening laundry
  access, packing style, or bag size never *increases* a resolved quantity.
- **Declared sensitivities produce real divergence** —
  `declaredSensitivitiesProduceStrictDivergence`: a policy that declares a
  non-`.none` sensitivity to laundry/style/bag must actually produce a
  different quantity for at least one such change (the property test that
  makes `NeedSensitivity.low`/`.high` — P2-1 in
  `docs/engine-audits/2026-09-03-engine-findings.md` — a declared-but-
  unused *distinction* rather than an unused *dimension*: `.none` vs.
  not-`.none` is enforced; `.low` vs. `.high` is not).
- **Plateau holds** — `plannedLaundryPlateausAboveWashCycle`,
  `plateauHoldsAcrossEveryLaundryState`: quantities stop growing once a trip
  is long enough that laundry (or the style/bag cap) becomes binding, across
  every laundry-access state, not just the planned case.
- **Bounds are contextual, and global floors hold** —
  `boundsAreContextualNotGlobal`, `globalFloorsHold`,
  `everyPolicyStaysWithinItsDeclaredMinimumAndResolvedMaximum`: every
  resolved quantity sits within its policy's declared minimum and the
  context-resolved maximum — **with the sleepwear caveat**: this last test
  passes for `.sleep` usage only because the hardcoded 1/2 formula
  happens to fit under the declared caps, not because `resolve()` enforces
  them for sleepwear (P2-2 in the findings doc; documented in-line at
  commit `fea8c5d`).
- **Formal-top offset is scoped correctly** —
  `formalTopsReduceDailyTopCount`, `formalOffsetRespectsFloorAndScope`,
  `formalTopOffsetIsInertOutsideDailyTop`: dress shirts reduce the t-shirt
  count they substitute for, never push it below the floor, and never leak
  into unrelated needs.
- **Manual quantity survives a weather refresh** —
  `manualQuantitySurvivesWeatherRefresh`: an explicit user quantity edit is
  not silently recomputed away when the weather-driven refresh path runs.

## 5. Authority/fallback matrix (Task 4)

Every explicit-user-decision and failure-mode case Task 4 put a test on:

| case | test | file |
| --- | --- | --- |
| Removed base-essential item stays removed | `removedBaseEssentialStaysRemovedAcrossRegeneration` | ConstraintTests.swift |
| Manual quantity survives changed context | `manualQuantitySurvivesRegenerationWithChangedContext` | ConstraintTests.swift |
| User-added canonical *and* custom items both survive regeneration | `userAddedCanonicalAndCustomItemsSurviveRegeneration` | ConstraintTests.swift |
| Packed state survives regeneration when quantity is unchanged | `packedStateSurvivesRegenerationWhenQuantityIsUnchanged` | ConstraintTests.swift |
| Owner stays with the same traveler across regeneration | `ownerStaysWithTheSameTravelerAcrossRegeneration` | ConstraintTests.swift |
| Manually reassigned carrier survives regeneration | `manuallyReassignedCarrierSurvivesRegeneration` | ConstraintTests.swift |
| Family sharing keeps medication personal (never pooled/shared) | `familySharingKeepsMedicationPersonal` | ConstraintTests.swift |
| Not-Needed rain jacket is not restored by a later weather change | `notNeededRainJacketIsNotRestored` | WeatherChangeTests.swift |
| Custom, packed, and user-modified items are preserved across a weather-change apply | `customPackedAndModifiedItemsArePreserved` | WeatherChangeTests.swift |
| Removals from a weather-change proposal stay suggestions, never auto-applied | `removalsStaySuggestionsNotAutoApplied` | WeatherChangeTests.swift |
| Existing user rain coverage prevents a duplicate weather-change proposal | `existingUserRainCoveragePreventsADuplicateProposal` | WeatherChangeTests.swift |
| **Throwing-intelligence-service fallback** — deterministic generation still succeeds when the remote intelligence service throws | `deterministicGenerationSucceedsAlongsideAThrowingIntelligenceService` (ContextIntelligenceGateTests.swift) and `deterministicGenerationSucceedsWhileIntelligenceServiceThrows` (IntelligenceServiceTests.swift) | both |
| Note enrichment never throws even when the underlying service does | `noteEnrichmentNeverThrowsEvenWhenTheServiceDoes` | ContextIntelligenceGateTests.swift |
| A family note about medication never becomes the primary traveler's chip | `familyNoteAboutMedicationNeverBecomesThePrimaryTravelersChip` | ContextIntelligenceGateTests.swift |
| Every server failure collapses to "unavailable," not a crash | `everyServerFailureCollapsesToUnavailable` | IntelligenceServiceTests.swift |
| A malformed intelligence-service response is "unavailable," not a crash | `malformedResponseIsUnavailableRatherThanACrash` | IntelligenceServiceTests.swift |
| A partial 30-day forecast does not silently claim full coverage | `partialForecastDoesNotCoverA30DayTrip` | WeatherChangeTests.swift |
| A refused App Attest assertion never sends the request | `aRefusedAssertionNeverSendsTheRequest` | IntelligenceServiceTests.swift |

Together these are global product gate 5 (user authority) and gate 6
(graceful failure) made concrete and test-enforced, not just promised in
prose.

## 6. Surfaced-input coverage (Task 5)

`docs/engine-audits/surfaced-input-contracts.json` — 49 records covering
every `TripType` (11), `BagType` (6), `PackingStyle` (3), `LaundryAccess`
(3), suggested `Activity` (17), and `ContextChip` (9) a user can select in
`TripSetupView`:

| engineContract | count | meaning |
| --- | --- | --- |
| deterministic, tested | 24 | a real rule fires and at least one golden fixture proves it |
| deterministic, untested | 23 | a real rule fires but no golden fixture exercises it (P2-6, see findings doc) |
| context-only | 0 | none currently — nothing surfaced folds into a broader bucket with no independent effect |
| missing (dead) | 2 | `activity/camping` and `tripType/other` — exposed, verified to contribute nothing (P1-2 and P2-3) |

Reproduce: `python3 scripts/audit_engine_inputs.py --contracts
docs/engine-audits/surfaced-input-contracts.json --format markdown`.

## 7. Trace metrics (Task 6, this task)

Full detail in `docs/engine-audits/2026-09-03-trace-coverage.md`. Headline
numbers from `scripts/audit_recommendation_traces.py --goldens
ios/PackWiseTests/Goldens`:

- **1011 total item rows** across the 27 fixtures.
- **3 user-authority rows** (`userModified: true` or a `custom.*` id) —
  correctly exempt from engine trace scoring; their empty
  `reasonCode`/`reason`/`signals` is the *correct* behavior, not a gap.
- **Inclusion completeness: 964/1008 engine-generated rows (95.6%)**, **zero
  hard defects** — no row anywhere has an empty reason code or an empty
  signal list. 614 rows are approved-base-essential explanations, 350 are
  specific (weather/activity/party/document/substitution-driven); the
  remaining 44 are "generic-only" (`trip_type.generic` — the weakest tier
  the engine has, applied only when no more specific tier exists — P2-4).
- **Quantity evidence: 194/219 requiring rows (88.6%)**, **25 rows
  missing evidence** (all policy-governed clothing needs resolving to their
  floor quantity with no `quantityReason` — P2-5); 789 rows are fixed
  singletons, correctly held to no bar at all.

## 8. Miami/Chicago gate (global product gate 1)

> "Same-duration context: Miami beach and Chicago business are
> distinguishable without destination labels."

Verified directly against fixture output, not inferred:

- **Miami** (`06-miami-5d-beach-personal-item`, 5 days): `activities.beach_towel`
  (`activity.beachDays`), `clothing.swimsuit` (`activity.swimming`),
  `footwear.sandals` (`activity.beachDays`), `clothing.shorts`/`hat_sun`/
  `essentials.sunglasses`/`toiletries.sunscreen` (all `weather.hot`). No
  business, cold-weather, or generic-only item on the list stands in the
  way of reading this as a beach trip at a glance.
- **Chicago** (`07-chicago-5d-business-checked`, 5 days, same duration):
  `clothing.blazer`/`dress_shirt`, `footwear.dress_shoes` (`trip_type.generic`
  business), `clothing.nice_outfit` (`activity.niceDinner`),
  `electronics.laptop`/`laptop_charger`/`headphones` (`activity.work`). No
  beach, swim, or leisure item competes for attention.

Both lists share the same base-essentials backbone (documents, toiletries,
chargers, pain reliever) at the same 5-day duration — the gate is about the
*differentiating* items, and those are unmistakable in both directions
without ever reading a "Miami" or "Chicago" label. **Gate holds.**

## 9. Evidence paths — every artifact this hardening arc produced

| task | artifact |
| --- | --- |
| 1 | `ios/PackWiseTests/GoldenEngineTests.swift` (schema); `ios/PackWiseTests/Goldens/*.json` (27 fixtures, 1011 rows) |
| 1 | `shared/fixtures/golden/golden-fixtures.json` (fixture manifest + `proves` field) |
| 2 | `scripts/report_engine_goldens.py` + `scripts/tests/test_report_engine_goldens.py` |
| 3 | fixtures 18–27 (`ios/PackWiseTests/Goldens/`, `shared/fixtures/golden/golden-fixtures.json`) |
| 4 | `ios/PackWiseTests/ClothingQuantityTests.swift`, `ConstraintTests.swift`, `IntelligenceServiceTests.swift`, `ContextIntelligenceGateTests.swift`, `WeatherChangeTests.swift` (invariant/authority/failure audits); commit `fea8c5d` (sleepwear caveat) |
| 5 | `docs/engine-audits/surfaced-input-contracts.json`; `scripts/audit_engine_inputs.py` + `scripts/tests/test_audit_engine_inputs.py` |
| 6 | `scripts/audit_recommendation_traces.py` + `scripts/tests/test_audit_recommendation_traces.py`; `scripts/run_engine_audit.sh`; this file; `docs/engine-audits/2026-09-03-trace-coverage.md`; `docs/engine-audits/2026-09-03-engine-findings.md` |
| 6 | `docs/plans/2026-09-02-product-hardening-program.md` (closure status) |

One command replays all of it: `scripts/run_engine_audit.sh`.
