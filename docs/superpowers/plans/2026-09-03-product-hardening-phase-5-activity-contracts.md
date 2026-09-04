# PackWise Product Hardening Phase 5 — Surfaced Activity Contracts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every surfaced activity an explicit `deterministic` or `contextOnly` contract, make Camping a real personal-travel packing signal, and make Camping and Hiking compose into one outdoor trip instead of two concatenated checklists.

**Architecture:** Introduce `ActivityContracts` as the single typed activity authority, mirroring how `CoverageResolver` is the single coverage authority. A surfaced activity maps to a closed `Set<ActivityNeed>`; needs map to candidate item IDs and, where they overlap, to Phase 4 `PackingCapability` values. Needs and the existing `rules.activities` adds both flow into the collector `addIDs` already keys by canonical item ID, so composition and de-duplication are structural. `shared/rules/activity-rules.json` stays the surfaced vocabulary; Camping and Hiking become vocabulary rows with empty `add` arrays whose behavior lives entirely in their typed contract.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI domain models, JSON shared catalog/rules, JSON golden fixtures, Python audit/report tooling, Xcode/iOS 18 simulator tests.

## Global Constraints

- Work on `product-hardening-phase1` from `756f68f`; preserve every Phase 1–4 commit and the unrelated signing change in the main checkout.
- Follow the approved design at `docs/superpowers/specs/2026-09-03-product-hardening-phase-5-activity-contracts-design.md`.
- `ActivityContracts` is the only activity authority. Do not add a second activity mechanism, and do not implement Camping as `camping → hardcoded list of item IDs`.
- `ActivityNeed` stays closed and typed in Swift at exactly eight cases, pinned by a count test the way `PackingCapability`'s is.
- `CoverageResolver` remains the only coverage authority. Activity needs reach coverage only through the `ActivityNeed → PackingCapability` map; no new capability is added.
- Activities may participate in existing weather logic and must never manufacture weather. Camping contributes no rain need and no general warmth need. `overnightWarmth` resolves only when an existing cold signal is already present.
- Camping must never add tents, sleeping bags, sleeping pads, camp stoves, fuel, cookware, food storage, or campsite furniture.
- Unknown activity ids stay in `unknownActivityIDs`, keep their `unsupportedButSafe` diagnostic, and produce no items, capabilities, or inferred mappings.
- Do not relabel a broken input `contextOnly` to make the audit green. `tripType.other` becomes `contextOnly` only under the three earned checks in the design doc.
- User authority is preserved: Not Needed stays Not Needed, manual quantity stays authoritative, user-added items survive, packed state survives, explicit owner/carrier survive, and an activity change cannot resurrect an explicitly rejected item.
- Phase 5 does not own new weather signals, changed thresholds, cold-without-snow glove generation (Phase 6), seasonal hardening, footwear/clothing quantity redesign, central shared-party constraints (Phase 7), GPT/context intelligence, UI, persistence, or notifications/lifecycle.
- Golden regressions include any clothing quantity, weather signal/threshold, unrelated footwear/outerwear, ownership/carrier (beyond the reviewed flashlight row), override, persistence, or presentation change.
- F-1 remains P2 unless it blocks a current-schema comparison against `756f68f`. The Phase 6 cold-hand finding stays routed. Presentation remains frozen; physical-device verification remains deferred; M3B/M3C remain blocked.
- Do not edit `docs/plans/2026-09-02-product-hardening-program.md` before Task 7. Stop at the Phase 5 exit gate; do not begin Phase 6.

---

## File Map

- Create `ios/PackWise/Domain/Packing/ActivityContracts.swift`: the closed `ActivityNeed` vocabulary, the per-activity contract table, need→candidate resolution, and the need→capability map.
- Modify `ios/PackWise/Domain/Packing/PackingEngine.swift`: pass the snapshot into `ruleSuggestions`, emit need-derived suggestions with deterministic reason attribution, and gate `overnightWarmth` on existing cold signals.
- Modify `ios/PackWise/Domain/Packing/CoverageResolver.swift`: derive `.hiking` from `ActivityNeed.trailFootwear` instead of the `"hiking"` string, and widen `CoverageContext`'s documentation to say it is the shared normalized surface.
- Modify `shared/rules/activity-rules.json`: add `"camping": []`, empty `"hiking"`.
- Modify `shared/rules/base.json`: add the `"camping"` free-text keyword.
- Modify `shared/rules/reasons.json`: add the `activity.camping` template.
- Modify `shared/rules/party.json`: add `miscellaneous.flashlight` to `sharedByDefault` with a `singlePerParty` policy.
- Modify `shared/fixtures/golden/golden-fixtures.json`: add fixtures 28–32.
- Modify `docs/engine-audits/surfaced-input-contracts.json`: `activity/camping` → `deterministic`, `tripType/other` → `contextOnly`, `testIDs` on every otherwise-untested deterministic activity.
- Modify `scripts/audit_engine_inputs.py` and `scripts/tests/test_audit_engine_inputs.py`: the `testIDs` field, the `fixtureIDs`-or-`testIDs` untested rule, verified test references, and removal of the hardcoded `activities.add("camping")`.
- Create `ios/PackWiseTests/ActivityContractTests.swift`: the Phase 5 focused suite.
- Modify `ios/PackWiseTests/TripContextSnapshotTests.swift`, `ios/PackWiseTests/PackingEngineTests.swift`, `ios/PackWiseTests/CoverageTests.swift`, `ios/PackWiseTests/ReasonQualityTests.swift`, `ios/PackWiseTests/GoldenEngineTests.swift`: retire the Camping-is-missing assertions and add the Phase 5 contracts.
- Regenerate `api/generated/` via `scripts/build_intelligence_schemas.py` and add `ios/PackWiseTests/Goldens/28..32*.json` after semantic review.
- Create `docs/engine-audits/2026-09-03-phase-5-activity-contracts.md`: exit evidence, reviewed diff, routed findings.
- Modify `docs/plans/2026-09-02-product-hardening-program.md`: close Phase 5 only after all gates pass, in Task 7 only.

---

### Task 1: Establish the Typed Activity Contract Vocabulary

**Files:**
- Create: `ios/PackWise/Domain/Packing/ActivityContracts.swift`
- Modify: `shared/rules/activity-rules.json`
- Modify: `shared/rules/reasons.json`
- Test: `ios/PackWiseTests/ActivityContractTests.swift`
- Test: `ios/PackWiseTests/TripContextSnapshotTests.swift`

**Interfaces:**
- Consumes: `PackingRulesFile.activities`, `TripContextSnapshot.knownActivityIDs`.
- Produces: `ActivityNeed`, `ActivityContract`, `ActivityContracts.contract(for:)`, `ActivityContracts.needs(for:)`, `ActivityContracts.candidates(for:)`, `ActivityContracts.capabilities(for:)`.

- [ ] **Step 1: Write the failing vocabulary tests.** Create `ActivityContractTests.swift` with a closed-count test, a completeness test against the shared vocabulary, and the two contracts that carry needs. Pin the sets explicitly so two wrong implementations cannot agree.

```swift
import Foundation
import Testing
@testable import PackWise

/// Phase 5 — every surfaced activity has an explicit contract.
struct ActivityContractTests {
    private func rules() throws -> PackingRulesFile { try SharedLibrary.rules() }

    /// Closed like `PackingCapability`. Growing this is a design decision.
    @Test func activityNeedVocabularyIsClosedAtEight() {
        #expect(ActivityNeed.allCases.count == 8)
    }

    /// The contract table must cover exactly the surfaced vocabulary — no
    /// activity chip without a contract, no contract without a chip.
    @Test func everySurfacedActivityHasAContract() throws {
        let vocabulary = Set(try rules().activities.keys)
        #expect(Set(ActivityContracts.all.keys) == vocabulary)
        #expect(vocabulary.contains("camping"))
        let suggested = Set(TripType.allCases.flatMap(\.suggestedActivityIDs))
        #expect(suggested.isSubset(of: vocabulary))
    }

    @Test func campingAndHikingDeclareTheirNeeds() {
        #expect(ActivityContracts.needs(for: ["hiking"]) == [
            .trailFootwear, .dayCarry, .hydration, .blisterCare
        ])
        #expect(ActivityContracts.needs(for: ["camping"]) == [
            .trailFootwear, .hydration, .portableLight,
            .insectProtection, .sunProtection, .overnightWarmth
        ])
    }

    /// Composition is a set union, so the shared needs appear once.
    @Test func hikingAndCampingComposeIntoOneNeedSet() {
        let composed = ActivityContracts.needs(for: ["hiking", "camping"])
        #expect(composed == ActivityContracts.needs(for: ["camping", "hiking"]))
        #expect(composed.count == 8)
        #expect(composed.contains(.trailFootwear))
        #expect(composed.contains(.hydration))
    }

    /// Hiking's typed needs must resolve to exactly the IDs its JSON row
    /// holds today — the equivalence that lets Task 3 empty that row.
    @Test func hikingNeedsResolveToItsHistoricalItemSet() {
        #expect(ActivityContracts.candidates(for: ActivityContracts.needs(for: ["hiking"])) == [
            "activities.daypack",
            "footwear.hiking_shoes",
            "health.blister_pads",
            "hydration.water_bottle"
        ])
    }

    /// Camping is a packing signal, not a campsite planner.
    @Test func campingNeverProducesCampsiteLogistics() {
        let forbidden: Set<String> = [
            "activities.tent", "activities.sleeping_bag", "activities.sleeping_pad",
            "activities.camp_stove", "activities.camp_fuel", "activities.cookware",
            "activities.food_storage", "activities.camp_chair"
        ]
        let candidates = Set(ActivityContracts.candidates(for: ActivityContracts.needs(for: ["camping"])))
        #expect(candidates.isDisjoint(with: forbidden))
    }

    /// An id with no contract stays inert — never mapped onto a known one.
    @Test func unknownActivityHasNoContractAndNoNeeds() {
        #expect(ActivityContracts.contract(for: "cosplayConvention") == nil)
        #expect(ActivityContracts.needs(for: ["cosplayConvention"]).isEmpty)
        #expect(ActivityContracts.candidates(for: ActivityContracts.needs(for: ["cosplayConvention"])).isEmpty)
    }
}
```

- [ ] **Step 2: Write the failing snapshot reclassification test.** Replace `campingIsHonestlyClassifiedUnknownLikeAnyOtherRulelessActivity` in `TripContextSnapshotTests.swift` with its Phase 5 successor, keeping an unknown-id case in the same test so the inert path stays proved.

```swift
/// Phase 5 gives camping a real contract, so it joins the known
/// vocabulary. A genuinely unknown id must still degrade inertly.
@Test func campingIsKnownWhileGenuinelyUnknownActivitiesStayUnknown() throws {
    var context = baseContext()
    context.activities = ["hiking", "camping", "cosplayConvention"]
    let snapshot = TripContextCompiler.compile(context, rules: try rules())

    #expect(snapshot.knownActivityIDs == ["hiking", "camping"])
    #expect(snapshot.unknownActivityIDs == ["cosplayConvention"])
    #expect(snapshot.diagnostics.contains(ContextDiagnostic(
        field: "activities",
        outcome: .unsupportedButSafe(reason: "cosplayConvention: no rule in the engine's activity vocabulary")
    )))
}
```

- [ ] **Step 3: Run the focused tests and verify RED.** Run:

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/ActivityContractTests \
  -only-testing:PackWiseTests/TripContextSnapshotTests
```

Expected: compile failures for missing `ActivityNeed`, `ActivityContract`, and `ActivityContracts`; the snapshot test fails because `camping` is still unknown.

- [ ] **Step 4: Add the vocabulary row and reason template.** In `shared/rules/activity-rules.json` add `"camping": []` (keep `hiking` as it is for now — Task 3 empties it under a zero-diff gate). In `shared/rules/reasons.json` add:

```json
"activity.camping": "You're camping on this trip."
```

Do not add camping to `TripType.suggestedActivityIDs`: presentation is frozen, and camping already reaches the engine through the custom-activity field and has full `PackWiseActivityStyle` styling.

- [ ] **Step 5: Implement the typed contract layer.** Create `ActivityContracts.swift`:

```swift
import Foundation

/// The closed activity-need vocabulary — Phase 5.
///
/// A need is admitted only when more than one contract can plausibly want it
/// or when it must route into the Phase 4 capability model. An open
/// vocabulary degenerates into one label per item and generalizes nothing,
/// which is exactly the failure `PackingCapability` was closed to avoid.
enum ActivityNeed: String, CaseIterable, Hashable, Sendable {
    case trailFootwear = "activity.trail_footwear"
    case dayCarry = "activity.day_carry"
    case hydration = "activity.hydration"
    case blisterCare = "activity.blister_care"
    case portableLight = "activity.portable_light"
    case insectProtection = "activity.insect_protection"
    case sunProtection = "activity.sun_protection"
    /// The only weather-gated need. Resolves to nothing unless an existing
    /// cold signal is already present — camping never assumes cold nights.
    case overnightWarmth = "activity.overnight_warmth"

    var isWeatherGated: Bool { self == .overnightWarmth }
}

/// One surfaced activity's product contract.
enum ActivityContract: Hashable, Sendable {
    /// Drives generation. `needs` may be empty when the activity's effect is
    /// still expressed by its `rules.activities` row.
    case deterministic(needs: Set<ActivityNeed>)
    /// Surfaced and stored, with no independent engine effect.
    case contextOnly
}

/// The single activity authority, the way `CoverageResolver` is the single
/// coverage authority. Typed and closed in Swift; `activity-rules.json`
/// remains the surfaced vocabulary and the item adds not yet migrated here.
enum ActivityContracts {
    static let all: [String: ActivityContract] = [
        "hiking": .deterministic(needs: [.trailFootwear, .dayCarry, .hydration, .blisterCare]),
        "camping": .deterministic(needs: [
            .trailFootwear, .hydration, .portableLight,
            .insectProtection, .sunProtection, .overnightWarmth
        ]),
        "walking": .deterministic(needs: []),
        "running": .deterministic(needs: []),
        "sightseeing": .deterministic(needs: []),
        "niceDinner": .deterministic(needs: []),
        "nightlife": .deterministic(needs: []),
        "shopping": .deterministic(needs: []),
        "museums": .deterministic(needs: []),
        "work": .deterministic(needs: []),
        "wildlife": .deterministic(needs: []),
        "swimming": .deterministic(needs: []),
        "beachDays": .deterministic(needs: []),
        "snorkeling": .deterministic(needs: []),
        "boatTrip": .deterministic(needs: []),
        "yoga": .deterministic(needs: []),
        "photography": .deterministic(needs: [])
    ]

    /// Sorted so callers never depend on dictionary iteration order.
    static let needCandidates: [ActivityNeed: [String]] = [
        .trailFootwear: ["footwear.hiking_shoes"],
        .dayCarry: ["activities.daypack"],
        .hydration: ["hydration.water_bottle"],
        .blisterCare: ["health.blister_pads"],
        .portableLight: ["miscellaneous.flashlight"],
        .insectProtection: ["toiletries.insect_repellent"],
        .sunProtection: ["toiletries.sunscreen"],
        .overnightWarmth: ["clothing.thermal_top"]
    ]

    /// The only bridge from an activity need into Phase 4's closed coverage
    /// vocabulary. Phase 5 adds no capability.
    static let needCapabilities: [ActivityNeed: PackingCapability] = [
        .trailFootwear: .hiking
    ]

    static func contract(for activityID: String) -> ActivityContract? {
        all[activityID]
    }

    static func needs(for activityIDs: some Sequence<String>) -> Set<ActivityNeed> {
        activityIDs.reduce(into: Set<ActivityNeed>()) { result, id in
            if case .deterministic(let needs) = all[id] { result.formUnion(needs) }
        }
    }

    static func candidates(for needs: Set<ActivityNeed>) -> [String] {
        needs.flatMap { needCandidates[$0] ?? [] }.sorted()
    }

    static func capabilities(for needs: Set<ActivityNeed>) -> Set<PackingCapability> {
        Set(needs.compactMap { needCapabilities[$0] })
    }

    /// The activity that owns a need-derived item's reason: the first
    /// declaring activity in the trip's own normalized selection order, which
    /// is exactly what `for activity in context.activities` already does.
    static func originatingActivity(for need: ActivityNeed, in orderedActivityIDs: [String]) -> String? {
        orderedActivityIDs.first { id in
            if case .deterministic(let needs) = all[id] { return needs.contains(need) }
            return false
        }
    }
}
```

- [ ] **Step 6: Verify GREEN and zero behavior drift.** Run the focused command from Step 3, then:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 scripts/report_engine_goldens.py \
  --baseline-ref 756f68f --candidate ios/PackWiseTests/Goldens --format markdown
```

Expected: focused tests pass. The golden diff is **not** clean yet — fixture 18 reclassifies `camping` from unknown to known — but no item, quantity, coverage, or constraint row may change, because Task 1 adds no candidate. Confirm exactly that before continuing.

- [ ] **Step 7: Run the shared-data gates.** Run `python3 scripts/build_intelligence_schemas.py` then `python3 scripts/validate_shared.py`. Expected: `api/generated/vocab/activities.json` gains `camping`, the manifest digest changes, and shared validation passes.

- [ ] **Step 8: Commit the contract vocabulary.**

```bash
git add ios/PackWise/Domain/Packing/ActivityContracts.swift \
  ios/PackWiseTests/ActivityContractTests.swift \
  ios/PackWiseTests/TripContextSnapshotTests.swift \
  shared/rules/activity-rules.json shared/rules/reasons.json api/generated
git commit -m "feat: type the surfaced activity contract vocabulary"
```

### Task 2: Resolve Activity Needs Into Candidates

**Files:**
- Modify: `ios/PackWise/Domain/Packing/PackingEngine.swift`
- Modify: `shared/rules/base.json`
- Modify: `shared/rules/party.json`
- Test: `ios/PackWiseTests/ActivityContractTests.swift`

**Interfaces:**
- Consumes: `ActivityContracts`, `TripContextSnapshot`, `CoverageContext(snapshot:thresholds:)`.
- Produces: `PackingEngine.ruleSuggestions(for:snapshot:)` and need-derived `RuleSuggestion` rows with `signal: .activity` and code `activity.<originating id>`.

- [ ] **Step 1: Write the failing Camping-only behavior test.** Assert the exact five items, the exact absent families, and the reason attribution. Do not assert "the list is short."

```swift
@Test func campingAloneAddsFiveItemsAndNoCampsiteLogistics() throws {
    let engine = try makeEngine()
    let ids = { (trip: TripContext) in Set(engine.generate(context: trip).compactMap(\.canonicalItemID)) }
    let base = campingContext(activities: ["sightseeing"])
    let camping = campingContext(activities: ["sightseeing", "camping"])

    #expect(ids(camping).subtracting(ids(base)) == [
        "footwear.hiking_shoes",
        "hydration.water_bottle",
        "miscellaneous.flashlight",
        "toiletries.insect_repellent",
        "toiletries.sunscreen"
    ])
    // Walking shoes are not "added" — coverage removes them. Prove it here
    // so the delta above cannot hide a footwear regression.
    #expect(ids(base).subtracting(ids(camping)) == ["footwear.walking_shoes"])
}
```

`campingContext` is a helper using Yellowstone, `weather: nil`, `startDate` 2027-08-15, 4 days, `.outdoor`, `.roadTripLuggage`, `.balanced` — a mild trip with no weather signals and no seasonal warmth fallback.

- [ ] **Step 2: Write the failing weather-boundary tests.** Three cases, each asserting an absence that would be a defect if Camping manufactured weather.

```swift
@Test func campingNeverManufacturesRainOrWarmth() throws {
    let engine = try makeEngine()
    let mild = try #require(engine.generateDetailed(context: campingContext(activities: ["camping"])).items as [PackingItemDraft]?)
    let ids = Set(mild.compactMap(\.canonicalItemID))
    #expect(!ids.contains("clothing.rain_jacket"))
    #expect(!ids.contains("essentials.umbrella_compact"))
    #expect(!ids.contains("clothing.winter_coat"))
    #expect(!ids.contains("clothing.light_sweater"))
    #expect(!ids.contains("clothing.thermal_top"))   // overnightWarmth is gated
}

@Test func overnightWarmthResolvesOnlyWithAnExistingColdSignal() throws {
    let engine = try makeEngine()
    let cold = coldCampingContext()   // DenverColdOutdoor-equivalent forecast
    let ids = Set(engine.generate(context: cold).compactMap(\.canonicalItemID))
    #expect(ids.contains("clothing.thermal_top"))

    let campingRow = try #require(engine.generateDetailed(context: cold).items
        .first { $0.canonicalItemID == "clothing.thermal_top" })
    // The item exists because the cold signal exists; camping only made it
    // relevant, so the weather reason still outranks the activity reason.
    #expect(campingRow.reasonCode.hasPrefix("weather."))
}

@Test func campingPlusRainProducesExactlyOneShellAndNoCampingRainItem() throws {
    let engine = try makeEngine()
    let items = engine.generate(context: rainyCampingContext())
    let shells = items.filter { $0.canonicalItemID == "clothing.rain_jacket" }
    #expect(shells.count == 1)
    #expect(!items.contains { $0.canonicalItemID == "activities.rain_cover" })
}
```

- [ ] **Step 3: Write the failing reason-attribution test.** Both orders must produce one row; only the reason may differ.

```swift
@Test func sharedNeedsAttributeToTheFirstDeclaringActivity() throws {
    let engine = try makeEngine()
    func bottleReason(_ activities: [String]) throws -> String {
        let items = engine.generate(context: campingContext(activities: activities))
        let bottles = items.filter { $0.canonicalItemID == "hydration.water_bottle" }
        #expect(bottles.count == 1)
        return try #require(bottles.first).reasonCode
    }
    #expect(try bottleReason(["hiking", "camping"]) == "activity.hiking")
    #expect(try bottleReason(["camping", "hiking"]) == "activity.camping")
}
```

- [ ] **Step 4: Run `ActivityContractTests` and verify RED.** Expected: camping still adds nothing, so the delta test fails with an empty set and the attribution test fails on a missing row.

- [ ] **Step 5: Wire the activity family to the snapshot.** Change `ruleSuggestions(for:)` to `ruleSuggestions(for context: TripContext, snapshot: TripContextSnapshot)`. `generateSimple` passes the generation snapshot. `generateForParty` compiles the trip-wide snapshot once — `TripContextCompiler.compile(tripWideContext(context), rules: rules)` — and passes it; it must not compile per traveler. Activities are trip-scoped (`ownerScope: "trip"` in the contract ledger), so need-derived rows join the trip-wide suggestion set and then split shared vs personal through the existing `rules.party.sharedByDefault` path.

- [ ] **Step 6: Emit need-derived suggestions.** Immediately after the existing `for activity in context.activities` loop in `ruleSuggestions`, add:

```swift
let ordered = snapshot.knownActivityIDs
let activityNeeds = ActivityContracts.needs(for: ordered)
let coverageContext = CoverageContext(snapshot: snapshot, thresholds: rules.weather.thresholds)
let coldSignals: Set<WeatherSignal> = [.snowExposure, .sustainedCold, .freezingCold, .coldEvenings]
let hasColdSignal = !coverageContext.weatherSignals.isDisjoint(with: coldSignals)

for need in activityNeeds.sorted(by: { $0.rawValue < $1.rawValue }) {
    // The weather boundary: a gated need never creates its own weather.
    if need.isWeatherGated && !hasColdSignal { continue }
    guard let origin = ActivityContracts.originatingActivity(for: need, in: ordered) else { continue }
    add(
        ActivityContracts.needCandidates[need] ?? [],
        signal: .activity,
        code: "activity.\(origin)",
        arguments: ["destination": context.destination.displayName],
        fallback: activityReason(origin, destination: context.destination.displayName)
    )
}
```

Sorting the needs makes emission order explicit rather than set-iteration dependent. Extend `activityReason` with `case "camping": "You're camping on this trip."`.

- [ ] **Step 7: Add the free-text keyword and the reviewed party sharing row.** In `shared/rules/base.json` add `"camping": "camping"` to `free_text_keywords` — the full word, not `"camp"`, which would also match "campus". In `shared/rules/party.json` add `miscellaneous.flashlight` to `sharedByDefault` and `"miscellaneous.flashlight": {"policy": "singlePerParty"}` to `sharingPolicies`. This is a data row inside the existing mechanism; central shared-party constraints remain Phase 7.

- [ ] **Step 8: Add the party and light-packing tests.**

```swift
@Test func aPartyCampingTripGetsOneFlashlight() throws {
    let engine = try makeEngine()
    let items = engine.generate(context: campingContext(activities: ["camping"], party: family(of: 4)))
    let lights = items.filter { $0.canonicalItemID == "miscellaneous.flashlight" }
    #expect(lights.count == 1)
    #expect(lights.first?.ownershipType == .shared)
}

/// Camping must not blow past an existing bag constraint — the optional
/// flashlight is trimmed by the constraint that already exists.
@Test func campingRespectsLightPackingConstraints() throws {
    let engine = try makeEngine()
    let generation = engine.generateDetailed(
        context: campingContext(activities: ["camping"], bag: .carryOn, style: .light)
    )
    let ids = Set(generation.items.compactMap(\.canonicalItemID))
    #expect(!ids.contains("miscellaneous.flashlight"))
    #expect(ids.contains("hydration.water_bottle"))
    #expect(generation.constraintDecisions.contains {
        $0.constraint == "bag.space_constrained" && $0.items.contains("miscellaneous.flashlight")
    })
}
```

- [ ] **Step 9: Add the user-authority test.** A user-added multifunction item that already satisfies a Camping need must survive and prevent a duplicate.

```swift
@Test func aUserAddedBottleSatisfiesCampingHydrationWithoutDuplication() throws {
    let engine = try makeEngine()
    let existing = [PackingItemDraft(
        canonicalItemID: "hydration.water_bottle",
        displayName: "My filter bottle",
        category: .essentials,
        quantity: 1,
        importance: .normal,
        sourceSignals: [.activity],
        reason: "Mine",
        isUserAdded: true
    )]
    let items = engine.generate(context: campingContext(activities: ["camping"]), existing: existing)
    let bottles = items.filter { $0.canonicalItemID == "hydration.water_bottle" }
    #expect(bottles.count == 1)
    #expect(bottles.first?.isUserAdded == true)
    #expect(bottles.first?.displayName == "My filter bottle")
}
```

- [ ] **Step 10: Verify GREEN and review the diff.** Run `ActivityContractTests`, `PackingEngineTests`, `ConstraintTests`, `CoverageTests`, `ClothingQuantityTests`, and `WeatherChangeTests`. Then rerun the semantic diff against `756f68f`. Expected: only fixture 18 changes, gaining the Camping need items. No quantity, weather, constraint, or ownership change anywhere else.

- [ ] **Step 11: Commit need resolution.**

```bash
git add ios/PackWise/Domain/Packing/PackingEngine.swift \
  ios/PackWiseTests/ActivityContractTests.swift \
  shared/rules/base.json shared/rules/party.json
git commit -m "feat: resolve camping needs through the activity contract layer"
```

### Task 3: Compose Hiking and Camping Through the Coverage Model

**Files:**
- Modify: `ios/PackWise/Domain/Packing/CoverageResolver.swift`
- Modify: `shared/rules/activity-rules.json`
- Test: `ios/PackWiseTests/ActivityContractTests.swift`
- Test: `ios/PackWiseTests/CoverageTests.swift`

**Interfaces:**
- Consumes: `ActivityContracts.capabilities(for:)`, `CoverageContext.activityIDs`.
- Produces: `CoverageResolver.needs(context:)` deriving `.hiking` from `ActivityNeed.trailFootwear`.

- [ ] **Step 1: Write the failing composition test.** Camping alone must earn the hiking capability, and Hiking + Camping must resolve to one pair with exact Phase 4 evidence.

```swift
@Test func campingEarnsTrailFootwearCoverageWithoutTheHikingString() throws {
    let engine = try makeEngine()
    let generation = engine.generateDetailed(context: campingContext(activities: ["camping", "walking"]))
    let ids = Set(generation.items.compactMap(\.canonicalItemID))
    #expect(ids.contains("footwear.hiking_shoes"))
    #expect(!ids.contains("footwear.walking_shoes"))

    let suppression = try #require(generation.coverageSuppressions.first {
        $0.canonicalItemID == "footwear.walking_shoes"
    })
    #expect(suppression.covered == [
        CapabilityCoverage(capability: .everydayWalking, coveringItemID: "footwear.hiking_shoes")
    ])
}

@Test func hikingPlusCampingIsOneComposedTripNotTwoChecklists() throws {
    let engine = try makeEngine()
    let items = engine.generateDetailed(context: campingContext(activities: ["hiking", "camping"])).items
    func count(_ id: String) -> Int { items.filter { $0.canonicalItemID == id }.count }
    #expect(count("hydration.water_bottle") == 1)
    #expect(count("footwear.hiking_shoes") == 1)
    #expect(count("activities.daypack") == 1)
    #expect(count("health.blister_pads") == 1)
    #expect(items.first { $0.canonicalItemID == "hydration.water_bottle" }?.quantity == 1)
}
```

- [ ] **Step 2: Write the failing hiking-only regression test.** Hiking's behavior must be byte-identical before and after its JSON row is emptied.

```swift
@Test func hikingOnlyBehaviorIsUnchangedByTheContractMigration() throws {
    let engine = try makeEngine()
    let items = engine.generate(context: campingContext(activities: ["hiking"]))
    let ids = Set(items.compactMap(\.canonicalItemID))
    #expect(ids.isSuperset(of: [
        "activities.daypack", "footwear.hiking_shoes",
        "health.blister_pads", "hydration.water_bottle"
    ]))
    for item in items where item.canonicalItemID == "activities.daypack" {
        #expect(item.reasonCode == "activity.hiking")
    }
}
```

- [ ] **Step 3: Run the focused tests and verify RED.** Expected: `campingEarnsTrailFootwearCoverage...` fails because `CoverageResolver.needs` still keys on the literal `"hiking"`.

- [ ] **Step 4: Derive the hiking capability from the need.** In `CoverageResolver.needs(context:)` replace:

```swift
if activities.contains("hiking") {
    needs.insert(.hiking)
}
```

with:

```swift
needs.formUnion(ActivityContracts.capabilities(for: ActivityContracts.needs(for: activities)))
```

Leave every other need derivation exactly as it is — the running, beach, formal, ski, and weather branches are unchanged. Widen `CoverageContext`'s doc comment to say it is the normalized surface the coverage **and activity** families read; do not rename the type.

- [ ] **Step 5: Empty hiking's JSON row under a zero-diff gate.** Set `"hiking": []` in `shared/rules/activity-rules.json`, making the typed contract hiking's sole source of truth. Then run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 scripts/report_engine_goldens.py \
  --baseline-ref 756f68f --candidate ios/PackWiseTests/Goldens --format markdown
```

Expected: fixture 18 shows only the Camping additions from Task 2 — no hiking item may appear, disappear, change quantity, or change reason. If any hiking row moves, the need→candidate table is wrong; fix it rather than re-recording the golden.

- [ ] **Step 6: Verify the Phase 4 coverage matrix is untouched.** Run `CoverageTests` in full. All eight Phase 4 overlap families (running+walking, hiking+walking, running+hiking+walking, formal business, rain+wind, winter layering, ski hands, existing-shell) must pass unchanged. Add one row to the Phase 4 matrix for `camping + walking → keep footwear.hiking_shoes, suppress footwear.walking_shoes`.

- [ ] **Step 7: Commit the composition.**

```bash
git add ios/PackWise/Domain/Packing/CoverageResolver.swift \
  ios/PackWiseTests/ActivityContractTests.swift ios/PackWiseTests/CoverageTests.swift \
  shared/rules/activity-rules.json
git commit -m "feat: compose camping and hiking through capability coverage"
```

### Task 4: Close `tripType.other` and the Unknown-Activity Contract

**Files:**
- Test: `ios/PackWiseTests/ActivityContractTests.swift`
- Test: `ios/PackWiseTests/PackingEngineTests.swift`

**Interfaces:**
- Consumes: `PackingRulesFile.tripTypes`, `PackingEngine.generateDetailed`.
- Produces: executable proof that `Other` is a declared identity, not a missing rule.

- [ ] **Step 1: Write the failing declared-identity tests.** `Other` earns `contextOnly` only through all three checks; none of them may be replaced by "the list looks fine."

```swift
/// `Other` means "no additional trip-type-specific needs; activities,
/// preferences, and context carry the meaning." That is a declared empty
/// rule, not a failed lookup — and it must stay the only one.
@Test func otherIsADeclaredIdentityTripType() throws {
    let tripTypes = try rules().tripTypes
    let other = try #require(tripTypes["other"])
    #expect(other.add.isEmpty)
    #expect(other.preferActivities?.isEmpty ?? true)

    let emptyRules = tripTypes.filter { $0.value.add.isEmpty }.keys.sorted()
    #expect(emptyRules == ["other"], "a trip type silently lost its rule: \(emptyRules)")
    #expect(Set(tripTypes.keys) == Set(TripType.allCases.map(\.rawValue)))
}

/// An `Other` trip still produces a complete, coherent list, and every row
/// is explained by base essentials, activities, weather, or party — never
/// by an invented `other` recommendation.
@Test func otherTripsAreCarriedEntirelyByActivitiesAndContext() throws {
    let engine = try makeEngine()
    let other = campingContext(activities: ["sightseeing", "walking"], type: .other)
    let items = engine.generateDetailed(context: other).items
    #expect(items.count > 10)
    #expect(!items.contains { $0.reasonCode == "trip_type.generic" })
    for item in items {
        #expect(item.sourceSignals.contains { $0 != .tripType })
    }
}
```

- [ ] **Step 2: Write the failing unknown-activity inertness test.** Keep the fixture-25 property provable at the unit level too.

```swift
@Test func anUnknownActivityChangesNothingAtAll() throws {
    let engine = try makeEngine()
    func rows(_ activities: [String]) -> [String] {
        engine.generate(context: campingContext(activities: activities))
            .compactMap(\.canonicalItemID).sorted()
    }
    #expect(rows(["sightseeing", "walking"]) == rows(["sightseeing", "walking", "cosplayConvention"]))

    let generation = engine.generateDetailed(
        context: campingContext(activities: ["sightseeing", "walking", "cosplayConvention"])
    )
    #expect(generation.contextDiagnostics.contains {
        $0.field == "activities" && $0.outcome.isUnsupportedButSafe
    })
}
```

- [ ] **Step 3: Run the focused tests and verify RED or GREEN honestly.** These tests may pass on first run — `other` is already a declared empty rule and unknown ids are already inert. That is the point: the tests convert an undocumented accident into a guarded contract. If any fails, `other` is a defect and must be routed forward, not relabelled.

- [ ] **Step 4: Retire the Camping-is-missing ledger tests.** In `PackingEngineTests.swift`, replace `campingIsRecordedMissingAndPointsAtFixture18` with its Phase 5 successor and simplify `surfacedInputContractCoversEverySuggestedActivity`:

```swift
@Test func campingIsRecordedDeterministicWithFixtureEvidence() throws {
    let records = try loadSurfacedInputContracts()
    let camping = try #require(records.first { $0.kind == "activity" && $0.id == "camping" })
    #expect(camping.engineContract == "deterministic")
    #expect(camping.fixtureIDs.contains("28-yellowstone-4d-camping-mild"))
    #expect(camping.fixtureIDs.contains("18-reykjavik-64d-roadtrip-camping-seasonal"))
    #expect(camping.iconContract == "tent")
}

@Test func otherIsRecordedContextOnlyWithTestEvidence() throws {
    let records = try loadSurfacedInputContracts()
    let other = try #require(records.first { $0.kind == "tripType" && $0.id == "other" })
    #expect(other.engineContract == "contextOnly")
    #expect(other.testIDs.contains("otherIsADeclaredIdentityTripType"))
}

@Test func noSurfacedInputRemainsMissing() throws {
    let records = try loadSurfacedInputContracts()
    let dead = records.filter { $0.engineContract == "missing" }.map { "\($0.kind)/\($0.id)" }
    #expect(dead.isEmpty, "surfaced inputs still doing nothing: \(dead)")
}
```

In `surfacedInputContractCoversEverySuggestedActivity`, drop `.union(["camping"])` — camping is now a real vocabulary key — and update the doc comment.

- [ ] **Step 5: Update the reason-template guard.** `ReasonQualityTests.everyActivityRuleHasSpecificTemplate` walks `rules.activities.keys`; add a companion assertion so an emptied JSON row cannot hide a missing template:

```swift
for activityID in ActivityContracts.all.keys {
    #expect(
        rules.reasons.templates["activity.\(activityID)"] != nil,
        "activity '\(activityID)' has no reason template"
    )
}
```

- [ ] **Step 6: Verify GREEN.** Run `ActivityContractTests`, `PackingEngineTests`, and `ReasonQualityTests`. Expected: pass; the ledger tests fail only until Task 5 writes the ledger rows they read.

- [ ] **Step 7: Commit the contract closures.**

```bash
git add ios/PackWiseTests/ActivityContractTests.swift \
  ios/PackWiseTests/PackingEngineTests.swift ios/PackWiseTests/ReasonQualityTests.swift
git commit -m "test: pin the other and unknown-activity contracts"
```

### Task 5: Close the Surfaced-Input Contract Audit

**Files:**
- Modify: `docs/engine-audits/surfaced-input-contracts.json`
- Modify: `scripts/audit_engine_inputs.py`
- Modify: `scripts/tests/test_audit_engine_inputs.py`

**Interfaces:**
- Consumes: the contract records and `ios/PackWiseTests/*.swift`.
- Produces: an optional `testIDs` field, a `fixtureIDs`-or-`testIDs` untested rule, and verified test references.

- [ ] **Step 1: Write the failing Python tests.** Prove the new rule and, critically, that it cannot be used to type a green audit.

```python
def test_a_named_test_satisfies_the_untested_bucket(self):
    records, errors = load_contracts(self.write_contracts([
        record(kind="activity", id_="yoga", engineContract="deterministic",
               fixtureIDs=[], testIDs=["yogaAddsAMatAndWorkoutClothes"]),
    ]))
    self.assertEqual(errors, [])
    self.assertEqual(build_report(records).untested, [])

def test_a_nonexistent_named_test_is_a_schema_error(self):
    records, errors = load_contracts(self.write_contracts([
        record(kind="activity", id_="yoga", engineContract="deterministic",
               fixtureIDs=[], testIDs=["thisTestDoesNotExist"]),
    ]))
    errors.extend(check_test_references(records, self.repo_root))
    self.assertTrue(any("thisTestDoesNotExist" in e for e in errors))

def test_no_record_remains_missing(self):
    records, _ = load_contracts(REAL_CONTRACTS_PATH)
    self.assertEqual([f"{r.kind}/{r.id}" for r in build_report(records).dead], [])
```

- [ ] **Step 2: Run the Python tests and verify RED.**

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -v
```

Expected: failures for the unknown `testIDs` field and the missing `check_test_references`.

- [ ] **Step 3: Implement `testIDs` and reference verification.** In `audit_engine_inputs.py`:

- add `test_ids: Tuple[str, ...]` to `ContractRecord`, parsed like `fixtureIDs` (absent means empty);
- change `Report.untested` to `engine_contract == "deterministic" and not r.fixture_ids and not r.test_ids`;
- add `check_test_references(records, repo_root)` that reads every `ios/PackWiseTests/*.swift`, collects `func <name>(` via regex, and returns one error per `testIDs` entry with no matching function;
- call it from `main` alongside `check_completeness`, so a fabricated test name fails schema validation (exit 1) rather than quietly greening the report;
- delete the hardcoded `activities.add("camping")` in `discover_expected_ids` and the comment above it — camping is now a real `activity-rules.json` key;
- update the module docstring: the DEAD bucket is expected to be empty from Phase 5 on, and `contextOnly` still may not be used to hide a defect.

- [ ] **Step 4: Update the contract ledger.** In `surfaced-input-contracts.json`:

- `activity/camping`: `engineContract` → `deterministic`; `fixtureIDs` → `["18-reykjavik-64d-roadtrip-camping-seasonal", "28-yellowstone-4d-camping-mild", "29-yellowstone-4d-hiking-camping", "30-seattle-5d-camping-rain", "31-phoenix-5d-camping-hot", "32-denver-5d-camping-cold"]`; add a `note` naming the Camping V1 boundary;
- `activity/hiking`: add fixtures 29 and 32 and `testIDs: ["hikingOnlyBehaviorIsUnchangedByTheContractMigration", "hikingPlusCampingIsOneComposedTripNotTwoChecklists"]`;
- `tripType/other`: `engineContract` → `contextOnly`; `testIDs: ["otherIsADeclaredIdentityTripType", "otherTripsAreCarriedEntirelyByActivitiesAndContext"]`; `note` recording the declared-identity decision;
- every deterministic activity with no fixture (`nightlife`, `shopping`, `museums`, `wildlife`, `snorkeling`, `boatTrip`, `yoga`, `photography`): add `testIDs` naming the real per-activity test written in Step 5.

Do not add `testIDs` to a row whose test does not exist — Step 3's verifier will reject it, and that rejection is the point.

- [ ] **Step 5: Write the per-activity observable-effect test.** One table-driven test in `ActivityContractTests.swift`, plus one named test per previously untested activity so the ledger has a real reference to point at.

```swift
/// Requirement 3: executable coverage for every deterministic activity.
/// Each row asserts an item the activity alone is responsible for, proved
/// as a delta against the same trip without it — presence in a full list
/// proves nothing.
@Test func everyDeterministicActivityHasAnObservableEffect() throws {
    let engine = try makeEngine()
    let expected: [String: Set<String>] = [
        "nightlife": ["clothing.nice_outfit"],
        "shopping": ["essentials.reusable_bag"],
        "museums": ["clothing.light_sweater"],
        "wildlife": ["activities.binoculars", "electronics.camera"],
        "snorkeling": ["activities.snorkel", "footwear.water_shoes"],
        "boatTrip": ["activities.dry_bag", "health.motion_sickness"],
        "yoga": ["activities.yoga_mat_travel"],
        "photography": ["electronics.camera", "electronics.memory_card"]
        // running/walking/hiking/camping/swimming/beachDays/work/
        // niceDinner/sightseeing are pinned by their own named tests and
        // golden fixtures.
    ]
    for (activity, mustAppear) in expected.sorted(by: { $0.key < $1.key }) {
        let without = Set(engine.generate(context: campingContext(activities: ["sightseeing"]))
            .compactMap(\.canonicalItemID))
        let with = Set(engine.generate(context: campingContext(activities: ["sightseeing", activity]))
            .compactMap(\.canonicalItemID))
        #expect(mustAppear.isSubset(of: with.subtracting(without)),
                "\(activity) produced no observable effect")
    }
}
```

Then add one thin named wrapper per activity (`yogaAddsAMatAndWorkoutClothes`, `nightlifeAddsANiceOutfit`, …) asserting that activity's row, so each ledger `testIDs` entry resolves to a real function.

- [ ] **Step 6: Verify GREEN across both toolchains.** Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests
PYTHONDONTWRITEBYTECODE=1 python3 scripts/audit_engine_inputs.py \
  --contracts docs/engine-audits/surfaced-input-contracts.json --format markdown
```

Expected: all Python tests pass; the audit reports **DEAD: 0**, one `contextOnly` row (`tripType/other`), and an UNTESTED bucket containing only the nine context chips. Chips are not Phase 5's scope; they stay visible as a routed finding, not silenced.

- [ ] **Step 7: Commit the ledger closure.**

```bash
git add docs/engine-audits/surfaced-input-contracts.json \
  scripts/audit_engine_inputs.py scripts/tests/test_audit_engine_inputs.py \
  ios/PackWiseTests/ActivityContractTests.swift
git commit -m "test: close the surfaced input contract audit"
```

### Task 6: Record and Review the Camping Golden Fixtures

**Files:**
- Modify: `shared/fixtures/golden/golden-fixtures.json`
- Modify: `ios/PackWiseTests/GoldenEngineTests.swift`
- Create: `ios/PackWiseTests/Goldens/28..32*.json`

**Interfaces:**
- Consumes: the fixture harness and `report_engine_goldens.py`.
- Produces: five reviewed Camping fixtures and fixture-level contracts.

- [ ] **Step 1: Add the five fixture definitions.** Append to `shared/fixtures/golden/golden-fixtures.json`, each with an honest `proves` line:

| id | destination | weatherFixture | start | days | tripType | activities | bag | style |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `28-yellowstone-4d-camping-mild` | Yellowstone | `null` | 2027-08-15 | 4 | outdoor | `["camping"]` | roadTripLuggage | balanced |
| `29-yellowstone-4d-hiking-camping` | Yellowstone | `null` | 2027-08-15 | 4 | outdoor | `["hiking","camping"]` | roadTripLuggage | balanced |
| `30-seattle-5d-camping-rain` | Seattle | `SeattleWetCity` | 2026-10-05 | 5 | outdoor | `["camping"]` | checked | balanced |
| `31-phoenix-5d-camping-hot` | Phoenix | `PhoenixHotDry` | 2026-07-13 | 5 | outdoor | `["camping"]` | checked | balanced |
| `32-denver-5d-camping-cold` | Denver | `DenverColdOutdoor` | 2026-11-09 | 5 | outdoor | `["hiking","camping"]` | checked | prepared |

Fixture 28's `weatherFixture: null` with an August start above 30° north is deliberately the *no-signal* case: no forecast, no seasonal warmth fallback. It isolates Camping's contract from every weather path. Fixtures 28 and 29 differ by one activity so the diff between them is exactly Hiking's contribution.

- [ ] **Step 2: Write the failing fixture contracts in `GoldenEngineTests`.**

```swift
@Test func campingFixturesProveTheV1Contract() throws {
    let mild = try renderFixture(id: "28-yellowstone-4d-camping-mild")
    let mildIDs = Set(mild.items.map(\.canonicalItemID))
    #expect(mildIDs.isSuperset(of: [
        "footwear.hiking_shoes", "hydration.water_bottle",
        "miscellaneous.flashlight", "toiletries.insect_repellent",
        "toiletries.sunscreen"
    ]))
    #expect(!mildIDs.contains("footwear.walking_shoes"))
    #expect(!mildIDs.contains("clothing.rain_jacket"))
    #expect(!mildIDs.contains("clothing.thermal_top"))

    let composed = try renderFixture(id: "29-yellowstone-4d-hiking-camping")
    #expect(composed.items.filter { $0.canonicalItemID == "hydration.water_bottle" }.count == 1)
    #expect(composed.items.filter { $0.canonicalItemID == "footwear.hiking_shoes" }.count == 1)

    let rain = try renderFixture(id: "30-seattle-5d-camping-rain")
    #expect(rain.items.filter { $0.canonicalItemID == "clothing.rain_jacket" }.count == 1)

    let hot = try renderFixture(id: "31-phoenix-5d-camping-hot")
    #expect(hot.items.filter { $0.canonicalItemID == "toiletries.sunscreen" }.count == 1)

    let cold = try renderFixture(id: "32-denver-5d-camping-cold")
    #expect(Set(cold.items.map(\.canonicalItemID)).contains("clothing.thermal_top"))
}

/// The long trip must improve because Camping has a general contract — not
/// because Reykjavik or 64 days is special-cased. Same deltas as fixture 28.
@Test func theLongRoadTripImprovesThroughTheGeneralCampingContract() throws {
    let long = try renderFixture(id: "18-reykjavik-64d-roadtrip-camping-seasonal")
    let ids = Set(long.items.map(\.canonicalItemID))
    #expect(ids.isSuperset(of: [
        "miscellaneous.flashlight", "toiletries.insect_repellent", "toiletries.sunscreen"
    ]))
    #expect(long.items.filter { $0.canonicalItemID == "hydration.water_bottle" }.count == 1)
    #expect(!ids.contains("clothing.thermal_top"))   // August: no cold signal
}
```

- [ ] **Step 3: Run `GoldenEngineTests` and verify RED.** Expected: "No golden for 28-…" issues for the five new fixtures.

- [ ] **Step 4: Run shared validation before recording.** Run `python3 scripts/validate_shared.py`. Expected: the five new fixture definitions resolve their destination and weather ids cleanly.

- [ ] **Step 5: Record goldens and stop on the deliberate recording failure.**

```bash
TEST_RUNNER_PACKWISE_RECORD_GOLDENS=1 xcodebuild test \
  -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/GoldenEngineTests
```

Expected: 32 files written and one recorded issue instructing review.

- [ ] **Step 6: Review and classify the semantic diff against `756f68f`.** Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 scripts/report_engine_goldens.py \
  --baseline-ref 756f68f --candidate ios/PackWiseTests/Goldens --format markdown
```

Two buckets. `EXPECTED ACTIVITY CHANGES` may contain: the five new fixtures; fixture 18's Camping additions and any coverage suppression they cause. `UNEXPECTED BEHAVIOR CHANGES` must be empty — reject any clothing quantity change, weather signal or generation change, footwear/outerwear change not explained by a Camping need, ownership/carrier change, override regression, or reason change in a fixture without Camping. Read every fixture 28–32 by hand against the Camping V1 boundary before accepting it: a fixture nobody read is not evidence.

- [ ] **Step 7: Run goldens without record mode.** Expected: `GoldenEngineTests` pass against the reviewed files.

- [ ] **Step 8: Commit fixtures and reviewed goldens together.**

```bash
git add shared/fixtures/golden/golden-fixtures.json \
  ios/PackWiseTests/GoldenEngineTests.swift ios/PackWiseTests/Goldens
git commit -m "test: record reviewed camping activity goldens"
```

### Task 7: Full Verification, Evidence, and Phase 5 Close

**Files:**
- Create: `docs/engine-audits/2026-09-03-phase-5-activity-contracts.md`
- Modify: `docs/plans/2026-09-02-product-hardening-program.md`

**Interfaces:**
- Consumes: all Task 1–6 commits and fresh test/audit output.
- Produces: a separate closure-evidence commit; Phase 6 remains unopened.

- [ ] **Step 1: Run the final semantic golden diff.** Compare against `756f68f` and record exact fixture and item counts under both buckets. The unexpected bucket may be called `none` only after additions, removals, quantities, traces, coverage, constraints, owners, and carriers have all been inspected.

- [ ] **Step 2: Run the one-command engine audit.** Run `scripts/run_engine_audit.sh`. Expected: all six steps pass, with step 5 now reporting DEAD 0.

- [ ] **Step 3: Run the full iOS suite.**

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Record exact tests, suites, failures, and the `.xcresult` path.

- [ ] **Step 4: Run shared and API gates.** Run `python3 scripts/validate_shared.py` and `npm --prefix api run preflight`. Shared data and the generated vocabulary both changed this phase, so record exact counts, the regenerated `api/generated` files, and exit codes — and confirm no hand-written API behavior changed.

- [ ] **Step 5: Audit scope mechanically.** Use `git diff --name-only 756f68f..HEAD` and `rg` to prove:

- `ActivityContracts` is the only activity authority and nothing else maps an activity id to an item list;
- no capability was added to `PackingCapability` and no weather signal, threshold, or `signalAdds` row changed;
- no clothing/footwear quantity policy, central constraint, SwiftData, GPT, lifecycle, or presentation file changed;
- the only party change is the reviewed `miscellaneous.flashlight` sharing row;
- the only `api/` change is regenerated vocabulary/manifest output;
- no forbidden campsite-logistics ID exists anywhere in the catalog or rules;
- the main checkout still contains its unrelated signing diff.

- [ ] **Step 6: Write the Phase 5 evidence report.** Include exact commits; the `ActivityNeed` vocabulary and per-activity contract table; the Camping V1 boundary and what it deliberately excludes; the composition rule and reason-attribution rule; the weather boundary and how `overnightWarmth` is gated; the `tripType.other` decision with its three checks; the unknown-activity result; the reviewed party sharing row; the regenerated API vocabulary; required fixture and scenario results 1–11; the golden review buckets with counts; every verification command and count; the remaining UNTESTED context chips as a routed finding; F-1 status; the Phase 6 cold-hand finding restated as still routed; presentation/device/M3B/M3C state; and the exit checklist.

- [ ] **Step 7: Close Phase 5 without opening Phase 6.** Update the program tracker's status line and add a Phase 5 closure section only after every gate is green. Preserve the Phase 1–4 closure text and leave the "Deferred and excluded" full-camping-logistics entry in place — Phase 5 honored it rather than superseding it.

- [ ] **Step 8: Commit evidence separately.**

```bash
git add docs/engine-audits/2026-09-03-phase-5-activity-contracts.md \
  docs/plans/2026-09-02-product-hardening-program.md
git commit -m "docs: close phase 5 activity contracts"
```

- [ ] **Step 9: Perform post-commit verification and stop.** Rerun `git status --short --branch`, `git log --oneline 756f68f..HEAD`, and the semantic diff against `756f68f`. Report the exact HEAD and leave `product-hardening-phase1` and its worktree intact. Do not merge, push, discard, clean the worktree, or begin Phase 6.

## Required Scenario Coverage

| # | Scenario | Where it is proved |
| --- | --- | --- |
| 1 | Camping only, mild conditions | fixture 28; `campingAloneAddsFiveItemsAndNoCampsiteLogistics` |
| 2 | Hiking only | `hikingOnlyBehaviorIsUnchangedByTheContractMigration`; fixture 18 |
| 3 | Hiking + Camping | fixture 29; `hikingPlusCampingIsOneComposedTripNotTwoChecklists` |
| 4 | Camping + rain | fixture 30; `campingPlusRainProducesExactlyOneShellAndNoCampingRainItem` |
| 5 | Camping + hot/sunny | fixture 31 |
| 6 | Camping + cold existing signal | fixture 32; `overnightWarmthResolvesOnlyWithAnExistingColdSignal` |
| 7 | Road Trip + Hiking + Camping (long trip) | fixture 18; `theLongRoadTripImprovesThroughTheGeneralCampingContract` |
| 8 | Camping + light packing | `campingRespectsLightPackingConstraints` |
| 9 | Camping + user-added multifunction item | `aUserAddedBottleSatisfiesCampingHydrationWithoutDuplication` |
| 10 | Unknown custom activity | fixture 25; `anUnknownActivityChangesNothingAtAll`; `unknownActivityHasNoContractAndNoNeeds` |
| 11 | Every surfaced preset activity contract | `everySurfacedActivityHasAContract`; `everyDeterministicActivityHasAnObservableEffect` plus its named wrappers; the contract ledger |

## Self-Review

- Spec coverage: Tasks 1–3 build the typed contract layer, Camping V1, and Hiking/Camping composition through the existing coverage model. Task 4 closes `tripType.other` and unknown activities. Task 5 closes the audit with verified test references. Task 6 records reviewed fixtures for all eleven required scenarios. Task 7 covers every exit command and a separate evidence commit.
- Architecture boundary: `ActivityContracts` is one new authority replacing a gap, not a second mechanism. `CoverageResolver` keeps its 12 capabilities and gains no new ones — it only learns to derive `.hiking` from a need instead of a string. No item-ID pair table, no per-activity hardcoded list for Camping, and the fifteen non-overlapping activities are deliberately not migrated.
- Weather boundary: the only weather-gated need is `overnightWarmth`, gated on signals that already exist. Camping contributes no rain need and no general warmth need, and three tests assert those absences directly.
- Type consistency: Task 1 defines `ActivityNeed`, `ActivityContract`, `ActivityContracts`; Task 2 consumes `needCandidates` and `originatingActivity`; Task 3 consumes `capabilities(for:)`; Tasks 4–7 consume those exact names.
- Scope honesty: context chips remain in the UNTESTED bucket and are reported, not silenced. The flashlight party row is called out as an explicitly reviewed change rather than slipped in. The regenerated `api/generated` vocabulary is named as the one file outside `ios/` and `shared/`.
- TDD and review: each behavior task starts red, turns green narrowly, runs a semantic checkpoint against `756f68f`, and ends in an independently reviewable commit. Recording goldens deliberately fails before review. Task 4 explicitly names the case where a test passes on first run and why that is still the right test.
- Placeholder scan: complete; no unresolved markers. Phase 6 weather work and Phase 7 party constraints are routed, not started inside Phase 5.
