# Phase 4 — Footwear and Outerwear Coverage

**Date:** 2026-09-03
**State:** implemented and simulator-verified; Phase 5 not started
**Branch:** `product-hardening-phase1`
**Phase 3 behavior baseline:** `0b52ae6`
**Approved design/plan:** `ccdb903`, `4a044df`
**Implementation commits:** `f32cf92`, `e3f5568`, `7e28be2`, `211bf63`, `53249b2`

## Result

Phase 4 is closed. `CoverageResolver` remains the single, closed, typed
authority for footwear, outerwear, and hand-protection overlap. It now consumes
only a `CoverageContext` projected from the normalized `TripContextSnapshot`,
records an exact capability-to-covering-item fact for every covered need, and
chooses the same minimal set and evidence independent of candidate input order.

No capability data moved into shared JSON and no canonical-ID pair exception
was added. Existing weather extraction and threshold semantics are unchanged;
Phase 4 only maps already-existing signals to typed needs.

## Context boundary

`CoverageContext` is the only new snapshot consumer. Its projection reads:

- `tripType`, normalized `knownActivityIDs`, and typed `contextChips`;
- the existing trip weather value and normalized `durationDays` to run the
  pre-existing `WeatherSignalExtractor` exactly once;
- `startDate` and destination latitude for the unchanged seasonal fallback;
- normalized `party` for owner grouping.

The projection also preserves the former resolver's forecast-presence and
minimum-temperature decisions as explicit booleans. Rule suggestion,
weather-item generation, constraints, companions, clothing policies,
persistence, and presentation remain on their prior boundaries.

## Typed coverage model

The closed vocabulary has 12 capabilities:

```text
footwear.everyday_walking  footwear.running       footwear.hiking
footwear.beach             footwear.formal        footwear.cold
outerwear.rain_shell       outerwear.wind_shell   outerwear.warmth_light
outerwear.warmth_heavy     hand_protection.cold   hand_protection.snow_sport
```

Phase 4 added exactly `hand_protection.cold` and
`hand_protection.snow_sport`. `activities.ski_gloves` provides both;
`clothing.gloves` provides cold-hand coverage only. A ski/snow trip requires
both, so the higher-priority ski glove satisfies the sport need and the general
cold-hand need without an ID-pair rule. Existing `snowExposure`,
`sustainedCold`, and `freezingCold` signals establish the cold-hand need.

Candidate priority remains explicit and deterministic:

```text
running shoes → hiking shoes → boots → dress shoes → sandals → walking shoes
→ flip-flops → winter coat → rain jacket → light sweater → light jacket
→ windbreaker → ski gloves → ordinary gloves
```

Partially useful candidates remain and claim only missing capabilities.
User-added and user-modified candidates are never suppressed, but may claim
coverage for their unambiguous owner. In a party list, an unassigned explicit
personal item remains unassigned and claims coverage for nobody.

## Exact suppression evidence

Each suppression now separates:

- `covered`: sorted `CapabilityCoverage(capability, coveringItemID)` facts;
- `refutedCapabilities`: sorted capabilities whose need was absent.

Compatibility accessors still serialize the readable `capabilities` and
`coveredBy` arrays. The golden schema adds `coveredCapabilities` and
`refutedCapabilities`; the semantic reporter treats both as coverage evidence
and decodes their absence in the Phase 3 baseline as empty.

The reviewed ledger contains 20 coverage-evidence changes:

| Exact mapping/refutation | Rows | Fixtures |
| --- | ---: | --- |
| everyday walking → running shoes | 9 | 02, 02b, 03, 04, 05, 08, 13, 14, 22 |
| rain/wind shell refuted | 4 | 06, 23, 24 (primary + partner) |
| wind shell → winter coat | 4 | 15, 16 (primary + partner + child) |
| everyday walking → hiking shoes | 1 | 18 |
| light warmth → light sweater | 1 | 19 |
| cold hands → ski gloves | 1 | 21 |

## Required overlap and authority results

The focused matrix passes for running+walking, hiking+walking,
running+hiking+walking, formal business footwear, rain+wind, winter layering,
and ski/cold hand protection. Fixture-level contracts additionally pin:

- fixture 08: runners cover walking shoes;
- fixture 18: hiking shoes cover walking shoes, with no Camping assertion;
- fixture 07: dress shoes and walking shoes both remain;
- fixture 09: rain shell plus one light layer remains non-duplicative;
- fixture 21: ski gloves cover ordinary gloves while coat, light layer, and
  boots remain;
- fixture 26: the explicit existing rain shell remains the sole shell and
  prevents duplication.

Repeated generation of every matrix case produces identical sorted item IDs
and exact suppression facts. Reversing distinct-priority resolver candidates
also produces identical kept IDs and evidence.

Explicit user authority is green. User-added runners and user-modified rain
shells preserve their ID, quantity, packed count, owner, carrier, and flags,
remain unsuppressed, and satisfy coverage for that owner. A primary-owned
runner suppresses only the primary's walking shoes; the partner keeps theirs.
An unassigned party runner suppresses neither traveler and receives no inferred
owner or carrier. The acceptance tests exposed and fixed two narrow authority
defects: user-added canonical quantities no longer pass through engine quantity
policy, and final party normalization no longer guesses an owner for an
ambiguous explicit row.

## Golden review

The semantic comparison against `0b52ae6` covers all 27 fixtures.

**EXPECTED COVERAGE CHANGES:** 20 evidence changes and one intended item
removal. Fixture 21 removes `primary/clothing.gloves` (quantity 1) because
`activities.ski_gloves` covers `hand_protection.cold`; its suppression ledger
names that exact mapping. The other 19 changes add exact mappings/refutations
to suppressions whose inclusion behavior already existed.

**UNEXPECTED BEHAVIOR CHANGES:** none. Across the ledger there are 1,010
unchanged item rows, zero additions, zero quantity changes, zero trace changes,
zero constraint changes, and zero ownership/carrier changes. The only removed
row is the approved duplicate glove. Ten fixtures are otherwise byte-semantic
unchanged; 17 carry expected coverage evidence.

## Verification

| Gate | Fresh result |
| --- | --- |
| Task 5 focused acceptance | 124 tests, 6 suites, 0 failures |
| `scripts/run_engine_audit.sh` | all 6 steps passed; 74 Python audit tests; 78 focused Swift tests; HEAD golden check clean |
| Full `xcodebuild test` on iPhone 17 Pro simulator | 218 tests, 16 suites, 0 failures; `Test-PackWise-2026.09.03_22-44-00--0500.xcresult` |
| `python3 scripts/validate_shared.py` | 202 catalog items; integrity checks passed |
| `npm --prefix api run preflight` | artifact/schema/type checks passed; 106 tests, 0 failures |
| Recommendation-trace audit | 1,010 rows; 1,007 engine-generated; 221/221 quantity-required rows evidenced; 0 defects |
| Semantic diff vs. `0b52ae6` | 20 expected coverage changes, 1 expected removal, 0 unexpected changes |

Mechanical review found no changed shared JSON, clothing or footwear quantity
policy, weather-signal/generation, central constraint, SwiftData, API, GPT,
lifecycle, or presentation file. Exact ordering is encoded in the resolver's
priority list and evidence sorts. Searches found no ski-glove/ordinary-glove
ID-pair special case. The main checkout still contains its unrelated
`ios/PackWise.xcodeproj/project.pbxproj` signing diff; it was not modified or
copied into this worktree.

## Routed findings and deferred gates

- **Phase 6:** existing `sustainedCold` and `freezingCold` signals establish a
  typed cold-hand need, but current weather rules generate ordinary gloves only
  for `snowExposure`. Phase 4 deliberately did not broaden weather item
  generation. Phase 6 should decide and test the intended cold-without-snow
  behavior.
- **Phase 5:** the existing Camping activity finding remains routed and was not
  touched.
- **Phase 8:** exact structured suppression facts are ready for later trace
  productization; Phase 4 added no prose-first UI.
- **F-1 remains P2:** this phase added schema-tolerant coverage fields, but did
  not fix the older missing-`carrier` baseline compatibility gap. It did not
  block review against the current Phase 3 schema.

Presentation remains frozen. Physical-device App Attest and UI/UX verification
remain deferred, not complete. M3B/M3C remain blocked by their existing gate.

## Exit gate

1. Coverage uses normalized snapshot context — **green**.
2. `CoverageResolver` remains the only closed typed authority — **green**.
3. Footwear, outerwear, and hand overlap choose deterministic minimal sets — **green**.
4. Every suppression names exact covering facts or refuted needs — **green**.
5. Explicit and ambiguous user/party authority is preserved — **green**.
6. Golden diffs contain only approved coverage behavior/evidence — **green**.
7. Focused tests, audit, full iOS, shared, and API gates — **green**.
8. No shared-JSON migration, ID-pair exception, or out-of-scope subsystem change — **green**.
9. Phase 4 evidence committed separately; Phase 5 unopened — **green on closure commit**.
