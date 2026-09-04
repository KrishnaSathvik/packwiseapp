# PackWise Product Hardening Program

**Date:** 2026-09-02  
**Status:** active; Phases 1–4 closed 2026-09-03; Phase 5 closed 2026-09-04; Phase 6 closed 2026-09-04; Phase 7 closed 2026-09-04; Phase 8 closed 2026-09-04; Phase 9 not started
**Source of truth:** this program orders the user-approved Final UI Refinement & Freeze Plan and Product Hardening + Engine V2 Plan against the repository as it exists today.

## Goal

For every normal trip configuration, PackWise produces a coherent, visibly trip-specific, explainable packing experience. Unsupported or ambiguous inputs degrade conservatively. Explicit user decisions always win.

## Repository reconciliation

The repository is ahead of the proposed sequence: the golden harness, clothing quantities, coverage, constraints, recommendation traces, memory-event capture, and the Miami/Chicago perception gate already exist and are committed. They are not rolled back. During Phase 0 they are frozen: no changes under `ios/PackWise/Domain/`, `ios/PackWise/Data/`, `api/`, or `shared/` unless the UI/device pass exposes a genuine defect.

The current uncommitted `ios/PackWise.xcodeproj/project.pbxproj` signing change predates this program and is excluded from the Phase 0 and product-hardening commits.

## Sequencing decision — 2026-09-03

The product owner explicitly deferred the physical-device UI/App Attest pass
and authorized deterministic Product Hardening Phase 1 after the
simulator-verified presentation baseline is committed. This changes sequencing,
not evidence: the device checks remain unverified, and no device-verified UI tag
is created.

```text
Phase 0 implementation          complete
Phase 0 simulator verification  complete — 143 tests, 87-screen matrix
Phase 0 device verification     deferred by product decision, not verified
Presentation baseline           frozen for deterministic hardening
Phase 1                         authorized
M3B/M3C                         still blocked by the M3A device exit gate
```

## Phase 1 closure — 2026-09-03

Phase 1 (golden ledger audit and fixture expansion) is complete. Six tasks:

1. Golden schema completeness (`carrier`, `reasonArguments`) — 17 → 27 fixtures serialize.
2. `scripts/report_engine_goldens.py` — semantic golden diff tool.
3. Fixture ledger expanded 17 → 27, closing coverage gaps the original set didn't reach (extreme duration/latitude, hot/dry climate, sustained rain sufficiency, ski/snow trip type, activity overlap, international-plus-beach, infant-vs-toddler contrast, unknown-input degradation, existing-item/custom-item authority).
4. Invariant/authority/failure audits across `ClothingQuantityTests`, `ConstraintTests`, `IntelligenceServiceTests`, `ContextIntelligenceGateTests`, `WeatherChangeTests`.
5. `docs/engine-audits/surfaced-input-contracts.json` — 49-record surfaced-input inventory; `scripts/audit_engine_inputs.py`.
6. `scripts/audit_recommendation_traces.py` (trace-completeness audit), `scripts/run_engine_audit.sh` (one reproducible command), and the closing report set below.

Exit evidence:

- `docs/engine-audits/2026-09-03-phase-1-baseline.md` — fixture manifest, schema gaps, two-run determinism (verified byte-identical, not assumed), quantity properties, authority/fallback matrix, surfaced-input coverage, trace metrics, the Miami/Chicago gate, and a full evidence-path index.
- `docs/engine-audits/2026-09-03-trace-coverage.md` — the trace-completeness numbers in full.
- `docs/engine-audits/2026-09-03-engine-findings.md` — every defect and coverage gap found across Tasks 3–6, ranked P0/P1/P2, each routed to the phase below that owns its fix. No P0s. Five P1s, six P2s (one of the P2s — 23 untested-but-deterministic surfaced inputs — spans phases 2, 5, and 7 by kind).
- `scripts/run_engine_audit.sh` passed end-to-end: shared-data validation, the full Python audit test suite, the five Task 4 Swift suites, the semantic golden diff against HEAD (clean), the surfaced-input audit, and the trace audit.
- Full `xcodebuild test` (all of `PackWiseTests`, not just the five focused suites) and `npm --prefix api run preflight` were run as this task's final validation pass — see the closing commit's evidence for pass/fail detail.

**Phase 2 (context model hardening) has not started.** No work under
`ios/PackWise/Domain/`, `ios/PackWise/Data/`, `api/`, or `shared/` happened
in Phase 1 beyond what the six tasks above required to build audit tooling
and fixtures — Phase 1 changed measurement and evidence, not engine or
production behavior.

## Phase 2 closure — 2026-09-03

Phase 2 (context model hardening) is complete. Six tasks:

1. `TripContextSnapshot`/`TripContextCompiler` type and date normalization
   (`ios/PackWise/Domain/TripContextSnapshot.swift`) — recomputes
   `durationDays`/`durationNights` from real dates rather than trusting a
   stale stored value, and reuses `TripDateMath`'s existing safe clamp for a
   reversed date range rather than inventing new date-safety logic.
2. Activity and bag/style normalization — known vs. unknown activity IDs
   against `rules.activities` (the engine's real vocabulary, no separate
   source of truth), `BagType.notSure` applying no invented constraint,
   `PackingStyle` passed through unchanged.
3. Laundry and weather-quality normalization — `laundryPlan` provably
   equivalent to `TripContext.laundryPlan` across every legacy signal path,
   `WeatherQuality` (`missing`/`seasonalOnly`/`partial`/`complete`)
   deliberately diverging from `TripWeatherContext.state()` only on
   cache-staleness handling (tracks structural coverage, not refresh
   timing).
4. Party normalization — reuses `PartyInvariants.violations`, drops invalid
   guardian references, never reassigns to a guessed adult even when
   multiple candidate adults exist on the party.
5. Full-ledger fixture compilation (all 27 golden fixtures compile
   deterministically) and engine-boundary wiring — `EngineGeneration`
   gained one additive `contextDiagnostics` field; `generateDetailed`
   compiles one snapshot per call for diagnostics only, read by no decision
   logic anywhere in the engine.
6. Full audit run, evidence report, and this closure section.

Exit evidence:

- `docs/engine-audits/2026-09-03-phase-2-context-snapshot.md` — what the
  snapshot/compiler do, the full 11-case edge-case coverage matrix mapped to
  tests, the independently-verified per-fixture diagnostics ledger (exactly
  fixtures 18 and 25 carry a diagnostic, both the expected `activities`
  case — every other fixture is diagnostic-free, confirmed by running the
  compiler against all 27 fixtures directly rather than assumed), the
  migration-boundary state (`ClothingQuantity.swift:268` named as the one
  known internal `laundryPlan` read left unmigrated, deliberately, for
  Phase 3), and one new tooling finding (F-1, P2: `report_engine_goldens.py`
  can't diff against a pre-Task-1 golden schema without a `KeyError` —
  worked around for this closure, routed for a future fix).
- `scripts/run_engine_audit.sh` passed clean, all 6 steps, numbers unchanged
  from the Phase 1 baseline (Phase 2 touched no golden-affecting code path).
- Full `xcodebuild test`: `** TEST SUCCEEDED **`, 191 tests across 16
  suites, including `TripContextSnapshotTests` (23/23) and
  `GoldenEngineTests`'s full-ledger snapshot-compilation test (the 24th new
  Phase 2 test).
- Zero recommendation-behavior drift proven twice: `report_engine_goldens.py
  --baseline-ref 81be9bb` (Phase 1's closing commit) shows 27/27 unchanged
  on the full modern schema, isolating Phase 2's own contribution; a
  schema-tolerant comparison against `fe7aca0` (pre-Phase-1) shows all 17
  fixtures that existed then are unchanged on every field that schema
  had, across the whole Phase 1 + Phase 2 arc.

## Phase 3 closure — 2026-09-03

Phase 3 (clothing needs and quantities) is complete. Clothing alone now reads
the normalized snapshot through `ClothingQuantityContext`; all unrelated
engine families remain on their prior inputs. Explicit family policies cover
daily essentials, high-reuse bottoms, low-sensitivity sleepwear, scheduled
workouts, swim drying rotation, appearance overlap, and existing attributed
age buffers. Each policy-sensitive result carries structured quantity
evidence without a SwiftData or UI change.

Exit evidence is
`docs/engine-audits/2026-09-03-phase-3-clothing-quantities.md`: 27-fixture
semantic review (3 intended clothing quantity changes, 189 clothing
quantity-trace changes, zero unexpected behavior changes), all 221
quantity-required trace rows evidenced, the six-step engine audit green, 205
iOS tests across 16 suites green, 202 shared items valid, and 106 API tests
green. User quantities, Not Needed, user-added items, packed state, owner, and
carrier remain authoritative.

## Phase 4 closure — 2026-09-03

Phase 4 (footwear and outerwear coverage) is complete. The existing
`CoverageResolver` remains the one closed typed authority and now reads a
narrow `CoverageContext` derived from `TripContextSnapshot`. Exact structured
facts map every suppressed capability to its deterministic covering item, with
separate evidence for refuted needs. Two approved hand-protection capabilities
resolve the ski-glove/ordinary-glove overlap generically; no shared-JSON
migration or ID-pair exception was added.

Exit evidence is
`docs/engine-audits/2026-09-03-phase-4-footwear-outerwear-coverage.md`: the
27-fixture semantic review contains 20 intended coverage-evidence changes and
one intended duplicate-glove removal, with zero unexpected additions,
quantities, traces, constraints, ownership/carrier, or unrelated behavior
changes. The seven-case overlap matrix, explicit-user and ambiguous-party
authority, and repeated-run determinism are executable. The six-step engine
audit, 218 iOS tests across 16 suites, 202-item shared validation, and 106 API
tests are green.

**Phase 5 (activity coverage) has not started.** Camping remains routed there.
The newly observed cold-without-snow glove-generation question and existing
seasonal/weather findings remain routed to Phase 6. Presentation stays frozen,
physical-device verification stays deferred, and M3B/M3C remain blocked.

## Phase 5 closure — 2026-09-04

Phase 5 (activity coverage) is complete. `ActivityContracts` is the one typed
activity authority: every surfaced activity maps to a closed
`Set<ActivityNeed>` (eight cases, count-pinned), needs resolve to candidate
item IDs and — where they overlap Phase 4's model — to `PackingCapability`
values, and needs flow into the same collector the JSON rows use, so
composition and de-duplication are structural. Only Camping and Hiking were
migrated off their `activity-rules.json` rows; the other fifteen are untouched.
No capability was added and no weather signal or threshold changed.

Camping is now a real personal-travel packing signal: portable light, water,
insect repellent, sun protection, and cold-gated sleep warmth. It adds no
campsite logistics, honoring rather than superseding the "Deferred and
excluded" entry below. It also deliberately claims no trail footwear — car
camping, campgrounds, festivals and cabins do not universally require trail
shoes — so Hiking remains the sole claimant of `PackingCapability.hiking` and
`Hiking + Camping` composes into one outdoor trip with one water bottle and one
pair of trail shoes.

Exit evidence is
`docs/engine-audits/2026-09-03-phase-5-activity-contracts.md`: the semantic
review contains three intended activity additions in fixture 18 and five new
hand-reviewed Camping fixtures, with zero unexpected additions, removals,
quantities, traces, coverage, constraints, or ownership/carrier changes.
Emptying hiking's JSON row produced a zero-row diff. The surfaced-input DEAD
bucket is empty for the first time: `activity/camping` is deterministic with
fixture and test evidence, and `tripType/other` earned `contextOnly` through
three explicit checks. The six-step engine audit, 255 iOS tests across 17
suites, 202-item shared validation, and 106 API tests are green.

`shared/rules/party.json` is unchanged. The possible flashlight over-count for
large camping parties is routed to Phase 7 as finding F-5 rather than decided
inside an activity phase.

Phase 6 closed this cold-without-snow routing the same day; see below. The 14
remaining UNTESTED ledger rows (nine context chips, two bag types, three trip
types) are all pre-existing and unowned; they stay reported. Presentation
stays frozen, physical-device verification stays deferred, and M3B/M3C remain
blocked.

## Phase 6 closure — 2026-09-04

Phase 6 (weather needs) is complete. Both `PackingEngine.addWeather` and
`CoverageResolver.CoverageContext` now route through Phase 2's existing
`TripContextSnapshot.weatherQuality` classification (`.missing`/
`.seasonalOnly`/`.partial(coveredDays:tripDays:)`/`.complete`) instead of each
re-deriving its own inline forecast check — a zero-diff refactor confirmed
across all 32 pre-existing golden fixtures (1,165 unchanged rows) before any
behavior change. A partial forecast keeps its exact covered-day signals and
now also gets the same seasonal month/latitude fallback a fully-unforecast
trip already receives for its genuinely uncovered remainder, relying solely
on `addSeasonal`'s pre-existing `collected[id] == nil` guard — no second
overwrite-prevention mechanism was added.

The cold-without-snow glove question Phase 4 first noticed and Phase 5's
closure routed here is decided: `shared/rules/weather.json`'s
`signalAdds.sustainedCold` gains `clothing.gloves`, reusing
`CoverageResolver`'s existing `.coldHands` capability and ski-glove priority
ordering with no new capability, code path, or ID-pair rule.
`snowExposure`'s own row and ski-glove suppression are unaffected;
`coldEvenings` was deliberately rejected as the gate (too mild a signal).
None of the 32 pre-existing golden fixtures gained a glove row from this
change, confirmed by a full `engineOutputMatchesGoldens()` pass, not assumed.

All eight named exit scenarios (hot+rain, cold+rain, wind+mild,
heat+strong-sun, hot-day/cool-night, snow+business, rain+hiking, rain+couple)
have execution evidence, five of them new this phase (three unit tests, two
golden fixtures 35–36). Four golden fixtures were added total (33–36); zero
unexpected changes landed on fixtures 1–32. `WeatherSignal` (11),
`PackingCapability` (12), and `ActivityNeed` (8) are unchanged; no threshold
in `weather.json` moved; `WeatherChangeReconciler`, `TripWeatherRefresh`,
`TripWeatherResolver`, `WeatherRefreshPolicy`, and `MockWeatherService` are
byte-unchanged since the `e958c07` baseline — Phase 11 still owns wiring V2
needs/coverage through the reconciler as its own step.

Exit evidence is
`docs/engine-audits/2026-09-04-phase-6-weather-need-hardening.md`: the four
review guards pinned in the plan's Global Constraints (seasonal fallback
fills only the uncovered remainder; seasonal-remainder items never take on a
precise-forecast reason code; precise and seasonal needs compose through one
pipeline; cached weather is distinct from missing weather) were each
re-confirmed against freshly re-run real generated output during closure, not
only against the tests that assert them. The full six-step engine audit, the
full 268-test/18-suite iOS run, 202-item shared validation, and 106 API tests
are all green.

One structural gap surfaced and is routed, not silently worked around: the
golden fixture format (`GoldenEngineTests.buildContext` /
`MockWeatherService.context`) always tiles a named weather fixture to the
full requested trip length and reports it as a whole-trip forecast, so no
golden fixture can itself demonstrate `.partial` `WeatherQuality` end to end.
Fixture 33 is recorded as a byte-stable pin with a `proves` field that says so
explicitly; the partial-forecast blend itself is proven at the unit level.
Extending the golden schema to express a weather fixture shorter than trip
days is unowned and routed as a follow-up.

## Phase 7 closure — 2026-09-04

Phase 7 (central constraints and user authority) is complete.
`ConstraintResolver` is now the single typed authority for party sharing
membership/quantity (`sharingResolution(for:rules:context:party:)`) and the
explicit-user-authority gate (`hasUserAuthority(_:)`,
`isExplicitlyRemoved(_:ownership:travelerID:overrides:)`), replacing two
independently-computed `sharedByDefault` checks, a free-standing
`sharedQuantity`/`sharedQuantityReason` pair, and four independently-written
`isUserAdded || isUserModified` / removed-override checks — both moves
confirmed zero-diff against the `c9cbb76` baseline (36 fixtures, 1,288
unchanged rows) before any behavior-adjacent test was trusted. Bag/style
conflicts and dependencies were confirmed already centralized (no roadmap
"scattered" framing held there); ownership/carrier stays deliberately split
between `resolve()` and `PartyInvariants`, the same two-closed-authorities
relationship `CoverageResolver` has to `ActivityContracts`.

The priority hierarchy is now provable, not asserted: one composite test
(`explicitUserStateSurvivesASimultaneousMultiDimensionalRefresh`) proves a
manual quantity edit, a Not Needed override, a user-added item, and a
carrier reassignment all survive one regeneration that simultaneously
changes weather, activities, and duration together — three rung-3
dimensions moving at once, not tested one at a time.

Finding F-5 (party flashlight sharing, routed by Phase 5) is decided:
personal-per-traveler, deliberate, no behavior change — a flashlight fails
every property (scarce, communal, physically-shared-for-a-child) that makes
the rest of `sharedByDefault` shared. Six new scenario tests plus a rewritten
decision comment on the existing pinned test close it; every scenario uses
adult travelers or an explicitly-typed school-age child role, never an
infant/toddler age group — F-5 decides sharing only, not traveler/age
eligibility, which stays Phase 10's.

A required amendment (decided during design review, before implementation)
also landed this phase: `SharingPolicy.personalOnly`'s
fallthrough-to-ownerless-shared-draft bug is fixed structurally inside
`sharingResolution` — a `.personalOnly` item now never reaches the
shared-draft path at all — and proven by four tests against a synthetic
test-local policy row. `shared/rules/party.json` gained no new row.

All 13 required test gates map to a named task and a named, currently
passing test. Two new golden fixtures (37 — family-of-4 hiking+camping, F-5
plus party scaling; 38 — couple rain trip, shared umbrella) add full-ledger
evidence; zero unexpected changes landed on fixtures 1–36. No new
`PackingCapability`, `ActivityNeed`, or `WeatherSignal` case; `party.json`,
`PartyInvariants`, and `CatalogItem.companions` are byte-unchanged;
`optionalRuling` gained only additive test coverage.

Exit evidence is
`docs/engine-audits/2026-09-04-phase-7-central-constraints-and-user-authority.md`.
The full six-step engine audit, the full 289-test/18-suite iOS run, 202-item
shared validation, and 106 API tests are all green.

One finding is routed, not fixed, surfaced by golden fixture 37:
`shared/rules/reasons.json`'s `party.shared` template is a static string
with no quantity placeholder (unlike `party.shared_umbrella`, which
pluralizes correctly), so a shared quantity greater than 1 still renders
"One for the group" copy. Pre-existing, not introduced by this phase;
`sharedQuantity`'s arithmetic itself is correct, only the reason copy
under-pluralizes. Editing `reasons.json` copy is outside Task 7's file list
and unowned by any phase yet.

## Phase 8 closure — 2026-09-04

Phase 8 (recommendation trace productization) is complete. PackWise's
existing provenance — `PackingItemDraft`'s
`reasonCode`/`reasonArguments`/`sourceSignals`/`quantityReason`/
`quantityEvidence`, `EngineGeneration`'s
`coverageSuppressions`/`constraintDecisions`, and Phase 7's
`ConstraintResolver.SharingResolution`/`hasUserAuthority`/
`isExplicitlyRemoved` — is now one complete, queryable
`RecommendationTrace` per item, wired into the already-frozen Item Detail
sheet without any layout change. The engine still decides once; this phase
made that decision legible.

Three required architectural amendments (decided during design review,
before implementation) landed as specified: constraint/authority trace
facts are captured once, at generation time, inside
`PackingEngine.resolve`'s one real `ConstraintResolver.optionalRuling` call
site — never re-derived by a second, live call from Item Detail;
`satisfiedCapabilities` is computed inside `CoverageResolver.resolve`'s own
per-item loop as `itemCapabilities ∩ activeNeeds`, not by inverting
`coverageSuppressions` afterward (closing a real gap the inversion design
could never see — a rain jacket satisfies `windShell` even when no
suppression for it exists); and `PackingItemRecord.apply(_:)` — found, on
inspection, to have zero callers anywhere in the app — is fixed and wired
into the real regeneration path (`recommendationDiff`'s baseline made
merge-aware, its per-item comparison widened from quantity-only to the full
causal unit, `TripRepository.applyDiff` and `WeatherChangeReconciler.prune`
both updated), proven by a regression test asserting causal fields refresh
while packed state, manual quantity, Not Needed, and explicit carrier
assignment on other items in the same regeneration are byte-identical.

The routed `party.shared` pluralization finding (Phase 7's closure, above)
is fixed: a shared quantity greater than 1 now reads "N for the group," not
"One for the group," derived from `SharingResolution`'s quantity exactly the
way `party.shared_umbrella` already did. Fixture 37's two shared-item rows
are the one reviewed golden diff this phase produced; every other row in
every other fixture is byte-identical to the `eadc345` baseline.

The exit metric "generic-only generated explanations = 0" is replaced with
"recommendations lacking causal structured provenance = 0" — the roadmap's
original wording conflated generic *prose* with missing *causal structure*;
the refined metric is exactly today's `missing_reason_code ∪ missing_signal`
defect count (0/1438), and the 68-row `trip_type.generic` bucket is reported
separately, informationally, never folded in or forced toward zero.
`scripts/audit_recommendation_traces.py` gained two new structural checks
(invalid seasonal provenance, fabricated user-authority provenance) plus
the `quantityReasonArguments` closed-six-key-vocabulary guard, all three now
`--strict`-enforced in `run_engine_audit.sh`; all three report 0 against the
current goldens.

All 18 required scenarios map to a named test — sixteen citing existing
decision-level evidence, one (party.shared) the production fix itself, one
(Not Needed) explicitly has no Item Detail row to trace by definition.

Exit evidence is
`docs/engine-audits/2026-09-04-phase-8-recommendation-trace-productization.md`,
including nine findings recorded explicitly (two design-doc illustrative
scenarios that didn't hold against real rule data and were substituted with
structurally-equivalent ones; the plan's env-var typo for golden re-recording;
new-file Xcode-project-registration mechanics; a second real caller of the
widened diff predicate found by tracing the chain; a collateral test-bug in
a temporary RED reproduction; a stale-generated-artifact gap from the
reasons.json edit, caught one task later and fixed; a deliberate
`quantityEvidence`-persistence scope inclusion grounded in the design doc's
own stated intent; no live simulator screenshot taken for the one-line
Item Detail UI change; and no on-disk `PackWiseSchemaV3`-era store fixture
to directly exercise the lightweight-migration claim). None required
weakening a test or reverting an amendment. The full six-step engine audit
(now `--strict`), the full 332-test/21-suite iOS run, 202-item shared
validation, and 106 API tests are all green.

**Phase 9 (context intelligence) has not started.** Presentation stays
frozen — now with an explicit, checked contract: Item Detail and
`RecommendationTrace` read persisted trace only, never call
`PackingEngine`/`CoverageResolver`/`ConstraintResolver`/
`WeatherSignalExtractor` directly, for any facet, enforced structurally by
`RecommendationTrace`'s facet function signatures (none accepts
`catalog`/`rules`/`context`/`party`). Physical-device verification stays
deferred, M3B/M3C remain blocked. The `CoverageContext` double-construction
efficiency note and the golden-fixture-schema gap for a true
partial-forecast fixture (both Phase 6) remain unowned follow-ups, noted
but not blocking. The 68-row `trip_type.generic` informational bucket is
unowned by any phase yet — reducing it is recommendation-content
authorship, not trace productization.

## Program order

| Phase | Deliverable | Entry gate | Exit evidence |
| --- | --- | --- | --- |
| 0 | Final UI refinement and UI baseline | Current committed app | UI checklist, simulator captures, full tests/build, simulator-verified baseline commit; physical-device evidence remains deferred |
| 1 | Golden ledger audit and fixture expansion | Simulator-verified presentation baseline committed | Reviewed golden diffs; core 14 plus approved hardening fixtures |
| 2 | Context model hardening | Phase 1 green | `TripContextSnapshot`, explicit laundry semantics, valid/normalized/safe input tests |
| 3 | Clothing needs and quantities | Phase 2 green | ordering, plateau, bounds, and preservation properties |
| 4 | Footwear and outerwear coverage | Phase 3 green | overlap fixtures with trace-backed suppression |
| 5 | Activity coverage | Phase 4 green | every surfaced activity has behavior or an explicit context-only contract |
| 6 | Weather needs | Phase 5 green | precise/partial/seasonal matrices without invented precision — closed 2026-09-04, `docs/engine-audits/2026-09-04-phase-6-weather-need-hardening.md` |
| 7 | Central constraints and user authority | Phase 6 green | bag/style/share/dependency/override tests — closed 2026-09-04, `docs/engine-audits/2026-09-04-phase-7-central-constraints-and-user-authority.md` |
| 8 | Recommendation trace productization | Phase 7 green | every generated item answers inclusion, quantity, and causal-signal questions — closed 2026-09-04, `docs/engine-audits/2026-09-04-phase-8-recommendation-trace-productization.md` |
| 9 | Context intelligence | M3A exit gate green and deterministic engine strong | accepted, traveler-safe structured context only |
| 10 | Family hardening and memory events | Phase 9 green | conservative age behavior and durable event capture |
| 11 | Weather-change V2 integration | Phase 10 green | proposal diffs use V2 coverage without silent mutation |
| 12 | Lifecycle features | Engine V2 product gate green | notifications, Final Check, post-trip review, then Packing Memory |

## Phase 0 boundary

Allowed:

- SwiftUI layout, navigation presentation, design-system primitives, accessibility, debug capture seeds, and presentation-only copy.
- Tests that prove presentation policy or preserve interaction boundaries.
- Documentation and screenshot artifacts used as verification evidence.

Forbidden:

- Packing inclusion, quantities, WeatherKit behavior, recommendation resolution, persistence semantics, API contracts, GPT behavior, or party architecture.
- M3B/M3C wiring.
- New customer-facing promises about note interpretation or learned memory.

## Global product gates

1. Same-duration context: Miami beach and Chicago business are distinguishable without destination labels.
2. Long-trip intelligence: laundry and bag/style materially change quantities; 30 days plateaus.
3. Overlap intelligence: compatible footwear and outerwear cover multiple needs without duplication.
4. Weather intelligence: rain plus outdoor activity yields sufficient, non-duplicative protection.
5. User authority: manual quantities and Not Needed survive unrelated refreshes and edits.
6. Graceful failure: OpenAI, WeatherKit, and network failure leave a usable local list.
7. Explainability: every generated item can state why it is included, why its quantity was chosen, and which signals mattered.

## Deferred and excluded

- Trip segments until multi-city is a product feature; date-scoped needs are sufficient.
- Travel advisories.
- Trip-type multi-select.
- Full camping logistics such as tents, fuel, stoves, and cookware.
- Packing Memory UI until real event history supports it.

## Governance

Phase status uses three states: implemented, simulator-verified, and
device-verified. A build is not visual verification. The 2026-09-03 sequencing
decision permits deterministic Phases 1–8 after the simulator-verified baseline
commit while leaving Phase 0 device verification explicitly deferred. M3B/M3C
remain blocked until the M3A physical-device exit gate is green. Engine work
does not resume while Phase 0 code or screenshot findings remain uncommitted.
