# Phase 7 — Central Constraints and User Authority

**Date:** 2026-09-04
**State:** implemented and simulator-verified; Phase 8 not started
**Branch:** `product-hardening-phase1`
**Phase 6 semantic baseline:** `c9cbb76`
**Approved design/plan:** `docs/superpowers/specs/2026-09-04-product-hardening-phase-7-central-constraints-design.md`, `docs/superpowers/plans/2026-09-04-product-hardening-phase-7-central-constraints-and-user-authority.md` (amended in `69fa731` — `SharingPolicy.personalOnly` moved from routed finding to a required Task 1 amendment; F-5 bounded to sharing only)
**Implementation commits:** `88bea65`, `63fae43`, `829781b`, `b2ea79e`, `77e3377`, `4853554`, `7226124`

## Result

Phase 7 is closed. `ConstraintResolver` is now the single typed authority for
party sharing membership/quantity (`sharingResolution(for:rules:context:party:)`)
and the explicit-user-authority gate (`hasUserAuthority(_:)`,
`isExplicitlyRemoved(_:ownership:travelerID:overrides:)`), replacing two
independent `sharedByDefault` membership checks, a free-standing
`sharedQuantity`/`sharedQuantityReason` pair, and four independently-written
`isUserAdded || isUserModified` / removed-override checks. Both moves were
zero-diff refactors, each verified against the `c9cbb76` semantic baseline
before any behavior-adjacent test was trusted. The priority hierarchy is now
provable, not asserted: one composite test exercises a manual quantity edit,
a Not Needed override, a user-added item, and a carrier reassignment
surviving a single regeneration that simultaneously changes weather,
activities, and duration together, not one dimension at a time.

F-5 (Camping flashlight party sharing) is decided: personal-per-traveler,
deliberate, no behavior change. Six new scenario tests (solo, couple,
Hiking+Camping composition, guardian-carried-but-personally-owned, explicit
carrier reassignment, unassigned explicit item) plus the existing pinned
test's rewritten decision comment close the finding. Every scenario test
uses adult travelers or an explicitly-typed school-age child role — F-5
decides sharing only, never traveler/age eligibility, which stays Phase 10's.

The required amendment landed as specified: `SharingPolicy.personalOnly`'s
fallthrough-to-ownerless-shared-draft bug is fixed structurally inside
`sharingResolution` (a `.personalOnly` item never reaches the shared-draft
path — it short-circuits to `.personal` before `generateForParty`'s
`.isShared` check ever sees it), proven by four tests against a synthetic
test-local policy row. `shared/rules/party.json` is byte-unchanged.

All 13 required test gates map to a named task and a named, currently
passing test (table below). Two new golden fixtures (37, 38) add full-ledger
evidence for F-5 combined with party scaling, and for the shared-umbrella
case. Zero unexpected changes landed on fixtures 1–36 across any task.

## Per-task results

| Task | Result | Zero-diff / semantic-golden check |
| --- | --- | --- |
| 1 — Centralize party sharing resolution (+ `personalOnly` amendment) | green | `report_engine_goldens.py --baseline-ref c9cbb76`: **0** row changes across all 36 fixtures (1,288 unchanged rows) |
| 2 — Centralize explicit-authority gate + priority-hierarchy proof | green | Same command, same result: **0** row changes, 1,288 unchanged rows |
| 3 — Decide and close F-5 | green, no production change | N/A — regression/scenario-pinning only |
| 4 — Sharing-policy scenario tests (gates 3, 4, 12) | green, no production change | N/A — all four tests passed on first run |
| 5 — Dependency authority (gate 6) | green, no production change | N/A — passed on first run |
| 6 — Bag/style conflict gate (gate 2) | green, no production change | N/A — passed on first run |
| 7 — New golden fixtures + sharing determinism | green | Exactly 2 new fixtures (37, 38), **0** changes to 1–36 |
| 8 — Close Phase 7 | this document | Full gate set below |

### RED verification, recorded honestly

- **Task 1:** Both `sharingResolutionMatchesTodaysSharedByDefaultMembership`
  and the four `personalOnly` contract tests failed to **compile** on first
  run (`ConstraintResolver.sharingResolution`/`SharingResolution` did not
  exist) — genuine RED, not a runtime failure. After implementation, all 5
  new tests plus the full focused suite (100 tests, 4 suites) passed.
- **Task 2:** `hasUserAuthorityIsTrueForAddedOrModifiedOnly` and
  `isExplicitlyRemovedMatchesTravelerAndOwnershipScoping` failed to compile
  on first run (functions did not exist yet) — genuine RED. After
  implementation, all pass; the composite priority-hierarchy test
  (`explicitUserStateSurvivesASimultaneousMultiDimensionalRefresh`) passed
  on its first run once the production code existed (no separate RED cycle
  applies to a test that depends on functions introduced in the same step).
- **Task 3:** All six new scenario tests plus the rewritten pinned test
  passed once one test-authoring bug was fixed (see Deviations #1) — F-5's
  decision required no production code change, exactly as the design doc
  predicted.
- **Task 4:** All four tests (`coupleWithRainSharesOneUmbrellaNotOnePerPerson`,
  `familyOfFiveScalesSharedSunscreenByPartySize`,
  `travelAdapterScalesByDeviceCarryingTravelersOnly`,
  `ambiguousExplicitPersonalItemStaysUnassignedInAPartyList`) passed on
  first run, confirmed rather than assumed — the design doc's read of
  `sharedQuantity`'s arithmetic found no structural conflict on paper, only
  an absence of tests.
- **Task 5:** `userAddedChargerPreemptsTheAutomaticLaptopCompanion` passed
  on first run, confirmed rather than assumed.
- **Task 6:** `lightStyleNeverTrimsOnACheckedBag` passed on first run,
  confirmed rather than assumed.
- **Task 7:** The two new golden fixtures required one env-var correction
  (see Deviations #3) but recorded and matched review expectations exactly;
  `repeatedGenerationOnASharingHeavyPartyContextIsByteIdentical` failed on
  first run for a structural reason unrelated to engine correctness (see
  Deviations #2), then passed once corrected.

## All 13 required gates — task, test, and current pass status

| Gate | Task | Test | Status |
| --- | --- | --- | --- |
| 1 — Prepared+personal item | cited | `ConstraintTests.preparedVersusPersonalItemResolvesExplicitly` | passing, unchanged |
| 2 — Light+checked bag | 6 | `ConstraintTests.lightStyleNeverTrimsOnACheckedBag` | passing, new |
| 3 — couple shared umbrella | 4 | `ConstraintTests.coupleWithRainSharesOneUmbrellaNotOnePerPerson` | passing, new |
| 4 — family shared-item scaling | 4 | `ConstraintTests.familyOfFiveScalesSharedSunscreenByPartySize` + `.travelAdapterScalesByDeviceCarryingTravelersOnly` | passing, new |
| 5 — owner vs. carrier | cited | `ConstraintTests.ownerStaysWithTheSameTravelerAcrossRegeneration` + `.manuallyReassignedCarrierSurvivesRegeneration` | passing, unchanged |
| 6 — user-added item satisfying dependency | 5 | `ConstraintTests.userAddedChargerPreemptsTheAutomaticLaptopCompanion` | passing, new |
| 7 — manual quantity survival | cited | `ConstraintTests.manualQuantitySurvivesRegenerationWithChangedContext` + `ClothingQuantityTests.manualQuantitySurvivesWeatherRefresh` | passing, unchanged |
| 8 — Not Needed survival | cited | `ConstraintTests.removedBaseEssentialStaysRemovedAcrossRegeneration`, `WeatherChangeTests.notNeededRainJacketIsNotRestored`, `PackingEngineTests.recommendationDiffHonorsNotNeededOverride` | passing, unchanged |
| 9 — packed-state survival | cited | `ConstraintTests.packedStateSurvivesRegenerationWhenQuantityIsUnchanged` | passing, unchanged |
| 10 — user-added custom item survival | cited | `ConstraintTests.userAddedCanonicalAndCustomItemsSurviveRegeneration` | passing, unchanged |
| 11 — flashlight party semantics | 3 | six new scenario tests + rewritten `aPartyCampingTripKeepsFlashlightsPersonalPerTraveler` | passing, new/updated |
| 12 — ambiguous/unassigned party row | 4 (+3) | `ConstraintTests.ambiguousExplicitPersonalItemStaysUnassignedInAPartyList` + `ActivityContractTests.unassignedExplicitPersonalFlashlightStaysUnassigned` | passing, new |
| 13 — repeated-generation determinism | cited (Phase 1) + 7 | `ConstraintTests.repeatedGenerationOnASharingHeavyPartyContextIsByteIdentical` | passing, new |

All 13 confirmed against actually-committed test names, not just the plan's
self-review table (the plan's table matches what actually landed; no gate
was silently dropped or relabeled).

## Architecture — what's centralized versus what stayed put

- **Bag/style conflicts:** unchanged, already centralized in
  `ConstraintResolver.optionalRuling`. Only test gates (1, 2) were added.
- **Dependencies:** unchanged, already a closed declarative table
  (`CatalogItem.companions` + `addCompanions`'s dedup). Only test gate 6 was
  added.
- **Party sharing:** now centralized. `ConstraintResolver.sharingResolution(for:rules:context:party:)`
  replaces the two independent `Set(rules.party.sharedByDefault)` checks in
  `generateForParty` and `addCompanions`, and the free-standing
  `sharedQuantity`/`sharedQuantityReason` pair that lived on `PackingEngine`.
  `applyQuantities`'s shared-item branch now calls the same function and
  re-renders its fallback reason through `PackingEngine`'s own
  `render(...)`, preserving templated-string behavior exactly.
- **Explicit user authority:** now centralized. `ConstraintResolver.hasUserAuthority(_:)`
  and `.isExplicitlyRemoved(_:ownership:travelerID:overrides:)` replace the
  four independently-written checks in `resolve()`, `applyQuantities()`, and
  `addCompanions()` (via `PackingEngine.isRemoved`, now deleted).
- **Ownership vs. carrier:** unchanged, deliberately left split between
  `resolve()` (draft-creation-time assignment) and `PartyInvariants`
  (structural fail-safe) — the same "second closed authority" relationship
  `CoverageResolver` has to `ActivityContracts`. Not folded into
  `ConstraintResolver`.

## The `SharingPolicy.personalOnly` amendment — decided and tested this phase, not routed

Stated explicitly per the amendment's own instruction: the design doc's
first draft proposed routing this as an out-of-scope finding; review
amended that before implementation began. Party sharing membership is
exactly Task 1's subject, and zero current `sharingPolicies` rows use
`.personalOnly`, so fixing its fallthrough-to-ownerless-shared-draft bug
here changed zero golden output.

**The fix, as landed:** `ConstraintResolver.sharingResolution` checks
`rules.sharedByDefault.contains(canonicalItemID)` and then
`guard policy.policy != .personalOnly else { return .personal }` *before*
computing any shared quantity. Because `generateForParty`'s draft-creation
check now asks `sharingResolution(...).isShared` instead of raw
`sharedByDefault` membership, a `.personalOnly`-policy item never becomes a
`.shared`-ownership draft in the first place — it flows through the
ordinary per-traveler personal-item path with a real `travelerID` on every
draft.

**Proof — four tests, verified passing:**

- `personalOnlySoloProducesOneOwnedPersonalItem`: one draft,
  `ownershipType == .personal`, `travelerID != nil`.
- `personalOnlyCoupleProducesOnePersonalRowPerTraveler`: two drafts, one
  per traveler, both personal.
- `personalOnlyFamilyNeverProducesAnOwnerlessSharedDraft`: one draft per
  family member (3), `allSatisfy { $0.ownershipType != .shared && $0.travelerID != nil }`
  — the exact defect this test exists to prevent.
- `sharingResolutionNeverReturnsSharedForPersonalOnlyPolicy`: the pure
  function boundary, so a future edit cannot silently reintroduce the
  fallthrough without failing here first.

All four run against `rulesWithSyntheticPersonalOnly(for:)`, a test-local
`PartyRulesFile` copy with a `.personalOnly` row added only inside the test
on `toiletries.toothbrush` (an ordinary real, per-traveler item, chosen so
the assertion is about actual generated items, not the bare function).
**`shared/rules/party.json` gained no new row** — confirmed:
`git diff 69fa731 -- shared/rules/party.json` is empty.

## F-5 decision — Camping flashlight stays personal-per-traveler

**Decision:** personal-per-traveler is the correct product contract. No
behavior change. A flashlight is a personal-safety item, not scarce
infrastructure (adapter) or naturally communal (sunscreen, snacks) — the
three properties everything else in `sharedByDefault` has. At a dark
campsite, someone getting up alone at night, or the party splitting into
two groups, each person needs their own light source independently.

**Scope guard, followed as written:** F-5 decides sharing only — a
flashlight is not `singlePerParty`. It does not decide traveler/age
eligibility. Every one of the six new scenario tests uses adult travelers
or an explicitly-typed school-age `.child` role; none uses `.infant` or
`.toddler`. `oneTravelerCarryingAnothersItemsDoesNotMergeTheirFlashlights`
exercises the guardian-carrier case with a school-age child, not an infant,
and its own doc comment states the scope guard explicitly.

**Evidence:** the existing pinned test's comment is rewritten to record the
decision (was: "Phase 5 makes no party-sharing decision... this test
records the baseline that decision will be made against" — no longer
true). Six new tests cover solo, couple, Hiking+Camping composition, one
traveler carrying another's items (guardian carries, child owns), an
explicit carrier reassignment surviving regeneration, and an unassigned
explicit personal-item flashlight. Golden fixture 37 adds full-ledger
evidence: four personal flashlight rows for a family of 4, not one shared.

## Priority-hierarchy proof

`ConstraintTests.explicitUserStateSurvivesASimultaneousMultiDimensionalRefresh`
is the composite proof the task requires — not four independent
single-fact tests, one list carrying a manual quantity edit (T-shirts 3),
a Not Needed override (rain jacket), a user-added custom item (Travel
journal), and an explicit carrier reassignment (contacts solution), all
surviving one regeneration call that simultaneously changes weather (dry →
rainy), activities (+museum), and duration (5d → 8d) — three independent
rung-3 recomputations at once. All four rung-1/2 facts hold afterward,
confirmed by a passing test, not asserted by comment.

## Golden review

**Expected changes:** 2 new fixtures (37, 38). **0** changes to any of the
36 pre-existing fixtures across every category the semantic differ tracks
(unchanged/added/removed/quantity/trace/coverage/constraint rows).

| Category | Count |
| --- | --- |
| Fixtures compared | 36 (36 unchanged) |
| New fixtures | 2 |
| Removed fixtures | 0 |
| Unchanged rows across 1–36 | 1,288 |
| Row changes of any kind across 1–36 | 0 |

- **Fixture 37** (`family4-5d-hiking-camping-outdoor`, Yellowstone, family
  of 4): 4 `miscellaneous.flashlight` rows (child, child-2, partner,
  primary — one each, not shared); `toiletries.sunscreen` scales to 2
  (`ceil(4/3)`) and `toiletries.insect_repellent` to 1, both
  `ownershipType == shared`; owner/carrier remain distinct for both
  children's items (guardian carries, child owns).
- **Fixture 38** (`couple-5d-seattle-shared-umbrella`, couple, rain): one
  `essentials.umbrella_compact` (`shared`, quantity 1, reason "Rain is
  expected on 3 days. One umbrella should cover your group — no need to
  pack one each."); personal `clothing.rain_jacket` per traveler (2 rows).

User authority preserved throughout — no fixture that pins Not Needed,
manual quantity, user-added survival, packed state, or explicit
owner/carrier moved.

## Mechanical scope confirmation

| Check | Result |
| --- | --- |
| `PackingCapability` case count | unchanged (no new case added) |
| `ActivityNeed` case count | unchanged (no new case added) |
| `WeatherSignal` case count | unchanged (no new case added) |
| `shared/rules/party.json` | byte-identical to `69fa731` (confirmed via `git diff`) |
| `PartyInvariants` (`ios/PackWise/Domain/Party.swift`) | byte-unchanged since `69fa731` (confirmed: zero diff stat) |
| `CatalogItem.companions` (`ios/PackWise/Domain/Packing/Catalog.swift`) | byte-unchanged since `69fa731` (confirmed: zero diff stat) |
| `optionalRuling` (`ConstraintResolver.swift`) | byte-unchanged beyond additive extensions — confirmed: `git diff 69fa731` for this file shows zero removed/modified lines, only appended `extension ConstraintResolver` blocks |
| No new dependency graph/solver | confirmed — `companions: [String]` untouched |
| Files touched | exactly the plan's File Map: `ConstraintResolver.swift`, `PackingEngine.swift`, `ConstraintTests.swift`, `ActivityContractTests.swift`, `golden-fixtures.json`, two new `Goldens/*.json` |

## Verification

| Gate | Fresh result |
| --- | --- |
| `ConstraintTests` (focused) | 28/28 passing |
| Focused suites (`ConstraintTests`, `PackingEngineTests`, `ActivityContractTests`, `GoldenEngineTests`) | 103/103 passing (Task 1/2 checkpoint) |
| `scripts/run_engine_audit.sh` | all steps CLEAN: `validate_shared.py` clean (202 items); inclusion completeness 95.3% complete, 0 defects; quantity evidence 100% (309/309); user-authority rows correctly exempt; semantic golden diff vs HEAD CLEAN |
| Full `xcodebuild test` on iPhone 17 Pro simulator | **289 tests, 18 suites, 0 failures** |
| `python3 scripts/validate_shared.py` | 202 catalog items; integrity checks passed |
| `npm --prefix api run preflight` | `validate_shared.py` + `verify-artifact.ts` + `tsc --noEmit` + 106 node tests, 0 failures, exit 0 |
| Semantic diff vs `c9cbb76` | 2 new reviewed fixtures (37–38); **0** unexpected changes to fixtures 1–36 (1,288 unchanged rows) |

## Deviations from the approved plan

Recorded rather than silently reconciled, following Phase 4/5/6 precedent:

1. **`ActivityContractTests.oneTravelerCarryingAnothersItemsDoesNotMergeTheirFlashlights`**
   initially failed: the plan's literal snippet set
   `child.packingResponsibility = .guardian` but never set
   `child.guardianTravelerID`, so `Traveler.carrierID` fell back to the
   child's own `id` (`guardianTravelerID ?? id`) instead of the primary's —
   a test-authoring gap, not a production defect. Fixed by constructing the
   primary first and setting `child.guardianTravelerID = primary.id`
   explicitly.
2. **`ConstraintTests.repeatedGenerationOnASharingHeavyPartyContextIsByteIdentical`**
   as the plan's literal snippet wrote it (`first.items == second.items`,
   full struct equality) can never pass regardless of engine correctness:
   `PackingItemDraft.id` is a fresh `UUID()` on every created draft, so two
   independent `generate()` calls always produce different `id` values even
   when every other field matches. Fixed by normalizing `id` to a fixed
   sentinel value before comparing on both sides — the same principle the
   golden harness's own doc comment states ("UUIDs, timestamps, and packing
   state are excluded from serialization"). `travelerID`/`assignedTravelerID`
   were deliberately *not* normalized, since their equality (derived from
   the same `party` value on both calls) is itself part of what the test
   proves.
3. **Golden-recording env var:** `TEST_RUNNER_PACKWISE_RECORD_GOLDENS=1`,
   not `PACKWISE_RECORD_GOLDENS=1` as the plan's Task 7 Step 2 snippet
   shows — same correction Phase 6's closure already recorded; repeating it
   here since Phase 7's plan text still had the uncorrected form.
4. **`ConstraintTests`'s local `context(...)` helper** gained a `weather:`
   parameter (default `nil`, every existing call site unaffected) and a
   `forecast(start:days:high:low:rain:uv:wind:)` helper mirroring
   `WeatherChangeTests`'s private helper of the same shape — needed by
   Task 2's composite test and Task 4's `rainyContext`/`sunnyContext`, not
   explicitly named as a plan step but required to build the weather
   fixtures the plan's own test snippets call for.
5. **`ActivityContractTests.campingContext`** gained a `days: Int = 4`
   parameter (default matches the prior hardcoded value, every existing
   call site unaffected) — needed by
   `explicitFlashlightCarrierReassignmentSurvivesRegeneration`'s
   `days: 6` regeneration call, which the plan's own snippet uses but the
   helper didn't support until this task.
6. **`ConstraintTests.travelAdapterScalesByDeviceCarryingTravelersOnly`**
   uses `chips: [.travelingInternationally]` instead of the plan's literal
   `type: .international` — no such `TripType` case exists (`TripType`'s
   11 cases do not include `international`; internationality is a derived
   property, `context.isInternationalConfirmed`, triggered by a
   `contextChips` chip or a destination/home-country mismatch). This
   produces the identical `context.isInternationalConfirmed == true` state
   the test needs to make the travel adapter a candidate.

## Finding routed, not fixed (outside this task's file list)

- **`shared/rules/reasons.json`'s `party.shared` template does not
  pluralize.** Surfaced by golden fixture 37 (family of 4, sunscreen
  scales to quantity 2): the rendered `quantityReason` still reads "One for
  the group — not one per person." — a static string with no `{quantity}`
  placeholder, unlike `party.shared_umbrella`, which pluralizes correctly
  via pre-built phrases (`rainDaysPhrase`/`umbrellaPhrase`). Confirmed
  pre-existing, not introduced by this phase's refactor: the same static
  string was already the template's committed value before any Phase 7
  commit, and `sharedQuantity`'s arithmetic (which Phase 7 moved verbatim)
  produces the correct `quantity == 2`; only the reason *copy*
  under-pluralizes. No existing fixture 1–36 has a party size large enough
  to expose this (the largest pre-existing sharing scenario tops out at
  quantity 1 for every `scaleByParty` item). Editing `reasons.json` copy is
  outside Task 7's file list and outside this phase's named scope (a
  presentation/copy-quality fix, not a constraint-resolution behavior
  question); routed forward, unowned by any phase yet.

## Routed findings carried forward, unaffected by Phase 7

- **F-1** (golden-diff schema tolerance, P2) — unaffected, carried forward.
- **Context-chip/bag-type/trip-type UNTESTED tail (14 rows)** — pre-existing,
  outside Phase 7's scope, unaffected.
- **`CoverageContext` double-construction** (noted by Phase 6's design doc)
  — unaffected by Phase 7, carried forward unchanged.
- **Golden fixture schema cannot express a weather fixture shorter than
  trip days** (Phase 6 finding) — unaffected, carried forward.

Presentation remains frozen. Physical-device App Attest and UI/UX
verification remain deferred, not complete. M3B/M3C remain blocked by their
existing gate. Phase 8 (trace productization) and Phase 9+ (context
intelligence) are not started; Phase 7 does not touch anything Phase 8/9+
owns.

## Exit gate

1. Party sharing resolution is a zero-diff refactor (Task 1) — **green**.
2. `SharingPolicy.personalOnly`'s fallthrough bug is fixed and tested this
   phase, `party.json` gains no new row — **green**.
3. Explicit-authority gate is centralized and zero-diff (Task 2) — **green**.
4. Priority hierarchy proven by a composite, multi-dimensional test, not
   asserted — **green**.
5. F-5 decided (personal-per-traveler), scope-bounded to sharing only, no
   behavior change — **green**.
6. All 13 required test gates map to a named task and a named, currently
   passing test — **green**.
7. Two new golden fixtures reviewed; 0 unexpected changes to 1–36 — **green**.
8. `PackingCapability`/`ActivityNeed`/`WeatherSignal` case counts unchanged;
   `party.json`, `PartyInvariants`, `CatalogItem.companions` byte-unchanged;
   `optionalRuling` additive-only — **green**.
9. User authority preserved (Not Needed, manual quantity, user-added,
   packed, owner/carrier) under both single- and multi-dimensional
   regeneration — **green**.
10. Focused suites, engine audit, full iOS, shared, and API gates — **green**.
11. Phase 7 evidence committed separately; Phase 8 unopened — **green on
    closure commit**.
