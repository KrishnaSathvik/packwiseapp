# Phase 3 — Clothing Needs and Quantity Hardening

**Date:** 2026-09-03  
**State:** implemented and simulator-verified; Phase 4 not started  
**Baseline:** `a73f4cf` (`product-hardening-phase1`)  
**Implementation commits:** `acf06d2`, `12cbead`, `d5b3111`, `fcde810`

## Result

Phase 3 is closed. Clothing quantity resolution now consumes a narrow
`ClothingQuantityContext` projected from the single normalized
`TripContextSnapshot` compiled by `PackingEngine.generateDetailed`. No other
recommendation family was migrated. Clothing policies now return a quantity,
a rendered reason, and structured `ClothingQuantityEvidence`; the evidence is
domain/test data only and was not added to SwiftData or presentation.

The snapshot fields consumed are `durationDays`, `packingStyle`, `bagType`,
`laundryPlan`, `knownActivityIDs`, `knownDatedActivityUses`, and normalized
`party`. Dated activity uses are normalized to known vocabulary, distinct
in-trip calendar dates; nil, duplicate-date, out-of-trip, and unknown activity
occurrences do not manufacture uses or attribution.

## Quantity policies

| Family | Basis and bounds | Declared sensitivity |
| --- | --- | --- |
| Tops | Daily wear; 2 minimum; 7-day planned wash cycle; style maxima 8/12/15; personal-item cap 5, constrained-bag cap 8; appearance garments offset uncovered uses once | laundry, style, bag |
| Underwear / socks | Daily use; 2 minimum; 7-day planned wash cycle; style maxima 10/12/15; personal-item cap 7, constrained-bag cap 10 | laundry, style, bag |
| Bottoms / hot bottoms | High reuse (3/2.5/2 wears); 1 minimum; 10-day planned wash cycle; maxima 5/6/8; personal-item cap 3, constrained-bag cap 5 | laundry, style, bag |
| Sleepwear | Repeat-wear rotation, 1–2; never daily scaling | style |
| Workout top / bottom | Explicit dated running/yoga uses when present; otherwise a bounded selected-activity estimate; maxima 4/5/6 | laundry, style, bag |
| Swimwear | Swim/beach/snorkeling/boat use; one suit for one use, two for drying rotation; maximum 2 | none |

Age buffers are applied only through the existing, explicitly resolved
traveler and the existing `party.json` multiplier. The diapered-toddler
underwear exception remains an explicit three-pair backup with evidence; no
new age inference was introduced.

Evidence records the policy ID, use basis and count, wears per item, wash
interval and laundry plan/reduction, style buffer, bag cap and whether it
bound, appearance offset, supported age multiplier, and final quantity.

## Invariants and required fixtures

The policy matrix covers days 1, 3, 5, 8, 10, 15, 21, 30, and 64. It proves
the requested five-point constraint chain never decreases, each declared
influence diverges somewhere, undeclared fixed/singleton behavior is not
forced upward, family floors/maxima hold, and planned laundry is never heavier
than possible laundry, which is never heavier than no laundry.

Representative reviewed fixture quantities:

| Fixture | Clothing result |
| --- | --- |
| Tokyo 15d, planned | pants 4, sleepwear 1, socks 7, tops 5, underwear 7, workout set 3 |
| Tokyo 15d, possible | pants 5, sleepwear 1, socks 8, tops 6, underwear 8, workout set 4 |
| Tokyo 15d, none | pants 5, sleepwear 1, socks 10, tops 8, underwear 10, workout set 4 |
| Tokyo 30d, planned | exactly the Tokyo 15d planned rotation for every policy above |
| Reykjavik 64d, planned | pants 4, sleepwear 2, socks 8, tops 7, underwear 8; no linear scaling |
| Chicago 1d | pants 1, sleepwear 1, socks/tops/underwear 2 |
| Miami beach/light/possible | swimsuit 2 for drying rotation; pants 2, tops 4 |
| Chicago business/prepared/none | dress shirts 2 + nice outfit 1 cover appearance uses once; tops fall 5 → 4 |
| Chicago business + running | workout top/bottom 2; no formal quantity inflation |
| Family/toddler 7d | explicit child tops 13 under the existing 1.75 multiplier; diapered underwear 3 |
| Manual quantity fixture | user-modified tops remain 3 and carry no manufactured engine evidence |

The existing ledger calls the extreme 64-day case Reykjavik; it is the
program's documented Anchorage-equivalent long-duration/latitude fixture.

## Golden review

Semantic comparison against `a73f4cf` covered 27 fixtures and 1,011 rows.

**EXPECTED CLOTHING QUANTITY CHANGES:** 3

- Miami swimsuit: 1 → 2 (drying rotation).
- Cancún swimsuit: 1 → 2 (drying rotation).
- Chicago business t-shirt: 5 → 4 (two dress shirts plus one nice outfit
  satisfy three appearance uses without duplicate signal inflation).

There are 189 trace changes, all confined to clothing `quantityReason` and/or
`quantityEvidence`. The current-schema semantic reporter now explicitly
classifies `quantityEvidence` as trace data and has a regression test for an
evidence-only change.

**UNEXPECTED BEHAVIOR CHANGES:** none. The diff contains zero item additions,
removals, coverage changes, constraint changes, ownership/carrier changes, or
non-clothing quantity changes. Footwear, weather inclusion, shared behavior,
and unrelated reason codes are unchanged.

## User authority

Focused and full-ledger tests prove manual quantity and packed quantity survive
an unrelated refresh, Not Needed remains rejected, user-added canonical and
custom items survive, and owner/carrier assignments remain stable. A
user-modified row exits before clothing policy evaluation, so Engine V2 does
not attach evidence that falsely claims it chose the user's number.

## Verification

| Command | Fresh result |
| --- | --- |
| `scripts/run_engine_audit.sh` | all 6 steps passed; 73 Python audit tests; 78 focused Swift tests; golden check clean at HEAD |
| `python3 scripts/validate_shared.py` | 202 catalog items; integrity checks passed |
| Full `xcodebuild test` on iPhone 17 Pro simulator | 205 tests, 16 suites, 0 failures |
| `npm --prefix api run preflight` | artifact/schema/type checks passed; 106 tests, 0 failures |
| Recommendation-trace audit | 1,011 rows; 1,008 engine-generated; 221/221 quantity-required rows have evidence; 0 defects |
| Semantic diff vs. `a73f4cf` | 3 expected clothing quantity changes, 189 clothing trace changes, 0 unexpected changes |

Mechanical scope review found no changed presentation, SwiftData, API,
footwear/outerwear resolver, weather-generation, shared-constraint, GPT, or
lifecycle file. The main checkout's unrelated
`ios/PackWise.xcodeproj/project.pbxproj` signing change remains present and was
not copied into this worktree.

## Routed findings and deferred gates

No new Phase 4–6 product defect was discovered. Existing Phase 1 findings stay
routed unchanged: footwear/outerwear coverage to Phase 4, Camping activity
coverage to Phase 5, and seasonal/weather behavior to Phase 6. F-1 remains P2:
the legacy-schema `carrier` compatibility gap did not block the current-schema
Phase 3 comparison and was not fixed. Quantity evidence is structured for
future Phase 8 productization; no prose-first UI was added.

Presentation remains frozen. Physical-device App Attest and UI/UX verification
remain deferred, not complete. M3B/M3C remain blocked by their existing gate.

## Exit gate

1. Clothing uses normalized snapshot context — **green**.
2. Planned / possible / no-laundry behavior diverges where declared — **green**.
3. 30-day planned-laundry quantities plateau — **green** (Tokyo 30d equals 15d).
4. Short-trip floors prevent under-packing — **green**.
5. Long trips avoid linear scaling under laundry/reuse — **green**.
6. Miami and Chicago remain distinct — **green**.
7. Manual quantities and overrides remain untouched — **green**.
8. Golden diffs contain only intended clothing quantity/evidence changes — **green**.
9. Focused tests, engine audit, full iOS, shared validation, and API preflight — **green**.
10. Phase 3 evidence committed separately; Phase 4 unopened — **green on closure commit**.
