# Integrating Product Hardening Phases 1–8 into Product Experience V2

Date: 2026-09-14 · Branch: `product-v2-stage-a` · Merges: `product-hardening-phase1` (`b302634`, 77 commits)

## Why

Both branches forked from `fe7aca0`. The V2 design treats Phase 8's `RecommendationTrace` as existing, and Task 3 needs the Phase 1–8 engine rework (`TripContextSnapshot`, `ActivityContracts`, coverage, constraint, and quantity hardening) plus the engine audit tooling. None of that was on this branch, so the merge had to land before Task 3.

## Resolution

- **Textual conflicts (3):**
  - `project.pbxproj`: took the V2 side and registered the 9 hardening sources with `scripts/add_ios_sources.py`.
  - `api/generated/manifest.json`: regenerated with `build_intelligence_schemas.py`. New build hash `027c646f44fc1430`, schema `2026-09-14`.
  - `docs/device-pass-checklist.md`: merged. V2's gate status now carries Phase 8's device-evidence anchor and the Phase 9 block.
- **Task 15 contract on hardening additions:**
  - 21 new golden fixtures (18–38) now use `tripTypes`/`bagTypes` arrays. Fixtures 18, 28, and 29 used legacy `roadTripLuggage`, which becomes `[]`; the engine treats the two identically (neither is space-constrained, `personalItem`, or `carryOn`).
  - 6 hardening test files now build `TripContext` through the set initializer.
- **Store schema:** Phase 8 adds four defaulted columns to `PackingItemRecord`. Following the schema-history rule (`2026-09-14-store-schema-history-fix.md`), 4.1.0 is frozen as a snapshot generated from `d7663a5`, the live types become `PackWiseSchemaV5` (5.0.0), and a lightweight 4.1.0→5.0.0 stage is added.
- **Pre-existing time bomb:** `WeatherChangeTests.partialForecastDoesNotCoverA30DayTrip` already failed on the hardening tip itself. It read `state()` at wall-clock `now` against a fixture that expired 2026-09-12 01:00, so it is now pinned to the fixture time.
- **Audit ledger:** `surfaced-input-contracts.json` said fixture 18 exercises `roadTripLuggage` and that no fixture exercises `notSure`. Both became false once fixtures 18, 28, and 29 converted to `[]`. `roadTripLuggage` is now `contextOnly` with named tests, and `notSure` cites 18, 28, and 29.

## Semantic result

`report_engine_goldens.py --baseline-ref product-hardening-phase1`: 38 fixtures compared, 38 unchanged, 1441 items unchanged. Adds, removes, and quantity, trace, coverage, and constraint changes are all zero. The 38 golden files are byte-identical to the hardening tip.

## Verification

| Check | Result |
| --- | --- |
| Hardening tip baseline | 332 tests / 21 suites; 1 failure (the time bomb above) |
| Integrated iOS suite | **396 tests / 25 suites, all pass** |
| Real install-over upgrades onto the merged build | V3 store and `main`'s 4.1.0 store each launched twice, 0 crash reports, persisted as 5.0.0 |
| `validate_shared.py` / API tests / preflight | OK / 141 pass / green |
| Engine audit steps 2, 4, 5, 6 | python audit tests CLEAN; golden diff CLEAN; input audit exit 0, Dead 0; trace audit `--strict` CLEAN |

## Follow-ups (not in this merge)

- `recommendationTraceRaw` (Task 2, V4 column) and Phase 8's separate persisted trace-fact columns now both exist. Task 13 has to choose one persisted trace representation.
- Hardening test prose still says "road-trip luggage" for fixtures that now carry `[]`. Their assertions still hold.
