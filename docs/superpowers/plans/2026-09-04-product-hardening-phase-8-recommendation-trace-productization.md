# PackWise Product Hardening Phase 8 — Recommendation Trace Productization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Amendment note (2026-09-04):** Review required three architectural
amendments, a metric refinement, and a scoping guard before execution.
This revision incorporates all five: (1) constraint/authority trace facts
are now captured once, at generation time, inside `PackingEngine.resolve`
and `ConstraintResolver.optionalRuling`, never re-derived by a second, live
call from presentation code (Task 1, Task 5); (2) `satisfiedCapabilities`
(renamed from `coveredCapabilities`) is now computed inside
`CoverageResolver.resolve`'s own resolution loop as
`itemCapabilities ∩ activeNeeds`, not by inverting `coverageSuppressions`
afterward — closing a real gap the inversion design could never see (Task
1); (3) `PackingItemRecord.apply(_:)` — found, on inspection, to have zero
callers anywhere in the app today — is fixed and finally wired into the
real regeneration path, with a concrete regression test (new Task 3); the
exit metric changes from "generic-only generated explanations = 0" to
"generated recommendations lacking causal structured provenance = 0" (Task
7, Task 9); and `quantityReasonArguments` gets a closed, tested key
vocabulary (Task 1). Tasks are renumbered 1–9 to fit the new Task 3; no
other task's intent changed. See the design doc's amendment sections for
the full investigation behind each change.

**Goal:** Turn PackWise's existing provenance — `PackingItemDraft`'s
`reasonCode`/`reasonArguments`/`sourceSignals`/`quantityReason`/
`quantityEvidence`, `EngineGeneration`'s `coverageSuppressions`/
`constraintDecisions`, and Phase 7's `ConstraintResolver.SharingResolution`/
`hasUserAuthority`/`isExplicitlyRemoved` — into one complete, queryable
recommendation trace per item, wire the already-frozen Item Detail sheet to
it, fix the routed `party.shared` pluralization finding, fix the
persisted-provenance staleness gap on regeneration, and strengthen
`scripts/audit_recommendation_traces.py`'s exit metrics. The engine decides
once; this phase only makes that decision legible. No new recommendation
behavior.

**Architecture:** Full detail in
`docs/superpowers/specs/2026-09-04-product-hardening-phase-8-recommendation-trace-design.md`.
Summary: three new, additive `PackingItemDraft` fields —
`quantityReasonArguments: [String: String]` (closed to six keys:
`quantity`, `days`, `rate`, `name`, `travelerCount`, `rainDays`),
`satisfiedCapabilities: [String]`, and `bagStyleConstraintFact:
BagStyleConstraintFact?` — capture structured facts the engine already
computes as a byproduct of the exact call that decides them: quantity
arguments in `applyQuantities`; `satisfiedCapabilities` inside
`CoverageResolver.resolve`'s own loop (`itemCapabilities ∩ activeNeeds`,
not a suppression inversion); `bagStyleConstraintFact` inside
`PackingEngine.resolve` at the one `ConstraintResolver.optionalRuling` call
site, which widens to report the fact instead of just `keep`/`conflictKey`
(Task 1). All three persist onto `PackingItemRecord` following the existing
`reasonArgumentsRaw`/`sourceSignalsRaw` flattening convention, no schema
version bump (Task 2). `PackingItemRecord.apply(_:)` — dead code today,
zero callers — is fixed and given a real caller: `recommendationDiff`'s
internal baseline becomes merge-aware (`existing: existing`, not `existing:
[]`), its per-item comparison widens from quantity-only to the full causal
unit, and `TripRepository.applyDiff` calls `record.apply(change.fresh)`
instead of mutating `record.quantity` directly (Task 3). `reasons.json`'s
`"party.shared"` template gains a `{quantityPhrase}` placeholder, mirroring
`party.shared_umbrella`'s already-correct pattern (Task 4). A new
`RecommendationTrace` enum is a pure read layer — every facet function
reads fields already populated at generation time, none takes a `catalog`/
`rules`/`context`/`party` parameter, and `ConstraintFacet` is reconstructed
from stored fields rather than re-calling `ConstraintResolver` (Task 5).
Item Detail is wired to it without any layout change (Task 6). The audit
script gains two new structural checks plus the closed-key-vocabulary
guard, and its exit-metrics wording is refined (Task 7). The 18 required
scenarios get trace-classification tests, citing the sixteen that already
have decision-level evidence — none needed re-classification under the
amended design (Task 8). Task 9 closes the phase.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, SwiftData, JSON shared
catalog/rules, JSON golden fixtures, Python audit tooling, Xcode/iOS 18
simulator tests.

## Global Constraints

- Work on `product-hardening-phase1` from `eadc345`; preserve every Phase
  1–7 commit and the unrelated signing change in the main checkout.
- Follow the approved, amended design at
  `docs/superpowers/specs/2026-09-04-product-hardening-phase-8-recommendation-trace-design.md`.
- **No second decision engine, and no second *reading* of a decision
  either.** Every function this plan adds either (a) is a pure derivation
  over data `PackingEngine`/`ConstraintResolver`/`CoverageResolver`
  already computed in the same call and stored on the draft (Task 1), or
  (b) is a pure field read of that stored data (Task 5). No task may
  change which items are generated, their quantities, coverage/suppression
  outcomes, weather signal extraction, activity contracts, or constraint/
  share decisions. **No task may re-call `ConstraintResolver.optionalRuling`,
  `.sharingResolution`, `.hasUserAuthority`, or `.isExplicitlyRemoved`, or
  invert `CoverageSuppression`, from presentation-layer code (Item Detail
  or `RecommendationTrace`) — every fact `RecommendationTrace` exposes must
  already be sitting on `PackingItemDraft`/`PackingItemRecord` before Item
  Detail ever reads it.** This is stronger than the original plan's
  constraint, per the required amendment.
- No new `RecommendationSignal` case, `PackingCapability` case,
  `ActivityNeed` case, or `WeatherSignal` case.
- `CoverageSuppression`, `ConstraintDecision`, and `CapabilityCoverage`
  stay `Hashable, Sendable` only — no `Codable` conformance is added to
  them. Only their derived, flattened facts (`satisfiedCapabilities:
  [String]`, `bagStyleConstraintFact`) are persisted.
- `quantityReasonArguments`'s key vocabulary is closed to exactly six
  keys: `quantity`, `days`, `rate`, `name`, `travelerCount`, `rainDays` —
  grounded in what `CareQuantityEngine.Result.arguments`,
  `WarmLayerQuantities.quantity`, and the sharing call site in
  `applyQuantities` actually produce. No task may write an unlisted key;
  Task 1 adds a test enforcing this closed set, the same discipline
  `ActivityNeed`/`PackingCapability`/`WeatherSignal` already established.
- `shared/rules/*.json` changes are limited to exactly one template key:
  `reasons.json`'s `"party.shared"` (Task 4). No other JSON row, threshold,
  or rule changes.
- Golden regressions include any item/quantity/coverage/constraint/
  ownership/carrier change outside the one reviewed `party.shared` wording
  diff on fixture 37. Run `report_engine_goldens.py --baseline-ref
  eadc345` after every task that touches `PackingEngine.swift`,
  `CoverageResolver.swift`, `ConstraintResolver.swift`, `Catalog.swift`, or
  `reasons.json`.
- Task 1/Task 2 (the additive-field tasks) are each a **zero-diff gate**:
  the new keys must appear in every fixture's serialized output with
  **zero** change to any existing key, verified before either task's
  behavior-adjacent test is trusted. `ConstraintResolver.optionalRuling`'s
  widened return (Task 1) must be verified byte-identical on `keep`/
  `conflictKey` for every input the golden suite exercises — the reorder
  that exposes `wouldTrimUnderKey` must not change which items survive a
  space-constrained bag.
- Task 3 (the persisted-provenance refresh fix) changes production
  behavior in the regeneration path — `recommendationDiff`'s internal
  baseline and `applyDiff`'s per-item application — and is **not** a
  zero-diff gate against `eadc345`'s golden fixtures (it does not touch
  `PackingEngine.generate`'s output at all, only how an *existing trip's*
  regeneration merges into *persisted* records). It is verified by its own
  named regression test, not a golden diff, and must not change
  `recommendationDiffIsEmptyWhenContextIsUnchanged`,
  `recommendationDiffPreservesPackedCustomAndModified`,
  `addingLaundryProducesQuantityChangeSuggestions`, or
  `recommendationDiffHonorsNotNeededOverride`'s existing pass/fail outcome
  (`PackingEngineTests.swift:607-723`) — those tests pin observable
  behavior this task must preserve exactly, even as its internal mechanism
  changes.
- Task 4 (the `party.shared` fix) is the plan's one **approved, reviewed**
  golden diff against `PackingEngine.generate`'s output — scoped exactly
  to fixture 37's two shared-item rows' `quantityReason` text. `quantity`
  values, every other fixture, and every other row in fixture 37 must be
  byte-identical to `eadc345`.
- The 68-row generic-only rendered-copy bucket is not driven to zero (see
  the design doc's Exit Metrics section) — no task in this plan adds a new
  `reasonCode`, `signalAdds` row, or `ActivityContract` entry to shrink it.
  It is reported, unchanged, as a separate informational count from the
  refined pass/fail metric (Task 7, Task 9).
- Presentation stays frozen: Item Detail's card structure, section order,
  and navigation are unchanged. New content fills existing sections
  (`ItemDetailView.reasons`) or adds one clearly-scoped subsection.
  **Strengthened by the amendment:** Item Detail (and `RecommendationTrace`)
  never call `PackingEngine`, `CoverageResolver`, `ConstraintResolver`, or
  `WeatherSignalExtractor` directly, for any facet.
- Physical-device verification stays deferred, M3B/M3C remain blocked.
- Do not edit `docs/plans/2026-09-02-product-hardening-program.md` before
  Task 9. Stop at the Phase 8 exit gate; do not begin Phase 9.

---

## File Map

- Modify `ios/PackWise/Domain/Packing/Catalog.swift`: add
  `quantityReasonArguments`, `satisfiedCapabilities`,
  `bagStyleConstraintFact` (new `BagStyleConstraintFact` struct) to
  `PackingItemDraft`; widen `QuantityChangeSuggestion` to carry the full
  merged draft (Task 1, Task 3).
- Modify `ios/PackWise/Domain/Packing/CoverageResolver.swift`:
  `resolve(items:needs:)` populates `satisfiedCapabilities` inside its own
  per-item loop (Task 1).
- Modify `ios/PackWise/Domain/Packing/ConstraintResolver.swift`: widen
  `OptionalRuling` with `wasConstraintLive`/`essentialTagProtected`/
  `wouldTrimUnderKey`, behavior-preserving reorder of `optionalRuling`
  (Task 1).
- Modify `ios/PackWise/Domain/Packing/PackingEngine.swift`: populate
  `quantityReasonArguments`/`bagStyleConstraintFact` (Task 1); widen
  `recommendationDiff`'s internal baseline and per-item comparison (Task
  3); fix the `party.shared` argument (Task 4).
- Modify `ios/PackWise/Data/Repositories/Repositories.swift`: `applyDiff`
  calls `record.apply(change.fresh)` instead of mutating `record.quantity`
  directly (Task 3).
- Modify `ios/PackWise/Domain/Weather/WeatherChangeReconciler.swift`:
  `prune`'s re-validation widens from a quantity-only check to
  `causallyDiffers(from:)`, and `QuantityChangeSuggestion.item` references
  rename to `.existing`/`.fresh` (Task 3 — a second real caller found by
  tracing the chain, not assumed absent).
- Modify `shared/rules/reasons.json`: `"party.shared"` template only (Task
  4).
- Modify `ios/PackWiseTests/GoldenEngineTests.swift`: serialize the three
  new fields into golden output (Task 1).
- Modify `shared/fixtures/golden/golden-fixtures.json`,
  `ios/PackWiseTests/Goldens/*.json`: re-recorded output for all 38
  fixtures (Task 1, additive only), fixture 37 wording diff (Task 4).
- Modify `ios/PackWise/Data/Persistence/Models.swift`: persist the three
  new fields on `PackingItemRecord` (`init(from:)`, `draft`); correct
  `apply(_:)`'s refresh contract (Task 2, Task 3).
- Modify `ios/PackWiseTests/PackingEngineTests.swift`: widen
  `recommendationDiff` coverage for causal-fact (not just quantity)
  changes (Task 3).
- Create `ios/PackWiseTests/RegenerationProvenanceTests.swift`: the
  Hiking-removed/different-activity-keeps-the-item regression test, plus
  the packed/manual-quantity/Not-Needed/explicit-carrier non-touch
  assertions (Task 3).
- Create `ios/PackWise/Domain/Packing/RecommendationTrace.swift`:
  `InclusionFamily`, `inclusionFamily(reasonCode:signals:)`,
  `QuantityFacet`, `ConstraintFacet`, `CoverageFacet`, `Authority` (Task
  5).
- Create `ios/PackWiseTests/RecommendationTraceTests.swift`: inclusion-
  family classification, quantity/constraint/coverage/authority-facet
  tests; the 18-scenario citation/classification matrix (Tasks 5, 8).
- Modify `ios/PackWise/Features/TripDetail/PackingListView.swift`: wire
  `ItemDetailView.reasons` to the new facets (Task 6).
- Modify `scripts/audit_recommendation_traces.py`: add the seasonal-
  provenance and user-authority-fabrication checks; refine the exit-metric
  wording (Task 7).
- Modify `scripts/tests/test_audit_recommendation_traces.py`: tests for
  both new checks (Task 7).
- Modify `scripts/run_engine_audit.sh`: pass `--strict` to
  `audit_recommendation_traces.py` (Task 7).
- Create `docs/engine-audits/2026-09-04-phase-8-recommendation-trace-productization.md`
  (Task 9).
- Modify `docs/plans/2026-09-02-product-hardening-program.md`: close Phase
  8 only in Task 9.

---

### Task 1: Generation-time trace capture — quantity arguments, satisfied capabilities, bag/style constraint facts

**Files:**
- Modify: `ios/PackWise/Domain/Packing/Catalog.swift`
- Modify: `ios/PackWise/Domain/Packing/CoverageResolver.swift`
- Modify: `ios/PackWise/Domain/Packing/ConstraintResolver.swift`
- Modify: `ios/PackWise/Domain/Packing/PackingEngine.swift`
- Modify: `ios/PackWiseTests/GoldenEngineTests.swift`
- Modify: `shared/fixtures/golden/golden-fixtures.json`, `ios/PackWiseTests/Goldens/*.json`

**Interfaces:**
- Consumes: `CareQuantityEngine.Result.arguments`, `WarmLayerQuantities.quantity(...)`'s
  `arguments` return element, `ConstraintResolver.SharingResolution`'s
  `quantity` (`ConstraintResolver.swift:120-125`), `CoverageResolver
  .resolve`'s own `needed = capabilities.intersection(needs)`
  (`CoverageResolver.swift:245`), `ConstraintResolver.optionalRuling`'s
  widened return — all either unchanged or widened, never re-called from
  a second site.
- Produces: `PackingItemDraft.quantityReasonArguments: [String: String]`
  (closed key set), `.satisfiedCapabilities: [String]`,
  `.bagStyleConstraintFact: BagStyleConstraintFact?`.

**This task supersedes the original design's `coveredCapabilities`
(inversion of `coverageSuppressions`) with `satisfiedCapabilities`
(`itemCapabilities ∩ activeNeeds`, computed inside `CoverageResolver
.resolve` itself) and adds `bagStyleConstraintFact`, which the original
design did not have — both are required amendments, not refinements; see
the design doc's "constraints" and "needs/capabilities and coverage"
sections for the full investigation.**

- [ ] **Step 1: Write the failing characterization tests**, pinning the
  three new fields against today's already-computed-but-discarded facts,
  the closed key vocabulary, and the coverage counterexample that
  motivates the `satisfiedCapabilities` redesign.

```swift
// GoldenEngineTests.swift — near the existing quantityEvidence assertions (:139-191)

@Test func warmLayerQuantityArgumentsSurviveOntoTheDraft() throws {
    let output = try engineOutput(for: "15-minneapolis-6d-deep-winter")
    let sweater = try item("clothing.light_sweater", owner: "primary", in: output)
    #expect(sweater.quantityReasonArguments["quantity"] == "\(sweater.quantity)")
    #expect(sweater.quantityReasonArguments["days"] != nil)
}

@Test func sharedItemQuantityArgumentsCaptureQuantityAndTravelerCount() throws {
    let output = try engineOutput(for: "38-couple-5d-seattle-shared-umbrella")
    let umbrella = try item("essentials.umbrella_compact", owner: "shared", in: output)
    #expect(umbrella.quantityReasonArguments["quantity"] == "\(umbrella.quantity)")
    // The umbrella branch also carries rainDays; a generic scaleByParty
    // item elsewhere in the same fixture should carry travelerCount
    // instead — asserted on whichever shared, scaleByParty item the
    // fixture actually contains.
}

@Test func fixedSingletonsCarryEmptyQuantityReasonArguments() throws {
    let output = try engineOutput(for: "01-chicago-5d-city-balanced")
    let toothbrush = try item("toiletries.toothbrush", owner: "primary", in: output)
    #expect(toothbrush.quantityReasonArguments.isEmpty)
}

@Test func satisfiedCapabilitiesNamesWhatASurvivingItemCovers() throws {
    // Hiking shoes cover walking (substitution.hiking_covers_walking,
    // fixture 29) — the same fact CoverageSuppression already records on
    // the *suppressed* walking-shoes row now also lands directly on the
    // surviving hiking-shoes row, computed once inside
    // CoverageResolver.resolve, not by inverting the suppression.
    let output = try engineOutput(for: "29-yellowstone-4d-hiking-camping")
    let hikingShoes = try item("footwear.hiking_shoes", owner: "primary", in: output)
    #expect(hikingShoes.satisfiedCapabilities.contains(PackingCapability.everydayWalking.rawValue))
}

/// The counterexample that motivated the redesign: a rain jacket
/// satisfies windShell even when no windbreaker candidate was ever
/// generated to be suppressed — inverting coverageSuppressions could
/// never see this fact, because nothing was suppressed for windShell.
@Test func satisfiedCapabilitiesIncludesAGenuinelyMetNeedEvenWithoutAnyMatchingSuppression() throws {
    let engine = try makeEngine()
    let windyRain = weather(days: 5, start: try someDate(), highF: 58, lowF: 46, rain: 0.7, wind: 30)
    let generation = engine.generateDetailed(context: context(
        destination: try destination("Seattle"), activities: ["sightseeing"],
        bag: .checked, style: .balanced, weather: windyRain
    ))
    let rainJacket = try #require(generation.items.first { $0.canonicalItemID == "clothing.rain_jacket" })
    #expect(rainJacket.satisfiedCapabilities.contains(PackingCapability.windShell.rawValue))
    #expect(!generation.coverageSuppressions.contains { $0.covered.contains { $0.capability == .windShell } },
            "no suppression exists for windShell in this fixture — the fact must not depend on one")
}

@Test func bagStyleConstraintFactIsNilWhenTheRulingNeverLeftItsNoOpGuard() throws {
    // A checked bag never constrains space — every optional item's
    // ruling is trivial, so the fact stays nil for all of them.
    let output = try engineOutput(for: "04-tokyo-15d-prepared-checked")
    let book = try item("travel_comfort.book", owner: "primary", in: output)
    #expect(book.bagStyleConstraintFact == nil)
}

@Test func bagStyleConstraintFactRecordsEssentialTagProtectionOnASpaceConstrainedBag() throws {
    // A personal-item bag trims optionals unless the item is tagged
    // essential (rain/cold/medication/base) — an essential-tagged
    // optional item on this bag survives via protection, and the trace
    // must say so, not just "kept."
    let engine = try makeEngine()
    let generation = engine.generateDetailed(context: context(
        destination: try destination("Chicago"), bag: .personalItem, style: .light
    ))
    if let protectedItem = generation.items.first(where: {
        $0.bagStyleConstraintFact?.survivedByEssentialTagProtection == true
    }) {
        #expect(protectedItem.bagStyleConstraintFact?.wouldTrimUnderKey != nil)
    }
}

@Test func quantityReasonArgumentsNeverWritesAKeyOutsideTheClosedVocabulary() throws {
    let allowed: Set<String> = ["quantity", "days", "rate", "name", "travelerCount", "rainDays"]
    for fixture in try allGoldenFixtures() {
        for item in fixture.items {
            for key in item.quantityReasonArguments.keys {
                #expect(allowed.contains(key), "\(fixture.name): \(item.canonicalItemID ?? "?") wrote unlisted quantityReasonArguments key \(key)")
            }
        }
    }
}
```

Add a small `engineOutput(for:)`/`item(_:owner:in:)` test helper if
`GoldenEngineTests` doesn't already expose one at file scope (it likely
does something equivalent already for its own `quantityEvidence`
assertions at `:139-191` — reuse that helper, don't duplicate it). Add
`allGoldenFixtures()` similarly if a fixture-sweep helper doesn't already
exist (`scripts/audit_recommendation_traces.py`'s own sweep is the
Python-side precedent; this is its Swift-side equivalent, scoped to one
new invariant).

- [ ] **Step 2: Run and verify RED.** Compile failure —
  `quantityReasonArguments`/`satisfiedCapabilities`/`bagStyleConstraintFact`
  don't exist on `PackingItemDraft` yet, `PackingCapability.windShell`
  isn't yet reachable from a kept item's own trace.

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/GoldenEngineTests
```

- [ ] **Step 3: Add the three fields to `PackingItemDraft`** (`Catalog.swift:362-438`):

```swift
struct PackingItemDraft: Hashable, Identifiable, Codable, Sendable {
    // ... existing fields unchanged ...
    var quantityEvidence: ClothingQuantityEvidence?
    /// Structured arguments behind quantityReason for the non-clothing
    /// quantity families (care, warm-layer rotation, party sharing) — the
    /// same role reasonArguments already plays for the inclusion reason.
    /// Closed key vocabulary: quantity, days, rate, name, travelerCount,
    /// rainDays. Empty for fixed singletons and for the clothing family,
    /// which already has quantityEvidence.
    var quantityReasonArguments: [String: String] = [:]
    /// itemCapabilities[canonicalItemID] ∩ activeNeeds, computed once
    /// inside CoverageResolver.resolve's own resolution loop. Empty when
    /// this item's own capabilities don't intersect any currently-active
    /// need (most items, and every item outside the closed capability
    /// vocabulary).
    var satisfiedCapabilities: [String] = []
    /// Captured once, in PackingEngine.resolve, at the one
    /// ConstraintResolver.optionalRuling call that decides whether this
    /// item survives a space-constrained bag. Nil whenever that ruling
    /// never left its own no-op guard for this item.
    var bagStyleConstraintFact: BagStyleConstraintFact? = nil
    // ... existing fields unchanged ...
}

struct BagStyleConstraintFact: Hashable, Codable, Sendable {
    var survivedByEssentialTagProtection: Bool
    var wouldTrimUnderKey: String?
}
```

Add all three to the memberwise `init(...)` (`:397-437`) with the same
default values, so every existing call site across the app and test suite
keeps compiling unchanged.

- [ ] **Step 4: Widen `ConstraintResolver.OptionalRuling` and
  `optionalRuling(...)`** (`ConstraintResolver.swift:35-70`) — a
  behavior-preserving reorder that computes the would-be conflict key
  before the essential-tag check, so a tag-protected item's trace can
  still say what it was protected *from*:

```swift
struct OptionalRuling {
    var keep: Bool
    var conflictKey: String?
    var wasConstraintLive: Bool
    var essentialTagProtected: Bool
    var wouldTrimUnderKey: String?
}

static func optionalRuling(
    importance: ItemImportance,
    tags: [String],
    bag: BagType,
    style: PackingStyle
) -> OptionalRuling {
    guard importance == .optional,
          bag.appliesBagConstraint, bag.isSpaceConstrained else {
        return OptionalRuling(keep: true, conflictKey: nil, wasConstraintLive: false, essentialTagProtected: false, wouldTrimUnderKey: nil)
    }
    let wouldBeKey: String? = {
        if bag == .personalItem {
            return style == .prepared ? "style.prepared_vs_personal_item" : "bag.personal_item"
        }
        if style == .light { return "bag.space_constrained" }
        return nil
    }()
    let isEssentialOptional = tags.contains { essentialOptionalTags.contains($0) }
    if isEssentialOptional {
        return OptionalRuling(keep: true, conflictKey: nil, wasConstraintLive: true, essentialTagProtected: true, wouldTrimUnderKey: wouldBeKey)
    }
    if let wouldBeKey {
        return OptionalRuling(keep: false, conflictKey: wouldBeKey, wasConstraintLive: true, essentialTagProtected: false, wouldTrimUnderKey: wouldBeKey)
    }
    return OptionalRuling(keep: true, conflictKey: nil, wasConstraintLive: true, essentialTagProtected: false, wouldTrimUnderKey: nil)
}
```

**Verify byte-identical `keep`/`conflictKey` for every input** — add a
focused `ConstraintTests.swift` table test enumerating
`(importance, tags, bag, style)` combinations already implied by the
golden suite and asserting `keep`/`conflictKey` match today's behavior
exactly; this reorder must change zero observable ruling outcomes.

- [ ] **Step 5: Populate `bagStyleConstraintFact` in `resolve`**
  (`PackingEngine.swift:715-743`), immediately after computing `ruling`:

```swift
let ruling = ConstraintResolver.optionalRuling(
    importance: catalogItem.importance,
    tags: catalogItem.tags,
    bag: context.bagType,
    style: context.packingStyle
)
if !ruling.keep {
    if let key = ruling.conflictKey {
        drops.append((travelerID, catalogItem.id, key))
    }
    continue
}

result.append(
    PackingItemDraft(
        // ... existing fields unchanged ...
        bagStyleConstraintFact: ruling.wasConstraintLive
            ? BagStyleConstraintFact(
                survivedByEssentialTagProtection: ruling.essentialTagProtected,
                wouldTrimUnderKey: ruling.wouldTrimUnderKey
              )
            : nil
    )
)
```

Note this only fires in `resolve`'s **new-item** branch (`:728-743`) — an
item already on the list from a prior generation takes the
`existingItem`-merge branch (`:688-710`) and never re-runs `optionalRuling`
at all, so its `bagStyleConstraintFact` (if already set from when it was
first added) is carried forward unchanged by that branch, which touches
neither this field nor any field not explicitly listed at `:695-704`. This
is existing, correct, unchanged behavior — named here so the implementing
task doesn't "fix" it by adding an unrequested re-ruling on every
regeneration.

- [ ] **Step 6: Populate `satisfiedCapabilities` inside
  `CoverageResolver.resolve`** (`CoverageResolver.swift:222-290`) — not by
  `PackingEngine` inverting `coverageSuppressions` afterward:

```swift
static func resolve(
    items: [PackingItemDraft],
    needs: Set<PackingCapability>
) -> (kept: [PackingItemDraft], suppressions: [CoverageSuppression]) {
    var covered: [PackingCapability: String] = [:]
    var kept: [PackingItemDraft] = []
    var suppressions: [CoverageSuppression] = []
    // ... unchanged priority ordering ...

    for item in ordered {
        guard let canonical = item.canonicalItemID,
              let capabilities = itemCapabilities[canonical] else {
            kept.append(item)
            continue
        }
        let needed = capabilities.intersection(needs)
        if item.isUserAdded || item.isUserModified {
            var copy = item
            copy.satisfiedCapabilities = needed.map(\.rawValue).sorted()
            kept.append(copy)
            for capability in needed where covered[capability] == nil {
                covered[capability] = canonical
            }
            continue
        }
        if needed.isEmpty {
            if item.sourceSignals == [.weather] {
                suppressions.append(/* unchanged */)
            } else {
                kept.append(item)   // satisfiedCapabilities stays empty — correct
            }
            continue
        }
        if needed.allSatisfy({ covered[$0] != nil }) {
            suppressions.append(/* unchanged */)
            continue
        }
        var copy = item
        copy.satisfiedCapabilities = needed.map(\.rawValue).sorted()
        kept.append(copy)
        for capability in needed where covered[capability] == nil {
            covered[capability] = canonical
        }
    }
    return (kept, suppressions)
}
```

`PackingEngine.applyCoverage` (`:826-864`) needs **no** post-processing
pass — it already receives `kept` from `CoverageResolver.resolve` and
forwards it unchanged into `addCompanions`/`applyQuantities`;
`satisfiedCapabilities` simply arrives already set. Delete nothing else in
`applyCoverage`; its "versatile shoe reasonCode" special case (`:846-859`)
is unrelated and untouched.

- [ ] **Step 7: Populate `quantityReasonArguments` in `applyQuantities`.**
  Three call sites, each already building the argument dictionary it
  passes to `render(...)` — assign a **closed-vocabulary subset** of it to
  the field instead of discarding it after the render call:

  - Shared items (`PackingEngine.swift:901-921`): in the umbrella branch,
    set `copy.quantityReasonArguments = ["quantity": "\(quantity)",
    "rainDays": "\(weather.rainDays)"]`; in the generic branch, set
    `copy.quantityReasonArguments = ["quantity": "\(quantity)",
    "travelerCount": "\(party.travelers.count)"]` — dropping the
    unused `"partySize"` key name in favor of the closed vocabulary's
    `"travelerCount"`.
  - Care items (`:929-932`): `copy.quantityReasonArguments =
    care.arguments` — already exactly `{quantity, rate, name, days}` or
    `{quantity, name}`, both closed-vocabulary subsets, no filtering
    needed.
  - Warm layers (`:937-945`): `copy.quantityReasonArguments =
    warm.arguments` — already exactly `{quantity, days}`.

  The clothing branch (`:951-962`) is deliberately untouched —
  `quantityEvidence` already carries its structured facts; do not also
  populate `quantityReasonArguments` there (would be a redundant second
  representation of the same facts, and `washCycleDays`/`requiredUses`/
  `packingStyle`/`bag` are `ClothingQuantityEvidence`'s vocabulary, not
  this field's).

- [ ] **Step 8: Serialize all three fields into golden output.**
  `GoldenEngineTests.swift`'s `GoldenItem` struct (`:485-508`) gains three
  fields (placed after `quantityEvidence`):

```swift
private struct GoldenItem: Codable {
    // ... existing fields unchanged through quantityEvidence ...
    var quantityReasonArguments: [String: String]
    var satisfiedCapabilities: [String]
    var bagStyleConstraintFact: BagStyleConstraintFact?
    var userModified: Bool?
}
```

And the `serialize(...)` mapping (`:565-586`) passes all three through
unchanged (empty dict/array serializes as `{}`/`[]`; `nil` serializes as
absent/`null`, matching the existing convention for other optional
fields).

- [ ] **Step 9: Re-record every golden fixture and verify the zero-diff gate.**

```bash
PACKWISE_RECORD_GOLDENS=1 xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/GoldenEngineTests
PYTHONDONTWRITEBYTECODE=1 python3 scripts/report_engine_goldens.py \
  --baseline-ref eadc345 --candidate ios/PackWiseTests/Goldens --format markdown
```

Expected: the diff tool reports **zero** semantic changes — it diffs the
fields it already knows about, and the three new keys are additive JSON
fields it doesn't compare, not a change to any compared field. Confirm
this directly by also running `git diff --stat ios/PackWiseTests/Goldens`
and spot-checking a handful of files: every existing key's value is
byte-identical; only the three new keys are newly present, and no item's
presence/quantity/coverage/constraint outcome moved (this is the direct
proof that Step 4's `OptionalRuling` reorder and Step 6's `resolve`
restructuring are behavior-preserving, not just claimed to be).

- [ ] **Step 10: Run and verify GREEN.**

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/GoldenEngineTests \
  -only-testing:PackWiseTests/CoverageTests \
  -only-testing:PackWiseTests/ConstraintTests \
  -only-testing:PackWiseTests/ClothingQuantityTests
```

- [ ] **Step 11: Commit.**

```bash
git add ios/PackWise/Domain/Packing/Catalog.swift \
  ios/PackWise/Domain/Packing/CoverageResolver.swift \
  ios/PackWise/Domain/Packing/ConstraintResolver.swift \
  ios/PackWise/Domain/Packing/PackingEngine.swift \
  ios/PackWiseTests/GoldenEngineTests.swift ios/PackWiseTests/ConstraintTests.swift \
  shared/fixtures/golden/golden-fixtures.json ios/PackWiseTests/Goldens
git commit -m "feat: capture quantity arguments, satisfied capabilities, and bag/style constraint facts at generation time"
```

---

### Task 2: Persist the new trace fields on `PackingItemRecord`

**Files:**
- Modify: `ios/PackWise/Data/Persistence/Models.swift`

**Interfaces:**
- Consumes: `PackingItemDraft.quantityReasonArguments`,
  `.satisfiedCapabilities`, `.bagStyleConstraintFact` (Task 1).
- Produces: `PackingItemRecord.quantityReasonArgumentsRaw: String`,
  `.satisfiedCapabilitiesRaw: String`, `.bagStyleConstraintFactRaw:
  String`, and their decoded computed properties. **Does not yet touch
  `apply(_:)`** — Task 3 owns that, because fixing `apply(_:)`'s contract
  and giving it a real caller are one coherent change, not split across
  two tasks that would each leave it in a half-fixed state.

- [ ] **Step 1: Write the failing round-trip test.**

```swift
// A new PersistenceTests.swift test (or the existing persistence suite,
// grep for where PackingItemRecord round-trip tests already live).
@Test func newTraceFieldsRoundTripThroughPersistence() throws {
    var draft = PackingItemDraft(
        canonicalItemID: "footwear.hiking_shoes", displayName: "Hiking shoes",
        category: .footwear, quantity: 1, importance: .normal,
        sourceSignals: [.activity], reason: "Hiking is on your plans."
    )
    draft.quantityReasonArguments = ["quantity": "1", "days": "5"]
    draft.satisfiedCapabilities = ["footwear.everyday_walking"]
    draft.bagStyleConstraintFact = BagStyleConstraintFact(survivedByEssentialTagProtection: true, wouldTrimUnderKey: "bag.personal_item")

    let trip = TripRecord(/* existing test fixture constructor */)
    let record = PackingItemRecord(from: draft, trip: trip)
    #expect(record.draft.quantityReasonArguments == draft.quantityReasonArguments)
    #expect(record.draft.satisfiedCapabilities == draft.satisfiedCapabilities)
    #expect(record.draft.bagStyleConstraintFact == draft.bagStyleConstraintFact)
}
```

- [ ] **Step 2: Run and verify RED.** Compile failure or an empty-value
  assertion failure — the fields aren't persisted yet.

- [ ] **Step 3: Add the three raw storage fields and computed accessors**
  to `PackingItemRecord` (`Models.swift:187-232`), mirroring
  `reasonArgumentsRaw`'s pipe/equals convention and `sourceSignalsRaw`'s
  comma convention exactly. `bagStyleConstraintFactRaw` follows the same
  pipe-joined key=value convention as `reasonArgumentsRaw`, keyed by its
  two fixed field names:

```swift
final class PackingItemRecord {
    // ... existing fields unchanged through reasonArgumentsRaw ...
    var quantityReason: String
    var quantityReasonArgumentsRaw: String = ""
    var satisfiedCapabilitiesRaw: String = ""
    var bagStyleConstraintFactRaw: String = ""
    // ... existing fields unchanged ...

    var quantityReasonArguments: [String: String] {
        Dictionary(uniqueKeysWithValues: quantityReasonArgumentsRaw.split(separator: "|").compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return (parts[0], parts[1])
        })
    }
    var satisfiedCapabilities: [String] {
        satisfiedCapabilitiesRaw.isEmpty ? [] : satisfiedCapabilitiesRaw.split(separator: ",").map(String.init)
    }
    var bagStyleConstraintFact: BagStyleConstraintFact? {
        guard !bagStyleConstraintFactRaw.isEmpty else { return nil }
        var protected = false
        var wouldTrim: String?
        for pair in bagStyleConstraintFactRaw.split(separator: "|") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            if parts[0] == "survivedByEssentialTagProtection" { protected = parts[1] == "true" }
            if parts[0] == "wouldTrimUnderKey" { wouldTrim = parts[1].isEmpty ? nil : parts[1] }
        }
        return BagStyleConstraintFact(survivedByEssentialTagProtection: protected, wouldTrimUnderKey: wouldTrim)
    }
}
```

- [ ] **Step 4: Set all three in `init(from:trip:)`** (`:210-232`),
  immediately after the existing `reasonArgumentsRaw` line:

```swift
self.reasonArgumentsRaw = draft.reasonArguments.map { "\($0.key)=\($0.value)" }.joined(separator: "|")
self.quantityReasonArgumentsRaw = draft.quantityReasonArguments.map { "\($0.key)=\($0.value)" }.joined(separator: "|")
self.satisfiedCapabilitiesRaw = draft.satisfiedCapabilities.joined(separator: ",")
if let fact = draft.bagStyleConstraintFact {
    self.bagStyleConstraintFactRaw = "survivedByEssentialTagProtection=\(fact.survivedByEssentialTagProtection)|wouldTrimUnderKey=\(fact.wouldTrimUnderKey ?? "")"
}
```

- [ ] **Step 5: Add all three to `var draft: PackingItemDraft`**
  (`:242-267`), passing the decoded computed properties through as the new
  initializer parameters from Task 1's Step 3.

- [ ] **Step 6: Confirm no schema version bump is required.** All three
  new properties are defaulted (`= ""`) on an unchanged model type — the
  same shape `reasonCode: String = ""` already uses without a
  `PackWiseSchemaV4`. Build the app target and run the existing
  persistence/migration test suite to confirm SwiftData's lightweight
  automatic migration accepts the addition; if it does not (verify by
  actually running the app against a `PackWiseSchemaV3`-era store
  fixture, if one exists in the test suite), escalate to adding
  `PackWiseSchemaV4` with a `.lightweight` migration stage — do not
  silently skip this check.

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/PersistenceTests
```

(Substitute the actual persistence test target name — grep
`ios/PackWiseTests/` for the suite that already exercises
`PackWisePersistence.container` / migration if `PersistenceTests` isn't
it.)

- [ ] **Step 7: Run and verify GREEN, full suite.**

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

- [ ] **Step 8: Commit.**

```bash
git add ios/PackWise/Data/Persistence/Models.swift ios/PackWiseTests/
git commit -m "feat: persist quantity trace arguments, satisfied capabilities, and bag/style constraint facts on PackingItemRecord"
```

---

### Task 3: Fix the persisted-provenance refresh gap on regeneration (required amendment)

**Files:**
- Modify: `ios/PackWise/Domain/Packing/PackingEngine.swift`
- Modify: `ios/PackWise/Domain/Packing/Catalog.swift`
- Modify: `ios/PackWise/Data/Repositories/Repositories.swift`
- Modify: `ios/PackWise/Data/Persistence/Models.swift`
- Modify: `ios/PackWise/Domain/Weather/WeatherChangeReconciler.swift`
- Modify: `ios/PackWiseTests/PackingEngineTests.swift`
- Modify: `ios/PackWiseTests/WeatherChangeTests.swift`
- Create: `ios/PackWiseTests/RegenerationProvenanceTests.swift`

**Interfaces:**
- Consumes: `PackingEngine.generate(context:existing:overrides:)` (Phase
  7's already-correct merge machinery in `resolve`/`applyQuantities`,
  unchanged); Task 1/Task 2's new fields.
- Produces: a merge-aware `recommendationDiff` baseline; a widened
  `RecommendationDiff.quantityChanges` bucket (renamed in spirit, kept
  additive in shape) that flags a causal-fact change even when quantity
  is unchanged; `TripRepository.applyDiff` calling
  `PackingItemRecord.apply(_:)` for real, for the first time; a corrected
  `apply(_:)` refresh contract.

**Grounding, reproduced live, not assumed:** `grep -rn "\.apply("
ios/PackWise --include="*.swift"` finds `PackingItemRecord.apply(_:)`
(`Models.swift:269-280`) has **zero call sites** anywhere in the app
target, and `grep -rn "\.apply(" ios/PackWiseTests` finds none in the test
suite either. The original design's premise — that this method is the
live regeneration-merge mechanism, already refreshing `reason`/
`quantityReason` but missing `reasonCode`/`sourceSignals` — describes a
method that isn't called at all. The real gap is worse: the actual
regeneration path (`TripSetupView.saveTrip()`'s existing-trip branch →
`PackingEngine.recommendationDiff` → `TripRepository.applyDiff`) leaves an
item whose quantity is unchanged but whose cause changed **completely
untouched** — not "missing two fields," untouched entirely. See the design
doc's "Persistence" section for the full trace.

- [ ] **Step 1: Write the failing regression test**, reproducing the
  staleness bug live before touching production code.

```swift
// RegenerationProvenanceTests.swift

/// Amendment 3's required scenario: a trip generates with Hiking, an item
/// carries activity.hiking evidence; the user removes Hiking and adds a
/// different activity that independently keeps the item on the list under
/// a new cause; regenerating must refresh reasonCode/sourceSignals/trace
/// fields to the new cause, not leave them pointing at Hiking — while
/// packed state, manual quantity, Not Needed, and explicit carrier
/// assignment on OTHER items in the same regeneration are untouched.
@Test func regenerationRefreshesCausalFieldsButNeverExplicitUserState() throws {
    let engine = try makeEngine()
    let repository = TripRepository(context: try makeInMemoryContext())

    let hikingContext = context(destination: try destination("Denver"), activities: ["hiking"])
    let initial = engine.generate(context: hikingContext)
    let trip = TripRecord(/* ... */)
    repository.attach(party: hikingContext.effectiveParty, bagType: hikingContext.bagType, on: trip)
    repository.replaceItems(on: trip, with: initial)

    // Pin the item under test, and pin three unrelated items into every
    // explicit-user-state category the non-touch list names.
    let boots = try #require(trip.items.first { $0.canonicalItemID == "footwear.hiking_shoes" })
    #expect(boots.reasonCode == "activity.hiking")

    if let packed = trip.items.first(where: { $0.canonicalItemID == "clothing.tshirt" }) {
        packed.packedQuantity = packed.quantity
    }
    if let manual = trip.items.first(where: { $0.canonicalItemID == "clothing.underwear" }) {
        manual.isUserModified = true
        manual.quantity = 11
    }
    let notNeededCandidate = try #require(trip.items.first { $0.canonicalItemID == "essentials.sunglasses" })
    repository.markNotNeeded(notNeededCandidate, on: trip)
    if let carried = trip.items.first(where: { $0.canonicalItemID == "toiletries.sunscreen" }) {
        carried.assignedTravelerID = UUID()
    }
    let pinnedPackedQuantity = trip.items.first { $0.canonicalItemID == "clothing.tshirt" }?.packedQuantity
    let pinnedManualQuantity = trip.items.first { $0.canonicalItemID == "clothing.underwear" }?.quantity
    let pinnedCarrier = trip.items.first { $0.canonicalItemID == "toiletries.sunscreen" }?.assignedTravelerID

    // Regenerate: Hiking removed, Camping added — footwear.hiking_shoes
    // must independently survive under Camping's own activity rule (or a
    // base-essential/coverage rule), not Hiking's.
    var edited = hikingContext
    edited.activities = ["camping"]
    let existingDrafts = trip.items.map(\.draft)
    let overrides = trip.overrides.map(\.draft)
    let diff = engine.recommendationDiff(context: edited, existing: existingDrafts, overrides: overrides)
    repository.applyDiff(
        diff,
        addIDs: Set(diff.add.map(\.id)),
        removeIDs: Set(diff.removeCandidates.map(\.id)),
        quantityIDs: Set(diff.quantityChanges.map(\.existing.id)),
        on: trip
    )

    let refreshedBoots = try #require(trip.items.first { $0.canonicalItemID == "footwear.hiking_shoes" })
    #expect(refreshedBoots.reasonCode != "activity.hiking", "the stale Hiking cause must not survive")
    #expect(!refreshedBoots.sourceSignals.isEmpty)

    #expect(trip.items.first { $0.canonicalItemID == "clothing.tshirt" }?.packedQuantity == pinnedPackedQuantity)
    #expect(trip.items.first { $0.canonicalItemID == "clothing.underwear" }?.quantity == pinnedManualQuantity)
    #expect(!trip.items.contains { $0.canonicalItemID == "essentials.sunglasses" }, "Not Needed must still hold")
    #expect(trip.items.first { $0.canonicalItemID == "toiletries.sunscreen" }?.assignedTravelerID == pinnedCarrier)
}
```

(Substitute the project's actual in-memory `ModelContext`/`TripRecord`
test-fixture helpers — grep `ios/PackWiseTests/` for how
`PersistenceTests`/`RepositoriesTests` already construct one, reuse it,
don't duplicate it. If `footwear.hiking_shoes` does not independently
survive under Camping in the real rule data, substitute a canonical item
that the fixture data actually keeps under both activities for a
different reason — the requirement is "same item, quantity possibly
unchanged, cause changed," not this specific item id.)

- [ ] **Step 2: Run and verify RED.** `refreshedBoots.reasonCode` still
  reads `"activity.hiking"` — the item was never touched by `applyDiff`
  because its quantity didn't change, reproducing the staleness gap live.

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/RegenerationProvenanceTests
```

- [ ] **Step 3: Make `recommendationDiff`'s internal baseline
  merge-aware** (`PackingEngine.swift:66-89`, specifically `:71`):

```diff
 func recommendationDiff(
     context: TripContext,
     existing: [PackingItemDraft],
     overrides: [RecommendationOverrideDraft]
 ) -> RecommendationDiff {
-    let generated = generate(context: context, existing: [], overrides: overrides)
+    let generated = generate(context: context, existing: existing, overrides: overrides)
     ...
```

This reuses `resolve`'s already-correct existing-item merge branch
(`:688-710` — refreshes `reason`/`reasonCode`/`reasonArguments`/
`sourceSignals`/`ownershipType`/`travelerID`, preserves `id`/
`packedQuantity`, preserves an already-set `assignedTravelerID`) and
`applyQuantities`'s already-correct `hasUserAuthority` short-circuit,
instead of diffing against a from-scratch generation that discards all of
that. Run `PackingEngineTests.swift`'s four existing `recommendationDiff`
tests (`:607-723`) immediately after this one-line change and confirm
each still passes with its existing assertions unchanged — this is the
proof the change is safe before widening anything else.

- [ ] **Step 4: Widen the per-item comparison and
  `QuantityChangeSuggestion`** (`PackingEngine.swift:81-87`, `:108-114`;
  `Catalog.swift:440-443`):

```swift
struct QuantityChangeSuggestion: Hashable, Codable, Sendable {
    var existing: PackingItemDraft
    var fresh: PackingItemDraft
    var suggestedQuantity: Int { fresh.quantity }
}
```

```swift
// recommendationDiff's per-item loop, both generateForParty- and
// generateSimple-shaped variants (:81-87, :108-114):
} else if let fresh = generatedByKey[item.recommendationKey], item.causallyDiffers(from: fresh) {
    quantityChanges.append(QuantityChangeSuggestion(existing: item, fresh: fresh))
}
```

`causallyDiffers` is placed as a `static`/instance-independent extension
on `PackingItemDraft` itself (`Catalog.swift`, next to `recommendationKey`)
— not a `private func` on `PackingEngine` — because **Step 4a below finds
a second caller that needs the exact same predicate**, and duplicating it
would let the two call sites silently drift apart:

```swift
// Catalog.swift, extension PackingItemDraft
func causallyDiffers(from fresh: PackingItemDraft) -> Bool {
    quantity != fresh.quantity
        || reasonCode != fresh.reasonCode
        || reasonArguments != fresh.reasonArguments
        || sourceSignals != fresh.sourceSignals
        || quantityReason != fresh.quantityReason
        || quantityReasonArguments != fresh.quantityReasonArguments
        || satisfiedCapabilities != fresh.satisfiedCapabilities
        || bagStyleConstraintFact != fresh.bagStyleConstraintFact
}
```

Update every existing reference to `QuantityChangeSuggestion.item`
(`RecommendationDiffSheet.swift`, `WeatherChangeReconciler.swift`,
`DebugPreviewScene.swift`, and `WeatherChangeTests.swift`/
`PackingEngineTests.swift`'s assertions) to `.existing`, confirmed by
`grep -rn "QuantityChangeSuggestion\|\.quantityChanges\b" ios/PackWise
ios/PackWiseTests` — every real call site, not assumed to be only the diff
sheet.

- [ ] **Step 4a: Widen `WeatherChangeReconciler.prune`'s re-validation to
  match — a second real caller found by tracing the chain, not
  optional.** `prune` (`WeatherChangeReconciler.swift:166-190`) re-checks
  a *pending* weather-driven diff against the trip's *current* state
  before it's shown to the user (the trip may have changed between the
  proposal being generated and the user opening it). Its quantity-change
  filter (`:186-189`) is exactly as narrow as the bug this task fixes:

```diff
     let quantityChanges = diff.quantityChanges.filter { change in
-        guard let current = existing.first(where: { $0.id == change.item.id }) else { return false }
-        return !current.isUserModified && current.quantity != change.suggestedQuantity
+        guard let current = existing.first(where: { $0.id == change.existing.id }) else { return false }
+        return !current.isUserModified && current.causallyDiffers(from: change.fresh)
     }
```

Left unwidened, this filter would silently drop exactly the causal-only
(quantity-unchanged) refresh this task exists to fix, for the one path
that routes through a weather-change proposal instead of a direct trip
edit — `current.quantity != change.suggestedQuantity` is false whenever
quantity didn't move, so the item is pruned away before it ever reaches
`applyDiff`, regardless of how visibly its cause changed. Also update
`previewNames`/`packingConsequenceKey` (`:39-44`, `:236-244`) to read
`change.existing`/`.fresh` in place of `change.item`, same rename as Step
4.

- [ ] **Step 5: Correct `PackingItemRecord.apply(_:)`'s refresh contract**
  (`Models.swift:269-280`) — the fields that must refresh together as one
  unit, and the explicit user-state fields that must never be touched by
  this method:

```swift
func apply(_ draft: PackingItemDraft) {
    quantity = draft.quantity
    reason = draft.reason
    reasonCode = draft.reasonCode
    reasonArgumentsRaw = draft.reasonArguments.map { "\($0.key)=\($0.value)" }.joined(separator: "|")
    sourceSignalsRaw = draft.sourceSignals.map(\.rawValue).joined(separator: ",")
    quantityReason = draft.quantityReason
    quantityReasonArgumentsRaw = draft.quantityReasonArguments.map { "\($0.key)=\($0.value)" }.joined(separator: "|")
    satisfiedCapabilitiesRaw = draft.satisfiedCapabilities.joined(separator: ",")
    if let fact = draft.bagStyleConstraintFact {
        bagStyleConstraintFactRaw = "survivedByEssentialTagProtection=\(fact.survivedByEssentialTagProtection)|wouldTrimUnderKey=\(fact.wouldTrimUnderKey ?? "")"
    } else {
        bagStyleConstraintFactRaw = ""
    }
    isUserModified = draft.isUserModified
    ownershipTypeRaw = draft.ownershipType.rawValue
    travelerID = draft.travelerID
    assignedTravelerID = draft.assignedTravelerID
    bagID = draft.bagID
    updatedAt = .now
    // packedQuantity is deliberately NOT set here — explicit user state
    // (packed count) must survive a causal refresh untouched. The
    // draft's own packedQuantity is already the preserved value (Step 3
    // made the baseline merge-aware), so this is a real behavior
    // decision, not an oversight: this method never resets packed state
    // even when handed a draft whose packedQuantity happens to match.
}
```

- [ ] **Step 6: Wire `TripRepository.applyDiff` to call `apply(_:)`**
  (`Repositories.swift:232-260`), replacing the ad hoc quantity mutation:

```diff
     for change in diff.quantityChanges where quantityIDs.contains(change.item.id) {
-        if let record = trip.items.first(where: { $0.id == change.item.id }) {
-            record.quantity = change.suggestedQuantity
-            if record.packedQuantity > record.quantity {
-                record.packedQuantity = record.quantity
-            }
-            record.updatedAt = .now
-        }
+        if let record = trip.items.first(where: { $0.id == change.existing.id }) {
+            record.apply(change.fresh)
+            if record.packedQuantity > record.quantity {
+                record.packedQuantity = record.quantity
+            }
+        }
     }
```

The packed-quantity clamp is preserved exactly as today — applied *after*
`apply(_:)`, in `applyDiff`, not folded into `apply(_:)` itself, so
`apply(_:)`'s own contract stays "never touches packed state" while the
one call site that legitimately needs a downward safety clamp (quantity
just decreased below what's already packed) still gets it, unchanged from
today's behavior.

- [ ] **Step 7: Run and verify GREEN**, both the new regression test and
  every existing `recommendationDiff`/`applyDiff` test:

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/RegenerationProvenanceTests \
  -only-testing:PackWiseTests/PackingEngineTests \
  -only-testing:PackWiseTests/RepositoriesTests
```

(Substitute the actual repository test suite name if `RepositoriesTests`
isn't it — grep for `applyDiff`/`markNotNeeded` test coverage.)

- [ ] **Step 8: Golden-fixture sanity check.** This task does not touch
  `PackingEngine.generate`'s output shape (only `recommendationDiff`'s
  internal baseline and the persistence-layer application of its diff), so
  `report_engine_goldens.py --baseline-ref eadc345` must report **zero**
  change. Run it anyway, not assumed:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 scripts/report_engine_goldens.py \
  --baseline-ref eadc345 --candidate ios/PackWiseTests/Goldens --format markdown
```

- [ ] **Step 9: Commit.**

```bash
git add ios/PackWise/Domain/Packing/PackingEngine.swift \
  ios/PackWise/Domain/Packing/Catalog.swift \
  ios/PackWise/Data/Repositories/Repositories.swift \
  ios/PackWise/Data/Persistence/Models.swift \
  ios/PackWise/Domain/Weather/WeatherChangeReconciler.swift \
  ios/PackWiseTests/PackingEngineTests.swift ios/PackWiseTests/RegenerationProvenanceTests.swift \
  ios/PackWiseTests/WeatherChangeTests.swift
git commit -m "fix: refresh persisted causal provenance on regeneration, not just quantity"
```

---

### Task 4: Fix the `party.shared` pluralization (routed finding)

**Files:**
- Modify: `shared/rules/reasons.json`
- Modify: `ios/PackWise/Domain/Packing/PackingEngine.swift`
- Modify: `ios/PackWiseTests/ConstraintTests.swift`
- Modify: `shared/fixtures/golden/golden-fixtures.json`, `ios/PackWiseTests/Goldens/37-family4-5d-hiking-camping-outdoor.json`

**Interfaces:**
- Consumes: `ConstraintResolver.SharingResolution`'s `quantity`
  (`ConstraintResolver.swift:120-125`, unchanged).
- Produces: correctly pluralized `party.shared` copy for any shared
  quantity, derived from that same `quantity`, matching
  `party.shared_umbrella`'s established pattern.

- [ ] **Step 1: Write the failing test**, reproducing the bug directly
  against the live fixture-37 scenario before touching production code.

```swift
/// Scenario 12 (Phase 8 required scenarios): a shared quantity greater
/// than one must not render "One for the group" — the routed finding
/// from Phase 7's closure (docs/plans/2026-09-02-product-hardening-program.md,
/// Phase 7 closure section). Sunscreen for a family of 4
/// (scaleByParty, per:3) resolves to quantity 2 today; the reason text
/// must say "2", not "One".
@Test func sharedQuantityGreaterThanOneIsNotDescribedAsOneForTheGroup() throws {
    let engine = try makeEngine()
    let family = TripParty(travelMode: .family, travelers: [
        Traveler.primarySelf(), Traveler(name: "Sam", role: .partner, ageGroup: .adult),
        Traveler(name: "Jo", role: .child, ageGroup: .child),
        Traveler(name: "Em", role: .child, ageGroup: .toddler)
    ])
    let items = engine.generate(context: try campingContext(activities: ["hiking", "camping"], party: family))
    let sunscreen = try #require(items.first { $0.canonicalItemID == "toiletries.sunscreen" })
    #expect(sunscreen.quantity == 2, "ceil(4/3) = 2 — unchanged by this fix")
    #expect(sunscreen.quantityReason == "2 for the group — not one per person.")
    #expect(!sunscreen.quantityReason.localizedCaseInsensitiveContains("one for the group"))
    #expect(sunscreen.quantityReasonArguments["quantity"] == "2")
    #expect(sunscreen.quantityReasonArguments["travelerCount"] == "4")
}

/// The quantity==1 case must still read "One", not "1" — the wording
/// this fix must not regress.
@Test func sharedQuantityOfOneStillReadsAsOneForTheGroup() throws {
    let engine = try makeEngine()
    let items = engine.generate(context: context(destination: try destination("Chicago"), party: .solo()))
    let firstAid = try #require(items.first { $0.canonicalItemID == "health.first_aid" })
    #expect(firstAid.quantityReason == "One for the group — not one per person.")
}
```

- [ ] **Step 2: Run and verify RED.** `sharedQuantityGreaterThanOneIsNotDescribedAsOneForTheGroup`
  fails: `quantityReason` reads `"One for the group — not one per person."`
  instead of `"2 for the group — not one per person."` — reproducing the
  routed finding as a failing test, not by inspection alone.

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/ConstraintTests
```

- [ ] **Step 3: Fix `reasons.json`'s template.**

```diff
-    "party.shared": "One for the group — not one per person.",
+    "party.shared": "{quantityPhrase} for the group — not one per person.",
```

- [ ] **Step 4: Build the pre-pluralized phrase argument at the call
  site**, `PackingEngine.applyQuantities`'s non-umbrella shared branch
  (`:913-919`), mirroring the umbrella branch immediately above it
  (`:905-912`) exactly. Note the template argument (`quantityPhrase`, for
  rendering) and the trace argument (`quantity`, for
  `quantityReasonArguments`, per Task 1's closed vocabulary) are two
  different things with two different keys — do not conflate them:

```swift
} else {
    let quantityPhrase = quantity == 1 ? "One" : "\(quantity)"
    copy.quantityReason = render(
        "party.shared",
        ["quantityPhrase": quantityPhrase],
        fallback: fallback
    )
    copy.quantityReasonArguments = ["quantity": "\(quantity)", "travelerCount": "\(party.travelers.count)"]
}
```

- [ ] **Step 5: Run and verify GREEN.**

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/ConstraintTests
```

- [ ] **Step 6: Re-record fixture 37 and confirm the diff is scoped to
  exactly the two shared-item wording changes.**

```bash
PACKWISE_RECORD_GOLDENS=1 xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/GoldenEngineTests
PYTHONDONTWRITEBYTECODE=1 python3 scripts/report_engine_goldens.py \
  --baseline-ref eadc345 --candidate ios/PackWiseTests/Goldens --format markdown
git diff ios/PackWiseTests/Goldens/37-family4-5d-hiking-camping-outdoor.json
```

Expected: the semantic diff tool shows exactly two `quantityReason` text
changes in fixture 37 (`toiletries.sunscreen` "One" → "2",
`toiletries.insect_repellent` — confirm its resolved quantity: if it is
also >1 under `scaleByParty`, its text changes too; if it resolves to 1,
its text is unchanged, since "One for the group" is still correct at
quantity 1). Every other fixture, every other row in fixture 37 (item
identities, quantities, `satisfiedCapabilities` from Task 1, coverage,
constraints), byte-identical. This is the plan's one **approved,
reviewed** golden diff — review it explicitly, do not skip the manual
`git diff` inspection even though the automated tool reports it as
expected.

- [ ] **Step 7: Commit.**

```bash
git add shared/rules/reasons.json ios/PackWise/Domain/Packing/PackingEngine.swift \
  ios/PackWiseTests/ConstraintTests.swift ios/PackWiseTests/Goldens/37-family4-5d-hiking-camping-outdoor.json
git commit -m "fix: pluralize the party.shared reason for a shared quantity greater than one"
```

---

### Task 5: `RecommendationTrace` — a pure read layer, no live re-calls

**Files:**
- Create: `ios/PackWise/Domain/Packing/RecommendationTrace.swift`
- Create: `ios/PackWiseTests/RecommendationTraceTests.swift`

**Interfaces:**
- Consumes: `PackingItemDraft.reasonCode/.sourceSignals/.quantity/
  .quantityReason/.quantityReasonArguments/.quantityEvidence/
  .satisfiedCapabilities/.bagStyleConstraintFact/.isUserAdded/
  .isUserModified/.canonicalItemID/.ownershipType` — every field either
  pre-existing or populated by Task 1, all generation-time facts.
- Produces: `RecommendationTrace.InclusionFamily`,
  `.inclusionFamily(reasonCode:signals:)`, `.QuantityFacet`,
  `.ConstraintFacet`, `.CoverageFacet`, `.Authority` — all pure field
  reads. **No function in this file takes a `catalog`, `rules`, `context`,
  or `party` parameter — that is the structural proof this facet layer
  never re-derives a decision, checked by the type signatures themselves,
  not just by convention.** This supersedes the original design's
  `ConstraintFacet.constraintFacet(for:catalog:rules:context:party:)`,
  which re-called `ConstraintResolver.optionalRuling`/`.sharingResolution`
  live — a required amendment, not a refinement.

- [ ] **Step 1: Write the failing classification tests**, covering every
  `reasonCode` prefix actually present in `reasons.json` (not a
  hand-picked subset) plus the user-authority and unknown-prefix cases,
  and the redesigned constraint/coverage facets.

```swift
// RecommendationTraceTests.swift

@Test func inclusionFamilyCoversEveryReasonCodePrefixInTheTemplateFile() throws {
    let templates = try SharedLibrary.rules().reasons.templates
    let expectations: [String: RecommendationTrace.InclusionFamily] = [
        "base.essential.clothing": .baseEssential,
        "weather.seasonal_sun": .weatherSeasonal,
        "weather.rain_days": .weatherPrecise,
        "activity.hiking": .activity,
        "party.shared": .party,
        "dependency.companion": .dependency,
        "preference.usuallyWorkOut": .personalPreference,
        "trip_type.generic": .tripType,
        "destination.international": .destination,
        "documents.visa_check": .documents,
        "flight.empty_bottle": .flight,
        "substitution.hiking_covers_walking": .substitution
    ]
    for (code, expected) in expectations {
        #expect(templates[code] != nil, "\(code) must be a real reasons.json key — the test itself would be meaningless otherwise")
        #expect(RecommendationTrace.inclusionFamily(reasonCode: code, signals: []) == expected)
    }
}

@Test func inclusionFamilyIsUserAuthorityForAnEmptyReasonCode() {
    #expect(RecommendationTrace.inclusionFamily(reasonCode: "", signals: []) == .userAuthority)
}

@Test func everyReasonCodeInTheTemplateFileClassifiesToAKnownFamilyNotTheFallback() throws {
    let templates = try SharedLibrary.rules().reasons.templates
    let categoryAndImpactAndQuantityPrefixes = ["category.", "impact.", "quantity.", "context."]
    for code in templates.keys where !categoryAndImpactAndQuantityPrefixes.contains(where: code.hasPrefix) {
        let family = RecommendationTrace.inclusionFamily(reasonCode: code, signals: [])
        #expect(family != .tripType || code.hasPrefix("trip_type."), "\(code) unexpectedly fell through to the fallback family")
    }
}

@Test func constraintFacetIsAPureFieldReadWithNoDecisionDependency() throws {
    // Structural proof, not just documentation: read(from:) takes only a
    // PackingItemDraft — there is no way to pass it a catalog, rules,
    // context, or party even if a future edit wanted to.
    let output = try engineOutput(for: "29-yellowstone-4d-hiking-camping")
    let hikingShoes = try item("footwear.hiking_shoes", owner: "primary", in: output)
    let facet = RecommendationTrace.ConstraintFacet.read(from: hikingShoes)
    #expect(facet.sharing == nil, "a personal item is never .shared")
}

@Test func constraintFacetReconstructsSharingFromStoredFieldsNotALiveCall() throws {
    let output = try engineOutput(for: "38-couple-5d-seattle-shared-umbrella")
    let umbrella = try item("essentials.umbrella_compact", owner: "shared", in: output)
    let facet = RecommendationTrace.ConstraintFacet.read(from: umbrella)
    if case .shared(let quantity, let reason) = facet.sharing {
        #expect(quantity == umbrella.quantity)
        #expect(reason == umbrella.quantityReason)
    } else {
        Issue.record("expected a shared resolution reconstructed from item.quantity/quantityReason")
    }
}

@Test func coverageFacetReadsSatisfiedCapabilitiesDirectly() throws {
    let output = try engineOutput(for: "29-yellowstone-4d-hiking-camping")
    let hikingShoes = try item("footwear.hiking_shoes", owner: "primary", in: output)
    let facet = RecommendationTrace.CoverageFacet(satisfiedCapabilities: hikingShoes.satisfiedCapabilities)
    #expect(facet.satisfiedCapabilities.contains(PackingCapability.everydayWalking.rawValue))
}
```

- [ ] **Step 2: Run and verify RED.** Compile failure —
  `RecommendationTrace` doesn't exist yet.

- [ ] **Step 3: Create `RecommendationTrace.swift`** with the shape from
  the design doc's Architecture section (`InclusionFamily`,
  `inclusionFamily(reasonCode:signals:)`, `QuantityFacet`,
  `ConstraintFacet`, `CoverageFacet`, `Authority`). Copy the design doc's
  snippets verbatim:

```swift
enum RecommendationTrace {
    enum InclusionFamily: String, Hashable, Sendable {
        case baseEssential, tripType, activity, weatherPrecise, weatherSeasonal
        case party, dependency, personalPreference, destination, documents
        case flight, substitution, userAuthority
    }

    static func inclusionFamily(reasonCode: String, signals: [RecommendationSignal]) -> InclusionFamily {
        if reasonCode.isEmpty { return .userAuthority }
        if reasonCode.hasPrefix("base.essential.") { return .baseEssential }
        if reasonCode.hasPrefix("weather.seasonal") { return .weatherSeasonal }
        if reasonCode.hasPrefix("weather.") { return .weatherPrecise }
        if reasonCode.hasPrefix("activity.") { return .activity }
        if reasonCode.hasPrefix("party.") { return .party }
        if reasonCode.hasPrefix("dependency.") { return .dependency }
        if reasonCode.hasPrefix("preference.") { return .personalPreference }
        if reasonCode.hasPrefix("trip_type.") { return .tripType }
        if reasonCode.hasPrefix("destination.") { return .destination }
        if reasonCode.hasPrefix("documents.") { return .documents }
        if reasonCode.hasPrefix("flight.") { return .flight }
        if reasonCode.hasPrefix("substitution.") { return .substitution }
        return .tripType
    }

    struct QuantityFacet: Hashable, Sendable {
        var value: Int
        var isFixedSingleton: Bool
        var clothingEvidence: ClothingQuantityEvidence?
        var reason: String
        var reasonArguments: [String: String]
    }

    struct ConstraintFacet: Hashable, Sendable {
        var bagStyle: BagStyleConstraintFact?
        var sharing: ConstraintResolver.SharingResolution?

        static func read(from item: PackingItemDraft) -> ConstraintFacet {
            ConstraintFacet(
                bagStyle: item.bagStyleConstraintFact,
                sharing: item.ownershipType == .shared
                    ? .shared(quantity: item.quantity, reason: item.quantityReason)
                    : nil
            )
        }
    }

    struct CoverageFacet: Hashable, Sendable {
        var satisfiedCapabilities: [String]
    }

    struct Authority: Hashable, Sendable {
        var isUserAdded: Bool
        var isUserModified: Bool
        var isCustomItem: Bool
    }
}

extension RecommendationTrace {
    static func quantityFacet(for item: PackingItemDraft) -> QuantityFacet {
        let isFixedSingleton = item.quantity == 1
            && item.ownershipType != .shared
            && item.quantityEvidence == nil
            && item.quantityReasonArguments.isEmpty
        return QuantityFacet(
            value: item.quantity,
            isFixedSingleton: isFixedSingleton,
            clothingEvidence: item.quantityEvidence,
            reason: item.quantityReason,
            reasonArguments: item.quantityReasonArguments
        )
    }

    static func coverageFacet(for item: PackingItemDraft) -> CoverageFacet {
        CoverageFacet(satisfiedCapabilities: item.satisfiedCapabilities)
    }

    static func authority(for item: PackingItemDraft) -> Authority {
        Authority(
            isUserAdded: item.isUserAdded,
            isUserModified: item.isUserModified,
            isCustomItem: item.canonicalItemID?.hasPrefix("custom.") ?? (item.canonicalItemID == nil)
        )
    }
}
```

- [ ] **Step 4: Run and verify GREEN.**

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/RecommendationTraceTests
```

- [ ] **Step 5: Commit.**

```bash
git add ios/PackWise/Domain/Packing/RecommendationTrace.swift ios/PackWiseTests/RecommendationTraceTests.swift
git commit -m "feat: add RecommendationTrace as a pure read layer over generation-time facts"
```

---

### Task 6: Wire Item Detail to the productized trace

**Files:**
- Modify: `ios/PackWise/Features/TripDetail/PackingListView.swift`

**Interfaces:**
- Consumes: `RecommendationTrace.inclusionFamily`/`.quantityFacet`/
  `.ConstraintFacet.read(from:)`/`.coverageFacet`/`.authority` (Task 5),
  `PackingItemRecord.draft` (Task 2 fields included).
- Produces: Item Detail's existing "Why it's on your list" section
  (`ItemDetailView.reasons`, `PackingListView.swift:778-808`) shows the
  quantity's structured basis (clothing evidence or the new
  `quantityReasonArguments`-backed families) and — new — a compact
  authority line, without changing the section's structure. **Item Detail
  reads `RecommendationTrace`'s output only — it never calls
  `PackingEngine`, `CoverageResolver`, `ConstraintResolver`, or
  `WeatherSignalExtractor` directly, for any facet** (this was implicit
  before the amendment; it is now the explicit, checked contract).

- [ ] **Step 1: Write the failing UI-model test.** `PackingListView.swift`
  has no existing snapshot/UI test target reachable from this plan's file
  list — test the *presentation-derivation function* directly (the same
  level `PackingReasonPresentation.inclusionReason` is already tested at,
  if a test exists for it; if not, this is the first one, following its
  exact pattern).

```swift
// RecommendationTraceTests.swift, continued

@Test func userAuthorityRowsPresentAsUserDecidedNotEngineGenerated() throws {
    var manual = PackingItemDraft(canonicalItemID: "clothing.tshirt", displayName: "T-Shirts", category: .clothing, quantity: 3, importance: .normal, sourceSignals: [], reason: "")
    manual.isUserModified = true
    let authority = RecommendationTrace.authority(for: manual)
    #expect(authority.isUserModified)
    #expect(!authority.isUserAdded)
}

@Test func clothingQuantityFacetPrefersStructuredEvidenceOverBareReasonText() throws {
    let output = try engineOutput(for: "02-tokyo-15d-light-laundry-possible")
    let tshirt = try item("clothing.tshirt", owner: "primary", in: output)
    let facet = RecommendationTrace.quantityFacet(for: tshirt)
    #expect(facet.clothingEvidence != nil)
    #expect(facet.isFixedSingleton == false)
}
```

- [ ] **Step 2: Run and verify RED or honest GREEN** (some of this may
  already pass purely from Task 5's facet functions — record the actual
  result).

- [ ] **Step 3: Add a presentation-derivation extension** next to
  `PackingReasonPresentation` (`PackingListView.swift:16-40`):

```swift
enum PackingTracePresentation {
    /// One short, honest line distinguishing a user's own decision from
    /// the engine's — never invents provenance for a user-authority row.
    static func authorityLine(_ authority: RecommendationTrace.Authority) -> String? {
        if authority.isCustomItem { return "Added by you." }
        if authority.isUserModified { return "You changed this." }
        if authority.isUserAdded { return "Added by you." }
        return nil
    }
}
```

- [ ] **Step 4: Wire `ItemDetailView.reasons`** (`:778-808`) to show the
  authority line (when present) ahead of the existing reason text — the
  existing `Text(item.quantityReason)` line (`:789`) already shows the
  rendered sentence; do not duplicate it with raw structured data. Add
  one line only:

```swift
if let authorityLine = PackingTracePresentation.authorityLine(
    RecommendationTrace.authority(for: item.draft)
) {
    Text(authorityLine)
        .font(.caption)
        .foregroundStyle(PackWiseColor.textSecondary)
}
```

placed inside the existing `PackWiseCard` (`:781-806`), above
`Text(item.reason.isEmpty ? "Added for this trip." : presentedReason)`
(`:783`) — no new card, no new section header, no layout change beyond
one conditional line.

- [ ] **Step 5: Run and verify GREEN**, plus a manual simulator check per
  the `run` skill (Item Detail for a user-added item, a manually-edited
  item, and an ordinary engine-generated item — confirm the new line
  appears only for the first two).

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/RecommendationTraceTests
```

- [ ] **Step 6: Commit.**

```bash
git add ios/PackWise/Features/TripDetail/PackingListView.swift
git commit -m "feat: wire Item Detail to the productized recommendation trace"
```

---

### Task 7: Strengthen `scripts/audit_recommendation_traces.py`, and refine the exit metric

**Files:**
- Modify: `scripts/audit_recommendation_traces.py`
- Modify: `scripts/tests/test_audit_recommendation_traces.py`
- Modify: `scripts/run_engine_audit.sh`

**Interfaces:**
- Consumes: the existing `TraceItem`/golden JSON schema (Task 1 adds three
  new keys the script does not need to read for the two structural
  checks below).
- Produces: two new defect buckets — `invalid_seasonal_provenance`,
  `fabricated_user_authority_provenance` — folded into `Report.is_clean`
  and `--strict`'s exit code; a closed-key-vocabulary check for
  `quantityReasonArguments`; and the refined exit-metric wording.

- [ ] **Step 1: Write the failing Python tests.**

```python
# scripts/tests/test_audit_recommendation_traces.py

def test_seasonal_reason_code_with_nonempty_arguments_is_a_defect(self):
    item = make_item(reason_code="weather.seasonal_sun", reason_arguments={"days": "3"})
    report = build_report([item], policy_sensitive_ids=frozenset(), catalog_warning=None)
    self.assertEqual(len(report.invalid_seasonal_provenance), 1)

def test_seasonal_reason_code_with_empty_arguments_is_clean(self):
    item = make_item(reason_code="weather.seasonal_sun", reason_arguments={})
    report = build_report([item], policy_sensitive_ids=frozenset(), catalog_warning=None)
    self.assertEqual(len(report.invalid_seasonal_provenance), 0)

def test_precise_weather_reason_code_with_arguments_is_unaffected(self):
    item = make_item(reason_code="weather.rain_days", reason_arguments={"rainDays": "2", "tripDays": "5"})
    report = build_report([item], policy_sensitive_ids=frozenset(), catalog_warning=None)
    self.assertEqual(len(report.invalid_seasonal_provenance), 0)

def test_user_authority_row_with_a_reason_code_is_fabricated_provenance(self):
    item = make_item(user_modified=True, reason_code="base.essential.clothing", signals=("baseEssential",))
    report = build_report([item], policy_sensitive_ids=frozenset(), catalog_warning=None)
    self.assertEqual(len(report.fabricated_user_authority_provenance), 1)

def test_user_authority_row_with_empty_trace_is_clean(self):
    item = make_item(user_modified=True, reason_code="", signals=())
    report = build_report([item], policy_sensitive_ids=frozenset(), catalog_warning=None)
    self.assertEqual(len(report.fabricated_user_authority_provenance), 0)

def test_quantity_reason_argument_key_outside_the_closed_vocabulary_is_a_defect(self):
    item = make_item(quantity_reason_arguments={"washCycleDays": "3"})
    report = build_report([item], policy_sensitive_ids=frozenset(), catalog_warning=None)
    self.assertEqual(len(report.invalid_quantity_reason_argument_keys), 1)

def test_quantity_reason_argument_keys_from_the_closed_vocabulary_are_clean(self):
    item = make_item(quantity_reason_arguments={"quantity": "2", "travelerCount": "4"})
    report = build_report([item], policy_sensitive_ids=frozenset(), catalog_warning=None)
    self.assertEqual(len(report.invalid_quantity_reason_argument_keys), 0)
```

(Add a `make_item(**overrides)` helper if the existing test file doesn't
already have one building a `TraceItem` with sensible defaults — check
before adding a duplicate.)

- [ ] **Step 2: Run and verify RED.**

```bash
python3 -m unittest scripts.tests.test_audit_recommendation_traces
```

- [ ] **Step 3: Add the checks to `audit_recommendation_traces.py`.**

```python
SEASONAL_REASON_PREFIX = "weather.seasonal"
CLOSED_QUANTITY_REASON_ARGUMENT_KEYS = frozenset({
    "quantity", "days", "rate", "name", "travelerCount", "rainDays",
})


def is_invalid_seasonal_provenance(item: TraceItem) -> bool:
    """A seasonal-fallback row must never carry the day-count/forecast
    arguments only a precise-forecast reason renders — that would mean
    seasonal copy is claiming forecast-derived specifics it doesn't have.
    Both current seasonal codes (weather.seasonal_sun,
    weather.seasonal_layer, PackingEngine.swift:637,649) are always
    rendered with empty arguments; this is a regression guard on that
    invariant, not a currently-failing check."""
    return item.reason_code.startswith(SEASONAL_REASON_PREFIX) and bool(item.reason_arguments)


def is_fabricated_user_authority_provenance(item: TraceItem) -> bool:
    """A user-authority row (userModified or custom.* id) must carry an
    empty reasonCode/reason/signals — the engine must never invent
    inclusion provenance for the user's own decision. Regression guard;
    0 violations confirmed at eadc345."""
    return item.is_user_authority and bool(item.reason_code or item.reason or item.signals)


def invalid_quantity_reason_argument_keys(item: TraceItem) -> FrozenSet[str]:
    """quantityReasonArguments is a closed vocabulary (Task 1) — any key
    outside it means an unreviewed fourth call site started writing this
    field, the same drift ActivityNeed/PackingCapability/WeatherSignal
    already guard against."""
    return frozenset(item.quantity_reason_arguments.keys()) - CLOSED_QUANTITY_REASON_ARGUMENT_KEYS
```

Thread `reason_arguments: Tuple[Tuple[str, str], ...]` and
`quantity_reason_arguments: Tuple[Tuple[str, str], ...]` (or plain dicts —
match `TraceItem`'s existing immutability convention, it's `@dataclass
(frozen=True)`) onto `TraceItem`/`TraceItem.from_json`, reading
`raw.get("reasonArguments", {})` / `raw.get("quantityReasonArguments",
{})`. Add the three new fields to `Report`
(`invalid_seasonal_provenance: List[TraceItem]`,
`fabricated_user_authority_provenance: List[TraceItem]`,
`invalid_quantity_reason_argument_keys: List[TraceItem]`), populate them
in `build_report`, and fold all three into `Report.is_clean` (`:299-301`)
alongside the existing two defect checks. Render all three in
`render_text`/`render_markdown`, following the exact style the existing
"DEFECTS — missing reason code" section already uses.

- [ ] **Step 4: Refine the exit-metric wording** — no new logic, a wording
  and grouping change confirmed compatible with what `classify_inclusion`
  (`:227-238`) already computes. Update the script's module docstring
  and, in `render_text`/`render_markdown`, the label on the existing
  `missing_reason_code ∪ missing_signal` total: rename the reported
  headline from implying "generic-only = 0" to **"recommendations lacking
  causal structured provenance: `{count}`"**, computed as the existing
  `len(report.inclusion["missing_reason_code"]) +
  len(report.inclusion["missing_signal"])` — unchanged arithmetic, new
  label. The `generic-only (weak, informational)` line stays exactly as
  it is today, reported separately, never summed into the new headline.

- [ ] **Step 5: Run and verify GREEN**, then run the real script against
  the current goldens and confirm **0** violations of all three new
  checks — the regression-guard claim from the design doc, verified live,
  not assumed:

```bash
python3 -m unittest scripts.tests.test_audit_recommendation_traces
python3 scripts/audit_recommendation_traces.py \
  --goldens ios/PackWiseTests/Goldens --format markdown --strict
```

Expected exit code 0 — confirms the new checks find zero defects against
the real, current, post-Task-1/2/3/4 goldens before `--strict` becomes a
standing CI gate.

- [ ] **Step 6: Wire `--strict` into `run_engine_audit.sh`'s existing
  step 6**, turning "0 today" into "0 forever":

```diff
 step "6/6  Recommendation-trace audit (scripts/audit_recommendation_traces.py)"
 python3 scripts/audit_recommendation_traces.py \
     --goldens ios/PackWiseTests/Goldens \
-    --format markdown
+    --format markdown --strict
```

- [ ] **Step 7: Run the full audit script end to end.**

```bash
scripts/run_engine_audit.sh
```

- [ ] **Step 8: Commit.**

```bash
git add scripts/audit_recommendation_traces.py scripts/tests/test_audit_recommendation_traces.py scripts/run_engine_audit.sh
git commit -m "test: strengthen the recommendation trace audit and refine the causal-provenance exit metric"
```

---

### Task 8: The 18 required scenarios — trace-classification evidence

**Files:**
- Modify: `ios/PackWiseTests/RecommendationTraceTests.swift`

**Interfaces:**
- Consumes: every fixture/test cited in the design doc's 18-scenario
  table; `RecommendationTrace`'s facet functions (Task 5).
- Produces: one trace-classification test per scenario not already
  proven at the trace level by Task 5's Step 1 tests, plus explicit
  citations (comments, not code) for scenarios fully covered there. **No
  citation in the design doc's table changed under Amendments 1–2** — see
  the design doc's "Re-classification review" — so this task's scope is
  unchanged from the original plan except for reading the redesigned
  facet types (`ConstraintFacet.read(from:)`, `CoverageFacet`) where a
  test happens to touch them.

- [ ] **Step 1: Add the remaining trace-classification tests.** Tasks 4
  and 5 already cover scenarios 12 (party.shared fix) and the inclusion-
  family sweep (1, 5–9, 11, 13). Add the rest, each a short assertion
  against an already-cited fixture/test — no new production behavior:

```swift
/// Scenario 2: Tokyo planned-laundry T-shirts — quantityFacet must
/// surface clothingEvidence with laundryPlan/laundryReduced, not just
/// the rendered string. Cites GoldenEngineTests.swift:139-158 for the
/// underlying decision; this proves the *trace* reads it correctly.
@Test func scenario2TokyoLaundryTshirtsExposeClothingEvidence() throws {
    let output = try engineOutput(for: "02b-tokyo-15d-light-laundry-planned")
    let tshirt = try item("clothing.tshirt", owner: "primary", in: output)
    let facet = RecommendationTrace.quantityFacet(for: tshirt)
    #expect(facet.clothingEvidence?.laundryPlan == .planned)
    #expect(facet.clothingEvidence?.laundryReduced == true)
}

/// Scenario 3: workout clothing quantity basis is the workout policy,
/// not a bare number. Cites fixture 08.
@Test func scenario3WorkoutClothingExposesWorkoutPolicyBasis() throws {
    let output = try engineOutput(for: "08-running-sightseeing-footwear")
    let top = try item("clothing.workout_top", owner: "primary", in: output)
    #expect(RecommendationTrace.quantityFacet(for: top).clothingEvidence?.policyID.contains("workout") == true)
}

/// Scenario 4: swimwear's drying-rotation basis is visible via the
/// clothing evidence, cited from GoldenEngineTests.swift:173.
@Test func scenario4SwimwearExposesDryingRotationBasis() throws {
    let output = try engineOutput(for: "06-miami-5d-beach-personal-item")
    let swimsuit = try item("clothing.swimsuit", owner: "primary", in: output)
    #expect(RecommendationTrace.quantityFacet(for: swimsuit).clothingEvidence?.basis == "dryingRotation")
}

/// Scenario 10: partial-forecast rows classify as weatherPrecise for
/// their covered days and weatherSeasonal for the seasonal remainder,
/// never the reverse — cites fixture 33 plus
/// WeatherNeedHardeningTests.partialForecastBlendsCoveredSignalsWithSeasonalRemainder.
@Test func scenario10PartialForecastKeepsPreciseAndSeasonalRowsDistinct() throws {
    let output = try engineOutput(for: "33-chicago-10d-partial-forecast-seasonal-remainder")
    for item in output.items {
        guard item.reasonCode.hasPrefix("weather.") else { continue }
        let family = RecommendationTrace.inclusionFamily(reasonCode: item.reasonCode, signals: item.sourceSignals)
        #expect(family == .weatherPrecise || family == .weatherSeasonal)
        if family == .weatherSeasonal {
            #expect(item.reasonArguments.isEmpty, "seasonal rows must never carry forecast-specific arguments")
        }
    }
}

/// Scenario 14: manual quantity override presents as user authority,
/// never engine-generated evidence. Cites ClothingQuantityTests.swift:485.
@Test func scenario14ManualQuantityPresentsAsUserAuthority() throws {
    let output = try engineOutput(for: "14-manual-quantity-survives-refresh")
    let tshirt = try item("clothing.tshirt", owner: "primary", in: output)
    #expect(RecommendationTrace.authority(for: tshirt).isUserModified)
    #expect(RecommendationTrace.quantityFacet(for: tshirt).reason.isEmpty, "no fabricated engine quantity reason on a user-authority row")
}

/// Scenario 16/17: user-added canonical vs. custom items are both
/// authority-flagged, distinctly. Cites fixture 27 and
/// ConstraintTests.swift:436.
@Test func scenario16And17UserAddedAndCustomItemsAreBothAuthorityFlaggedDistinctly() throws {
    let output = try engineOutput(for: "27-chicago-5d-custom-item-survives-regeneration")
    let custom = try item("custom.lucky_travel_journal", owner: "primary", in: output)
    let authority = RecommendationTrace.authority(for: custom)
    #expect(authority.isCustomItem)
}

/// Scenario 18: owner vs. carrier stay distinct in the authority/identity
/// read. Cites ConstraintTests.swift:497,519 and fixture 37.
@Test func scenario18OwnerAndCarrierStayDistinctForATraceRead() throws {
    let output = try engineOutput(for: "37-family4-5d-hiking-camping-outdoor")
    let toddlerFlashlight = try item("miscellaneous.flashlight", owner: "child-2", in: output)
    #expect(toddlerFlashlight.owner != toddlerFlashlight.carrier || toddlerFlashlight.carrier == "unassigned")
}
```

Scenario 15 (Not Needed) has no Item Detail row to trace by definition —
a removed item never reaches the presentation layer — so its evidence
stays exactly `removedBaseEssentialStaysRemovedAcrossRegeneration`
(`ConstraintTests.swift:387`), cited, no new trace test; record this
explicitly in Task 9's exit report rather than force a test where none is
meaningful.

- [ ] **Step 2: Run and verify GREEN.**

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/RecommendationTraceTests
```

- [ ] **Step 3: Commit.**

```bash
git add ios/PackWiseTests/RecommendationTraceTests.swift
git commit -m "test: cite and prove trace evidence for all 18 required recommendation scenarios"
```

---

### Task 9: Close Phase 8

**Files:**
- Create: `docs/engine-audits/2026-09-04-phase-8-recommendation-trace-productization.md`
- Modify: `docs/plans/2026-09-02-product-hardening-program.md`

**Interfaces:**
- Consumes: Tasks 1–8.
- Produces: full audit evidence, an 18-scenario evidence table (cited vs.
  new test, per scenario), the exit-metrics table (all five roadmap
  metrics, with the refined causal-structured-provenance metric and the
  informational generic-only count reported side by side, not folded
  together), and the Phase 8 closure section.

- [ ] **Step 1: Run the full gate set.**

```bash
scripts/run_engine_audit.sh
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
python3 scripts/validate_shared.py
npm --prefix api run preflight
PYTHONDONTWRITEBYTECODE=1 python3 scripts/report_engine_goldens.py --baseline-ref eadc345 --candidate ios/PackWiseTests/Goldens --format markdown
python3 scripts/audit_recommendation_traces.py --goldens ios/PackWiseTests/Goldens --format markdown --strict
```

- [ ] **Step 2: Write the exit report.** Cover, at minimum: the full
  18-scenario evidence table (cited-existing vs. new, matching the design
  doc's table exactly, updated with real test names from Tasks 5/8, and
  the explicit confirmation that no citation was re-classified by
  Amendments 1–2); the exit-metrics table with all five roadmap metrics
  and their actual values (the two already-zero metrics reconfirmed fresh
  at the Phase 8 HEAD; the refined "causal structured provenance" metric
  and its value, reported distinctly from the informational generic-only
  count; the two new script checks plus the closed-key-vocabulary check
  reporting 0); the `party.shared` fix and the one reviewed golden diff it
  produced; the persistence gap closed (`quantityEvidence`/
  `quantityReasonArguments`/`satisfiedCapabilities`/
  `bagStyleConstraintFact` all now round-trip through `PackingItemRecord`,
  and — the real fix — `apply(_:)` now has an actual caller and a
  regression test proving causal fields refresh on regeneration while
  explicit user state does not); mechanical scope confirmation (no new
  `RecommendationSignal`/`PackingCapability`/`ActivityNeed`/
  `WeatherSignal` case; `CoverageSuppression`/`ConstraintDecision`/
  `CapabilityCoverage` remain non-`Codable`; exactly one `reasons.json`
  key changed; `quantityReasonArguments`'s six-key closed vocabulary
  enforced with zero violations).

- [ ] **Step 3: Close Phase 8 in the program tracker.** Update
  `docs/plans/2026-09-02-product-hardening-program.md`: change the header
  status line, add a "Phase 8 closure" section in the style of Phases
  1–7's closure sections, update the "Program order" table's Phase 8
  exit-evidence cell, and name what Phase 9 inherits (M3B/M3C still
  blocked; presentation still frozen structurally, now with an explicit
  "no direct engine calls from Item Detail" contract; physical-device
  verification still deferred).

- [ ] **Step 4: Commit the closure.**

```bash
git add docs/engine-audits/2026-09-04-phase-8-recommendation-trace-productization.md \
  docs/plans/2026-09-02-product-hardening-program.md
git commit -m "docs: close product hardening phase 8 recommendation trace productization"
```

---

## Self-Review

- **Spec coverage:** Task 1 closes the quantity-evidence gap (unchanged
  from the original design) and now also closes the two amendments the
  review required in the generation layer: `satisfiedCapabilities`
  computed inside `CoverageResolver.resolve`'s own loop (not a suppression
  inversion), and `bagStyleConstraintFact` captured at
  `ConstraintResolver.optionalRuling`'s one real call site inside
  `PackingEngine.resolve`. Task 2 persists all three. Task 3 is the third
  required amendment: `PackingItemRecord.apply(_:)`, found to be dead code
  with zero callers, is fixed and wired into the actual regeneration path
  (`recommendationDiff`'s merge-aware baseline, a widened per-item
  comparison, `applyDiff` calling `apply(_:)` for real), with a concrete
  regression test. Task 4 fixes the one routed finding Phase 7 explicitly
  handed forward, reproduced live against fixture 37 before any code
  changed. Task 5 builds the trace as a pure read layer — no facet
  function takes a decision-dependency parameter, closing the boundary
  violation the original `ConstraintFacet` design had. Task 6 populates
  the already-frozen Item Detail surface without restructuring it. Task 7
  turns two already-clean invariants and the new closed-vocabulary
  guarantee into standing regression gates, and refines the exit metric's
  wording to match what the script already computes. Task 8 proves all 18
  required scenarios at the trace level, citing the sixteen that already
  have decision-level evidence — confirmed unaffected by Amendments 1–2's
  redesign, not assumed. Task 9 is one reproducible exit command set and a
  separate evidence commit.
- **All 18 required scenarios map to a named task and named evidence, not
  prose:** 1, 5, 6, 7, 8, 9, 11, 13 — Task 5 Step 1's inclusion-family
  sweep plus cited existing tests/fixtures (design doc table). 2, 3, 4,
  10, 14, 16/17, 18 — Task 8's new trace-classification tests, each citing
  the underlying decision evidence by name. 12 — Task 4 (the production
  fix itself, proven by a failing-then-passing test against the live
  fixture-37 reproduction). 15 — explicitly has no Item Detail row to
  trace by definition; cited (`ConstraintTests.swift:387`), not forced
  into a meaningless test (named in Task 8 Step 1 and Task 9's exit
  report, not silently dropped).
- **Architecture boundary, strengthened by the amendment:** `RecommendationTrace`
  is entirely a read layer — `inclusionFamily` is a pure string-prefix
  classification over the closed `reasons.json` vocabulary;
  `quantityFacet`/`coverageFacet`/`authority` read existing/Task-1 fields
  directly; `ConstraintFacet.read(from:)` reconstructs the sharing fact
  from stored fields and reads the bag/style fact directly — **no facet
  function takes a `catalog`, `rules`, `context`, or `party` parameter**,
  a structural (not just conventional) guarantee that nothing in
  `RecommendationTrace` can re-derive a decision. Nothing in this plan
  changes `PackingEngine.generateDetailed`'s selection, quantity,
  coverage, or constraint decisions — verified per task by the zero-diff
  gate (Tasks 1, 2, 5, 6, 7, 8), the one approved, reviewed diff (Task 4),
  or Task 3's own regression test plus its explicit golden-fixture
  sanity check (Task 3 touches regeneration persistence, not
  `PackingEngine.generate`'s output shape).
- **Roadmap/reality conflict named, not silently resolved — and now
  correctly scoped:** the design doc's Exit Metrics section states
  explicitly that the original "generic-only generated explanations = 0"
  wording conflated two different questions, and the refined metric
  ("generated recommendations lacking causal structured provenance = 0")
  is exactly today's existing `missing_reason_code ∪ missing_signal`
  defect count — verified against the real script's `classify_inclusion`
  function, not assumed compatible. The 68-row generic-only bucket stays
  reported, separately, as informational. Two of the roadmap's five
  metrics were also found already at zero before this phase started —
  stated plainly rather than claimed as this phase's achievement.
- **Judgment calls made and recorded, not hidden:** the `party.shared` fix
  builds a pre-pluralized phrase argument (mirroring
  `party.shared_umbrella`) rather than deleting the `reasons.json`
  template and relying on `ConstraintResolver`'s already-correct Swift
  fallback string — unchanged reasoning from the original plan.
  `ConstraintResolver.optionalRuling`'s reorder (Task 1, Step 4) is a
  deliberate behavior-preserving restructuring, not a new decision — Task
  1 requires a table test proving every `keep`/`conflictKey` output is
  byte-identical to today's, precisely because a reorder this close to a
  real decision function deserves that specific proof, not just a golden
  zero-diff. `PackingItemRecord.apply(_:)`'s corrected contract
  deliberately never sets `packedQuantity` — Task 3 treats this as a real
  behavior decision (explicit user state must survive a causal refresh
  untouched), not an oversight, and keeps the existing downward
  packed-quantity clamp in `applyDiff` rather than folding it into
  `apply(_:)` itself, so the method's own contract stays simple ("never
  touches packed state") while the one caller that legitimately needs a
  safety clamp still has it.
- **Design-doc decision: written**, because Phase 8 reads and builds on
  top of Phases 3–7's evidence simultaneously (clothing quantity,
  footwear/outerwear coverage, activity contracts, weather-quality
  provenance, and constraint/user-authority evidence all feed one trace
  at once) — more subsystems touched at once than any single prior phase,
  and now including a real regeneration-persistence bug fix discovered
  during this amendment's investigation — and because the persistence-gap
  finding and the roadmap/reality conflict on generic-only explanations
  are real product decisions, not mechanical moves. Same bar Phases 4–7
  used, applied more rigorously per the required review.
- **Type/name consistency:** `PackingItemDraft.quantityReasonArguments`/
  `.satisfiedCapabilities`/`.bagStyleConstraintFact`,
  `PackingItemRecord.quantityReasonArgumentsRaw`/
  `.satisfiedCapabilitiesRaw`/`.bagStyleConstraintFactRaw`,
  `ConstraintResolver.OptionalRuling`'s three new fields, and
  `RecommendationTrace.InclusionFamily`/`.QuantityFacet`/
  `.ConstraintFacet`/`.CoverageFacet`/`.Authority` are the only new
  symbols this phase introduces (`coveredCapabilities` from the original
  design is renamed to `satisfiedCapabilities` throughout, tracking the
  concept change, not left as a stale alias); every task after Task 1/2/5
  consumes them without renaming.
- **Placeholder scan:** complete; no unresolved markers. Phase 9
  (Accepted Context Intelligence / M3B) is routed, not started inside
  Phase 8. This plan does not touch
  `docs/plans/2026-09-02-product-hardening-program.md` before Task 9, and
  Task 9 is not executed by the planning pass that produced this
  document.
