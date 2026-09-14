# PackWise Product Hardening Phase 4 — Footwear and Outerwear Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make footwear, outerwear, and hand-protection coverage choose the smallest deterministic non-duplicative set while recording exact capability-to-coverer evidence.

**Architecture:** Keep `CoverageResolver` as the single closed, typed coverage authority. `PackingEngine` projects the one compiled `TripContextSnapshot` into a coverage-only context; existing weather extraction is passed through unchanged, and the resolver maps those existing signals to typed needs. Resolution remains a deterministic priority pass, gains exact per-capability suppression facts, and lets explicit user-owned items claim coverage without ever suppressing those items.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI domain models, JSON golden fixtures, Python semantic-golden audit tooling, Xcode/iOS 18 simulator tests.

## Global Constraints

- Work on `product-hardening-phase1` from `0b52ae6`; preserve every Phase 1–3 commit and the unrelated signing change in the main checkout.
- Follow the approved design at `docs/superpowers/specs/2026-09-03-product-hardening-phase-4-coverage-design.md`.
- `CoverageResolver` remains the only coverage authority. Do not move capability policy into shared JSON and do not add ID-pair substitution exceptions.
- Keep the capability vocabulary closed and typed. Add only the two hand-protection capabilities required by the observed ski/cold overlap.
- `CoverageResolver.needs` must consume a narrow projection derived from the single `TripContextSnapshot`; no unrelated engine family migrates in Phase 4.
- Existing weather signals may be inputs. Do not add signals, alter thresholds, reinterpret partial/seasonal behavior, or change weather recommendation generation.
- User-added and user-modified items are never suppressed. They may satisfy needs only inside their unambiguous owner group; an unassigned party item claims coverage for nobody.
- Deterministic priority and evidence ordering are product behavior. Do not depend on dictionary or set iteration order.
- Phase 4 owns footwear, outerwear, and glove/hand-protection inclusion, suppression, absorbed-capability reasons, and coverage evidence only.
- Phase 4 does not own footwear quantities, clothing quantities, Camping rules, seasonal weather, shared constraints, presentation, persistence, GPT/context intelligence, notifications, or lifecycle behavior.
- Golden regressions include any clothing quantity, Camping, weather-generation, shared-constraint, ownership/carrier, persistence, or unrelated reason change.
- F-1 remains P2 unless it blocks a current-schema comparison against `0b52ae6`. Presentation remains frozen; physical-device verification remains deferred; M3B/M3C remain blocked.
- Stop at the Phase 4 exit gate. Do not begin Phase 5.

---

## File Map

- Modify `ios/PackWise/Domain/TripContextSnapshot.swift`: pass through typed context chips and the existing weather context so coverage can project entirely from the compiled snapshot.
- Modify `ios/PackWise/Domain/Packing/CoverageResolver.swift`: define `CoverageContext`, add typed hand capabilities, preserve deterministic priority, and emit exact per-capability suppression evidence.
- Modify `ios/PackWise/Domain/Packing/PackingEngine.swift`: pass the snapshot only into coverage, group with normalized party ownership, and render absorbed-capability reasons without changing other families.
- Modify `ios/PackWiseTests/TripContextSnapshotTests.swift`: prove the new pass-through fields are deterministic and do not reinterpret weather.
- Modify `ios/PackWiseTests/CoverageTests.swift`: cover projection parity, capability closure, minimal-set behavior, user authority, owner scope, evidence, and determinism.
- Modify `ios/PackWiseTests/GoldenEngineTests.swift`: serialize exact capability-to-coverer evidence and assert the required existing fixtures.
- Modify `scripts/report_engine_goldens.py` and `scripts/tests/test_report_engine_goldens.py`: compare the additive current-schema coverage mapping as a coverage change while accepting its absence in the `0b52ae6` baseline.
- Regenerate only affected files under `ios/PackWiseTests/Goldens/` after semantic review.
- Create `docs/engine-audits/2026-09-03-phase-4-footwear-outerwear-coverage.md`: exit evidence, reviewed diff, and routed findings.
- Modify `docs/plans/2026-09-02-product-hardening-program.md`: close Phase 4 only after all gates pass and leave Phase 5 unopened.

---

### Task 1: Define the Snapshot-Derived Coverage Input Boundary

**Files:**
- Modify: `ios/PackWise/Domain/TripContextSnapshot.swift`
- Modify: `ios/PackWise/Domain/Packing/CoverageResolver.swift`
- Modify: `ios/PackWise/Domain/Packing/PackingEngine.swift`
- Test: `ios/PackWiseTests/TripContextSnapshotTests.swift`
- Test: `ios/PackWiseTests/CoverageTests.swift`

**Interfaces:**
- Consumes: `TripContextCompiler.compile(_:rules:) -> TripContextSnapshot`, `WeatherSignalExtractor.extract(weather:thresholds:outdoorActivities:tripDays:)`, and `WeatherThresholds`.
- Produces: `CoverageContext.init(snapshot:thresholds:)`, `CoverageResolver.needs(context:) -> Set<PackingCapability>`, and `PackingEngine.applyCoverage(_:snapshot:)`.

- [ ] **Step 1: Write failing snapshot pass-through tests.** Add one test with `.runWhileTraveling` and `.needFormalOutfit` chips and one with a fixture weather context. Assert `snapshot.contextChips` equals the typed input set, `snapshot.weather` equals the same value, and two compilations remain equal.

```swift
@Test func coverageInputsPassThroughWithoutWeatherReinterpretation() throws {
    var context = baseContext()
    context.contextChips = [.runWhileTraveling, .needFormalOutfit]
    let weatherFixture = try #require(try SharedLibrary.weatherFixtures()["ChicagoRainyFall"])
    context.weather = MockWeatherService.context(
        from: weatherFixture,
        start: context.startDate,
        end: context.endDate,
        fixtureID: weatherFixture.id
    )

    let first = TripContextCompiler.compile(context, rules: try rules())
    let second = TripContextCompiler.compile(context, rules: try rules())

    #expect(first.contextChips == context.contextChips)
    #expect(first.weather == context.weather)
    #expect(first == second)
}
```

- [ ] **Step 2: Write a failing coverage-projection parity test.** Build a raw running/business/rain-and-wind trip, compile it, create `CoverageContext`, and assert the projected needs equal the current resolver's pre-migration result. Pin the expected set explicitly so two wrong implementations cannot agree.

```swift
@Test func snapshotProjectionPreservesExistingCoverageNeeds() throws {
    let start = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 14))!
    let rainAndWind = weather(days: 5, start: start, highF: 55, lowF: 45, rain: 0.6, wind: 26)
    var raw = context(
        destination: try destination("Chicago"),
        type: .business,
        activities: ["running", "walking"],
        weather: rainAndWind
    )
    raw.contextChips = [.needFormalOutfit]
    let rules = try SharedLibrary.rules()
    let snapshot = TripContextCompiler.compile(raw, rules: rules)
    let projected = CoverageContext(snapshot: snapshot, thresholds: rules.weather.thresholds)

    #expect(CoverageResolver.needs(context: projected) == [
        .everydayWalking, .running, .formal, .rainShell, .windShell, .warmthLight
    ])
}
```

- [ ] **Step 3: Run the focused tests and verify RED.** Run:

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/TripContextSnapshotTests \
  -only-testing:PackWiseTests/CoverageTests
```

Expected: compile failures for missing `TripContextSnapshot.contextChips`, `TripContextSnapshot.weather`, and `CoverageContext`.

- [ ] **Step 4: Add only the snapshot fields needed by coverage.** Extend `TripContextSnapshot` and its compiler construction with exact typed pass-through values:

```swift
var contextChips: Set<ContextChip>
var weather: TripWeatherContext?

// TripContextCompiler.compile
contextChips: context.contextChips,
weather: context.weather,
```

Do not add a diagnostic: both fields are already typed, and Phase 4 does not normalize or reinterpret them.

- [ ] **Step 5: Implement the narrow coverage projection with the existing weather semantics verbatim.** Define:

```swift
struct CoverageContext: Hashable, Sendable {
    var tripType: TripType
    var activityIDs: Set<String>
    var contextChips: Set<ContextChip>
    var weatherSignals: Set<WeatherSignal>
    var usesSeasonalWarmthFallback: Bool
    var party: TripParty

    init(snapshot: TripContextSnapshot, thresholds: WeatherThresholds) {
        tripType = snapshot.tripType
        activityIDs = Set(snapshot.knownActivityIDs)
        contextChips = snapshot.contextChips
        party = snapshot.party

        let outdoor = !activityIDs.isDisjoint(with: ["hiking", "sightseeing", "walking", "running", "beachDays"])
        if let weather = snapshot.weather,
           weather.isPreciseForecast || !weather.dailyForecast.isEmpty {
            weatherSignals = WeatherSignalExtractor.extract(
                weather: weather,
                thresholds: thresholds,
                outdoorActivities: outdoor,
                tripDays: snapshot.durationDays
            ).signals
            usesSeasonalWarmthFallback = false
        } else {
            weatherSignals = []
            let month = Calendar.current.component(.month, from: snapshot.startDate)
            let northWinter = snapshot.destination.latitude >= 0 && [12, 1, 2].contains(month)
            let southWinter = snapshot.destination.latitude < 0 && [6, 7, 8].contains(month)
            usesSeasonalWarmthFallback = (northWinter || southWinter) && abs(snapshot.destination.latitude) > 30
        }
    }
}
```

Move only the need mapping into `CoverageResolver.needs(context:)`; keep every existing signal-to-capability mapping unchanged.

- [ ] **Step 6: Wire only coverage to the snapshot.** Change both generation paths to call `applyCoverage(..., snapshot: snapshot)`. Inside `applyCoverage`, create `CoverageContext(snapshot:thresholds:)`, use `snapshot.party` for owner grouping, and leave rule suggestions, weather generation, constraints, companions, quantities, and reconciliation on their existing inputs.

- [ ] **Step 7: Verify GREEN and zero behavior drift.** Run the focused command from Step 3, then:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 scripts/report_engine_goldens.py \
  --baseline-ref 0b52ae6 --candidate ios/PackWiseTests/Goldens --format markdown
```

Expected: focused tests pass and all 27 golden fixtures are unchanged.

- [ ] **Step 8: Commit the input boundary.** Commit only Task 1 files:

```bash
git add ios/PackWise/Domain/TripContextSnapshot.swift \
  ios/PackWise/Domain/Packing/CoverageResolver.swift \
  ios/PackWise/Domain/Packing/PackingEngine.swift \
  ios/PackWiseTests/TripContextSnapshotTests.swift \
  ios/PackWiseTests/CoverageTests.swift
git commit -m "feat: derive coverage needs from normalized trip context"
```

### Task 2: Make Suppression Evidence Capability-Exact

**Files:**
- Modify: `ios/PackWise/Domain/Packing/CoverageResolver.swift`
- Modify: `ios/PackWise/Domain/Packing/PackingEngine.swift`
- Test: `ios/PackWiseTests/CoverageTests.swift`

**Interfaces:**
- Consumes: `PackingCapability`, the resolver's deterministic `covered: [PackingCapability: String]` map, and owner-grouped candidates.
- Produces: `CapabilityCoverage`, `CoverageSuppression.covered`, `CoverageSuppression.refutedCapabilities`, plus stable compatibility accessors `capabilities` and `coveredBy` during golden migration.

- [ ] **Step 1: Write failing evidence tests at the resolver boundary.** Construct a running-shoe candidate followed by walking shoes and assert an exact fact rather than two unrelated arrays. Add a hot-rain shell case whose evidence is explicitly refuted and has no coverer.

```swift
@Test func suppressionPairsEachCapabilityWithItsCoverer() {
    let (kept, suppressions) = CoverageResolver.resolve(
        items: [runningShoes(), walkingShoes()],
        needs: [.running, .everydayWalking]
    )
    #expect(kept.compactMap(\.canonicalItemID) == ["footwear.running_shoes"])
    #expect(suppressions == [CoverageSuppression(
        travelerID: nil,
        canonicalItemID: "footwear.walking_shoes",
        covered: [CapabilityCoverage(capability: .everydayWalking, coveringItemID: "footwear.running_shoes")],
        refutedCapabilities: []
    )])
}
```

- [ ] **Step 2: Write failing ordering and partial-coverage tests.** Reverse candidate input order and expect identical kept canonical IDs and evidence. Provide a candidate with one covered and one uncovered required capability and assert it stays, then claims only the missing capability; do not suppress a partially useful item.

- [ ] **Step 3: Run `CoverageTests` and verify RED.** Expected: missing `CapabilityCoverage`, `covered`, and `refutedCapabilities` APIs.

- [ ] **Step 4: Implement exact evidence and stable ordering.** Add:

```swift
struct CapabilityCoverage: Hashable, Sendable {
    var capability: PackingCapability
    var coveringItemID: String
}

struct CoverageSuppression: Hashable, Sendable {
    var travelerID: UUID?
    var canonicalItemID: String
    var covered: [CapabilityCoverage]
    var refutedCapabilities: [PackingCapability]

    var capabilities: [String] {
        Set(covered.map(\.capability)).union(refutedCapabilities)
            .map(\.rawValue).sorted()
    }

    var coveredBy: [String] {
        Set(covered.map(\.coveringItemID)).sorted()
    }
}
```

When all needed capabilities are already covered, create one `CapabilityCoverage` per needed capability and sort by `capability.rawValue`, then `coveringItemID`. For a weather candidate with no needed capabilities, set `covered = []` and sort all item capabilities into `refutedCapabilities`. Keep the existing priority sort's original-index tie breaker.

- [ ] **Step 5: Preserve user authority and reason rendering.** Keep `isUserAdded || isUserModified` candidates unconditionally. Let them populate the same owner group's coverage map. Update `PackingEngine` to derive walking-cover reason copy from the exact `.everydayWalking` fact, not from the first arbitrary entry in `coveredBy`.

- [ ] **Step 6: Verify GREEN and semantic parity.** Run `CoverageTests`, `ConstraintTests`, and `GoldenEngineTests`. Run the semantic diff against `0b52ae6`. Expected: tests pass and goldens remain byte/semantically unchanged because compatibility accessors preserve the current schema.

- [ ] **Step 7: Commit the evidence model.**

```bash
git add ios/PackWise/Domain/Packing/CoverageResolver.swift \
  ios/PackWise/Domain/Packing/PackingEngine.swift \
  ios/PackWiseTests/CoverageTests.swift
git commit -m "feat: make coverage suppression evidence capability exact"
```

### Task 3: Resolve Footwear, Outerwear, and Hand Protection Through Typed Capabilities

**Files:**
- Modify: `ios/PackWise/Domain/Packing/CoverageResolver.swift`
- Test: `ios/PackWiseTests/CoverageTests.swift`

**Interfaces:**
- Consumes: `CoverageContext` and the exact evidence model from Tasks 1–2.
- Produces: `PackingCapability.coldHands`, `PackingCapability.snowSportHands`, and general typed coverage for both glove candidates.

- [ ] **Step 1: Write the failing Aspen overlap test.** Generate fixture-equivalent ski/snow context and assert ski gloves remain, ordinary gloves are absent, and ordinary gloves' suppression maps `.coldHands` to `activities.ski_gloves`.

```swift
@Test func skiGlovesCoverColdHandsWithoutAnIDPairRule() throws {
    let start = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 12))!
    let snowy = weather(days: 5, start: start, highF: 30, lowF: 14, rain: 0.1, wind: 18, snow: true)
    let skiTrip = context(
        destination: try destination("Denver"),
        type: .skiSnow,
        activities: ["sightseeing"],
        bag: .checked,
        style: .prepared,
        weather: snowy
    )
    let generation = try makeEngine().generateDetailed(context: skiTrip)
    let ids = Set(generation.items.compactMap(\.canonicalItemID))
    #expect(ids.contains("activities.ski_gloves"))
    #expect(!ids.contains("clothing.gloves"))
    let suppression = try #require(generation.coverageSuppressions.first {
        $0.canonicalItemID == "clothing.gloves"
    })
    #expect(suppression.covered == [
        CapabilityCoverage(capability: .coldHands, coveringItemID: "activities.ski_gloves")
    ])
}
```

- [ ] **Step 2: Write cold-only and snow-sport-only boundary tests.** A cold non-ski trip keeps `clothing.gloves` and has no snow-sport hand need. A ski/snow trip without precise weather still keeps ski gloves and suppresses ordinary gloves through trip intent, not manufactured weather.

- [ ] **Step 3: Run `CoverageTests` and verify RED.** Expected: both hand capability cases are missing and the current engine keeps two glove pairs.

- [ ] **Step 4: Extend the closed vocabulary by exactly two.** Add:

```swift
case coldHands = "hand_protection.cold"
case snowSportHands = "hand_protection.snow_sport"
```

Update the vocabulary-count test from 10 to 12. Add `activities.ski_gloves` before `clothing.gloves` in `priority`; map ski gloves to `[.snowSportHands, .coldHands]` and ordinary gloves to `[.coldHands]`. Add both needs for `.skiSnow`; add `.coldHands` for existing `.snowExposure`, `.sustainedCold`, or `.freezingCold` signals. Do not add a canonical-ID pair table or edit shared JSON.

- [ ] **Step 5: Verify all focused overlap families.** Run `CoverageTests` and assert these cases remain green: running+walking; hiking+walking; running+hiking+walking; formal+business; rain+wind; temperature-swing light layer; winter coat+light layer+boots; ski/cold hands.

- [ ] **Step 6: Run the semantic diff checkpoint.** Before recording goldens, render fixture 21 and verify the only behavior delta is `clothing.gloves` suppression with `activities.ski_gloves` retained. Confirm no footwear, outerwear, clothing quantity, or weather recommendation changes in any other fixture.

- [ ] **Step 7: Commit the typed hand model.**

```bash
git add ios/PackWise/Domain/Packing/CoverageResolver.swift \
  ios/PackWiseTests/CoverageTests.swift
git commit -m "fix: resolve snow hand protection by capability"
```

### Task 4: Serialize Coverage Facts and Review the Golden Ledger

**Files:**
- Modify: `ios/PackWiseTests/GoldenEngineTests.swift`
- Modify: `scripts/report_engine_goldens.py`
- Modify: `scripts/tests/test_report_engine_goldens.py`
- Modify: affected `ios/PackWiseTests/Goldens/*.json`

**Interfaces:**
- Consumes: `CoverageSuppression.covered` and `refutedCapabilities`.
- Produces: additive golden fields `coveredCapabilities` and `refutedCapabilities`, plus semantic comparison of both as `COVERAGE CHANGES`.

- [ ] **Step 1: Write a failing Python reporter test.** Compare an old-schema baseline coverage row with a candidate carrying exact facts and assert one coverage change, not an item trace or constraint change.

```python
def test_exact_capability_mapping_is_a_coverage_change(self):
    baseline = golden(coverage=[coverage_entry(
        "footwear.walking_shoes",
        capabilities=["footwear.everyday_walking"],
        covered_by=["footwear.running_shoes"],
    )])
    candidate = golden(coverage=[coverage_entry(
        "footwear.walking_shoes",
        capabilities=["footwear.everyday_walking"],
        covered_by=["footwear.running_shoes"],
        covered_capabilities={"footwear.everyday_walking": "footwear.running_shoes"},
    )])
    report = compare_fixture(baseline, candidate)
    self.assertEqual(len(report.coverage_changes), 1)
```

- [ ] **Step 2: Run the one reporter test and verify RED.** Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
  scripts.tests.test_report_engine_goldens.CoverageChangeTests.test_exact_capability_mapping_is_a_coverage_change -v
```

Expected: the reporter ignores the new mapping and reports no change.

- [ ] **Step 3: Extend the golden schema additively.** Keep `capabilities` and `coveredBy` for readable continuity, and add sorted exact facts:

```swift
private struct GoldenCoverageEntry: Codable {
    var owner: String
    var suppressed: String
    var capabilities: [String]
    var coveredBy: [String]
    var coveredCapabilities: [String: String]?
    var refutedCapabilities: [String]?
}
```

Serialize `coveredCapabilities` from `suppression.covered`, `nil` when empty, and sorted `refutedCapabilities`, `nil` when empty. JSON output already uses `.sortedKeys`, so dictionary key order is deterministic.

- [ ] **Step 4: Teach the reporter the additive current schema.** Extend `CoverageEntry` with stable sorted tuples for both fields. Parse missing baseline fields as empty so `0b52ae6` remains a valid baseline; do not change missing `carrier` handling or otherwise fix F-1.

- [ ] **Step 5: Run all Python reporter tests and verify GREEN.** Expected: 25 tests pass (24 Phase 3 tests plus the new coverage-mapping test).

- [ ] **Step 6: Record goldens and stop on the deliberate recording failure.** Run:

```bash
TEST_RUNNER_PACKWISE_RECORD_GOLDENS=1 xcodebuild test \
  -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/GoldenEngineTests
```

Expected: files are rewritten and the suite deliberately records one issue instructing review.

- [ ] **Step 7: Review and classify the semantic diff against `0b52ae6`.** Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 scripts/report_engine_goldens.py \
  --baseline-ref 0b52ae6 --candidate ios/PackWiseTests/Goldens --format markdown
```

Create two review buckets. `EXPECTED COVERAGE CHANGES` may contain additive exact evidence on existing suppressions and the fixture-21 ordinary-glove suppression/removal. `UNEXPECTED BEHAVIOR CHANGES` must remain empty: reject clothing quantities, unrelated item inclusion, Camping, weather generation, shared constraints, owner/carrier, persistence, or unrelated reasons.

- [ ] **Step 8: Run goldens without record mode.** Expected: `GoldenEngineTests` pass against the reviewed files.

- [ ] **Step 9: Commit schema tooling and reviewed goldens together.**

```bash
git add ios/PackWiseTests/GoldenEngineTests.swift \
  ios/PackWiseTests/Goldens \
  scripts/report_engine_goldens.py \
  scripts/tests/test_report_engine_goldens.py
git commit -m "test: record exact phase 4 coverage evidence"
```

### Task 5: Enforce Required Coverage, Authority, and Determinism Gates

**Files:**
- Modify: `ios/PackWiseTests/CoverageTests.swift`
- Modify: `ios/PackWiseTests/GoldenEngineTests.swift`

**Interfaces:**
- Consumes: normalized `CoverageContext`, the typed capability table, exact suppression facts, and the reviewed golden ledger.
- Produces: executable Phase 4 exit-gate properties across focused and ledger fixtures.

- [ ] **Step 1: Add a table-driven minimal-set matrix.** Cover at least these expected kept sets:

```swift
struct CoverageCase {
    var name: String
    var context: TripContext
    var kept: Set<String>
    var suppressed: Set<String>
}

let destination = try destination("Denver")
let start = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 14))!
let rainWind = weather(days: 5, start: start, highF: 55, lowF: 45, rain: 0.6, wind: 26)
let winter = weather(days: 5, start: start, highF: 30, lowF: 14, snow: true)
let cases = [
    CoverageCase(name: "running + walking",
        context: context(destination: destination, activities: ["running", "walking"]),
        kept: ["footwear.running_shoes"], suppressed: ["footwear.walking_shoes"]),
    CoverageCase(name: "hiking + walking",
        context: context(destination: destination, type: .outdoor, activities: ["hiking", "walking"]),
        kept: ["footwear.hiking_shoes"], suppressed: ["footwear.walking_shoes"]),
    CoverageCase(name: "running + hiking + walking",
        context: context(destination: destination, type: .outdoor, activities: ["running", "hiking", "walking"]),
        kept: ["footwear.running_shoes", "footwear.hiking_shoes"], suppressed: ["footwear.walking_shoes"]),
    CoverageCase(name: "formal business",
        context: context(destination: destination, type: .business, activities: ["work"]),
        kept: ["footwear.dress_shoes", "footwear.walking_shoes"], suppressed: []),
    CoverageCase(name: "rain + wind",
        context: context(destination: destination, weather: rainWind),
        kept: ["clothing.rain_jacket", "clothing.light_sweater"], suppressed: ["clothing.windbreaker"]),
    CoverageCase(name: "winter layering",
        context: context(destination: destination, type: .outdoor, weather: winter),
        kept: ["clothing.winter_coat", "clothing.light_sweater", "footwear.boots"], suppressed: []),
    CoverageCase(name: "ski hands",
        context: context(destination: destination, type: .skiSnow, weather: winter),
        kept: ["activities.ski_gloves"], suppressed: ["clothing.gloves"]),
]
```

Filter expectations to the capability-family IDs named by each case so unrelated base items do not make the test brittle.

- [ ] **Step 2: Add user-owned multifunction tests.** A user-added running shoe and a user-modified rain shell must remain and suppress the engine's walking shoe/windbreaker as applicable. Assert the user row retains quantity, packed count, owner, carrier, and modification flags.

- [ ] **Step 3: Add party owner-scope tests.** In a two-adult party, an explicit primary-owned running shoe suppresses only the primary's walking shoe. The partner retains their walking shoe. An unassigned personal running shoe suppresses neither traveler's candidate and gains no inferred owner/carrier.

- [ ] **Step 4: Add deterministic-output tests.** Generate each matrix case twice. Compare sorted canonical IDs and sorted `CoverageSuppression` arrays exactly. Also reverse direct resolver input order and prove the priority result/evidence is unchanged for candidates with distinct priority.

- [ ] **Step 5: Add golden fixture contracts.** In `GoldenEngineTests`, assert existing fixtures cover:

- `08-running-sightseeing-footwear`: runners keep, walking shoes suppressed by everyday-walking capability.
- `18-reykjavik-64d-roadtrip-camping-seasonal`: hiking shoes keep, walking shoes suppressed; make no Camping assertion.
- `07-chicago-5d-business-checked`: dress and walking shoes both remain.
- `09-seattle-rain-layering`: rain/wind/light-layer coverage is non-duplicative.
- `21-aspen-5d-skisnow-checked-prepared-snow`: ski gloves cover ordinary cold gloves while winter coat, light layer, and boots remain.
- `26-seattle-5d-existing-rain-shell`: explicit existing shell remains authoritative and prevents a duplicate.

- [ ] **Step 6: Run focused suites and semantic review.** Run `TripContextSnapshotTests`, `CoverageTests`, `ConstraintTests`, `PackingEngineTests`, `GoldenEngineTests`, and `WeatherChangeTests`. Then rerun the semantic diff against `0b52ae6`. Expected: all tests pass and only reviewed coverage-family changes remain.

- [ ] **Step 7: Commit the acceptance suite separately.**

```bash
git add ios/PackWiseTests/CoverageTests.swift ios/PackWiseTests/GoldenEngineTests.swift
git commit -m "test: enforce phase 4 coverage gates"
```

### Task 6: Full Verification, Evidence, and Phase 4 Close

**Files:**
- Create: `docs/engine-audits/2026-09-03-phase-4-footwear-outerwear-coverage.md`
- Modify: `docs/plans/2026-09-02-product-hardening-program.md`

**Interfaces:**
- Consumes: all Task 1–5 commits and fresh test/audit output.
- Produces: a separate closure-evidence commit; Phase 5 remains unopened.

- [ ] **Step 1: Run the final semantic golden diff.** Compare against `0b52ae6` and record exact fixture/item counts under `EXPECTED COVERAGE CHANGES` and `UNEXPECTED BEHAVIOR CHANGES`. The unexpected bucket may be called `none` only when additions/removals, quantities, traces, coverage, constraints, owners, and carriers have all been inspected.

- [ ] **Step 2: Run the one-command engine audit.** Run `scripts/run_engine_audit.sh`. Expected: all six steps pass, including the HEAD-to-current golden check and trace audit.

- [ ] **Step 3: Run the full iOS suite.** Run:

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Record exact tests, suites, failures, and the `.xcresult` path.

- [ ] **Step 4: Run shared and API gates.** Run `python3 scripts/validate_shared.py` and `npm --prefix api run preflight`. Record exact counts and exit codes even though Phase 4 should not change shared/API files.

- [ ] **Step 5: Audit scope mechanically.** Use `git diff --name-only 0b52ae6..HEAD` and `rg` to prove:

- `CoverageContext` is the only new snapshot consumer;
- no shared JSON, quantity, weather-signal, constraint, persistence, API, or presentation file changed;
- no ID-pair glove special case exists;
- capability/evidence order is explicit;
- the main checkout still contains its unrelated signing diff.

- [ ] **Step 6: Write the Phase 4 evidence report.** Include exact commits; capability vocabulary; snapshot fields consumed; priority order; required fixture results; user/party authority results; exact suppression facts; golden counts; all verification commands/counts; F-1 status; routed Phase 5/6/8 findings; presentation/device/M3B/M3C state; and the exit checklist.

- [ ] **Step 7: Close Phase 4 without opening Phase 5.** Update the program status and add a Phase 4 closure section only after every gate is green. Preserve the Phase 1–3 closure text.

- [ ] **Step 8: Commit evidence separately.**

```bash
git add docs/engine-audits/2026-09-03-phase-4-footwear-outerwear-coverage.md \
  docs/plans/2026-09-02-product-hardening-program.md
git commit -m "docs: close phase 4 footwear and outerwear coverage"
```

- [ ] **Step 9: Perform post-commit verification and stop.** Rerun `git status --short --branch`, `git log --oneline 0b52ae6..HEAD`, the semantic diff against `0b52ae6`, and any documentation-sensitive check. Report the exact HEAD and leave `product-hardening-phase1` and its worktree intact. Do not merge, push, discard, clean the worktree, or begin Phase 5.

## Self-Review

- Spec coverage: Tasks 1–5 cover the normalized coverage boundary, the closed typed vocabulary, exact suppression evidence, deterministic priority, every requested footwear/outerwear/hand overlap, user-owned multifunction coverage, owner-scoped ambiguity handling, repeated-run determinism, and the golden boundary. Task 6 covers every exit command and separate evidence commit.
- Architecture boundary: `CoverageResolver` remains the only authority; shared substitutions/capabilities are not migrated or extended. Existing weather extraction is moved behind the projection without changing signals or thresholds. No quantity, constraint, UI, persistence, API, GPT, or lifecycle file belongs to the plan.
- Type consistency: Task 1 defines `CoverageContext`; Task 2 defines `CapabilityCoverage` and the new suppression fields; Task 3 adds `.coldHands`/`.snowSportHands`; Tasks 4–6 consume those exact names.
- TDD and review: each behavior task starts red, turns green narrowly, runs a semantic checkpoint, and ends in an independently reviewable commit. Recording goldens deliberately fails before review.
- Placeholder scan: complete; no unresolved markers or vague implementation steps remain. Phase 5 work is routed, not deferred inside Phase 4 code.
