# Phase 2 closure — context snapshot audit

Closing evidence for Product Hardening Phase 2
(`docs/plans/2026-09-02-product-hardening-program.md`,
`docs/plans/2026-09-03-phase-2-context-model-hardening.md`). Everything in
this file was regenerated or re-verified against the state at Phase 2's
closing commit (see the git log for the exact SHA the `docs: close phase 2
context model hardening` commit records).

---

## 1. What `TripContextSnapshot`/`TripContextCompiler` do, and where they live

- **Type:** `ios/PackWise/Domain/TripContextSnapshot.swift` — a new, pure,
  `Sendable`, `Hashable` domain type. It is compiled once, behind the engine
  boundary, from the same `TripContext` and `PackingRulesFile` the engine
  already loads — there is no separate source of truth for what counts as a
  "known" activity, laundry state, or party structure.
- **Compiler:** `TripContextCompiler.compile(_:rules:) -> TripContextSnapshot`
  (same file) is the single entry point. It normalizes six dimensions —
  dates, activities, bag/style, laundry, weather quality, and party — into
  one deterministic value, and produces zero or more `ContextDiagnostic`
  entries (`field`, `outcome`) recording anywhere a raw `TripContext` value
  was recomputed (`normalized`) or couldn't be honored as given
  (`unsupportedButSafe`). A field with no diagnostic is valid by omission —
  that is the sparse convention the compiler actually follows (see the
  doc comment on `ContextOutcome.valid`, which exists for completeness but
  is not constructed by any path in the compiler today).
- **Wiring:** `PackingEngine.generateDetailed(context:existing:overrides:)`
  (`ios/PackWise/Domain/Packing/PackingEngine.swift`) compiles one snapshot
  per call and attaches its `diagnostics` to a new, additive
  `EngineGeneration.contextDiagnostics: [ContextDiagnostic]` field. No
  decision logic anywhere in `generateSimple`, `generateForParty`, or
  `resolve` reads from the snapshot — it exists purely for validation and
  observability in this phase. `contextDiagnostics` is not serialized into
  golden JSON (`GoldenEngineTests.swift`'s `GoldenOutput`/`GoldenItem` never
  reference it), so it cannot appear in a golden diff.
- **Tests:** `ios/PackWiseTests/TripContextSnapshotTests.swift` — 23 tests,
  one per normalization case plus determinism (narrow and broad). The 24th
  new Phase 2 test — the full-ledger fixture test — lives in
  `ios/PackWiseTests/GoldenEngineTests.swift`'s
  `everyGoldenFixtureCompilesToADeterministicSnapshot()`.

---

## 2. Edge-case coverage matrix

Every case named in the Phase 2 directive, and the test(s) that cover it —
all in `ios/PackWiseTests/TripContextSnapshotTests.swift` unless noted:

| case | test(s) |
| --- | --- |
| Valid context (no diagnostic) | `validDatesCompileWithNoDiagnostic`, `knownActivitiesAreClassifiedKnown`, `packingStylePassesThroughUnchanged`, `validPartyPassesThroughWithNoDiagnostic` |
| Normalized context (`.normalized`) | `mismatchedStoredDurationIsRecomputedAndNormalized` (dates), `legacyLaundrySignalIsNormalizedNotJustPassedThrough` (laundry) |
| `unsupportedButSafe` | `reversedDatesAreUnsupportedButSafe` (dates), `unrecognizedActivityIsPreservedAndFlaggedUnsupportedButSafe` (activities), `childWithGuardianOutsidePartyLosesTheReferenceRatherThanGuessing`, `guardianNotAllowedOnAdultTravelerIsAlsoDropped`, `guardianNotAdultIsDroppedNotReassigned` (party — all three `PartyInvariants` violation kinds) |
| Unknown/custom activity | `unrecognizedActivityIsPreservedAndFlaggedUnsupportedButSafe`, `campingIsHonestlyClassifiedUnknownLikeAnyOtherRulelessActivity` (pins the Phase 1 finding: `camping` gets no hardcoded exception) |
| `BagType.notSure` invents no constraint | `notSureBagAppliesNoConstraint` |
| Missing weather | `missingWeatherIsClassifiedMissing` |
| Partial/seasonal weather quality | `partialForecastDoesNotClaimWholeTripCoverage` (partial), `seasonalWeatherIsClassifiedSeasonalOnly` (seasonal); `wholeTripForecastIsClassifiedComplete` and `cacheSourceDoesNotChangeWeatherQualityFromLiveCoverage` round out the four `WeatherQuality` cases and pin the deliberate cache-staleness divergence from `TripWeatherContext.state()` |
| Invalid/reversed dates | `reversedDatesAreUnsupportedButSafe` |
| Empty/malformed party state | `emptyPartyIsAlreadySafeViaEffectiveParty` (empty, via `effectiveParty`'s existing `.solo()` fallback), `childWithGuardianOutsidePartyLosesTheReferenceRatherThanGuessing`, `guardianNotAllowedOnAdultTravelerIsAlsoDropped`, `guardianNotAdultIsDroppedNotReassigned` (malformed — all three violation kinds) |
| Legacy laundry normalization | `laundryPlanMatchesExistingTripContextEquivalenceForEveryLegacyPath` (explicit/chip/notes/none, asserted equal to `TripContext.laundryPlan` itself — the equivalence baseline, not reimplemented), `legacyLaundrySignalIsNormalizedNotJustPassedThrough` |
| Deterministic compilation across repeated runs | `compilationIsDeterministicAcrossRepeatedRuns` (single context), `partyCompilationIsDeterministicAcrossRepeatedRuns` (a violation-bearing context), `everyGoldenFixtureCompilesToADeterministicSnapshot` in `GoldenEngineTests.swift` (all 27 real fixtures, compiled twice each) |
| Ambiguous traveler context → don't infer | `ambiguousGuardianAmongMultipleAdultsIsNeverInferred` (a `nil`-guardian child with two candidate adults present stays `nil`, never defaults to "the first adult"), `childWithGuardianOutsidePartyLosesTheReferenceRatherThanGuessing`, `guardianNotAdultIsDroppedNotReassigned` (a dropped reference is never rewritten to a guessed real member) |

All 12 required cases are covered. `ambiguousGuardianAmongMultipleAdultsIsNeverInferred`
additionally asserts `!diagnostics.contains { $0.field == "party" }` — a
`nil` guardian on a child who needs one is not itself a `PartyInvariants`
violation (it's an already-valid "no guardian assigned" state), so it
correctly produces no diagnostic; the "don't infer" property holds even
where there's nothing to normalize.

---

## 3. Per-fixture diagnostics — verified, not assumed

The Task 5 full-ledger test (`everyGoldenFixtureCompilesToADeterministicSnapshot`)
only asserts that no fixture shows an *unexpected* (non-"activities")
diagnostic — its assertion is structural (any fixture with an activities
diagnostic passes), not scoped to fixture IDs 18/25 specifically. Per this
task's brief, that structural pass was independently re-verified by running
the compiler against all 27 real fixture-derived contexts and recording the
actual per-fixture diagnostics ledger (temporary instrumentation added to
`GoldenEngineTests.swift`, run via `xcodebuild test
-only-testing:PackWiseTests/GoldenEngineTests`, captured, then reverted
before this closing commit — it is not part of the committed test suite).

Real output, all 27 fixtures:

| fixture | diagnostics |
| --- | --- |
| 01-chicago-5d-city-balanced | none |
| 02-tokyo-15d-light-laundry-possible | none |
| 02b-tokyo-15d-light-laundry-planned | none |
| 03-tokyo-15d-light-laundry-none | none |
| 04-tokyo-15d-prepared-checked | none |
| 05-tokyo-30d-light-laundry-planned | none |
| 06-miami-5d-beach-personal-item | none |
| 07-chicago-5d-business-checked | none |
| 08-running-sightseeing-footwear | none |
| 09-seattle-rain-layering | none |
| 10-one-day-trip | none |
| 11-couple-5d-rain | none |
| 12-family-toddler-7d-seasonal | none |
| 13-override-survives-regeneration | none |
| 14-manual-quantity-survives-refresh | none |
| 15-minneapolis-6d-deep-winter | none |
| 16-minneapolis-7d-winter-family | none |
| **18-reykjavik-64d-roadtrip-camping-seasonal** | **`activities` → `unsupportedButSafe("camping: no rule in the engine's activity vocabulary")`** |
| 19-phoenix-5d-city-walking-hot | none |
| 20-seattle-5d-vacation-rain-sufficiency | none |
| 21-aspen-5d-skisnow-checked-prepared-snow | none |
| 22-chicago-5d-business-running-overlap | none |
| 23-cancun-7d-international-beach-personal-item | none |
| 24-miami-6d-family-infant-no-needs | none |
| **25-chicago-5d-unknown-activity-cosplay** | **`activities` → `unsupportedButSafe("cosplayConvention: no rule in the engine's activity vocabulary")`** |
| 26-seattle-5d-existing-rain-shell | none |
| 27-chicago-5d-custom-item-survives-regeneration | none |

**Confirmed exactly as expected: fixtures 18 and 25 are the only two of the
27 that carry any diagnostic at all, and both are the "activities" diagnostic
already predicted by the published Phase 1 finding** (`camping` and
`cosplayConvention` have no `rules.activities` entry —
`docs/engine-audits/2026-09-03-engine-findings.md`, P1-2 and the
unknown-activity-degrades-inertly design fixture 25 was built to prove). No
fixture — including the 64-day/high-latitude fixture 18, the reversed-date
adjacent duration edge cases (fixture 10's one-day trip), or any of the
family/party fixtures (12, 16, 24) — shows a `dates` or `party` diagnostic.
Every one of the 27 fixtures is a real, well-formed trip with a structurally
valid party, so this is the correct, unsurprising result — not a coincidence
being reported as a finding.

---

## 4. Migration-boundary state

**Compiled behind the boundary now:** `PackingEngine.generateDetailed` is
the only call site that invokes `TripContextCompiler.compile`. It uses the
resulting snapshot for exactly one purpose — attaching
`EngineGeneration.contextDiagnostics` — and nothing else. `generate`,
`generateSimple`, `generateForParty`, `resolve`, and every downstream
decision path (`ClothingQuantity`, `CoverageResolver`, `ConstraintResolver`,
weather rule application) continue to read `TripContext` directly, exactly
as before this phase. Grepping the full `ios/PackWise` tree confirms
`TripContextSnapshot`/`TripContextCompiler` appear in exactly two files:
`TripContextSnapshot.swift` itself and `PackingEngine.swift`. No UI,
SwiftData repository, or other engine file references either type.

**What still reads `TripContext` directly:** everything else — the entire
decision surface of the engine, all of `ios/PackWise/Data/` (SwiftData
persistence), all of `ios/PackWise/Presentation/` (UI/`TripSetupView` and
friends), and the API/WeatherKit boundaries. The one internal call site
worth naming specifically is `ios/PackWise/Domain/Packing/ClothingQuantity.swift:268`
(`ClothingQuantityEngine.compute(_:context:formalTopUnits:)`'s
`laundry: context.laundryPlan` argument) — the single cleanest candidate for
migrating to `snapshot.laundryPlan`, since Task 3 already proved the two are
provably equivalent. **This is deliberately not migrated in Phase 2.** Per
the plan's Global Constraints and self-review, `ClothingQuantity.swift`
belongs to the Phase-3-owned clothing/quantity family; migrating its one
`laundryPlan` read now would blur Phase 2's scope (context correctness) into
Phase 3's (clothing decision logic) for a change with zero behavioral
payoff in this phase — the values are already provably identical, so
migrating it here would be pure churn against a file this phase has no
mandate to touch. Deciding whether to migrate it (or migrate the family more
broadly to `TripContextSnapshot` reads) is explicitly left to Phase 3.

**Why no consumer opted in during Phase 2:** the plan's exit gate for this
phase is a compiled, tested, wired-for-diagnostics snapshot with zero
behavior drift — not consumer adoption. Every other candidate read site
(coverage, constraints, weather rule application, activity rule lookups)
sits inside files the plan's self-review explicitly reserves for Phases 3,
4, 5, and 6 (`ClothingQuantity.swift`, `CoverageResolver.swift`,
`ConstraintResolver.swift`, `QuantityEngine.swift`, and weather/reconciliation
logic). Opting any of them in now would mean either duplicating decision
logic against two sources of context (risking silent divergence) or
migrating a family's decision path wholesale — both out of scope for a
phase whose job was to prove the model, not adopt it.

---

## 5. Validation — three commands, exact output

### 5.1 `scripts/run_engine_audit.sh`

Ran clean end-to-end, all 6 steps:

```text
==> 1/6  Shared data referential integrity (scripts/validate_shared.py)
OK: 202 items, integrity checks passed

==> 2/6  Python audit test suite (scripts/tests)
... (deliberate error-path tests for malformed JSON / bad refs / missing dirs, all expected) ...
CLEAN

==> 3/6  Focused Swift suites (Task 4 invariant/authority/failure audits)
    ClothingQuantityTests, ConstraintTests, IntelligenceServiceTests,
    ContextIntelligenceGateTests, WeatherChangeTests
** TEST SUCCEEDED **

==> 4/6  Semantic golden diff against HEAD (scripts/report_engine_goldens.py)
  UNCHANGED: 1011  ADDED: 0  REMOVED: 0  QUANTITY CHANGES: 0  TRACE CHANGES: 0
  COVERAGE CHANGES: 0  CONSTRAINT CHANGES: 0
CLEAN

==> 5/6  Surfaced-input contract audit (scripts/audit_engine_inputs.py)
| total | deterministic (tested) | untested | context-only | dead |
| 49    | 24                     | 23       | 0            | 2    |

==> 6/6  Recommendation-trace audit (scripts/audit_recommendation_traces.py)
Inclusion completeness: 964/1008 (95.6%), 0 hard defects
Quantity evidence: 194/219 (88.6%), 25 rows missing evidence

All engine audit steps passed.
```

Exit code 0. Numbers are unchanged from the Phase 1 baseline
(`docs/engine-audits/2026-09-03-phase-1-baseline.md`) — expected, since
Phase 2 did not touch any golden-affecting code path (see §5.3).

### 5.2 Full `xcodebuild test`

```text
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

`** TEST SUCCEEDED **` — `Test run with 191 tests in 16 suites passed after
0.874 seconds`. Includes `TripContextSnapshotTests` (23/23) and
`GoldenEngineTests`'s `everyGoldenFixtureCompilesToADeterministicSnapshot`,
both passing. Zero failures anywhere in the suite.

### 5.3 `report_engine_goldens.py` against the pre-Phase-1 baseline

The plan's literal command,
`python3 scripts/report_engine_goldens.py --baseline-ref fe7aca0 --candidate ios/PackWiseTests/Goldens`,
**fails with `KeyError: 'carrier'`** rather than producing a report. This is
a genuine, verified tool/schema-compatibility gap, not a recommendation
regression — see the finding in §6 (F-1) for the root cause and routing.
`fe7aca0` predates Phase 1 Task 1's addition of the `carrier` and
`reasonArguments` fields (`GoldenItem.from_json` reads `raw["carrier"]`
with no fallback), and it predates fixtures 18–27 (Phase 1 Task 3): `git
ls-tree -r fe7aca0 -- ios/PackWiseTests/Goldens` returns 17 files with the
pre-Task-1 item schema (`canonicalItemID`, `category`, `displayName`,
`importance`, `owner`, `quantity`, `quantityReason`, `reason`, `reasonCode`,
`signals` — no `carrier`, no `reasonArguments`), confirmed directly against
both `fe7aca0` and the current tree.

To still deliver the evidence this step exists to produce — proof that
Phase 1 + Phase 2 together changed zero recommendation behavior relative to
the pre-Phase-1 baseline — two compatible comparisons were run instead:

**(a) Phase 2's own isolated diff**, comparing the Phase 1 closing commit
(`81be9bb`, already on the modern schema) against the current candidate —
this directly answers "did Phase 2 alone change anything," on the full
schema, with the shipped tool unmodified:

```text
python3 scripts/report_engine_goldens.py --baseline-ref 81be9bb --candidate ios/PackWiseTests/Goldens

Overall
-------
Fixtures compared: 27 (27 unchanged)
  UNCHANGED: 1011  ADDED: 0  REMOVED: 0  QUANTITY CHANGES: 0  TRACE CHANGES: 0
  COVERAGE CHANGES: 0  CONSTRAINT CHANGES: 0
CLEAN
```

**(b) The pre-Phase-1 slice**, using a schema-tolerant comparator (ad hoc,
not committed — decodes both sides but restricts the field-level diff to
the 10 fields that existed in both the `fe7aca0` and current item schemas:
`canonicalItemID`, `category`, `displayName`, `importance`, `owner`,
`quantity`, `quantityReason`, `reason`, `reasonCode`, `signals`):

```text
Baseline (fe7aca0) fixtures: 17
Candidate (working tree) fixtures: 27
Shared (schema-comparable) fixtures: 17
Fixtures only in candidate (added since baseline): 10
  (18, 19, 20, 21, 22, 23, 24, 25, 26, 27 — all Phase 1 Task 3 additions,
   already reviewed and closed in Phase 1)

[01] ... UNCHANGED=28 ADDED=0 REMOVED=0 FIELD-DIFFS=0
[02] ... UNCHANGED=35 ADDED=0 REMOVED=0 FIELD-DIFFS=0
... (all 17 shared fixtures, same pattern) ...
[16] ... UNCHANGED=98 ADDED=0 REMOVED=0 FIELD-DIFFS=0

CLEAN on shared-schema fields across all 17 shared fixtures.
```

**Together, (a) and (b) prove what the single command was meant to prove:**
every fixture that existed before Phase 1 began is byte-identical, on every
field that schema had, all the way through Phase 1 + Phase 2 (b); and the
Phase-2-only slice — including the 10 fixtures Phase 1 added — shows zero
change on the full modern schema, `carrier`/`reasonArguments` included (a).
No recommendation, quantity, trace, coverage, or constraint output changed
anywhere across the whole arc.

---

## 6. New findings from this task's own work

### F-1 — `report_engine_goldens.py` cannot diff against a pre-Task-1 golden baseline

- **File:** `scripts/report_engine_goldens.py:109` (`GoldenItem.from_json`:
  `carrier=raw["carrier"]`, no `.get` fallback).
- **Observed:** the script's `GoldenItem` schema mirrors the *current*
  `GoldenEngineTests.swift` serialization unconditionally. Any baseline ref
  from before Phase 1 Task 1 added `carrier`/`reasonArguments` (i.e. any
  commit at or before `fe7aca0`) raises `KeyError: 'carrier'` instead of
  producing a diff or a clear "schema mismatch" error.
- **Desired:** either `GoldenItem.from_json` tolerates missing
  `carrier`/`reasonArguments` (treating them as "not tracked in this
  baseline" rather than crashing), or the script fails with a clear,
  actionable message ("baseline schema predates field X; use
  `--baseline-ref <post-Task-1 commit>` or accept a reduced field set")
  instead of an unguarded `KeyError`. This is the second time in this
  phase's evidence work that a baseline-ref comparison needed a schema-aware
  fallback (see §5.3) — worth fixing once in the tool rather than
  re-deriving a workaround at each future phase closure that wants to diff
  against a pre-Phase-1 commit.
- **Command:**
  ```bash
  python3 scripts/report_engine_goldens.py --baseline-ref fe7aca0 --candidate ios/PackWiseTests/Goldens
  # KeyError: 'carrier'
  ```
- **Severity/destination:** P2 (tooling-only; no recommendation-behavior
  impact — verified via the two-part workaround in §5.3). This isn't a
  program-numbered engine phase's finding — it's audit-infrastructure debt
  that whichever phase next needs to diff against a pre-Phase-1 commit
  should either fix (extend `GoldenItem.from_json`) or route around (pick a
  post-Task-1 baseline ref, as §5.3(a) did for the Phase-2-only slice).
  Flagging it here rather than silently working around it and moving on.

No other new findings surfaced. The full-ledger fixture compilation (§3)
matched its predicted result exactly — no new unexpected diagnostic, no
crash, no non-determinism — so this task's own work did not uncover any
engine-behavior defect beyond the one tooling gap above.

---

## 7. Evidence paths

| artifact | path |
| --- | --- |
| Snapshot type + compiler | `ios/PackWise/Domain/TripContextSnapshot.swift` |
| Engine wiring | `ios/PackWise/Domain/Packing/PackingEngine.swift` (`EngineGeneration.contextDiagnostics`, `generateDetailed`) |
| Unit tests | `ios/PackWiseTests/TripContextSnapshotTests.swift` (23 tests) |
| Full-ledger fixture test | `ios/PackWiseTests/GoldenEngineTests.swift` (`everyGoldenFixtureCompilesToADeterministicSnapshot`) |
| Phase 2 plan | `docs/plans/2026-09-03-phase-2-context-model-hardening.md` |
| This report | `docs/engine-audits/2026-09-03-phase-2-context-snapshot.md` |
| Program closure | `docs/plans/2026-09-02-product-hardening-program.md` ("Phase 2 closure" section) |

One command replays the deterministic-regression slice of this evidence:
`scripts/run_engine_audit.sh`.
