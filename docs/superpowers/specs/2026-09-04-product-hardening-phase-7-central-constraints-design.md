# Product Hardening Phase 7 — Central Constraints and User Authority Design

**Date:** 2026-09-04
**Base:** `product-hardening-phase1` at `e50592b` (semantic golden baseline: `c9cbb76`, Phase 6's closing commit — `e50592b` only adds unrelated pycache housekeeping)
**State:** approved design; implementation not started

## Objective

`ConstraintResolver` becomes the single typed authority for conflicts that
happen after needs, candidates, quantities, and coverage are known — the
same role `CoverageResolver` took for footwear/outerwear (Phase 4) and
`ActivityContracts` took for activities (Phase 5). Concretely: bag/style
conflicts, party sharing membership and quantity, the explicit-user-authority
gate (manual quantity, Not Needed, user-added items), and ownership/carrier
preservation all resolve through one place, with the priority hierarchy
provable by test, not asserted by comment. Finding F-5 (party camping
flashlight sharing, routed by Phase 5's closure) gets a genuine, tested
product decision.

## The current shape — what's actually centralized versus scattered

The master roadmap's Phase 7 entry
(`docs/superpowers/plans/2026-09-03-product-hardening-phase-1-and-next-phases.md`)
says Phase 7 will "centralize bag/style conflicts, sharing, dependencies,
manual quantities, Not Needed, user-added items, ownership, and carrier" as
if all eight are scattered today. Reading `ConstraintResolver.swift`,
`PackingEngine.swift`, `Party.swift`, and `Catalog.swift` in full shows a
mixed picture — some of the eight are already centralized, one has a genuine
duplication bug, and the rest are correct but not expressed through
`ConstraintResolver` at all:

1. **Bag/style conflicts — already centralized.** `ConstraintResolver.optionalRuling(importance:tags:bag:style:)`
   (`ConstraintResolver.swift:48`) is the only place in the app target that
   branches on `BagType`/`PackingStyle` to resolve a conflict. A repo-wide
   grep for `BagType.` / `PackingStyle.` / `bagType ==` / `packingStyle ==`
   / `style ==` across `PackingEngine.swift` and `CoverageResolver.swift`
   finds exactly one other bag/style read: the carry-on/personal-item/flight
   "empty security bottle" *addition* at `PackingEngine.swift:470`, which is
   a suggestion, not a conflict resolution. **The roadmap's framing is wrong
   here** — there is no scattered `if bag == ...` logic to gather up. Phase 7
   does not restructure this family; it adds the two required test gates
   (Prepared+personal item, Light+checked bag) against the existing function.

2. **Dependencies — already a small, closed, declarative table**, exactly
   the shape the master roadmap and this task's instructions ask for, and
   it already exists: `CatalogItem.companions: [String]`
   (`Catalog.swift:14`) is a per-item companion list (6 items declare one
   today — laptop→charger, contacts solution→case, camera→charger, etc.),
   read by `PackingEngine.addCompanions(_:context:overrides:)`
   (`PackingEngine.swift:777`). It already respects Not Needed
   (`isRemoved(companionID:...)` at `:802`) and never duplicates an item
   already present in the same ownership/traveler group (`presentShared`/
   `presentByGroup` at `:784-788, 799`) — which, read carefully, also covers
   "respects user-added equivalents," since `items` (built from `resolve()`)
   already contains user-added drafts before `addCompanions` runs. **No new
   dependency mechanism is needed.** Phase 7 adds one test that was never
   written: a user hand-adds the companion itself, and no duplicate follows.

3. **Party sharing — genuinely scattered, and there is a real duplication.**
   `Set(rules.party.sharedByDefault)` is computed independently at two call
   sites — `generateForParty` (`PackingEngine.swift:150`) and
   `addCompanions` (`:783`) — with no shared function between them. The
   quantity/scaling step (`sharedQuantity`, `:1008`; `sharedQuantityReason`,
   `:1023`) is a third, free-standing pair of functions on `PackingEngine`
   itself, not `ConstraintResolver`. None of this lives in
   `ConstraintResolver` today. This is the one place the roadmap's framing
   is accurate, and it is where Phase 7's centralization work actually
   belongs.

4. **Manual quantity / Not Needed / user-added authority — correct, but
   expressed as four independent inline checks**, not one gate:
   `resolve()`'s existing-item merge (`isUserModified || isUserAdded` short-circuit,
   `:690`), `applyQuantities()`'s per-item early return (`:914`), and
   `isRemoved(...)` (`:757`, called from both `resolve()` and
   `addCompanions()`). Each is individually tested and correct (see
   "Existing evidence" below), but the *fact* of explicit user authority is
   computed four separate times rather than asked once. This is a milder
   form of scattering than #3, and it is what makes "provable, not
   asserted" hard today: proving the priority hierarchy holds requires
   trusting that all four sites independently agree, rather than reading one
   function.

5. **Ownership vs. carrier — centralized, but in two places, neither of
   which is `ConstraintResolver`.** `PackingItemDraft.travelerID` (owner) and
   `.assignedTravelerID` (carrier) (`Catalog.swift:382-384`) are kept
   distinct everywhere they're read. `resolve()` assigns both on draft
   creation and only *fills* a carrier when none was chosen
   (`if updated.assignedTravelerID == nil { updated.assignedTravelerID = assignedTravelerID }`,
   `:703-705`) — never overwrites an explicit reassignment. `PartyInvariants.normalize(_:in:)`
   (`Party.swift:314`) is the fail-safe: an invalid/missing owner resolves to
   the primary traveler (never a guess among several candidates), a
   `shared`-ownership item always has `travelerID == nil`, and an
   `assignedTravelerID` pointing outside the party is dropped. This is a
   legitimate second "one typed authority" (`PartyInvariants`), the same
   relationship `CoverageResolver` has to `ActivityContracts` — two closed
   authorities, not a scattering. Phase 7 does not fold `PartyInvariants`
   into `ConstraintResolver`; it leaves the boundary alone and adds the one
   test gate the roadmap calls for (owner vs. carrier distinction; already
   proven — see below) plus the untested ambiguous/unassigned case in
   `generateDetailed` (`:49-58`).

## Existing evidence — cited, not re-derived

`ConstraintTests.swift` already proves five of the thirteen required gates
end to end, and other suites prove three more:

- **Dependencies:** `userAddedCameraSurfacesChargerWithNamingReason`,
  `companionNotDuplicatedWhenRulesAlreadyEmitIt`, `removedCompanionStaysRemoved`,
  `contactsChainAddsCase` (`ConstraintTests.swift:58-118`).
- **Prepared + personal item (gate 1):** `preparedVersusPersonalItemResolvesExplicitly`
  (`:125-142`) — the conflict is recorded as a `ConstraintDecision`, not
  silently resolved, and the same items exist on a checked bag.
- **Removed canonical item / Not Needed survival (gate 8):**
  `removedBaseEssentialStaysRemovedAcrossRegeneration` (`:160-176`);
  `notNeededRainJacketIsNotRestored` (`WeatherChangeTests.swift:183-195`,
  weather-refresh path); `recommendationDiffHonorsNotNeededOverride`
  (`PackingEngineTests.swift:716-723`, diff path).
- **Manual quantity survival (gate 7):**
  `manualQuantitySurvivesRegenerationWithChangedContext`
  (`ConstraintTests.swift:184-202`, non-clothing `QuantityEngine` family);
  `manualQuantitySurvivesWeatherRefresh` (`ClothingQuantityTests.swift:485`,
  clothing/weather family — this is the exact "T-shirts 7 → 3" shape the
  task names).
- **Packed-state survival (gate 9):** `packedStateSurvivesRegenerationWhenQuantityIsUnchanged`
  (`ConstraintTests.swift:249-263`).
- **User-added canonical/custom item survival (gate 10):**
  `userAddedCanonicalAndCustomItemsSurviveRegeneration` (`:209-242`);
  `customPackedAndModifiedItemsArePreserved` (`WeatherChangeTests.swift:197+`).
- **Owner vs. carrier distinction (gate 5):**
  `ownerStaysWithTheSameTravelerAcrossRegeneration`,
  `manuallyReassignedCarrierSurvivesRegeneration` (`ConstraintTests.swift:270-317`).
- **Family sharing keeps medication personal:** `familySharingKeepsMedicationPersonal`
  (`:324-352`) — proves personal-vs-shared separation for one family, not
  the scaling policies themselves.
- **Two-run determinism (gate 13):** the Phase 1 baseline report
  (`docs/engine-audits/2026-09-03-phase-1-baseline.md`) already verified
  byte-identical repeated generation across the full fixture ledger, not
  assumed. Phase 7 does not re-derive this; it adds one determinism check
  scoped to the party/sharing surface this phase actually touches, since
  that surface (traveler iteration order via `party.travelers`, dictionary
  merges in `sharedCollected`) is new territory for a determinism claim.

**Gaps — no existing test proves these, and Phase 7 must add them:**
Light+checked bag never trims (gate 2); a shared item scaled by an explicit
policy (`scaleByParty`/`scaleByDevices`/`scaleByDurationAndParty`) — no test
anywhere exercises these three policy branches, including the couple+umbrella
case (gate 3) and family scaling (gate 4); the ambiguous/ unassigned party
row (gate 12) — the `generateDetailed` special case at `PackingEngine.swift:49-58`
has no test; a user-added item satisfying a dependency and pre-empting the
auto-companion (gate 6, distinct from "removed companion stays removed");
and a *stacked* priority-hierarchy proof that exercises several authority
dimensions across several kinds of regeneration at once (the composite gate
the task calls out — T-shirts 7→3 *and* Rain jacket→Not Needed *and* an
owner/carrier assignment all surviving one multi-dimensional refresh
together, not as three independent single-fact tests).

## Architecture

`ConstraintResolver` gains two responsibilities alongside its existing
`optionalRuling`/`decisions` pair. Both are moved, not reinvented — the
logic already exists and is already correct; only its location and
duplication change.

### 1. `ConstraintResolver.SharingResolution` — the party sharing authority

```swift
/// Whether an item is shared across the party or stays personal, and if
/// shared, its resolved quantity and user-facing reason — the one place
/// `PackingEngine` asks this question, replacing two independent
/// `sharedByDefault` membership checks and the free-standing
/// `sharedQuantity`/`sharedQuantityReason` pair.
enum SharingResolution: Hashable, Sendable {
    case personal
    case shared(quantity: Int, reason: String)
}

static func sharingResolution(
    for canonicalItemID: String,
    rules: PartyRulesFile,
    context: TripContext,
    party: TripParty
) -> SharingResolution
```

`generateForParty` (`:150-172`) and `addCompanions` (`:783-796`) both call
`ConstraintResolver.sharingResolution(...).isShared` (a thin computed
property) instead of independently testing `sharedIDs.contains(...)`.
`applyQuantities`'s shared-item branch (`:916-924`) calls the same function
and takes its `quantity`/`reason` directly instead of calling
`sharedQuantity`/`sharedQuantityReason` inline. The `.personalOnly` case
already declared on `SharingPolicy` (`Party.swift:90`) is read but not
changed — see "Deliberately out of scope" below.

This is a **zero-diff refactor**: same `sharedByDefault` list, same
`sharingPolicies` JSON, same arithmetic in `sharedQuantity`'s four-case
switch, moved verbatim. The golden report against `c9cbb76` must show zero
row changes before any behavior task runs.

### 2. `ConstraintResolver.hasUserAuthority` / `isExplicitlyRemoved` — the explicit-authority gate

```swift
/// True when a draft carries explicit current-trip user state that no
/// lower-priority layer may override: a manual quantity edit or a
/// hand-added item. The one place this fact is asked, replacing the same
/// `isUserAdded || isUserModified` check written independently in
/// `resolve()` and `applyQuantities()`.
static func hasUserAuthority(_ item: PackingItemDraft) -> Bool {
    item.isUserAdded || item.isUserModified
}

/// True when an explicit "Not Needed" override exists for this candidate,
/// scoped to ownership and traveler exactly as before — moved verbatim
/// from `PackingEngine.isRemoved`, not changed.
static func isExplicitlyRemoved(
    _ canonicalItemID: String,
    ownership: PackingOwnership,
    travelerID: UUID?,
    overrides: [RecommendationOverrideDraft]
) -> Bool
```

Both are pure functions with no new state and no new decision — reading the
same fields the four existing call sites already read. This is intentionally
the smallest possible move: proving the priority hierarchy no longer
requires trusting four independent call sites agree; it requires reading two
functions and the tests that pin them.

### What does NOT move

- `PartyInvariants` (`Party.swift:271-330`) stays where it is. It is a
  correct, closed, already-tested authority for a different question (is
  this draft's owner/carrier *structurally valid for this party*, independent
  of any specific item's sharing policy). Folding it into
  `ConstraintResolver` would be cosmetic churn with real regression risk for
  no behavior change — the same judgment Phase 6 made keeping
  `WeatherChangeReconciler` untouched.
- `CatalogItem.companions` and `addCompanions`'s de-duplication logic stay
  as they are — already the small declarative table the task asks for; nothing
  to centralize.
- `optionalRuling` stays as it is — already the sole bag/style authority.

## Decision — F-5: Camping flashlight party sharing

**The routed finding, verbatim** (`docs/engine-audits/2026-09-03-phase-5-activity-contracts.md:304-309`):

> a party camping trip generates one `miscellaneous.flashlight` per
> traveler. Whether a party should share one is a sharing-policy question
> about personal-carry items, not an activity-contract question, and it
> belongs with the central shared-party constraint work alongside the rest
> of `sharedByDefault`/`sharingPolicies`. Phase 5 changed nothing and pinned
> the current behavior with a test.

**Decision: personal-per-traveler is the correct product contract. No
behavior change.** A flashlight is a personal-safety item, not a
consumable-scarcity or shared-infrastructure one. The existing
`sharedByDefault` catalog (sunscreen, first aid, adapter, umbrella, snacks,
camera/charger, beach towel, insect repellent, stroller, carrier, wipes) is
either genuinely scarce-to-duplicate (adapter), naturally communal
(sunscreen, snacks), or physically shared infrastructure for a child
(stroller, carrier). A flashlight fails all three tests: at a dark
campsite, someone getting up at night, walking to a bathroom alone, or the
party splitting into two groups all need their own light source
independently. This reasoning also answers the task's explicit prompt —
"a couple" and "one traveler carrying a shared item" are exactly the cases
where personal-per-light matters most, not least: a couple who split up
after dark each need their own light; the fact that a family *could*
physically hand one flashlight around does not make it a good idea to model
that as the default.

This closes as **"expected behavior, decided deliberately"** per the task's
own escape clause, not as an unaddressed defect. The existing pinned test
(`ActivityContractTests.aPartyCampingTripKeepsFlashlightsPersonalPerTraveler`,
`:354-365`) already proves the family-of-4 case; Phase 7's Task 3 replaces
its comment (which currently reads as "Phase 5 makes no decision here" —
no longer true) and adds the six scenarios the task requires that aren't
covered yet: solo, couple, Hiking+Camping, one traveler carrying a shared
item, explicit owner assignment, and an unassigned explicit personal-item
flashlight.

**Scope guard: this decides sharing, not eligibility.** F-5 answers one
question — should a flashlight be `sharedByDefault`/`singlePerParty`, or
stay personal — and the answer is personal. It does not decide, and Task 3's
tests must not encode, whether every traveler *class* independently
receives a Camping flashlight regardless of age. Whether an infant or
toddler should get their own light (versus, say, being covered by a
guardian's) is a traveler-eligibility question for Family Hardening
(Phase 10), which already owns age-conditional item behavior via
`skipForYoungChildren`/`skipForInfantsAndToddlers`. Phase 7's scenario tests
(Task 3) use adult travelers and an explicitly-typed child role, never an
infant/toddler age group, so the sharing decision this phase makes stays
separable from the eligibility decision Phase 10 has not made yet.

### Required amendment: `SharingPolicy.personalOnly` is decided and tested this phase

Reading `sharedQuantity`/`applyQuantities` closely surfaces a real but
narrow bug, found while designing the sharing-resolution move: the
`.personalOnly` case (`Party.swift:90`) is declared, has partial handling
in `applyQuantities` (`:919`, `sharedQuantity`'s `.singlePerParty, .personalOnly:`
branch, `:1012`), is used by **zero** `sharingPolicies` rows in `party.json`,
and is exercised by **zero** tests anywhere in the suite. Worse, its actual
semantics don't match its name today: an item reaches that branch only
after already being folded into the single shared `PackingItemDraft` (via
raw `sharedByDefault` membership, checked independently of `policy.policy`
at draft-creation time), so `.personalOnly` doesn't currently produce
per-traveler personal items — it produces one shared-ownership draft whose
quantity computation falls through to the traveler-based paths with
`traveler == nil`, an unexercised and likely-wrong code path.

**Review amendment: this is Phase 7's to fix, not to route.** Party sharing
membership is exactly the family this phase centralizes, and it is the
safest possible time to correct it — zero current `sharingPolicies` rows use
`.personalOnly`, so defining its truthful contract changes no golden output.
Routing a defect inside the exact subsystem this phase owns, discovered
while building that subsystem, back out to an unnamed future phase would be
the wrong call.

**The fix is structural, not a patch layered on top.** `ConstraintResolver.sharingResolution`
(Task 1) already asks `rules.sharedByDefault.contains(canonicalItemID)`
*and then* `guard policy.policy != .personalOnly else { return .personal }`
before ever computing a shared quantity. Because `generateForParty`'s
draft-creation check moves from raw `sharedByDefault` membership to
`sharingResolution(...).isShared`, a `.personalOnly`-policy item is never
created as a `.shared`-ownership draft in the first place — it flows
through the same per-traveler personal-item path every non-shared item
already uses, with a real `travelerID` on every draft. The contract:

```text
singlePerParty          → one shared item for the party
scaleByParty             → shared quantity scales with party size
scaleByDevices            → shared quantity scales by relevant devices
scaleByDurationAndParty  → shared quantity uses duration + party policy
personalOnly              → personal ownership semantics: one draft per
                             traveler, `ownershipType == .personal`,
                             `travelerID` always set — never an
                             `ownershipType == .shared` draft with
                             `travelerID == nil` produced by fallthrough
```

Task 1 adds focused tests proving this against a synthetic, test-local
`PartyRulesFile` (an existing candidate item's rules copy, with a
`.personalOnly` row added only inside the test) — **no `party.json` row is
added**, because no current catalog item independently needs one:

```text
personalOnly + solo    → owned personal item (one draft, real travelerID)
personalOnly + couple  → one personal row per traveler
personalOnly + family  → no ownerless shared draft anywhere in the result
personalOnly            → never travelerID == nil merely from fallthrough
```

If `sharedQuantity`'s now-unreachable `.personalOnly` arm (kept for
`Codable`/switch-exhaustiveness, never invoked once `sharingResolution`
short-circuits first) reads as dead weight once Task 1 lands, leave it —
removing an unreachable switch case is cosmetic churn outside this task's
purpose, not a behavior fix Phase 7 needs.

## Priority-hierarchy proof

The task requires the hierarchy be provable, not asserted:

```text
explicit current-trip user decision
    ↓
manual quantity / Not Needed / user-added
    ↓
current trip constraints
    ↓
accepted personal memory later
    ↓
accepted context enrichment later
    ↓
generic defaults
```

PackWise today has no personal-memory-write or context-enrichment layer
feeding the engine (enrichment stays gated off until M3B per the program's
Global Constraints), so the bottom two rungs are structurally absent, not
merely untested — there is nothing yet that could try to overwrite a user
decision from below them. The provable claim, scoped to what exists, is:
**explicit user state (rungs 1-2) always wins over current-trip constraints
(rung 3) regardless of how many rung-3 dimensions change in the same
regeneration.** Task 2's composite test exercises this directly: one
existing list carrying a manual quantity edit, a Not Needed override, a
user-added custom item, and a reassigned carrier is regenerated against a
context that simultaneously changes weather, activities, and duration —
three independent rung-3 recomputations at once — and every rung-1/2 fact
must be unchanged afterward. This is stronger than the four single-fact
tests already in `ConstraintTests.swift`, each of which only changes one
context dimension at a time.

## Non-goals

- Clothing quantity redesign, footwear/outerwear coverage redesign, new
  activity contracts, new weather signals or thresholds — Phases 3, 4, 5,
  6 respectively, all closed.
- Recommendation Trace UI/productization (Phase 8) — `ConstraintDecision`
  gains no new UI-facing fields this phase.
- GPT/context intelligence (Phase 9+), notifications/Final Check/post-trip
  memory (Phase 12), persistence architecture.
- Assigning any existing catalog item to `SharingPolicy.personalOnly` — its
  semantics are made truthful and tested this phase (see above), but no
  current item independently needs the policy, so no `sharingPolicies` row
  is added.
- Deciding traveler/age eligibility for Camping items (infant/toddler
  behavior) — Phase 10 (Family Hardening), not F-5's sharing decision (see
  above).
- Folding `PartyInvariants` into `ConstraintResolver` — deliberately kept
  as a separate, already-correct authority (see Architecture).
- Any change to `shared/rules/party.json`'s data — `sharedByDefault` and
  `sharingPolicies` are read, not edited; F-5 needs no new row, and neither
  does the `personalOnly` fix.

## Verification plan

- Zero-diff gate: `report_engine_goldens.py --baseline-ref c9cbb76` shows
  zero row changes after Tasks 1 and 2 (pure refactor), and only the two
  new fixtures Task 7 adds afterward — reviewed, not silently absorbed.
- `scripts/run_engine_audit.sh` clean after every task.
- Full `xcodebuild test`, `python3 scripts/validate_shared.py`,
  `npm --prefix api run preflight` at close.
- All 13 required test gates map to a named task and a named test (see the
  implementation plan's task table).

## Routed findings anticipated

- **F-1** (golden-diff schema tolerance, P2) — unaffected by Phase 7,
  carried forward unchanged.
- **Context-chip/bag-type/trip-type UNTESTED tail (14 rows)** — pre-existing,
  outside Phase 7's scope, carried forward unchanged.
- **`CoverageContext` double-construction** (noted by Phase 6's design doc)
  — unaffected by Phase 7, carried forward unchanged.
