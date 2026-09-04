# Product Hardening Phase 5 — Surfaced Activity Contracts Design

**Date:** 2026-09-03
**Base:** `product-hardening-phase1` at `756f68f`
**State:** approved design; implementation not started

## Objective

Every activity PackWise surfaces has an explicit product contract —
`deterministic` or a legitimate `contextOnly` — and no surfaced activity
remains `missing`. Camping becomes a real personal-travel packing signal.
Camping and Hiking compose into one outdoor trip instead of concatenating two
checklists.

## The current shape, and why it can't hold Camping

Today an activity's entire engine effect is one row in
`shared/rules/activity-rules.json`:

```json
"hiking": ["footwear.hiking_shoes", "activities.daypack",
           "hydration.water_bottle", "health.blister_pads"]
```

`PackingEngine.ruleSuggestions(for:)` looks that row up and adds each ID with
reason code `activity.<id>`. `camping` has no row at all — which is why
`TripContextSnapshot` classifies it in `unknownActivityIDs`, why the Phase 1
ledger records it `missing`, and why `scripts/audit_engine_inputs.py` has to
hardcode `activities.add("camping")` to keep the ledger complete.

Adding `"camping": [ ...eight item IDs... ]` would close the ledger row and be
wrong. Two activities that both imply a water bottle would then be two
independent lists that happen to name the same catalog ID, and the composition
rule would live nowhere. Phase 4 already rejected the analogous shortcut for
gloves (no canonical-ID pair table); Phase 5 rejects it for activities.

## Architecture

Phase 5 inserts one typed layer between a surfaced activity and the existing
pipeline:

```text
surfaced activity id
        ↓  ActivityContracts (typed, closed, Swift)
   Set<ActivityNeed>
        ↓  ActivityNeed → candidate item IDs   /   ActivityNeed → PackingCapability
existing candidate collection → coverage → quantity → constraint pipeline
```

`ActivityContracts` is the single activity authority, the way
`CoverageResolver` is the single coverage authority. It is typed Swift with a
closed vocabulary, not shared JSON, for the same reason Phase 4 kept
`PackingCapability` in Swift: an open vocabulary degenerates into one label per
item and generalizes nothing.

`shared/rules/activity-rules.json` remains the surfaced **vocabulary** (its
keys are what `TripContextSnapshot` splits known from unknown on, what
`validate_shared.py` and `audit_engine_inputs.py` read, and what
`ReasonQualityTests` walks). Phase 5 adds a `camping` key whose `add` array is
empty and empties `hiking`'s. Camping and Hiking are vocabulary rows with no
item list; all of their behavior comes from their typed contract. The other
fifteen activities keep their existing `add` arrays untouched and declare an
empty need set — migrating activities with no overlap would be churn with no
product value and real golden risk.

Needs and JSON adds both flow into the same `collected[canonicalItemID]`
dictionary `addIDs` already maintains, so composition and de-duplication are
structural, not asserted after the fact.

One consequence is mechanical and must be reviewed rather than waved through:
`scripts/build_intelligence_schemas.py` derives the API's closed activity
vocabulary from `activity-rules.json`, so adding the `camping` key regenerates
`api/generated/vocab/activities.json` and the manifest digest. That is a
generated-vocabulary change, not hand-written API behavior — but it is the one
file outside `ios/` and `shared/` Phase 5 touches, and the closure evidence must
name it. Enrichment stays gated off until M3B either way.

## The `ActivityNeed` vocabulary

Closed, eight cases, count pinned by a test the way `PackingCapability`'s is:

| Need | Candidate | Also a coverage need |
| --- | --- | --- |
| `trailFootwear` | `footwear.hiking_shoes` | `PackingCapability.hiking` |
| `dayCarry` | `activities.daypack` | — |
| `hydration` | `hydration.water_bottle` | — |
| `blisterCare` | `health.blister_pads` | — |
| `portableLight` | `miscellaneous.flashlight` | — |
| `insectProtection` | `toiletries.insect_repellent` | — |
| `sunProtection` | `toiletries.sunscreen` | — |
| `overnightWarmth` | `clothing.thermal_top` | — |

A need is admitted only when more than one contract can plausibly want it or
when it must route into the Phase 4 capability model. `overnightWarmth` is the
only weather-gated need; every other need is unconditional for the activities
that declare it.

## Contracts

```text
hiking   → deterministic [trailFootwear, dayCarry, hydration, blisterCare]
camping  → deterministic [trailFootwear, hydration, portableLight,
                          insectProtection, sunProtection, overnightWarmth]
the other 15 surfaced activities
         → deterministic [] with their existing JSON adds unchanged
unknown ids (e.g. cosplayConvention)
         → no contract; preserved verbatim, inert
```

`hiking`'s need set resolves to exactly the four IDs its JSON row holds today,
which is why the row can be emptied under a zero-diff golden gate rather than
left as a second source of truth.

### Camping V1 boundary

Camping may create or strengthen: portable light, suitable outdoor footwear,
water, insect repellent, sun protection, and cold-gated sleep warmth. Camping
must never add tents, sleeping bags, pads, stoves, fuel, cookware, food storage
or campsite furniture. PackWise packs the traveler; the program tracker's
"Deferred and excluded" section already excludes full camping logistics, and
this contract is the code-level expression of that exclusion. A test asserts
the forbidden IDs are absent for every Camping scenario, not merely that the
list looks short.

Camping alone in mild conditions therefore adds five items —
`footwear.hiking_shoes`, `hydration.water_bottle`,
`toiletries.insect_repellent`, `toiletries.sunscreen`,
`miscellaneous.flashlight` — and suppresses `footwear.walking_shoes` through
the existing coverage model. That is a visible, honest effect and not a
wilderness inventory.

## Composition

Composition needs no merge logic: two contracts contribute to one
`Set<ActivityNeed>`, each need resolves to its candidate once, and the
collector is keyed by canonical item ID.

- `Hiking + Camping → {trailFootwear, dayCarry, hydration, blisterCare,
  portableLight, insectProtection, sunProtection, overnightWarmth}` — one
  water bottle, one pair of trail shoes.
- Footwear composes through Phase 4: `trailFootwear` contributes
  `PackingCapability.hiking`, `footwear.hiking_shoes` provides both `.hiking`
  and `.everydayWalking`, and `footwear.walking_shoes` is suppressed with exact
  `CapabilityCoverage` evidence. Camping alone reaches the same result, because
  the capability comes from the need, not from the string `"hiking"`.
- Quantities are unchanged: a shared need yields one row, and only the existing
  party/quantity policy may raise it.

**Reason attribution.** When two activities produce the same item, the reason
follows the activity that appears first in the snapshot's normalized
`knownActivityIDs` — the user's own selection order, which is already what the
current `for activity in context.activities` loop does. `hiking` first reads
"Hiking is on your plans."; `camping` first reads the new `activity.camping`
template. Both are true; neither duplicates a row. This is stated as product
behavior and tested in both orders.

## Weather boundary

An activity may participate in existing weather logic. It may never manufacture
weather.

- Camping contributes **no** rain need. A rain shell on a camping trip comes
  from the existing rain signals exactly as it does on any other trip, and
  `Camping + rain` must produce exactly one shell with no camping-specific rain
  item.
- Camping contributes **no** general warmth need. Warm layers on a camping trip
  come from the existing cold signals.
- `overnightWarmth` resolves only when the projected weather signals already
  contain `snowExposure`, `sustainedCold`, `freezingCold`, or `coldEvenings`.
  With no forecast, or a mild one, it resolves to nothing. Camping never
  assumes cold nights.

The activity family reads the same normalized projection Phase 4 built —
`CoverageContext(snapshot:thresholds:)` — rather than deriving a second set of
signals. The type keeps its name in Phase 5; its documentation widens to say it
is the normalized surface the coverage **and activity** families read. A rename
is cosmetic churn across Phase 4's files and is routed forward if a third
family joins.

## `tripType.other`

`Other` is a legitimate `contextOnly` contract, not a defect.

`shared/rules/trip-types.json` already declares
`"other": {"add": [], "prefer_activities": []}`. The lookup succeeds and
deliberately contributes nothing: `Other` is the identity element of trip type,
meaning "no additional trip-type-specific needs; activities, preferences, and
context carry the meaning." It is still surfaced, stored, round-tripped, styled
(`ellipsis.circle`), offered `["sightseeing", "walking"]` as starting chips, and
carried in weather-change signatures.

That is exactly the audit's `contextOnly` definition, and the distinction from
`missing` is real: `missing` is an oversight, `other` is a declared empty rule.
The relabel is earned, not asserted, by three checks:

1. the rule file must contain the `other` key with an empty `add` — a declared
   identity, not a failed lookup;
2. `other` must be the only trip type with an empty `add`, so `contextOnly`
   cannot spread silently to a trip type that simply lost its rule;
3. an `Other` trip must still produce a complete, coherent list whose contents
   are fully explained by base essentials, activities, weather, and party.

Phase 5 invents no recommendations for `Other`.

## Unknown custom activities

An activity id with no contract stays in `unknownActivityIDs`, keeps its
`unsupportedButSafe` diagnostic, produces no items, no capability, and no
inferred mapping to a known activity. `cosplayConvention` must remain byte-for-
byte identical to the Phase 4 baseline in fixture 25. Unknown activity text does
not become packing meaning before accepted context intelligence exists.

## Party sharing — one explicitly reviewed change

`miscellaneous.flashlight` has no sharing policy, so a four-person camping trip
would generate four flashlights. Phase 5 adds `miscellaneous.flashlight` to
`party.sharedByDefault` with a `singlePerParty` sharing policy. This is a data
row inside the existing mechanism, not a new central shared-party constraint
(which remains Phase 7). No existing fixture has camping in a party, so the
golden diff for this row is zero; it is proved by a focused party test and
recorded as an explicitly reviewed party change.

## Contract ledger and the UNTESTED bucket

`docs/engine-audits/surfaced-input-contracts.json` remains the authority.
Phase 5 flips `activity/camping` from `missing` to `deterministic` and
`tripType/other` from `missing` to `contextOnly`, leaving the DEAD bucket empty.

Eight deterministic activities (`nightlife`, `shopping`, `museums`, `wildlife`,
`snorkeling`, `boatTrip`, `yoga`, `photography`) have real code paths and no
golden fixture. The requirement is "at least one fixture **or** test," so the
record schema gains an optional `testIDs` array and `Report.untested` requires
`fixtureIDs` **or** `testIDs` to be non-empty. To keep that from becoming a way
to type a green audit, the script verifies every named test actually exists as
a `func <name>(` in `ios/PackWiseTests/*.swift` and fails schema validation
otherwise. Fixture spam is not a better answer than a named, verified test.

Context chips remain untested in the ledger. Phase 5 does not own them; they
stay a visible routed finding rather than being papered over.

## Golden boundary

Expected: activity-driven inclusion and removal; activity-related reason and
need evidence; coverage suppressions caused by the new activity needs; the five
new Camping fixtures; fixture 18 improving because Camping now has a general
contract rather than because Reykjavik or 64 days is special-cased.

Reject conditions: clothing quantity policy changes; footwear or outerwear
changes not explained by a new activity need; any weather signal or threshold
change; ownership or carrier changes beyond the reviewed flashlight row; manual
override regressions; persistence, UI, API, or GPT changes.

## User authority

Not Needed stays Not Needed. Manual quantity stays authoritative. User-added
items survive and may satisfy an activity need for their unambiguous owner
without being suppressed. Packed state and explicit owner/carrier survive.
Selecting Camping cannot resurrect an explicitly rejected item.

## Non-goals

- Full campsite logistics: tents, bags, pads, stoves, fuel, cookware, furniture.
- New weather signals, changed thresholds, or seasonal-weather hardening.
- Cold-without-snow ordinary-glove generation — the Phase 4 finding stays
  Phase 6.
- Footwear or clothing quantity redesign.
- Central shared-party constraints (Phase 7).
- GPT/context intelligence, UI, persistence, notifications, lifecycle.
- Migrating the fifteen non-overlapping activities off their JSON adds.

## Verification

Focused activity-contract tests; the surfaced-input contract audit with the new
`testIDs` verification; a semantic golden diff against `756f68f`; the Phase 4
coverage suite unchanged; authority and override tests;
`scripts/run_engine_audit.sh`; the full iOS suite;
`python3 scripts/validate_shared.py` (shared data does change);
`npm --prefix api run preflight` (the generated intelligence vocabulary gains
`camping`).
