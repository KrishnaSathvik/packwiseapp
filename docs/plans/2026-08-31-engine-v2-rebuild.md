# PackWise Engine V2 — Rebuild Plan

Consolidated and final. Supersedes the earlier next-steps document and the original Engine V2 proposal.

**Scope:** the layer between `TripContext` and `RecommendationResolver`. Nothing else is rebuilt.

**Method:** baseline → one family → review the diff → prove behavior → migrate the next family.

**Gate:** Miami beach vs Chicago business, both five days, must be unmistakably different.

---

## Preserved as-is

Do not touch, refactor, or "improve while in there":

```
SwiftUI presentation           MapKit destination search
SwiftData persistence          App Attest
WeatherKit → TripWeatherContext   Redis
WeatherSnapshot caching        OpenAI backend boundary
WeatherSignalDiff              structured schemas
WeatherChangeProposal lifecycle   canonical item IDs
recommendationDiff()           party owner/carrier model
                               RecommendationOverride
```

The engine's output type stays `[PackingSuggestion]`. UI, persistence, weather diffing, and proposals never learn the engine changed.

---

## Cut from the roadmap

**Travel advisories — removed, not deferred.** Power banks, batteries, aerosols, medications, sharp objects, country restrictions. Per-airline and per-country rules with no maintenance process, on a liability surface a small team shouldn't take. `Passport` as a checklist row is fine; advisory content is not the product.

## Deferred, deliberately

Trip segments · activity occurrences with dates · traveler-scoped model signals · notifications · Final Check · post-trip review · Packing Memory UI · pack-lighter · gap detection · Ask PackWise

**Segments:** the only future-proofing needed now is `PackingNeed.dateRange` plus weather addressable by date. Writing segment aggregation at `n = 1` produces code that looks future-proof and has never been exercised.

**Traveler-scoped signals** move up if family trips become a priority. Until they ship, one safety rule applies immediately:

> Ambiguous multi-traveler inference resolves to **don't infer**, never **infer onto self**.
>
> "My daughter needs medication" must not become `dailyMedication` for the primary traveler. Dropping the signal is acceptable; misattributing it is not.

---

# Step 0 — Stabilize

Engine work does not begin on a dirty tree.

1. Land the round-2 UI fixes (separate document). The checkbox/importance bug first — a third of items currently cannot be packed, and it's roughly an hour.
2. Commit that work. The no-commit constraint was for the UI conformance pass; carrying ~1,750 uncommitted lines into an engine rebuild removes your only ability to isolate a regression.
3. Branch: `engine-v2`.
4. **No visual work on this branch.** Device UI QA continues separately.

---

# Step 1 — Golden-file harness

Before a single packing rule changes.

Run the current engine over each fixture, serialize the complete output, commit it.

```json
{
  "fixture": "tokyo-15d-light-laundry-possible",
  "engineVersion": "v1",
  "items": [
    {
      "canonicalItemID": "clothing.tshirt",
      "category": "clothing",
      "quantity": 15,
      "importance": "normal",
      "reasonCode": "duration.default",
      "travelerID": "primary"
    }
  ]
}
```

A test asserts current output matches. When output changes intentionally, regenerate and **review the diff**.

**The golden file is a regression ledger, not truth.** Today's wrong behavior gets committed deliberately, so that V2 produces a reviewable diff:

```diff
- T-shirts ×15
+ T-shirts ×7
- Socks ×16
+ Socks ×8
- Underwear ×16
+ Underwear ×8
```

That diff is the deliverable of every subsequent step.

## Fixtures

| # | Fixture | Proves |
|---|---|---|
| 1 | Chicago · 5d · city · walking · carry-on · balanced | Baseline sanity |
| 2 | Tokyo · 15d · vacation · walking+running · carry-on · light · laundry **possible** | The current bug |
| 2b | Same, laundry **planned** | Planned vs possible (see note below) |
| 3 | Same as 2, laundry **none** | Laundry matters |
| 4 | Same as 2, checked + prepared | Style and bag matter |
| 5 | Same as 2 at 30d | Plateau |
| 6 | Miami · 5d · beach · swimming · personal item · light · laundry | **Gate A** |
| 7 | Chicago · 5d · business · work+dinner · checked · prepared · no laundry | **Gate B** |
| 8 | 5d · running + sightseeing · carry-on · light | Footwear substitution (slice 2) |
| 9 | 5d · rain 3 days + cool evenings | Weather layering, no duplicate outerwear |
| 10 | 1d trip | No duration overpacking |
| 11 | Couple · 5d · rain | Personal vs shared |
| 12 | Family + toddler · 7d | Age-aware; no inferred formula |
| 13 | Fixture 2 + `Not Needed` on rain jacket, regenerated | Overrides survive |
| 14 | Fixture 2 + manual `T-shirts ×3`, then weather refresh | Manual quantity survives |

**Note on fixture 2/2b.** The existing laundry chip maps to `.possible` under migration, and no control currently emits `.planned`. Either add the three-way control during Step 2, or mark 2b `pending-UI` and exclude it from the gate. Do not let a fixture silently assert on an unreachable state.

---

# Step 2 — Needs + Quantity (clothing only)

Fused deliberately: `requiredUses`, `reuseModel`, and laundry sensitivity are properties of a **need**, not of a `canonicalItemID`. Building quantity first would produce a formula keyed on items that gets rewritten one step later, silently changing numbers already tuned.

## Scope

Clothing family only: tops, bottoms, underwear, socks, sleepwear, swimwear, workout. Everything else passes through `LegacyRuleAdapter` untouched.

## Types

```swift
struct PackingNeed {
    let id: String              // "clothing.daily_underwear"
    let scope: NeedScope        // .traveler(id) | .shared
    let requiredUses: Int?
    let dateRange: DateInterval?
    let signals: [Signal]
}

struct QuantityPolicy {
    let usageModel: UsageModel          // .daily .dailyish .multiDay .perEvent .perSequence
    let reuseModel: ReuseModel          // .none .allowed .high
    let laundrySensitivity: Sensitivity // .none .low .high
    let styleSensitivity: Sensitivity
    let bagSensitivity: Sensitivity
    let minimum: Int
    let maximum: Int?
    let contingency: ContingencyPolicy
}

enum LaundryPlan {
    case none
    case possible
    case planned          // later: planned(days: [Int])
}
```

**Migration:** the existing laundry boolean maps to `.possible`. `.planned` requires deliberate user intent, which the current wording doesn't establish.

## Quantity model

Quantity derives from required uses bounded by the reuse cycle, not from trip days:

```
planned laundry     → bounded by max inter-wash interval + style buffer
possible laundry    → conservative reduction, not full plateau
no laundry          → policy-capped growth; bag constraint becomes binding
```

## Freeze the catalog

**No item renames, recategorization, or reason-string edits during this step.** The entire value of the golden diff on slice 1 is that it should be *purely quantity*. If names and categories move simultaneously, the diff becomes unreviewable and the plan's only safety mechanism is gone. Catalog cleanup is its own commit, before or after, never during.

## Tests

### Property 1 — global non-decreasing

Across the constraint chain on the same trip, quantities are **non-decreasing** (not strictly increasing):

```
Light + personal item + laundry planned
 ≤ Light + carry-on + laundry planned
 ≤ Balanced + carry-on + laundry possible
 ≤ Balanced + checked + no laundry
 ≤ Prepared + checked + no laundry
```

Non-decreasing is required because correct behavior includes flat sequences: sleepwear may legitimately run `1 → 1 → 1 → 2 → 2`, swimwear `0 → 0 → 0 → 0 → 0` on a non-swimming trip, a formal outfit `1` throughout.

**Assert at the need level, or on aggregate garment count per need — not per canonical item** for any family that will participate in substitution. Write it this way now: once coverage lands in Step 3, a versatile item chosen under tight constraints can be *replaced* by two specialized items under loose ones, producing a correct `1 → 1 → 1 → 0 → 0` that a per-item assertion would flag as a regression.

### Property 2 — declared sensitivity must bite

For every policy where `laundrySensitivity != .none`, `styleSensitivity != .none`, or `bagSensitivity != .none`, require **at least one strict divergence** across the relevant fixture chain.

This is the test that prevents settings from becoming decorative. A policy that claims sensitivity and never changes its output is a bug.

### Property 3 — plateau

Fixture 5 (30d, laundry planned) within ±1 of fixture 2b (15d, same wash interval), per item. Above the wash cycle, duration stops mattering.

### Property 4 — contextual bounds

Bounds are keyed to policy and context, **not global constants**:

```
planned laundry, wash interval ≤ 7d   → socks plateau near interval + buffer
no laundry                            → growth allowed up to policy maximum
```

`socks ≤ 10` universally would wrongly fail an 18-day, no-laundry, prepared, cold-weather trip.

Global sanity bounds are limited to floors that are always true: every trip has `shirts ≥ 2`, `underwear ≥ 2`.

### Property 5 — preservation

Fixtures 13 and 14 unchanged: `Not Needed` overrides and manual quantity edits survive regeneration and weather refresh.

**Exit:** golden diff reviewed and accepted. Fixture 2 clothing quantities materially lower. Properties 1–5 green.

---

# Step 3 — Capability + Coverage

## Scope

Footwear and outerwear only.

## Closed vocabulary

A **closed enum**, target 15–20 capabilities. Adding one is a design decision, not a line an engineer writes while authoring a rule. An open vocabulary degenerates into a lookup table with no generalization — `footwear.long_city_walk`, `footwear.medium_city_walk`, `footwear.casual_sightseeing`.

```json
{
  "id": "footwear.running_shoes",
  "capabilities": ["footwear.running", "footwear.walking", "footwear.casual"]
}
{
  "id": "footwear.walking_shoes",
  "capabilities": ["footwear.walking", "footwear.casual"]
}
{
  "id": "footwear.dress_shoes",
  "capabilities": ["appearance.smart_casual", "appearance.formal"]
}
```

## Resolver

**Greedy with explicit priority ordering.** Set cover is NP-hard in general and irrelevant at this scale — tens of needs, hundreds of candidates. A deterministic greedy resolver is easier to test, debug, and explain. No solver framework.

Priority ordering must be explicit and stable so output is reproducible.

**Exit:** fixture 8 produces one pair of shoes, not two. Golden diff reviewed.

---

# Step 4 — Recommendation Trace + Item Detail

This is the first step that pays the user back rather than only the codebase. It comes before the constraint resolver deliberately — no more internal sophistication before the existing sophistication is visible.

```swift
struct RecommendationTrace {
    let needsSatisfied: [NeedID]
    let signals: [Signal]
    let quantityDecision: QuantityDecision   // value + contributing factors
    let coverageDecision: CoverageDecision?
    let suppressedCandidates: [CanonicalItemID]
    let userConstraints: [Constraint]
    let reasonCodes: [ReasonCode]
}
```

Rendered:

> **Running shoes ×1**
>
> Covers running and everyday walking.
>
> **Why one pair** — you're packing light in a carry-on, and running shoes work for both.
>
> **Based on** — Running · Sightseeing · Carry-on · Light packing

## UI requirements

- **Whole row tappable** → Item Detail. Leading circle remains the packing control.
- Chevron on rows that have a trace.
- Reason copy generated from `reasonCode` + arguments via a template catalog with an explicit fallback ladder: specific templated reason → category-level reason → generic. **A generic fallback appearing on a weather- or activity-driven item is a bug**, not acceptable degradation.

Ban the current generic strings from weather/activity items: "Based on what you'll be doing," "A core item for almost every trip."

**Exit:** every generated item has a trace; Item Detail renders it; no generic fallback on any item with a weather or activity signal.

---

# Step 5 — Constraint Resolver

Single place where conflicts resolve: bag, style, personal vs shared, dependencies, overrides, criticality.

## Dependencies as first-class

```
laptop    → laptop charger (required)
camera    → charger/batteries (required), memory card (recommended)
contacts  → solution, case (required)
```

Applies to user-added items too — adding `Camera` manually should surface the charger.

## Personal vs shared

Fixture 11, couple + rain:

```
Krishna → rain layer
Partner → rain layer
Shared  → umbrella ×1
```

Not `umbrella ×2`.

## Conflicting signals

`Prepared` + `personal item only` conflict. The resolver decides explicitly and the decision enters the trace:

> Prepared preference acknowledged; personal-item constraint takes priority for bulky optional items.

Two rules must never fight silently.

## Decision hierarchy

```
1. Explicit user state (added / removed / quantity edited / Not Needed)
2. Safety-critical non-mutating reminders
3. Current trip requirements
4. Traveler preferences
5. Packing Memory (later)
6. Contextual model recommendations
7. Generic defaults
```

Non-mutating reminders are distinct from list mutation. If `Passport` is marked `Not Needed` on an international trip, the list stays as the user left it — but Final Check may later warn. Warning is not editing.

**Exit:** fixture 11 correct. Dependencies resolve. Conflicts appear in traces.

---

# Step 6 — Memory events

Immutable event log. Nothing reads it yet.

```swift
struct PackingMemoryEvent {
    let tripID: TripID
    let travelerID: TravelerID
    let canonicalItemID: CanonicalItemID
    let kind: EventKind     // suggested userAdded notNeeded packed quantityChanged
    let value: Int?
    let timestamp: Date
    let context: ContextFingerprint
}
```

**`ContextFingerprint` must be a structured value, not an opaque hash:**

```swift
struct ContextFingerprint {
    let durationBucket: DurationBucket   // .short .medium .long .extended
    let laundryPlan: LaundryPlan
    let packingStyle: PackingStyle
    let bag: BagType
    let tripType: TripType
    let partySize: Int
}
```

A hash makes the events unqueryable and you'd collect useless data for months. Structured, it supports the queries that matter later — "when laundry is available, you usually reduce shirts by ~40%" is a group-by, not a research project.

---

# Step 7 — Full matrix + gate

Run all fixtures. Review the complete golden diff.

## Gate: fixture 6 vs fixture 7

Miami beach vs Chicago business. Same duration, different everything else.

**Test:** anonymize the destination names and show both lists to someone uninvolved. They should immediately identify which is the beach trip and which is the business trip — from items, quantities, and reasons alone.

Expected divergence:

| Miami | Chicago |
|---|---|
| swimwear, sandals, sun protection | work clothing, dress shoes, nice outfit |
| small clothing capsule, light quantities | larger quantities, backups |
| minimal formal | laptop and work gear |

If they look like the same list with a few rows swapped, the rebuild isn't done.

This gate replaces the 23-day multi-city mega-case as the readiness bar. That trip is a good aspiration and a bad gate — building for it now slows every earlier decision. Once 6 vs 7 is unmistakable, the rest of the matrix is hardening, and hardening is far easier when the core claim is demonstrably true.

---

# Sequence summary

```
STEP 0   Land + commit UI work · branch engine-v2 · no visual work on branch
STEP 1   Golden harness · 14 fixtures · capture V1
STEP 2   Needs + Quantity — CLOTHING ONLY · catalog frozen
STEP 3   Capability + Coverage — FOOTWEAR + OUTERWEAR · closed enum · greedy
STEP 4   Recommendation Trace + Item Detail + reason templates
STEP 5   Constraint Resolver · dependencies · shared · conflicts
STEP 6   Memory event collection · structured fingerprint
STEP 7   Full matrix · golden diff review
GATE     Miami vs Chicago must unmistakably differ
```

Only after the gate is green: decide between Context Intelligence, Packing Memory, or Notifications / Final Check — based on what the product needs at that point, not what's planned now.

---

# Standing rules for this rebuild

1. Every step ends with a **reviewed golden diff**. An unreviewed diff means the step isn't finished.
2. One family per slice. No universal migration.
3. Catalog changes never share a commit with engine changes.
4. Output type stays `[PackingSuggestion]`.
5. A policy that declares sensitivity and never changes its output is a bug.
6. A generic reason string on a weather- or activity-driven item is a bug.
7. Ambiguous multi-traveler inference resolves to *don't infer*.
8. No solver frameworks, no capability vocabulary growth without a decision.
