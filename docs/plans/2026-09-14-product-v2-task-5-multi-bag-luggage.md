# Product Experience V2, Task 5 — multi-bag luggage capacity

Date: 2026-09-14 · Branch: `product-v2-stage-a` · Semantic baseline: `45d0b2c` (Task 4.1 closure)

## Commits

| Commit | Scope |
| --- | --- |
| `45d0b2c` | Task 4.1: normalized `PackingNeed`s are the one trip-type authority for coverage ([Task 4 record](2026-09-14-product-v2-task-4-trip-type-composition.md#task-41-closure--normalized-needs-are-the-one-trip-type-authority)) |
| `fe0895e` | `LuggageContext`; constraints, clothing caps, and the snapshot consume it; singular bag authority deleted; fixtures 49–52 |
| `42ea686` | Constraint evidence records the normalized luggage decision; golden ledger and semantic report compare it |
| docs | This record, the structural luggage-authority guard, plan checkboxes |

## The luggage authority

`LuggageContext.resolve(Set<BagType>)` in `Domain/Packing/LuggageContext.swift` is the only code that asks which bags were selected. Legacy `notSure` and `roadTripLuggage` are dropped from the set before resolution.

| Selected bags | Capacity | Constraint applies |
| --- | --- | --- |
| none | `unspecified` | no |
| personal item | `veryConstrained` | yes |
| backpack | `compact` | yes |
| personal item + backpack | `compact` | yes |
| carry-on | `carryOnConstrained` | yes |
| personal item + carry-on | `carryOnConstrained` | yes |
| carry-on + backpack | `moderate` | yes |
| personal item + carry-on + backpack | `moderate` | yes |
| any set containing checked (all 8) | `checkedAvailable` | no |

`LuggageContextTests.everyBagSubsetResolvesToItsApprovedCapacity` lists all 16 subsets explicitly.

### What each capacity drives

These are the existing single-bag policies, now keyed by capacity instead of by one bag.

| Capacity | Optional-item trim (`ConstraintResolver.optionalRuling`) | Clothing cap (`ClothingQuantityEngine`) | Restriction-review skip |
| --- | --- | --- | --- |
| `unspecified`, `checkedAvailable` | none | none | no |
| `veryConstrained` | every style (`bag.personal_item`; Prepared records `style.prepared_vs_personal_item`) | `personalItemMaximum` | yes |
| `compact`, `carryOnConstrained`, `moderate` | Light only (`bag.space_constrained`) | `constrainedBagMaximum` | yes |

- Packing style is a separate input. `LuggageContext` does not read it, and Light keeps reducing quantities through its own style policy even with a checked bag.
- More bags never means more clothes: caps depend on capacity only, and no bag-count multiplier exists.
- Transportation stays separate: `.flight` is read exactly as before.

## Singular bag authority removed

| Removed | Replacement |
| --- | --- |
| `TripContext.bagType` (fail-safe accessor) | `TripContext.luggage` |
| `BagType.appliesBagConstraint`, `BagType.isSpaceConstrained` | `LuggageContext.appliesCapacityConstraint`, `Capacity` |
| `TripContextSnapshot.bagType`, `.appliesBagConstraint` | `.bagTypes`, `.luggage` |
| `ConstraintResolver.optionalRuling(bag:)` | `optionalRuling(luggage:)` |
| `ClothingQuantityContext.bag`, `ClothingQuantityEngine.compute(bag:)` | `.luggage` |
| `PackingEngine`: two restriction-review checks, trim ruling, security-bottle condition | `context.luggage` / `snapshot.luggage` |

Recommendation/context signatures already used the stable bag set (Task 15). `LuggageContextTests.engineDecisionFilesNeverInterpretBagsDirectly` fails if an engine decision file queries `bagTypes`, reads a `.bagType`, names a primary or preferred bag, or names a bag case. It matches the pre-Task-5 `PackingEngine.swift`.

### Remaining singular bag readers (all non-engine)

| Reader | Why it may remain | Owner |
| --- | --- | --- |
| `TripSetupView` `draft.bagType` single-select, summary chip, and `createTrip`/`apply`/`attach` singular params | setup UI still selects one bag | Task 8 |
| `TripRecord.bagType`, `TripDraft.fresh` from `preferences.preferredBag`, `setSingleSelectPreferredBag` | Me single-select, synced to V4 by Task 15.1 | Task 8 |
| `TripRepository.applyBagTypes` throws `multipleBagsNotYetSupported` for more than one bag | no shipped screen can save a multi-bag trip yet | Task 8 |
| `PackingMemoryEventRecord.bagRaw` compat scalar (first stable bag) | older diagnostics read it; never read back as authority | none (compat) |
| `DebugPreviewScene` singular bag arguments | Debug preview data | Task 8 |

## Approved decisions (2026-09-14)

1. **`moderate` intentionally shares the constrained-bag policy.** Carry-on + Backpack is classified `moderate`, distinct for trace and for future per-bag/airline policy. For Product V2 it shares the optional-trim and clothing-cap policy of `carryOnConstrained` and `compact`, because no principled rule says what an extra backpack adds. Pinned as deliberate by `LuggageContextTests.moderateIntentionallySharesTheConstrainedBagPolicy` and `MultiBagEngineTests.backpackPlusCarryOnIsModerateCapacity`.
2. **The empty security bottle follows the cabin-accessible-bag signal, not capacity.** `LuggageContext.hasCabinAccessibleBag` is true when a personal item or carry-on is selected, whatever else is selected. Carry-on only, Carry-on + Checked, and Personal item + Checked get the bottle; Checked only does not. A checked bag never erases the cabin-bag signal. No transport model was introduced; Task 13 owns the item's naming and reason. Pinned by `LuggageContextTests.cabinAccessibleBagIsNotACapacityFact` and `MultiBagEngineTests.securityBottleFollowsTheCabinBagSignalNotCapacity`.
3. **Trimming before coverage, the dead `multi_tool` restriction rule, and the golden-record filter** are recorded as V2-N1, V2-N2, and V2-N3 in `docs/engine-audits/2026-09-03-engine-findings.md`. None is scheduled.

## Multi-bag fixtures — manual review

Each fixture was also recorded once per member bag and once with no bags, in the identical context (temporary fixtures, since removed). The no-bag variant reproduces pre-Task-5 behavior exactly: the old accessor collapsed every multi-bag set to not-sure.

| Fixture | Luggage | Items | Constraints | Against members | Against pre-Task-5 |
| --- | --- | --- | --- | --- | --- |
| `49` Chicago, 3-day City Break, Light, Personal item + Carry-on | `carryOnConstrained` | 25 | none | identical to Personal item alone and to Carry-on alone | + empty security bottle |
| `50` Tokyo, 10-day Vacation, Balanced, Carry-on + Checked | `checkedAvailable` | 30 | none | = Checked + bottle; vs Carry-on: socks 10→11, T-shirts 8→9, underwear 10→11 (carry-on caps lifted) | + bottle |
| `51` Paris, 9-day Vacation, Balanced, Personal item + Carry-on + Checked | `checkedAvailable` | 31 | none | = Checked + bottle; vs Personal item: book returns, pants 3→4, socks 7→10, T-shirts 5→8, underwear 7→10 | + bottle |
| `52` Reykjavik, 7-day Outdoor, Prepared, Checked + Backpack | `checkedAvailable` | 33 | none | identical to Checked alone; vs Backpack: T-shirts 8→9 | identical |

- Fixture `49` cannot discriminate the capacities: a 3-day trip has no optional item to trim and no cap binds. The truth-table and engine tests (`personalItemPlusCarryOnIsCarryOnCapacity`) carry that proof.
- No fixture emits constraint evidence for an item luggage didn't affect.

## Quantity comparison

14-day Miami beach trip, running + swimming + beach days, no laundry, seasonal weather (temporary fixtures; the Balanced row is pinned by `ClothingQuantityTests.representativeClothingFollowsCapacityNotBagCount`).

| Style | Item | Carry-on | Carry-on + Checked | Personal item | Checked |
| --- | --- | --- | --- | --- | --- |
| Balanced | T-shirts | 8 | 12 | 5 | 12 |
| | Underwear | 10 | 12 | 7 | 12 |
| | Socks | 10 | 12 | 7 | 12 |
| | Pants | 5 | 6 | 3 | 6 |
| | Sleepwear | 2 | 2 | 2 | 2 |
| | Workout top / bottom | 4 / 4 | 5 / 5 | 2 / 2 | 5 / 5 |
| | Swimsuit | 2 | 2 | 2 | 2 |
| Light | T-shirts / underwear / socks / pants | 8 / 10 / 10 / 5 | 8 / 10 / 10 / 5 | 5 / 7 / 7 / 3 | 8 / 10 / 10 / 5 |
| | Sleepwear, workout, swimsuit | 1, 4, 2 | 1, 4, 2 | 1, 2, 2 | 1, 4, 2 |
| Prepared | T-shirts / underwear / socks / pants | 8 / 10 / 10 / 5 | 15 / 15 / 15 / 7 | 5 / 7 / 7 / 3 | 15 / 15 / 15 / 7 |
| | Sleepwear, workout, swimsuit | 2, 4, 2 | 2, 6, 2 | 2, 2, 2 | 2, 6, 2 |

Carry-on + Checked equals Checked in every style. Light with a checked bag packs light through style (T-shirts 8 vs 12 Balanced) with no capacity trim.

## Constraint comparison (same trip)

| Style | Carry-on | Carry-on + Checked | Personal item | Checked |
| --- | --- | --- | --- | --- |
| Balanced | none | none | `bag.personal_item`: goggles, coverup, flip-flops | none |
| Light | `bag.space_constrained`: goggles, coverup, flip-flops | none | `bag.personal_item`: same three | none |
| Prepared | none | none | `style.prepared_vs_personal_item`: same three | none |

## Trace

Every generation records its one luggage decision (`EngineGeneration.luggage`, golden `luggage`). Each constraint decision names the capacity and stable-ordered bags that caused it.

```json
"constraints": [{
  "capacity": "veryConstrained", "constraint": "bag.personal_item",
  "items": ["activities.goggles", "clothing.coverup", "footwear.flip_flops"],
  "owner": "primary", "selectedBags": ["personalItem"], "summary": "Trimmed to fit a personal item."
}],
"luggage": { "appliesCapacityConstraint": true, "capacity": "veryConstrained", "selectedBags": ["personalItem"] }
```

```json
"luggage": { "appliesCapacityConstraint": false, "capacity": "checkedAvailable", "selectedBags": ["carryOn", "checked"] }
```

The second is fixture `50`: no `constraints`, and no item carries a `bagStyleConstraintFact`. That is how "no carry-on trim applied" is recorded.

`GoldenEngineTests.everyGoldenRecordsOneConsistentLuggageDecision` checks every golden: stable bag order; no constraints and no item facts unless capacity is constrained; every decision names the generation's own capacity. `report_engine_goldens.py` compares the luggage block and per-decision capacity under CONSTRAINT CHANGES (`--ignore-luggage-evidence` for pre-Task-5 baselines).

## User authority

`MultiBagEngineTests`:

- **Not Needed** coverup stays out across Carry-on → Carry-on + Checked → Carry-on.
- **Manual quantity** (T-shirts 3) survives Carry-on + Checked, Personal item, and no bags.
- **Custom item** survives with its owner (partner).
- **Packed state** survives.
- **Explicit carrier** on a shared item is unchanged.
- Each edit is a `RecommendationDiff` that never offers an authority row for removal and is smaller than the list.

## Tests added

| Suite | Tests |
| --- | --- |
| `LuggageContextTests` (new, 10) | truth table; constrained-capacity flag; checked defeats every trim; legacy values excluded; insertion order and equality/hash; trim keys by capacity and style; essential-tag protection; clothing caps by capacity; bag count never multiplies clothing; structural authority guard |
| `MultiBagEngineTests` (new, 15) | empty, personal item, carry-on, carry-on + checked, backpack + checked, personal + carry-on + checked, personal + carry-on, carry-on + backpack; Light + Checked; Personal + Prepared; insertion-order output/trace/signature; signature stable order; Road Trip guard both directions; Not Needed; manual quantity/custom/packed/carrier with diffs |
| `ConstraintTests` (+2) | checked beside a carry-on emits no carry-on trim; constraints run once from the resolved capacity |
| `ClothingQuantityTests` (+1) | representative clothing across carry-on, carry-on + checked, personal item, checked |
| `RecommendationTraceTests` (+1) | constraint evidence names the normalized decision in stable order |
| `GoldenEngineTests` (+1) | every golden records one consistent luggage decision |
| Python `test_report_engine_goldens` (+4) | luggage evidence comparison |

Existing tests migrated to the new APIs without changing assertions, except `optionalRulingReorderIsByteIdenticalOnKeepAndConflictKeyForEveryInput`. It now resolves every `BagType` case, legacy included, through `LuggageContext` against the pre-V2 singular reference.

## Semantic golden diff

- **Existing 48 vs `45d0b2c`** (behavior commit `fe0895e`): 1737 unchanged; zero added, removed, quantity, trace, coverage, or constraint changes.
- **New:** fixtures 49–52, reviewed above.
- **Trace commit `42ea686` vs `fe0895e`:**
  - With `--ignore-luggage-evidence`: CLEAN, all 52 fixtures and 1856 items unchanged.
  - With the evidence: 61 constraint-ledger additions, namely 52 luggage records and the capacity/bags on the 9 existing trim decisions. Items, trims, and summaries are identical.

## Verification (final tree, docs commit)

- **iOS:** 464 tests / 30 suites, all passing.
- **Clean Debug build:** succeeded, 0 Swift warnings.
- **`scripts/run_engine_audit.sh`:** all 6 steps pass. That covers `validate_shared` OK (202 items), 119 Python audit tests, 107 focused Swift tests, golden diff CLEAN for 52 fixtures, input audit, and trace audit `--strict` CLEAN.
- **API:** 141 tests pass; preflight green. No contract, DTO, or schema changed; `product-v2-combinations.json` changed only its comment.
