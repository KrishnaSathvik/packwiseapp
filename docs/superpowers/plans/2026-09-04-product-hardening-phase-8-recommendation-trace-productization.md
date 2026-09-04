# PackWise Product Hardening Phase 8 — Recommendation Trace Productization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn PackWise's existing provenance — `PackingItemDraft`'s
`reasonCode`/`reasonArguments`/`sourceSignals`/`quantityReason`/
`quantityEvidence`, `EngineGeneration`'s `coverageSuppressions`/
`constraintDecisions`, and Phase 7's `ConstraintResolver.SharingResolution`/
`hasUserAuthority`/`isExplicitlyRemoved` — into one complete, queryable
recommendation trace per item, wire the already-frozen Item Detail sheet to
it, fix the routed `party.shared` pluralization finding, and strengthen
`scripts/audit_recommendation_traces.py`'s exit metrics. The engine decides
once; this phase only makes that decision legible. No new recommendation
behavior.

**Architecture:** Full detail in
`docs/superpowers/specs/2026-09-04-product-hardening-phase-8-recommendation-trace-design.md`.
Summary: two new, additive `PackingItemDraft` fields
(`quantityReasonArguments: [String: String]`, `coveredCapabilities:
[String]`) capture structured facts the engine already computes and
currently discards (Task 1); both persist onto `PackingItemRecord` following
the existing `reasonArgumentsRaw`/`sourceSignalsRaw` flattening convention,
no schema version bump (Task 2); `reasons.json`'s `"party.shared"` template
gains a `{quantityPhrase}` placeholder, mirroring `party.shared_umbrella`'s
already-correct pattern (Task 3); a new `RecommendationTrace` enum is a pure
presentation-layer assembler — an `InclusionFamily` derived from the
already-closed `reasonCode` prefix vocabulary, plus quantity/constraint/
authority facets read directly off existing fields — with no new decision
logic anywhere (Task 4); Item Detail is wired to it without any layout
change (Task 5); the audit script gains two new structural checks (Task 6);
the 18 required scenarios get trace-classification tests, citing the
sixteen that already have decision-level evidence (Task 7); Task 8 closes
the phase.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, SwiftData, JSON shared
catalog/rules, JSON golden fixtures, Python audit tooling, Xcode/iOS 18
simulator tests.

## Global Constraints

- Work on `product-hardening-phase1` from `eadc345`; preserve every Phase
  1–7 commit and the unrelated signing change in the main checkout.
- Follow the approved design at
  `docs/superpowers/specs/2026-09-04-product-hardening-phase-8-recommendation-trace-design.md`.
- **No second decision engine.** Every function this plan adds either (a)
  is a pure derivation over data `PackingEngine`/`ConstraintResolver`/
  `CoverageResolver` already computed in the same call, or (b) re-calls an
  existing pure authority function (`ConstraintResolver.optionalRuling`,
  `.sharingResolution`) for its own already-decided answer. No task may
  change which items are generated, their quantities, coverage/suppression
  outcomes, weather signal extraction, activity contracts, or constraint/
  share decisions.
- No new `RecommendationSignal` case, `PackingCapability` case,
  `ActivityNeed` case, or `WeatherSignal` case.
- `CoverageSuppression`, `ConstraintDecision`, and `CapabilityCoverage`
  stay `Hashable, Sendable` only — no `Codable` conformance is added to
  them. Only their derived, flattened facts (`[String]` of raw capability
  values) are persisted.
- `shared/rules/*.json` changes are limited to exactly one template key:
  `reasons.json`'s `"party.shared"` (Task 3). No other JSON row, threshold,
  or rule changes.
- Golden regressions include any item/quantity/coverage/constraint/
  ownership/carrier change outside the one reviewed `party.shared` wording
  diff on fixture 37. Run `report_engine_goldens.py --baseline-ref eadc345`
  after every task that touches `PackingEngine.swift`, `Catalog.swift`, or
  `reasons.json`.
- Task 1/Task 2 (the two additive-field tasks) are each a **zero-diff
  gate**: the new keys must appear in every fixture's serialized output
  with **zero** change to any existing key, verified before either task's
  behavior-adjacent test is trusted.
- Task 3 (the `party.shared` fix) is the plan's one **approved, reviewed**
  golden diff — scoped exactly to fixture 37's two shared-item rows'
  `quantityReason` text. `quantity` values, every other fixture, and every
  other row in fixture 37 must be byte-identical to `eadc345`.
- The 68-row generic-only inclusion bucket is not driven to zero (see the
  design doc's Exit Metrics section) — no task in this plan adds a new
  `reasonCode`, `signalAdds` row, or `ActivityContract` entry to shrink it.
- `PackingItemRecord.apply(_:)`'s pre-existing non-refresh of `reasonCode`/
  `sourceSignals` is not fixed by this plan — the two new fields this plan
  adds to `apply(_:)` follow `reason`/`quantityReason`'s existing
  refresh-on-merge behavior (Task 2), and that is the full extent of this
  plan's touch on `apply(_:)`.
- Presentation stays frozen: Item Detail's card structure, section order,
  and navigation are unchanged. New content fills existing sections
  (`ItemDetailView.reasons`) or adds one clearly-scoped subsection.
- Physical-device verification stays deferred, M3B/M3C remain blocked.
- Do not edit `docs/plans/2026-09-02-product-hardening-program.md` before
  Task 8. Stop at the Phase 8 exit gate; do not begin Phase 9.

---

## File Map

- Modify `ios/PackWise/Domain/Packing/Catalog.swift`: add
  `quantityReasonArguments`, `coveredCapabilities` to `PackingItemDraft`
  (Task 1).
- Modify `ios/PackWise/Domain/Packing/PackingEngine.swift`: populate both
  new fields (Task 1); fix the `party.shared` argument (Task 3).
- Modify `shared/rules/reasons.json`: `"party.shared"` template only (Task
  3).
- Modify `ios/PackWiseTests/GoldenEngineTests.swift`: serialize the two new
  fields into golden output (Task 1).
- Modify `shared/fixtures/golden/golden-fixtures.json`,
  `ios/PackWiseTests/Goldens/*.json`: re-recorded output for all 38
  fixtures (Task 1, additive only), fixture 37 wording diff (Task 3).
- Modify `ios/PackWise/Data/Persistence/Models.swift`: persist both new
  fields on `PackingItemRecord` (`init(from:)`, `draft`, `apply(_:)`) (Task
  2).
- Create `ios/PackWise/Domain/Packing/RecommendationTrace.swift`:
  `InclusionFamily`, `inclusionFamily(reasonCode:signals:)`,
  `QuantityFacet`, `ConstraintFacet`, `Authority` (Task 4).
- Create `ios/PackWiseTests/RecommendationTraceTests.swift`: inclusion-
  family classification, quantity-facet, constraint-facet, authority-facet
  tests; the 18-scenario citation/classification matrix (Tasks 4, 7).
- Modify `ios/PackWise/Features/TripDetail/PackingListView.swift`: wire
  `ItemDetailView.reasons` to the new facets (Task 5).
- Modify `scripts/audit_recommendation_traces.py`: add the seasonal-
  provenance and user-authority-fabrication checks (Task 6).
- Modify `scripts/tests/test_audit_recommendation_traces.py`: tests for
  both new checks (Task 6).
- Modify `scripts/run_engine_audit.sh`: pass `--strict` to
  `audit_recommendation_traces.py` (Task 6).
- Create `docs/engine-audits/2026-09-04-phase-8-recommendation-trace-productization.md`
  (Task 8).
- Modify `docs/plans/2026-09-02-product-hardening-program.md`: close Phase
  8 only in Task 8.

---

### Task 1: Structured quantity arguments and covered capabilities on `PackingItemDraft`

**Files:**
- Modify: `ios/PackWise/Domain/Packing/Catalog.swift`
- Modify: `ios/PackWise/Domain/Packing/PackingEngine.swift`
- Modify: `ios/PackWiseTests/GoldenEngineTests.swift`
- Modify: `shared/fixtures/golden/golden-fixtures.json`, `ios/PackWiseTests/Goldens/*.json`

**Interfaces:**
- Consumes: `CareQuantityEngine.Result.arguments`, `WarmLayerQuantities.quantity(...)`'s
  `arguments` return element, `ConstraintResolver.SharingResolution`'s
  `quantity` (`ConstraintResolver.swift:120-125`), `CoverageSuppression.covered`
  (`CoverageResolver.swift:92-107`) — all unchanged.
- Produces: `PackingItemDraft.quantityReasonArguments: [String: String]`,
  `.coveredCapabilities: [String]`.

- [ ] **Step 1: Write the failing characterization tests**, pinning the
  two new fields against today's already-computed-but-discarded facts.

```swift
// GoldenEngineTests.swift — near the existing quantityEvidence assertions (:139-191)

@Test func warmLayerQuantityArgumentsSurviveOntoTheDraft() throws {
    // A sustained-cold multi-day trip whose light sweater rotates
    // (WarmLayerQuantities, ClothingQuantity.swift:236-266) — today's
    // `quantity.warm_rotation` code + {quantity, days} arguments are
    // computed and thrown away after rendering; the field should carry
    // the same {quantity, days} keys the render call already used.
    let output = try engineOutput(for: "15-minneapolis-6d-deep-winter")
    let sweater = try item("clothing.light_sweater", owner: "primary", in: output)
    #expect(sweater.quantityReasonArguments["quantity"] == "\(sweater.quantity)")
    #expect(sweater.quantityReasonArguments["days"] != nil)
}

@Test func sharedItemQuantityArgumentsCaptureQuantityAndPartySize() throws {
    let output = try engineOutput(for: "38-couple-5d-seattle-shared-umbrella")
    let umbrella = try item("essentials.umbrella_compact", owner: "shared", in: output)
    #expect(umbrella.quantityReasonArguments["quantity"] == "\(umbrella.quantity)")
}

@Test func coveredCapabilitiesNamesWhatASurvivingItemCovers() throws {
    // Hiking shoes cover walking (substitution.hiking_covers_walking,
    // fixture 29) — CoverageSuppression already records this on the
    // *suppressed* walking-shoes row; the surviving hiking-shoes row
    // should now carry the inverse fact directly.
    let output = try engineOutput(for: "29-yellowstone-4d-hiking-camping")
    let hikingShoes = try item("footwear.hiking_shoes", owner: "primary", in: output)
    #expect(hikingShoes.coveredCapabilities.contains(PackingCapability.everydayWalking.rawValue))
}

@Test func fixedSingletonsCarryEmptyQuantityReasonArguments() throws {
    let output = try engineOutput(for: "01-chicago-5d-city-balanced")
    let toothbrush = try item("toiletries.toothbrush", owner: "primary", in: output)
    #expect(toothbrush.quantityReasonArguments.isEmpty)
}
```

Add a small `engineOutput(for:)`/`item(_:owner:in:)` test helper if
`GoldenEngineTests` doesn't already expose one at file scope (it likely
does something equivalent already for its own `quantityEvidence`
assertions at `:139-191` — reuse that helper, don't duplicate it).

- [ ] **Step 2: Run and verify RED.** Compile failure —
  `quantityReasonArguments`/`coveredCapabilities` don't exist on
  `PackingItemDraft` yet.

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/GoldenEngineTests
```

- [ ] **Step 3: Add the two fields to `PackingItemDraft`** (`Catalog.swift:362-438`):

```swift
struct PackingItemDraft: Hashable, Identifiable, Codable, Sendable {
    // ... existing fields unchanged ...
    var quantityEvidence: ClothingQuantityEvidence?
    /// Structured arguments behind quantityReason for the non-clothing
    /// quantity families (care, warm-layer rotation, party sharing) — the
    /// same role reasonArguments already plays for the inclusion reason.
    /// Empty for fixed singletons and for the clothing family, which
    /// already has quantityEvidence.
    var quantityReasonArguments: [String: String] = [:]
    /// Raw PackingCapability values this item satisfies for another need
    /// — the inverse of CoverageSuppression.covered, computed once after
    /// coverage resolution. Empty when this item covers no capability
    /// another candidate also wanted.
    var coveredCapabilities: [String] = []
    // ... existing fields unchanged ...
}
```

Add both to the memberwise `init(...)` (`:397-437`) with the same default
values, so every existing call site across the app and test suite keeps
compiling unchanged.

- [ ] **Step 4: Populate `quantityReasonArguments` in `applyQuantities`.**
  Three call sites, each already building the argument dictionary it
  passes to `render(...)` — assign it to the field instead of discarding
  it after the render call:

  - Shared items (`PackingEngine.swift:901-922`): in both the umbrella and
    generic branches, set `copy.quantityReasonArguments = ["quantity":
    "\(quantity)"]` (drop the unused `"partySize"` key — confirmed unused
    by any `reasons.json` template) before `return copy`.
  - Care items (`:929-932`): `copy.quantityReasonArguments = care.arguments`.
  - Warm layers (`:937-945`): `copy.quantityReasonArguments = warm.arguments`.

  The clothing branch (`:951-962`) is deliberately untouched —
  `quantityEvidence` already carries its structured facts; do not also
  populate `quantityReasonArguments` there (would be a redundant second
  representation of the same facts).

- [ ] **Step 5: Populate `coveredCapabilities` in `generateDetailed`**
  (`PackingEngine.swift:34-64`), after `coverageSuppressions` is known and
  before the `EngineGeneration` is constructed:

```swift
let coverageByItem = Dictionary(
    grouping: generated.suppressions.flatMap(\.covered),
    by: \.coveringItemID
).mapValues { coverages in Set(coverages.map(\.capability.rawValue)).sorted() }

let itemsWithCoverage = generated.items.map { item -> PackingItemDraft in
    guard let canonical = item.canonicalItemID, let covered = coverageByItem[canonical] else { return item }
    var copy = item
    copy.coveredCapabilities = covered
    return copy
}
```

Feed `itemsWithCoverage` (not `generated.items`) into the existing
`PartyInvariants.normalize` map at `:48-58`. No change to `suppressions`,
`drops`, or the normalize call itself.

- [ ] **Step 6: Serialize both fields into golden output.**
  `GoldenEngineTests.swift`'s `GoldenItem` struct (`:485-508`) gains two
  fields (placed after `quantityEvidence`):

```swift
private struct GoldenItem: Codable {
    // ... existing fields unchanged through quantityEvidence ...
    var quantityReasonArguments: [String: String]
    var coveredCapabilities: [String]
    var userModified: Bool?
}
```

And the `serialize(...)` mapping (`:565-586`) passes
`item.quantityReasonArguments` / `item.coveredCapabilities` through
unchanged (empty dict/array serialize as `{}`/`[]`, matching the existing
convention for other empty-collection fields).

- [ ] **Step 7: Re-record every golden fixture and verify the zero-diff gate.**

```bash
PACKWISE_RECORD_GOLDENS=1 xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/GoldenEngineTests
PYTHONDONTWRITEBYTECODE=1 python3 scripts/report_engine_goldens.py \
  --baseline-ref eadc345 --candidate ios/PackWiseTests/Goldens --format markdown
```

Expected: the diff tool reports **zero** semantic changes — it diffs the
fields it already knows about, and the two new keys are additive JSON
fields it doesn't compare, not a change to any compared field. Confirm
this directly by also running `git diff --stat ios/PackWiseTests/Goldens`
and spot-checking a handful of files: every existing key's value is
byte-identical; only `quantityReasonArguments`/`coveredCapabilities` keys
are newly present.

- [ ] **Step 8: Run and verify GREEN.**

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/GoldenEngineTests \
  -only-testing:PackWiseTests/CoverageTests \
  -only-testing:PackWiseTests/ConstraintTests \
  -only-testing:PackWiseTests/ClothingQuantityTests
```

- [ ] **Step 9: Commit.**

```bash
git add ios/PackWise/Domain/Packing/Catalog.swift \
  ios/PackWise/Domain/Packing/PackingEngine.swift \
  ios/PackWiseTests/GoldenEngineTests.swift \
  shared/fixtures/golden/golden-fixtures.json ios/PackWiseTests/Goldens
git commit -m "feat: capture structured quantity arguments and covered capabilities on PackingItemDraft"
```

---

### Task 2: Persist the new trace fields on `PackingItemRecord`

**Files:**
- Modify: `ios/PackWise/Data/Persistence/Models.swift`

**Interfaces:**
- Consumes: `PackingItemDraft.quantityReasonArguments`,
  `.coveredCapabilities` (Task 1).
- Produces: `PackingItemRecord.quantityReasonArgumentsRaw: String`,
  `.coveredCapabilitiesRaw: String`, and their decoded computed properties.

- [ ] **Step 1: Write the failing round-trip test.**

```swift
// A new PersistenceTests.swift test (or the existing persistence suite,
// grep for where PackingItemRecord round-trip tests already live).
@Test func quantityReasonArgumentsAndCoveredCapabilitiesRoundTripThroughPersistence() throws {
    var draft = PackingItemDraft(
        canonicalItemID: "footwear.hiking_shoes", displayName: "Hiking shoes",
        category: .footwear, quantity: 1, importance: .normal,
        sourceSignals: [.activity], reason: "Hiking is on your plans."
    )
    draft.quantityReasonArguments = ["quantity": "1", "days": "5"]
    draft.coveredCapabilities = ["footwear.everyday_walking"]

    let trip = TripRecord(/* existing test fixture constructor */)
    let record = PackingItemRecord(from: draft, trip: trip)
    #expect(record.draft.quantityReasonArguments == draft.quantityReasonArguments)
    #expect(record.draft.coveredCapabilities == draft.coveredCapabilities)
}
```

- [ ] **Step 2: Run and verify RED.** Compile failure or an empty-value
  assertion failure — the fields aren't persisted yet.

- [ ] **Step 3: Add the two raw storage fields and computed accessors**
  to `PackingItemRecord` (`Models.swift:187-232`), mirroring
  `reasonArgumentsRaw`'s pipe/equals convention exactly and
  `sourceSignalsRaw`'s comma convention exactly:

```swift
final class PackingItemRecord {
    // ... existing fields unchanged through reasonArgumentsRaw ...
    var quantityReason: String
    var quantityReasonArgumentsRaw: String = ""
    var coveredCapabilitiesRaw: String = ""
    // ... existing fields unchanged ...

    var quantityReasonArguments: [String: String] {
        Dictionary(uniqueKeysWithValues: quantityReasonArgumentsRaw.split(separator: "|").compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return (parts[0], parts[1])
        })
    }
    var coveredCapabilities: [String] {
        coveredCapabilitiesRaw.isEmpty ? [] : coveredCapabilitiesRaw.split(separator: ",").map(String.init)
    }
}
```

- [ ] **Step 4: Set both in `init(from:trip:)`** (`:210-232`), immediately
  after the existing `reasonArgumentsRaw` line:

```swift
self.reasonArgumentsRaw = draft.reasonArguments.map { "\($0.key)=\($0.value)" }.joined(separator: "|")
self.quantityReasonArgumentsRaw = draft.quantityReasonArguments.map { "\($0.key)=\($0.value)" }.joined(separator: "|")
self.coveredCapabilitiesRaw = draft.coveredCapabilities.joined(separator: ",")
```

- [ ] **Step 5: Add both to `var draft: PackingItemDraft`** (`:242-267`),
  passing the decoded computed properties through as the new
  initializer parameters from Task 1's Step 3.

- [ ] **Step 6: Add both to `apply(_:)`** (`:269-280`), as peers of
  `reason`/`quantityReason` (which already refresh on merge) — per the
  design doc's explicit call not to silently copy `reasonCode`'s
  non-refresh instead:

```swift
func apply(_ draft: PackingItemDraft) {
    quantity = draft.quantity
    packedQuantity = draft.packedQuantity
    reason = draft.reason
    quantityReason = draft.quantityReason
    quantityReasonArgumentsRaw = draft.quantityReasonArguments.map { "\($0.key)=\($0.value)" }.joined(separator: "|")
    coveredCapabilitiesRaw = draft.coveredCapabilities.joined(separator: ",")
    isUserModified = draft.isUserModified
    ownershipTypeRaw = draft.ownershipType.rawValue
    travelerID = draft.travelerID
    assignedTravelerID = draft.assignedTravelerID
    bagID = draft.bagID
    updatedAt = .now
}
```

- [ ] **Step 7: Confirm no schema version bump is required.** Both new
  properties are defaulted (`= ""`) on an unchanged model type — the same
  shape `reasonCode: String = ""` already uses without a
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

- [ ] **Step 8: Run and verify GREEN, full suite.**

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

- [ ] **Step 9: Commit.**

```bash
git add ios/PackWise/Data/Persistence/Models.swift ios/PackWiseTests/
git commit -m "feat: persist quantity trace arguments and covered capabilities on PackingItemRecord"
```

---

### Task 3: Fix the `party.shared` pluralization (routed finding)

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
  (`:905-912`) exactly:

```swift
} else {
    let quantityPhrase = quantity == 1 ? "One" : "\(quantity)"
    copy.quantityReason = render(
        "party.shared",
        ["quantityPhrase": quantityPhrase],
        fallback: fallback
    )
}
```

Also apply `quantityPhrase` (not the raw `"quantity"`/`"partySize"` keys)
to `quantityReasonArguments` here, so Task 1's new field stays consistent
with what the rendered text actually used:
`copy.quantityReasonArguments = ["quantityPhrase": quantityPhrase]`.

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
identities, quantities, `coveredCapabilities` from Task 1, coverage,
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

### Task 4: `RecommendationTrace` — inclusion family and facet derivation

**Files:**
- Create: `ios/PackWise/Domain/Packing/RecommendationTrace.swift`
- Create: `ios/PackWiseTests/RecommendationTraceTests.swift`

**Interfaces:**
- Consumes: `PackingItemDraft.reasonCode/.sourceSignals/.quantity/
  .quantityReason/.quantityReasonArguments/.quantityEvidence/
  .coveredCapabilities/.isUserAdded/.isUserModified/.canonicalItemID/
  .ownershipType` (all existing or Task 1's additions),
  `ConstraintResolver.optionalRuling`/`.sharingResolution` (Phase 7,
  unchanged), `shared/rules/reasons.json`'s full template key set.
- Produces: `RecommendationTrace.InclusionFamily`,
  `.inclusionFamily(reasonCode:signals:)`, `.QuantityFacet`,
  `.ConstraintFacet`, `.Authority` — all pure, no `PackingEngine`
  dependency.

- [ ] **Step 1: Write the failing classification tests**, covering every
  `reasonCode` prefix actually present in `reasons.json` (not a
  hand-picked subset) plus the user-authority and unknown-prefix cases.

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
    // Closed-vocabulary guard: every key in reasons.json must hit a real
    // prefix branch, proving the final `.tripType` fallback branch in
    // inclusionFamily is unreachable today — a documented, tested
    // invariant, not an assumption.
    let templates = try SharedLibrary.rules().reasons.templates
    let categoryAndImpactAndQuantityPrefixes = ["category.", "impact.", "quantity.", "context."]
    for code in templates.keys where !categoryAndImpactAndQuantityPrefixes.contains(where: code.hasPrefix) {
        let family = RecommendationTrace.inclusionFamily(reasonCode: code, signals: [])
        #expect(family != .tripType || code.hasPrefix("trip_type."), "\(code) unexpectedly fell through to the fallback family")
    }
}
```

- [ ] **Step 2: Run and verify RED.** Compile failure —
  `RecommendationTrace` doesn't exist yet.

- [ ] **Step 3: Create `RecommendationTrace.swift`** with the shape from
  the design doc's Architecture section (`InclusionFamily`,
  `inclusionFamily(reasonCode:signals:)`, `QuantityFacet`,
  `ConstraintFacet`, `Authority`). Copy the design doc's snippet verbatim
  for the enum and the prefix-branch function; add:

```swift
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

    static func constraintFacet(
        for item: PackingItemDraft,
        catalog: PackingCatalog,
        rules: PackingRulesFile,
        context: TripContext,
        party: TripParty
    ) -> ConstraintFacet? {
        guard let canonical = item.canonicalItemID, let catalogItem = catalog.item(id: canonical) else { return nil }
        let ruling = ConstraintResolver.optionalRuling(
            importance: item.importance, tags: catalogItem.tags,
            bag: context.bagType, style: context.packingStyle
        )
        let sharing = ConstraintResolver.sharingResolution(
            for: canonical, rules: rules.party, context: context, party: party
        )
        return ConstraintFacet(bagStyleTrimEligible: !ruling.keep, sharing: sharing)
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
git commit -m "feat: add RecommendationTrace inclusion-family and facet derivation"
```

---

### Task 5: Wire Item Detail to the productized trace

**Files:**
- Modify: `ios/PackWise/Features/TripDetail/PackingListView.swift`

**Interfaces:**
- Consumes: `RecommendationTrace.inclusionFamily`/`.quantityFacet`/
  `.constraintFacet`/`.authority` (Task 4), `PackingItemRecord.draft`
  (Task 2 fields included).
- Produces: Item Detail's existing "Why it's on your list" section
  (`ItemDetailView.reasons`, `PackingListView.swift:778-808`) shows the
  quantity's structured basis (clothing evidence or the new
  `quantityReasonArguments`-backed families) and — new — a compact
  authority/constraint line, without changing the section's structure.

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
  already pass purely from Task 4's facet functions — record the actual
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
  authority line (when present) ahead of the existing reason text, and to
  prefer `quantityEvidence`/`quantityReasonArguments`-backed detail over
  the bare `quantityReason` string only where it adds real content — the
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

### Task 6: Strengthen `scripts/audit_recommendation_traces.py`

**Files:**
- Modify: `scripts/audit_recommendation_traces.py`
- Modify: `scripts/tests/test_audit_recommendation_traces.py`
- Modify: `scripts/run_engine_audit.sh`

**Interfaces:**
- Consumes: the existing `TraceItem`/golden JSON schema (Task 1 adds two
  new keys the script does not need to read for these checks).
- Produces: two new defect buckets — `invalid_seasonal_provenance`,
  `fabricated_user_authority_provenance` — folded into `Report.is_clean`
  and `--strict`'s exit code.

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
```

(Add a `make_item(**overrides)` helper if the existing test file doesn't
already have one building a `TraceItem` with sensible defaults — check
before adding a duplicate.)

- [ ] **Step 2: Run and verify RED.**

```bash
python3 -m unittest scripts.tests.test_audit_recommendation_traces
```

- [ ] **Step 3: Add both checks to `audit_recommendation_traces.py`.**

```python
SEASONAL_REASON_PREFIX = "weather.seasonal"

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
```

Thread `reason_arguments: Tuple[Tuple[str, str], ...]` (or a plain dict —
match `TraceItem`'s existing immutability convention, it's `@dataclass
(frozen=True)`) onto `TraceItem`/`TraceItem.from_json`, reading
`raw.get("reasonArguments", {})`. Add both new fields to `Report`
(`invalid_seasonal_provenance: List[TraceItem]`,
`fabricated_user_authority_provenance: List[TraceItem]`), populate them
in `build_report`, and fold both into `Report.is_clean`
(`:299-301`) alongside the existing two defect checks. Render both in
`render_text`/`render_markdown`, following the exact style the existing
"DEFECTS — missing reason code" section already uses.

- [ ] **Step 4: Run and verify GREEN**, then run the real script against
  the current goldens and confirm **0** violations of both new checks —
  the regression-guard claim from the design doc, verified live, not
  assumed:

```bash
python3 -m unittest scripts.tests.test_audit_recommendation_traces
python3 scripts/audit_recommendation_traces.py \
  --goldens ios/PackWiseTests/Goldens --format markdown --strict
```

Expected exit code 0 — confirms the two new checks find zero defects
against the real, current, post-Task-1/2/3 goldens before `--strict`
becomes a standing CI gate.

- [ ] **Step 5: Wire `--strict` into `run_engine_audit.sh`'s existing
  step 6**, turning "0 today" into "0 forever":

```diff
 step "6/6  Recommendation-trace audit (scripts/audit_recommendation_traces.py)"
 python3 scripts/audit_recommendation_traces.py \
     --goldens ios/PackWiseTests/Goldens \
-    --format markdown
+    --format markdown --strict
```

- [ ] **Step 6: Run the full audit script end to end.**

```bash
scripts/run_engine_audit.sh
```

- [ ] **Step 7: Commit.**

```bash
git add scripts/audit_recommendation_traces.py scripts/tests/test_audit_recommendation_traces.py scripts/run_engine_audit.sh
git commit -m "test: strengthen the recommendation trace audit for seasonal provenance and user-authority fabrication"
```

---

### Task 7: The 18 required scenarios — trace-classification evidence

**Files:**
- Modify: `ios/PackWiseTests/RecommendationTraceTests.swift`

**Interfaces:**
- Consumes: every fixture/test cited in the design doc's 18-scenario
  table; `RecommendationTrace`'s facet functions (Task 4).
- Produces: one trace-classification test per scenario not already
  proven at the trace level by Task 4's Step 1 tests, plus explicit
  citations (comments, not code) for scenarios fully covered there.

- [ ] **Step 1: Add the remaining trace-classification tests.** Tasks 3
  and 4 already cover scenarios 12 (party.shared fix) and the inclusion-
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
explicitly in Task 8's exit report rather than force a test where none is
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

### Task 8: Close Phase 8

**Files:**
- Create: `docs/engine-audits/2026-09-04-phase-8-recommendation-trace-productization.md`
- Modify: `docs/plans/2026-09-02-product-hardening-program.md`

**Interfaces:**
- Consumes: Tasks 1–7.
- Produces: full audit evidence, an 18-scenario evidence table (cited vs.
  new test, per scenario), the exit-metrics table (all five roadmap
  metrics, with the generic-only conflict stated explicitly), and the
  Phase 8 closure section.

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
  doc's table exactly, updated with real test names from Tasks 4/7); the
  exit-metrics table with all five roadmap metrics and their actual
  values (the two already-zero metrics reconfirmed fresh at the Phase 8
  HEAD, not cited stale from Phase 1; the two new script checks reporting
  0; the generic-only bucket reported at its real count with the explicit
  non-goal stated, not silently omitted); the `party.shared` fix and the
  one reviewed golden diff it produced; the persistence gap closed
  (`quantityEvidence`/`quantityReasonArguments`/`coveredCapabilities` all
  now round-trip through `PackingItemRecord`) and the `apply(_:)` refresh
  parity decision; mechanical scope confirmation (no new
  `RecommendationSignal`/`PackingCapability`/`ActivityNeed`/
  `WeatherSignal` case; `CoverageSuppression`/`ConstraintDecision`/
  `CapabilityCoverage` remain non-`Codable`; exactly one `reasons.json`
  key changed).

- [ ] **Step 3: Close Phase 8 in the program tracker.** Update
  `docs/plans/2026-09-02-product-hardening-program.md`: change the header
  status line, add a "Phase 8 closure" section in the style of Phases
  1–7's closure sections, update the "Program order" table's Phase 8
  exit-evidence cell, and name what Phase 9 inherits (M3B/M3C still
  blocked; presentation still frozen structurally; physical-device
  verification still deferred).

- [ ] **Step 4: Commit the closure.**

```bash
git add docs/engine-audits/2026-09-04-phase-8-recommendation-trace-productization.md \
  docs/plans/2026-09-02-product-hardening-program.md
git commit -m "docs: close product hardening phase 8 recommendation trace productization"
```

---

## Self-Review

- **Spec coverage:** Task 1 closes the one genuine cross-family gap the
  design doc found (structured quantity evidence exists only for
  clothing) as a zero-diff, additive move — the same discipline Phase
  6/7 used for their own zero-diff refactors. Task 2 closes the
  persistence gap `Catalog.swift:377`'s own comment already named as
  Phase 8's to close. Task 3 fixes the one routed finding Phase 7
  explicitly handed forward, reproduced live against fixture 37 before
  any code changed. Task 4 builds the trace as pure derivation, no new
  decision. Task 5 populates the already-frozen Item Detail surface
  without restructuring it. Task 6 turns two already-clean invariants
  into standing regression gates. Task 7 proves all 18 required
  scenarios at the trace level, citing the sixteen that already have
  decision-level evidence rather than re-deriving it. Task 8 is one
  reproducible exit command set and a separate evidence commit.
- **All 18 required scenarios map to a named task and named evidence,
  not prose:** 1, 5, 6, 7, 8, 9, 11, 13 — Task 4 Step 1's inclusion-family
  sweep plus cited existing tests/fixtures (design doc table). 2, 3, 4,
  10, 14, 16/17, 18 — Task 7's new trace-classification tests, each
  citing the underlying decision evidence by name. 12 — Task 3 (the
  production fix itself, proven by a failing-then-passing test against
  the live fixture-37 reproduction). 15 — explicitly has no Item Detail
  row to trace by definition; cited (`ConstraintTests.swift:387`), not
  forced into a meaningless test (named in Task 7 Step 1 and Task 8's
  exit report, not silently dropped).
- **Architecture boundary:** `RecommendationTrace` is entirely a read
  layer — `inclusionFamily` is a pure string-prefix classification over
  the closed `reasons.json` vocabulary; `quantityFacet`/`authority` read
  existing/Task-1 fields directly; `constraintFacet` re-calls Phase 7's
  own pure authority functions for their own already-decided answer.
  Nothing in this plan changes `PackingEngine.generateDetailed`'s
  selection, quantity, coverage, or constraint decisions — verified per
  task by the zero-diff gate (Tasks 1, 2, 4, 5, 6, 7) or the one
  approved, reviewed diff (Task 3).
- **Roadmap/reality conflict named, not silently resolved:** the design
  doc's Exit Metrics section states explicitly that "generic-only
  generated explanations = 0" conflicts with Phase 1's own P2-4 finding
  (the fallback ladder working correctly, not failing) and with this
  plan's Global Constraints (no new rule content). Global Constraints
  restates it as a hard boundary, not a suggestion. Two of the roadmap's
  five metrics were also found already at zero before this phase started
  — stated plainly in the design doc rather than claimed as this phase's
  achievement.
- **Judgment calls made and recorded, not hidden:** the `party.shared`
  fix builds a pre-pluralized phrase argument (mirroring
  `party.shared_umbrella`) rather than deleting the `reasons.json`
  template and relying on `ConstraintResolver`'s already-correct Swift
  fallback string, even though the latter would be a smaller diff —
  chosen because a visible template placeholder is self-documenting to a
  future content editor the same way `party.shared_umbrella`'s already
  is, and because relying on an un-obvious fallback path is exactly the
  kind of implicit behavior this hardening arc has been closing
  elsewhere. `PackingItemRecord.apply(_:)`'s pre-existing `reasonCode`/
  `sourceSignals` non-refresh is named and deliberately not fixed —
  Task 2 only adds the two new fields to `apply(_:)`'s refresh set,
  matching `reason`/`quantityReason`'s existing behavior, and does not
  extend the fix to fields this phase didn't add.
- **Design-doc decision: written**, because Phase 8 reads and builds on
  top of Phases 3–7's evidence simultaneously (clothing quantity,
  footwear/outerwear coverage, activity contracts, weather-quality
  provenance, and constraint/user-authority evidence all feed one trace
  at once) — more subsystems touched at once than any single prior
  phase — and because the persistence-gap finding and the roadmap/reality
  conflict on generic-only explanations are real product decisions, not
  mechanical moves. Same bar Phases 4–7 used.
- **Type/name consistency:** `PackingItemDraft.quantityReasonArguments`/
  `.coveredCapabilities`, `PackingItemRecord.quantityReasonArgumentsRaw`/
  `.coveredCapabilitiesRaw`, and `RecommendationTrace.InclusionFamily`/
  `.QuantityFacet`/`.ConstraintFacet`/`.Authority` are the only new
  symbols this phase introduces; every task after Task 1/2/4 consumes
  them without renaming.
- **Placeholder scan:** complete; no unresolved markers. Phase 9
  (Accepted Context Intelligence / M3B) is routed, not started inside
  Phase 8. This plan does not touch
  `docs/plans/2026-09-02-product-hardening-program.md` before Task 8, and
  Task 8 is not executed by the planning pass that produced this
  document.
