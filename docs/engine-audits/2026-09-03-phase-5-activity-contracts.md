# Phase 5 — Surfaced Activity Contracts

**Date:** 2026-09-04
**State:** implemented and simulator-verified; Phase 6 not started
**Branch:** `product-hardening-phase1`
**Phase 4 behavior baseline:** `756f68f`
**Approved design/plan:** `9dc5d7a`, amended `9b7bde8`
**Implementation commits:** `d4df439`, `ebd63b4`, `c6f0a44`, `8b0119b`, `20a65b3`, `6e43b89`

## Result

Phase 5 is closed. `ActivityContracts` is the single typed authority mapping a
surfaced activity to a closed `Set<ActivityNeed>`; needs resolve to candidate
item IDs and, where they overlap Phase 4's model, to `PackingCapability`
values. Needs and the surviving JSON `add` rows flow into the same
`collected[canonicalItemID]` dictionary, so composition and de-duplication are
structural rather than asserted after the fact.

No surfaced input remains `missing`. Camping is a real personal-travel packing
signal. Camping and Hiking compose into one outdoor trip rather than two
concatenated checklists. No capability was added to `PackingCapability`
(still 12), no weather signal or threshold changed, and `shared/rules/party.json`
is byte-identical to the baseline.

## The `ActivityNeed` vocabulary

Closed at eight cases, pinned by a count test the way `PackingCapability`'s is.

| Need | Candidate | Also a coverage need | Declared by |
| --- | --- | --- | --- |
| `trailFootwear` | `footwear.hiking_shoes` | `PackingCapability.hiking` | hiking |
| `dayCarry` | `activities.daypack` | — | hiking |
| `hydration` | `hydration.water_bottle` | — | hiking, camping |
| `blisterCare` | `health.blister_pads` | — | hiking |
| `portableLight` | `miscellaneous.flashlight` | — | camping |
| `insectProtection` | `toiletries.insect_repellent` | — | camping |
| `sunProtection` | `toiletries.sunscreen` | — | camping |
| `overnightWarmth` | `clothing.thermal_top` | — | camping |

Contracts: `hiking → deterministic [trailFootwear, dayCarry, hydration,
blisterCare]`; `camping → deterministic [hydration, portableLight,
insectProtection, sunProtection, overnightWarmth]`; the other fifteen surfaced
activities `→ deterministic []` with their existing JSON adds untouched;
unknown ids get no contract at all.

Only Camping and Hiking were migrated. Their `activity-rules.json` rows are now
empty and the file remains the surfaced vocabulary. Hiking's row was emptied
under a zero-diff golden gate: the ledger did not move by a single row.

## Camping V1 boundary

Camping may create or strengthen portable light, water, insect repellent, sun
protection, and cold-gated sleep warmth.

Camping must never add tents, sleeping bags, pads, stoves, fuel, cookware, food
storage, or campsite furniture — asserted as an explicit forbidden-ID set, not
as "the list looks short". PackWise packs the traveler; the program tracker's
"Deferred and excluded" full-camping-logistics entry is honored, not superseded.

**Camping does not claim trail footwear.** This is the one deliberate change
from the originally-drafted plan. Car camping, campground stays, festival
camping, and cabin stays are all camping, and none of them universally require
trail shoes or justify suppressing the walking shoes a normal traveler already
packs. Hiking keeps `.trailFootwear` and remains the sole strong signal that
claims `PackingCapability.hiking`. The general rule — trail footwear implies
the hiking capability — is unchanged and is gated behind no destination-,
fixture-, or duration-specific exception.

## Composition and reason attribution

Composition needs no merge logic: two contracts contribute to one
`Set<ActivityNeed>`, each need resolves to its candidate once, and the
collector is keyed by canonical item ID.

When two activities want the same item, the reason follows the activity that
appears first in the snapshot's normalized `knownActivityIDs` — the user's own
selection order. Tested in both orders: `["hiking","camping"]` gives the water
bottle `activity.hiking`, `["camping","hiking"]` gives it `activity.camping`,
and both produce exactly one row.

## Exact item sets for the required scenarios

**Camping only, mild — fixture 28** (Yellowstone, no forecast, 2027-08-15,
4 days, `outdoor`, road-trip luggage, balanced). 28 items. Camping owns four
rows:

| Item | qty | reason code | signals |
| --- | --- | --- | --- |
| `hydration.water_bottle` | 1 | `activity.camping` | activity, tripType |
| `miscellaneous.flashlight` | 1 | `activity.camping` | activity |
| `toiletries.insect_repellent` | 1 | `activity.camping` | activity, tripType |
| `toiletries.sunscreen` | 1 | `activity.camping` | activity |

`footwear.walking_shoes` is present, `footwear.hiking_shoes` is absent, and
there is **no coverage suppression at all**. No rain jacket, no thermal top, no
campsite logistics.

Only the flashlight is a *new* row against the same trip without Camping: the
`outdoor` trip type already supplies water and repellent, and Yellowstone at
44.4° N in August takes the seasonal-sun path which already supplies sunscreen.
That is the structural de-duplication working, and Camping's visible effect on
the other three is the reason they carry. On a trip that supplies none of them
— an August Seattle road trip, above the seasonal-sun cutoff — the same
contract contributes all four as new rows. One general contract, different
honest results per trip; no fixture is tuned to make the number look bigger.

**Hiking + Camping — fixture 29** (identical to 28 plus `hiking`). Also 28
items. The difference is exactly Hiking's contribution:

| Item | qty | reason code |
| --- | --- | --- |
| `footwear.hiking_shoes` | 1 | `substitution.hiking_covers_walking` |
| `activities.daypack` | 1 | `activity.hiking` |
| `health.blister_pads` | 1 | `activity.hiking` |
| `hydration.water_bottle` | 1 | `activity.hiking` |
| `miscellaneous.flashlight` | 1 | `activity.camping` |
| `toiletries.insect_repellent` | 1 | `activity.camping` |
| `toiletries.sunscreen` | 1 | `activity.camping` |

`footwear.walking_shoes` is suppressed with exact evidence —
`everydayWalking` covered by `footwear.hiking_shoes` — and there is exactly one
water bottle for the need both contracts declare. Footwear is identical with
and without Camping on the same trip, so the need is sourced once by Hiking and
never double-sourced.

## Weather boundary

An activity may participate in existing weather logic and may never manufacture
weather. Camping contributes no rain need and no general warmth need.
`overnightWarmth` is the only weather-gated need and resolves only when the
projection already contains `snowExposure`, `sustainedCold`, `freezingCold`, or
`coldEvenings`.

| Trip | thermal top | why |
| --- | --- | --- |
| Fixture 28, mild, no forecast | absent | no cold signal exists |
| Fixture 31, Phoenix hot | absent | no cold signal exists |
| Fixture 30, Seattle October rain | present, `activity.camping` | `coldEvenings` already in the forecast |
| Fixture 32, Denver cold | present (qty 2), `activity.camping` | cold signals already present; the existing warm-layer quantity path rotates it |
| Minneapolis deep winter (unit test) | present, `weather.*` | weather emits it itself and its higher-tier reason outranks the activity's |

`clothing.thermal_top` appears only in the `freezingCold` `signalAdds` row, so
on a cold-but-not-freezing trip weather never emits it and Camping legitimately
owns the reason. The drafted plan asserted a weather reason in that case; the
data says otherwise, and the test now pins all three cases rather than the one
that happened to be assumed.

Fixture 30 also confirms the rain boundary directly: exactly one
`clothing.rain_jacket`, from the existing rain signals, with no
camping-specific rain item. Fixture 31 confirms sun: one `toiletries.sunscreen`
row carrying `weather.hot`, the higher-tier reason winning over
`activity.camping`.

## `tripType.other`

Relabelled `missing` → `contextOnly`, earned by three checks rather than
asserted:

1. `shared/rules/trip-types.json` declares `other` with an explicit empty
   `add` — a declared identity, not a failed lookup;
2. `other` is the **only** trip type with an empty `add`, so the label cannot
   spread silently to a trip type that merely lost its rule;
3. an `Other` trip still produces a complete list (>10 rows) whose every row is
   explained by base essentials, activities, weather, or party, and no row
   carries `trip_type.generic`.

Phase 5 invented no recommendations for `Other`.

## Unknown custom activities

An id with no contract stays in `unknownActivityIDs`, keeps its
`unsupportedButSafe` diagnostic, and produces no items, no capability, and no
inferred mapping. `cosplayConvention` is byte-for-byte identical to the Phase 4
baseline in fixture 25, and a unit test proves the full item list is unchanged
by appending it.

## Party sharing — unchanged

`shared/rules/party.json` is **not modified by Phase 5**;
`git diff 756f68f..HEAD -- shared/rules/party.json` is empty.
`miscellaneous.flashlight` remains absent from `sharedByDefault` with no
sharing policy, so it is a personal-carry item: one per traveler. No `headlamp`
canonical item was created and no party constraint logic was written.

The drafted plan proposed adding a `singlePerParty` policy so a family of four
would get one flashlight. That was removed on review: a personal light is a
legitimate personal-carry item, and one-per-family is a party-sharing policy
judgement — exactly the class of decision Phase 7 exists to centralize. The
current behavior is pinned by a focused test so the Phase 7 baseline is
explicit and cannot drift unnoticed. See routed finding F-5.

## Contract ledger and the audit

`activity/camping` → `deterministic` with six fixtures and three named tests.
`activity/hiking` keeps its contract with three fixtures and three named tests.
`tripType/other` → `contextOnly` with two named tests. The DEAD bucket is empty.

The record schema gains an optional `testIDs` array so the real requirement —
at least one fixture **or** test — can be met by a named test rather than
fixture spam. Every entry is file-qualified `<SwiftFile>::<testFunctionName>`
and is verified against **that specific file**: an unqualified entry is a
schema error, a function that exists only in another suite does not satisfy the
reference, and a missing file is an error. `check_test_references` runs from
`main` alongside `check_completeness`, so a fabricated or relocated reference
fails validation (exit 1) rather than quietly greening the report. Five
negative-control Python tests cover exactly those abuse paths.

`discover_expected_ids` no longer hardcodes `activities.add("camping")` —
camping is a real `activity-rules.json` key now.

| Bucket | Baseline `756f68f` | Phase 5 |
| --- | --- | --- |
| DEAD | 2 (`activity/camping`, `tripType/other`) | **0** |
| CONTEXT-ONLY | 0 | 1 (`tripType/other`) |
| UNTESTED | 23 | 14 |

UNTESTED fell by nine: the eight previously-untested activities gained named
verified tests, and `tripType/outdoor` gained fixture evidence because the five
Camping fixtures are the first to select it. The remaining 14 rows — nine
context chips, two bag types, three trip types — are entirely pre-existing and
outside Phase 5's scope. They stay visible as a routed finding rather than
being silenced. The drafted plan predicted "only the nine context chips" would
remain; that was an understatement, corrected here.

## Golden review

Every changed and new fixture was read by hand against the Camping V1 boundary
before being accepted.

**Expected activity changes**

- Fixture 18 (`roadTrip` + hiking + camping, Reykjavik, 64 days): three
  additions — `miscellaneous.flashlight`, `toiletries.insect_repellent`,
  `toiletries.sunscreen`, all `activity.camping`, all activity-signalled. Its
  water bottle stays at one row (Hiking's), no thermal top (August, no cold
  signal), and its trail footwear is unchanged from the Phase 4 baseline and
  attributed to Hiking. The long trip improves because Camping has a general
  contract, not because Reykjavik or 64 days is special-cased.
- Five new fixtures: 28, 29, 30, 31, 32.

**Unexpected behavior changes: none.**

| Category | Count |
| --- | --- |
| Fixtures compared | 27 (26 unchanged, 1 changed) |
| Additions | 3 |
| Removals | 0 |
| Quantity changes | 0 |
| Trace changes | 0 |
| Coverage changes | 0 |
| Constraint changes | 0 |
| New fixtures | 5 |

No existing fixture's footwear, outerwear, clothing quantity, weather signal,
constraint, ownership, or carrier moved. Emptying hiking's JSON row produced a
zero-row diff, which is the gate that proves the typed contract reproduces the
data it replaced.

## Verification

| Gate | Fresh result |
| --- | --- |
| Focused activity contract suite | `ActivityContractTests` 33 tests, 0 failures |
| `scripts/run_engine_audit.sh` | all 6 steps passed; 83 Python audit tests; 77 focused Swift tests; HEAD golden check clean |
| Full `xcodebuild test` on iPhone 17 Pro simulator | 255 tests, 17 suites, 0 failures; `Test-PackWise-2026.09.04_00-10-28--0500.xcresult` |
| `python3 scripts/validate_shared.py` | 202 catalog items; integrity checks passed |
| `npm --prefix api run preflight` | artifact/schema/type checks passed; 106 tests, 0 failures; exit 0 |
| Surfaced-input contract audit | 49 rows; DEAD 0; CONTEXT-ONLY 1; UNTESTED 14 |
| Recommendation-trace audit | 1,165 rows; 1,162 engine-generated; 250/250 quantity-required rows evidenced; 0 defects; CLEAN |
| Semantic diff vs. `756f68f` | 3 expected activity additions in 1 fixture, 5 new reviewed fixtures, 0 unexpected changes |

Coverage and authority gates specifically: the Phase 4 overlap matrix passes
unchanged and gained two rows (`camping + walking` keeps ordinary walking shoes
and suppresses nothing; `hiking + camping + walking` is identical to
`hiking + walking`). Not Needed stays Not Needed (fixture 13), manual quantity
stays authoritative (fixture 14), user-added items and packed state survive
(fixtures 26, 27), explicit owner/carrier survive (fixtures 11, 12, 16, 24),
and a user-added multifunction bottle satisfies Camping's hydration need
without duplication.

Mechanical scope review confirmed: `PackingCapability` still has 12 cases;
`shared/rules/party.json`, `weather.json`, `trip-types.json`,
`substitutions.json`, and `shared/catalog/` are all unchanged; `.trailFootwear`
is declared by exactly one contract; no file outside
`ios/PackWise/Domain/Packing/` changed in the app target; the only `api/` change
is regenerated vocabulary/manifest output; no `headlamp` id exists anywhere; and
the only `project.pbxproj` change is the two new source-file registrations. The
main checkout still contains its unrelated `project.pbxproj` signing diff; it
was not modified or copied into this worktree.

## Generated API vocabulary

`scripts/build_intelligence_schemas.py` derives the API's closed activity
vocabulary from `activity-rules.json`, so adding the `camping` key regenerated
`api/generated/vocab/activities.json` (gains `camping`),
`api/generated/vocab/reason-codes.json` (gains `activity.camping`), the two
schema files that embed those enums, and the manifest digest
(`e9a8c2c9b5c97d73` → `9469340a256a58c8`). That is generated output, not
hand-written API behavior; no hand-written API file changed and the API test
suite is unchanged and green. Enrichment stays gated off until M3B.

## Routed findings and deferred gates

- **F-5 → Phase 7 (new):** a party camping trip generates one
  `miscellaneous.flashlight` per traveler. Whether a party should share one is
  a sharing-policy question about personal-carry items, not an activity-contract
  question, and it belongs with the central shared-party constraint work
  alongside the rest of `sharedByDefault`/`sharingPolicies`. Phase 5 changed
  nothing and pinned the current behavior with a test.
- **Phase 6 (still routed, untouched):** existing `sustainedCold` and
  `freezingCold` signals establish a typed cold-hand need, but current weather
  rules generate ordinary gloves only for `snowExposure`. Phase 5 did not
  broaden weather item generation. Phase 6 should decide and test the intended
  cold-without-snow behavior.
- **Context chips and the UNTESTED tail:** 14 rows (nine context chips, two bag
  types, three trip types) remain deterministic with no fixture or test. All
  pre-existing; no phase owns them yet. Reported, not silenced.
- **F-1 remains P2:** it did not block a current-schema comparison against
  `756f68f`.
- **Phase 8:** the activity-need attribution now recorded on every row is ready
  for later trace productization; Phase 5 added no prose-first UI.

Presentation remains frozen. Physical-device App Attest and UI/UX verification
remain deferred, not complete. M3B/M3C remain blocked by their existing gate.

## Deviations from the approved plan

Three, all recorded rather than silently improvised:

1. **Camping no longer declares `.trailFootwear`** (review amendment). Camping
   alone leaves footwear to the baseline; Hiking remains the sole claimant.
2. **The `party.json` flashlight sharing row was dropped** (review amendment)
   and routed to Phase 7 as F-5.
3. **Two drafted assertions were corrected against the data**: Camping's
   observable delta on the `outdoor`/Yellowstone fixture is one new row, not
   five, because the trip type and the seasonal-sun path already supply three
   of its four candidates; and `clothing.thermal_top` carries `activity.camping`
   rather than a weather reason on a cold-but-not-freezing trip, because weather
   emits that item only under `freezingCold`. Both are the design working
   correctly; only the drafted expectations were wrong.

`testIDs` entries are file-qualified per the review refinement.

## Exit gate

1. Every surfaced activity has an explicit typed contract — **green**.
2. `ActivityContracts` is the only activity authority; no second mechanism — **green**.
3. `ActivityNeed` closed at eight, pinned by a count test — **green**.
4. Camping is a real packing signal within its V1 boundary, with no campsite logistics and no trail-footwear claim — **green**.
5. Hiking and Camping compose into one trip; shared needs yield one row — **green**.
6. Hiking's JSON migration produced a zero-row golden diff — **green**.
7. Activities never manufacture weather; `overnightWarmth` gated on existing cold — **green**.
8. `tripType.other` earned `contextOnly` through three checks; DEAD bucket empty — **green**.
9. Unknown activities remain inert — **green**.
10. User authority preserved across Not Needed, manual quantity, user-added, packed, owner/carrier — **green**.
11. Golden diffs contain only approved activity behavior — **green**.
12. Focused tests, audit, full iOS, shared, and API gates — **green**.
13. `party.json` unchanged; no out-of-scope subsystem change — **green**.
14. Phase 5 evidence committed separately; Phase 6 unopened — **green on closure commit**.
