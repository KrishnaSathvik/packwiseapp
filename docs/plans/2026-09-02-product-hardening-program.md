# PackWise Product Hardening Program

**Date:** 2026-09-02  
**Status:** active; Phases 1–3 closed 2026-09-03; Phase 4 not started
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

**Phase 4 (footwear and outerwear coverage) has not started.** Existing
footwear/outerwear findings remain routed there; Camping and weather findings
remain routed to Phases 5 and 6. Presentation stays frozen, physical-device
verification stays deferred, and M3B/M3C remain blocked.

## Program order

| Phase | Deliverable | Entry gate | Exit evidence |
| --- | --- | --- | --- |
| 0 | Final UI refinement and UI baseline | Current committed app | UI checklist, simulator captures, full tests/build, simulator-verified baseline commit; physical-device evidence remains deferred |
| 1 | Golden ledger audit and fixture expansion | Simulator-verified presentation baseline committed | Reviewed golden diffs; core 14 plus approved hardening fixtures |
| 2 | Context model hardening | Phase 1 green | `TripContextSnapshot`, explicit laundry semantics, valid/normalized/safe input tests |
| 3 | Clothing needs and quantities | Phase 2 green | ordering, plateau, bounds, and preservation properties |
| 4 | Footwear and outerwear coverage | Phase 3 green | overlap fixtures with trace-backed suppression |
| 5 | Activity coverage | Phase 4 green | every surfaced activity has behavior or an explicit context-only contract |
| 6 | Weather needs | Phase 5 green | precise/partial/seasonal matrices without invented precision |
| 7 | Central constraints and user authority | Phase 6 green | bag/style/share/dependency/override tests |
| 8 | Recommendation trace productization | Phase 7 green | every generated item answers inclusion, quantity, and causal-signal questions |
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
