# PackWise Product Hardening Program

**Date:** 2026-09-02  
**Status:** active; Phase 1 is authorized after the simulator-verified presentation baseline commit  
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
