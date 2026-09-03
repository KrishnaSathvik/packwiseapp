# Phase 2 — Context Model Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce an immutable `TripContextSnapshot`, compiled once from the existing `TripContext` behind the engine boundary, that normalizes dates, activities, bag/style, laundry, party, and weather quality into one deterministic representation with explicit `valid` / `normalized` / `unsupportedButSafe` diagnostics — without changing any engine recommendation behavior or touching UI/persistence boundaries.

**Architecture:** `TripContextSnapshot` and `TripContextCompiler` are new pure, `Sendable`, side-effect-free domain types under `ios/PackWise/Domain/`. The compiler consumes the same `PackingRulesFile` the engine already loads (so "known activity" means exactly what the engine's rule vocabulary means — no separate source of truth). `TripContext` remains the type UI, SwiftData repositories, and `PackingEngine`'s public API surface use. `PackingEngine.generateDetailed` compiles a snapshot once per call, purely for validation and diagnostics — no internal decision logic reads from it in this phase. Golden outputs (items/coverage/constraints) must stay byte-identical throughout; only an additive `contextDiagnostics` field is allowed to appear on `EngineGeneration`.

**Tech Stack:** Swift 6, Swift Testing, the existing `shared/` JSON catalogs/rules, `xcodebuild`, `scripts/report_engine_goldens.py` and `scripts/run_engine_audit.sh` (built in Phase 1) as the regression authority.

## Global Constraints

- Phase 2 is context hardening, not recommendation tuning. Do not fix Camping, clothing quantities, footwear coverage, seasonal outerwear, explanation gaps, or any other Phase-1-routed finding, unless a change is strictly required to represent context correctly.
- Golden item/coverage/constraint outputs must remain byte-identical across all 27 fixtures for the entire phase. If any step's golden diff shows anything besides the addition of the new `contextDiagnostics` field (which is not serialized into golden JSON at all — see Task 5), stop and treat it as a defect in that step, not a Phase 3+ finding.
- Keep UI, SwiftData repositories, and external boundaries (API, WeatherKit client, `TripSetupView` and friends) on `TripContext`. Nothing outside `PackingEngine`'s implementation may reference `TripContextSnapshot` in this phase.
- Ambiguous traveler attribution resolves to **don't infer** — never guess a guardian, owner, or carrier the snapshot compiler can't determine structurally.
- `BagType.notSure` applies no bag constraint — the snapshot must not invent one.
- Presentation stays frozen. Do not touch SwiftUI/DesignSystem code or `ios/PackWise.xcodeproj/project.pbxproj`.
- Physical-device verification remains deferred, not completed. M3B/M3C remain blocked.
- Run `python3 scripts/validate_shared.py` after any catalog/rule edits (none are expected in this phase — it touches Domain/Test code only).

## Repository Baseline (post-Phase-1)

- `TripContext` (`ios/PackWise/Domain/TripTypes.swift:374`) is the struct the engine, UI, and persistence all share today. Relevant fields: `destination`, `startDate`/`endDate`/`durationDays`/`durationNights`, `tripType`, `activities: [String]`, `bagType`, `packingStyle`, `laundryAccess`, `contextChips`, `userNotes`, `weather: TripWeatherContext?`, `party: TripParty`, `preferences`.
- `TripContext.laundryPlan` (`TripTypes.swift:415`) already folds legacy signals (explicit `laundryAccess` wins; `.laundryAvailable` chip or a "laundry" substring in notes resolves to `.possible`; otherwise `.none`). The snapshot's laundry normalization must be provably equivalent to this — it is the regression baseline, not something to redesign.
- `TripDateMath.daysAndNights(from:to:calendar:)` (`TripTypes.swift:430`) already clamps a reversed date range to a safe 1-day/0-night trip (`max(1, ...)`/`max(0, ...)`) rather than crashing or producing a negative duration. The compiler reuses this, it does not reimplement date safety.
- `PackingRulesFile.activities: [String: [String]]` (`Catalog.swift`) is the engine's real activity vocabulary — Phase 1 Task 5 confirmed `camping` has **no** entry here despite being a real, styled, selectable activity, and that this is the exact "advertised input with no effect" pattern. The snapshot compiler must not special-case `camping` — any activity ID absent from `rules.activities` is structurally unrecognized, camping included, and that is the honest, correct classification (matches the already-published finding in `docs/engine-audits/2026-09-03-engine-findings.md`).
- `TripParty`/`Traveler`/`PartyInvariants` (`ios/PackWise/Domain/Party.swift`) already define guardian/owner structural rules. `TripContext.effectiveParty` (`TripTypes.swift:394`) already falls back an empty `travelers` array to `.solo()` — so "empty party" is already handled upstream; the snapshot's job is to normalize a non-empty-but-malformed party (invalid guardian references, etc.), never to guess a replacement value.
- `TripWeatherContext` (`ios/PackWise/Domain/Weather/WeatherDomain.swift:93`) carries `source: WeatherSource` (`.weatherKit`/`.fixture`/`.cache`/`.seasonal`/`.none`), `forecastAvailableForWholeTrip`/`forecastAvailableForPartialTrip: Bool`, and `dailyForecast: [DailyForecast]`. `context.weather == nil` is the "missing" case; `source == .seasonal` is "seasonal-only"; the two `forecastAvailableFor...` booleans distinguish partial from complete coverage.
- `PackingEngine.generateDetailed(context:existing:overrides:) -> EngineGeneration` (`PackingEngine.swift:29`) is the single entry point this phase hooks. `EngineGeneration` (`PackingEngine.swift:7`) currently has `items`, `coverageSuppressions`, `constraintDecisions` — Task 5 adds a fourth field, `contextDiagnostics`, additively.
- `ClothingQuantity.swift:268` is currently the only internal call site reading `context.laundryPlan` inside a decision path. **Do not migrate it in this phase** — it belongs to the Phase-3-owned clothing/quantity family, and migrating it now would blur Phase 2 into Phase 3's territory. Phase 2 closes with the compiler proven correct and wired for diagnostics only; deciding which family opts in first is explicitly left to whichever later phase owns that family.
- Test conventions: `ios/PackWiseTests/PackingEngineTests.swift:14` has a private `context(destination:days:type:activities:bag:style:chips:home:homeSource:weather:laundry:)` builder — reuse this pattern (or the equivalent already used in `GoldenEngineTests.swift`) rather than inventing a new one. `ios/PackWiseTests/` is flat (no subfolders) — new test files go directly in it.

---

## Phase 2 File Map

- Create: `ios/PackWise/Domain/TripContextSnapshot.swift` (the new type + compiler).
- Create: `ios/PackWiseTests/TripContextSnapshotTests.swift`.
- Modify: `ios/PackWise/Domain/Packing/PackingEngine.swift` (Task 5 only — additive `contextDiagnostics` field and one compile-and-attach call).
- Modify: `ios/PackWiseTests/GoldenEngineTests.swift` or a new `ios/PackWiseTests/TripContextSnapshotFixtureTests.swift` (Task 5 — full-ledger compilation test; implementer's call which file, see Task 5).
- Create: `docs/engine-audits/2026-09-03-phase-2-context-snapshot.md` (Task 6).
- Modify: `docs/plans/2026-09-02-product-hardening-program.md` (Task 6 — Phase 2 closure section).

---

### Task 1: `TripContextSnapshot` type, diagnostics, and date normalization

**Files:**
- Create: `ios/PackWise/Domain/TripContextSnapshot.swift`
- Create: `ios/PackWiseTests/TripContextSnapshotTests.swift`

**Interfaces:**
- Produces: `TripContextSnapshot`, `ContextOutcome`, `ContextDiagnostic`, and `TripContextCompiler.compile(_ context: TripContext, rules: PackingRulesFile) -> TripContextSnapshot`.

**Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import PackWise

struct TripContextSnapshotTests {
    private func rules() throws -> PackingRulesFile { try SharedLibrary.rules() }

    private func baseContext(
        start: Date = Calendar.current.startOfDay(for: .now),
        days: Int = 5
    ) -> TripContext {
        let end = Calendar.current.date(byAdding: .day, value: days - 1, to: start)!
        let math = TripDateMath.daysAndNights(from: start, to: end)
        return TripContext(
            destination: Destination(displayName: "Chicago", city: "Chicago", region: "IL", country: "United States", countryCode: "US", latitude: 41.8, longitude: -87.6, timeZone: "America/Chicago"),
            startDate: start,
            endDate: end,
            durationDays: math.days,
            durationNights: math.nights,
            tripType: .cityBreak,
            activities: ["sightseeing", "walking"],
            datedActivities: [],
            bagType: .carryOn,
            packingStyle: .balanced,
            transportation: .unknown,
            laundryAccess: .none,
            travelerCount: 1,
            userNotes: "",
            contextChips: [],
            weather: nil,
            preferences: .deviceDefaults()
        )
    }

    @Test func validDatesCompileWithNoDiagnostic() throws {
        let snapshot = TripContextCompiler.compile(baseContext(), rules: try rules())
        #expect(snapshot.durationDays == 5)
        #expect(snapshot.durationNights == 4)
        #expect(!snapshot.diagnostics.contains { $0.field == "dates" })
    }

    @Test func mismatchedStoredDurationIsRecomputedAndNormalized() throws {
        var context = baseContext()
        context.durationDays = 999 // stale/incorrect stored value
        let snapshot = TripContextCompiler.compile(context, rules: try rules())
        #expect(snapshot.durationDays == 5) // recomputed from real dates, not trusted verbatim
        #expect(snapshot.diagnostics.contains { $0.field == "dates" && $0.outcome.isNormalized })
    }

    @Test func reversedDatesAreUnsupportedButSafe() throws {
        var context = baseContext()
        let start = context.startDate
        context.endDate = Calendar.current.date(byAdding: .day, value: -3, to: start)!
        let snapshot = TripContextCompiler.compile(context, rules: try rules())
        #expect(snapshot.durationDays == 1) // TripDateMath's existing safe clamp, not a new invention
        #expect(snapshot.durationNights == 0)
        #expect(snapshot.diagnostics.contains { $0.field == "dates" && $0.outcome.isUnsupportedButSafe })
    }

    @Test func compilationIsDeterministicAcrossRepeatedRuns() throws {
        let context = baseContext()
        let r = try rules()
        let first = TripContextCompiler.compile(context, rules: r)
        let second = TripContextCompiler.compile(context, rules: r)
        #expect(first == second)
    }
}
```

**Step 2: Run to verify it fails**

Run: `xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PackWiseTests/TripContextSnapshotTests`
Expected: build failure — `TripContextSnapshot`/`TripContextCompiler` don't exist yet.

**Step 3: Implement the type and compiler skeleton**

Create `ios/PackWise/Domain/TripContextSnapshot.swift`. Real shape to implement (adapt field names if you find a clearer fit while building later tasks, but keep this file's public surface additive-only from here on — Tasks 2-4 add fields and diagnostics to the same file, they don't redesign it):

```swift
import Foundation

/// One deterministic outcome for a single normalized field of a
/// `TripContextSnapshot`. `valid` means the raw `TripContext` value was
/// already exactly what the snapshot uses. `normalized` means the snapshot
/// derived a different (but equivalent-intent) value — e.g. recomputing
/// `durationDays` from the real dates instead of trusting a stale stored
/// value. `unsupportedButSafe` means the raw value can't be honored as
/// given, and the snapshot fell back to a documented, non-invented safe
/// default rather than guessing at the user's intent.
enum ContextOutcome: Hashable, Sendable {
    case valid
    case normalized(reason: String)
    case unsupportedButSafe(reason: String)

    var isNormalized: Bool { if case .normalized = self { true } else { false } }
    var isUnsupportedButSafe: Bool { if case .unsupportedButSafe = self { true } else { false } }
}

/// One diagnostic entry per normalized field. `field` names the
/// `TripContextSnapshot` property the diagnostic is about (e.g. "dates",
/// "activities", "bagType", "laundry", "party", "weather"), so later
/// phases and the audit tooling can filter/report on exactly what changed.
struct ContextDiagnostic: Hashable, Sendable {
    var field: String
    var outcome: ContextOutcome
}

/// Compiled once from `TripContext` behind the engine boundary. Immutable
/// and deterministic: compiling the same `TripContext` against the same
/// `PackingRulesFile` twice always produces an equal snapshot. UI,
/// SwiftData repositories, and every boundary outside `PackingEngine`'s
/// implementation continue to use `TripContext` directly — see the Phase 2
/// plan's migration rule.
struct TripContextSnapshot: Hashable, Sendable {
    var destination: Destination
    var startDate: Date
    var endDate: Date
    var durationDays: Int
    var durationNights: Int
    var tripType: TripType

    var diagnostics: [ContextDiagnostic]
}

enum TripContextCompiler {
    static func compile(_ context: TripContext, rules: PackingRulesFile) -> TripContextSnapshot {
        var diagnostics: [ContextDiagnostic] = []
        let (days, nights, dateDiagnostic) = normalizedDates(context)
        if let dateDiagnostic { diagnostics.append(dateDiagnostic) }

        return TripContextSnapshot(
            destination: context.destination,
            startDate: context.startDate,
            endDate: context.endDate,
            durationDays: days,
            durationNights: nights,
            tripType: context.tripType,
            diagnostics: diagnostics
        )
    }

    private static func normalizedDates(_ context: TripContext) -> (days: Int, nights: Int, diagnostic: ContextDiagnostic?) {
        let math = TripDateMath.daysAndNights(from: context.startDate, to: context.endDate)
        if context.endDate < context.startDate {
            return (math.days, math.nights, ContextDiagnostic(field: "dates", outcome: .unsupportedButSafe(reason: "endDate before startDate; treated as a 1-day trip")))
        }
        if math.days != context.durationDays || math.nights != context.durationNights {
            return (math.days, math.nights, ContextDiagnostic(field: "dates", outcome: .normalized(reason: "durationDays/durationNights recomputed from startDate/endDate")))
        }
        return (math.days, math.nights, nil)
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PackWiseTests/TripContextSnapshotTests`
Expected: `** TEST SUCCEEDED **`, all 4 tests pass.

**Step 5: Run the full suite to confirm no regressions, then commit**

Run: `xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: `** TEST SUCCEEDED **`, 171 tests (167 + 4 new).

```bash
git add ios/PackWise/Domain/TripContextSnapshot.swift ios/PackWiseTests/TripContextSnapshotTests.swift
git commit -m "feat: introduce TripContextSnapshot with date normalization"
```

---

### Task 2: Activity and bag/style normalization

**Files:**
- Modify: `ios/PackWise/Domain/TripContextSnapshot.swift`
- Modify: `ios/PackWiseTests/TripContextSnapshotTests.swift`

**Interfaces:**
- Consumes: `rules.activities` (the engine's real activity vocabulary) and `ActivityVocabulary.normalize` (the existing rename-shim from `TripTypes.swift`).
- Produces: `knownActivityIDs`, `unknownActivityIDs`, `bagType`, `appliesBagConstraint`, `packingStyle` on `TripContextSnapshot`.

**Step 1: Write the failing tests**

```swift
@Test func knownActivitiesAreClassifiedKnown() throws {
    var context = baseContext()
    context.activities = ["sightseeing", "hiking"]
    let snapshot = TripContextCompiler.compile(context, rules: try rules())
    #expect(Set(snapshot.knownActivityIDs) == ["sightseeing", "hiking"])
    #expect(snapshot.unknownActivityIDs.isEmpty)
    #expect(!snapshot.diagnostics.contains { $0.field == "activities" })
}

@Test func unrecognizedActivityIsPreservedAndFlaggedUnsupportedButSafe() throws {
    var context = baseContext()
    context.activities = ["sightseeing", "cosplayConvention"]
    let snapshot = TripContextCompiler.compile(context, rules: try rules())
    #expect(snapshot.knownActivityIDs == ["sightseeing"])
    #expect(snapshot.unknownActivityIDs == ["cosplayConvention"]) // preserved verbatim, never dropped
    #expect(snapshot.diagnostics.contains {
        $0.field == "activities" && $0.outcome == .unsupportedButSafe(reason: "cosplayConvention: no rule in the engine's activity vocabulary")
    })
}

@Test func campingIsHonestlyClassifiedUnknownLikeAnyOtherRulelessActivity() throws {
    // Matches the published Phase 1 finding: camping has no rules.activities
    // entry. The compiler does not special-case it — this is the exact
    // "advertised input with no effect" pattern, and hiding it behind a
    // hardcoded exception would be exactly what the Phase 1 plan forbade
    // ("do not relabel a broken control as context-only to make the report
    // green"). See docs/engine-audits/2026-09-03-engine-findings.md.
    var context = baseContext()
    context.activities = ["hiking", "camping"]
    let snapshot = TripContextCompiler.compile(context, rules: try rules())
    #expect(snapshot.unknownActivityIDs == ["camping"])
}

@Test func notSureBagAppliesNoConstraint() throws {
    var context = baseContext()
    context.bagType = .notSure
    let snapshot = TripContextCompiler.compile(context, rules: try rules())
    #expect(snapshot.bagType == .notSure)
    #expect(snapshot.appliesBagConstraint == false)
    #expect(!snapshot.diagnostics.contains { $0.field == "bagType" }) // notSure is valid, not a fallback
}

@Test func packingStylePassesThroughUnchanged() throws {
    var context = baseContext()
    context.packingStyle = .prepared
    let snapshot = TripContextCompiler.compile(context, rules: try rules())
    #expect(snapshot.packingStyle == .prepared)
}
```

**Step 2: Run, verify failure** (same `-only-testing:PackWiseTests/TripContextSnapshotTests` command). Expected: compile failure — new properties don't exist.

**Step 3: Implement**

Add to `TripContextSnapshot`: `knownActivityIDs: [String]`, `unknownActivityIDs: [String]`, `bagType: BagType`, `appliesBagConstraint: Bool`, `packingStyle: PackingStyle`. Add to `TripContextCompiler.compile`:

```swift
let normalizedActivityIDs = ActivityVocabulary.normalize(context.activities)
var known: [String] = []
var unknown: [String] = []
for id in normalizedActivityIDs {
    if rules.activities[id] != nil { known.append(id) } else { unknown.append(id) }
}
for id in unknown {
    diagnostics.append(ContextDiagnostic(field: "activities", outcome: .unsupportedButSafe(reason: "\(id): no rule in the engine's activity vocabulary")))
}
```

Wire `bagType: context.bagType`, `appliesBagConstraint: context.bagType.appliesBagConstraint` (reuse the existing computed property — don't reimplement it), `packingStyle: context.packingStyle` straight through, no diagnostic (both are always structurally valid — every `BagType`/`PackingStyle` case is a real, supported case; there is no "unknown bag type" the way there's an unknown activity string, since these are closed Swift enums, not free-text IDs).

**Step 4/5: Run tests, run full suite, commit**

```bash
git add ios/PackWise/Domain/TripContextSnapshot.swift ios/PackWiseTests/TripContextSnapshotTests.swift
git commit -m "feat: normalize activities and bag semantics in context snapshot"
```

---

### Task 3: Laundry and weather-quality normalization

**Files:**
- Modify: `ios/PackWise/Domain/TripContextSnapshot.swift`
- Modify: `ios/PackWiseTests/TripContextSnapshotTests.swift`

**Interfaces:**
- Consumes: `TripContext.laundryPlan` (as the equivalence baseline, not something to reimplement independently), `TripWeatherContext`.
- Produces: `laundryPlan: LaundryAccess`, `weatherQuality: WeatherQuality` on `TripContextSnapshot`.

**Step 1: Write the failing tests**

```swift
@Test func laundryPlanMatchesExistingTripContextEquivalenceForEveryLegacyPath() throws {
    let r = try rules()
    var explicit = baseContext(); explicit.laundryAccess = .planned
    var chip = baseContext(); chip.contextChips = [.laundryAvailable]
    var notes = baseContext(); notes.userNotes = "I'll do laundry halfway through"
    var none = baseContext()
    for context in [explicit, chip, notes, none] {
        let snapshot = TripContextCompiler.compile(context, rules: r)
        #expect(snapshot.laundryPlan == context.laundryPlan, "snapshot must never diverge from TripContext.laundryPlan")
    }
}

@Test func legacyLaundrySignalIsNormalizedNotJustPassedThrough() throws {
    var context = baseContext()
    context.contextChips = [.laundryAvailable] // legacy chip, no explicit laundryAccess
    let snapshot = TripContextCompiler.compile(context, rules: try rules())
    #expect(snapshot.laundryPlan == .possible)
    #expect(snapshot.diagnostics.contains { $0.field == "laundry" && $0.outcome.isNormalized })
}

@Test func missingWeatherIsClassifiedMissing() throws {
    var context = baseContext(); context.weather = nil
    let snapshot = TripContextCompiler.compile(context, rules: try rules())
    #expect(snapshot.weatherQuality == .missing)
}

@Test func seasonalWeatherIsClassifiedSeasonalOnly() throws {
    var context = baseContext(); context.weather = .seasonal()
    let snapshot = TripContextCompiler.compile(context, rules: try rules())
    #expect(snapshot.weatherQuality == .seasonalOnly)
}

@Test func partialForecastDoesNotClaimWholeTripCoverage() throws {
    var context = baseContext(days: 30)
    var weather = TripWeatherContext.seasonal()
    weather.source = .fixture
    weather.isPreciseForecast = true
    weather.dailyForecast = (0..<10).map { i in
        DailyForecast(date: Calendar.current.date(byAdding: .day, value: i, to: context.startDate)!, symbol: "sun.max", highF: 70, lowF: 50, rainProbability: 0, uvIndex: 3, windMph: 5, snowExpected: false, summary: "")
    }
    weather.forecastAvailableForPartialTrip = true
    weather.forecastAvailableForWholeTrip = false
    context.weather = weather
    let snapshot = TripContextCompiler.compile(context, rules: try rules())
    #expect(snapshot.weatherQuality == .partial(coveredDays: 10, tripDays: 30))
}

@Test func wholeTripForecastIsClassifiedComplete() throws {
    var context = baseContext(days: 5)
    var weather = TripWeatherContext.seasonal()
    weather.source = .fixture
    weather.isPreciseForecast = true
    weather.dailyForecast = (0..<5).map { i in
        DailyForecast(date: Calendar.current.date(byAdding: .day, value: i, to: context.startDate)!, symbol: "sun.max", highF: 70, lowF: 50, rainProbability: 0, uvIndex: 3, windMph: 5, snowExpected: false, summary: "")
    }
    weather.forecastAvailableForWholeTrip = true
    context.weather = weather
    let snapshot = TripContextCompiler.compile(context, rules: try rules())
    #expect(snapshot.weatherQuality == .complete)
}
```

**Step 3: Implement**

Add `enum WeatherQuality: Hashable, Sendable { case missing; case seasonalOnly; case partial(coveredDays: Int, tripDays: Int); case complete }` to the same file. Add `laundryPlan`/`weatherQuality` fields. Compiler logic:

```swift
let laundry = context.laundryPlan // TripContext already owns this normalization — reuse it verbatim
if laundry != context.laundryAccess {
    diagnostics.append(ContextDiagnostic(field: "laundry", outcome: .normalized(reason: "legacy chip/notes signal folded into laundryPlan")))
}

let weatherQuality: WeatherQuality
if let weather = context.weather {
    if weather.source == .seasonal || (!weather.isPreciseForecast && weather.dailyForecast.isEmpty) {
        weatherQuality = .seasonalOnly
    } else if weather.forecastAvailableForWholeTrip {
        weatherQuality = .complete
    } else {
        weatherQuality = .partial(coveredDays: weather.dailyForecast.count, tripDays: days)
    }
} else {
    weatherQuality = .missing
}
```

Read `WeatherDomain.swift`'s `TripWeatherContext.state()` (`WeatherDomain.swift:169`) before finalizing this branch order — match its precedence for `.seasonal`/`.none`/partial-vs-complete rather than inventing a divergent ordering, since `weatherQuality` is meant to be the same classification the product already trusts, just exposed as a pure value instead of requiring `now`/refresh-state parameters `state()` needs.

**Step 4/5: Run tests, full suite, commit**

```bash
git commit -m "feat: normalize laundry and weather quality in context snapshot"
```

---

### Task 4: Party normalization — never infer ambiguous attribution

**Files:**
- Modify: `ios/PackWise/Domain/TripContextSnapshot.swift`
- Modify: `ios/PackWiseTests/TripContextSnapshotTests.swift`

**Interfaces:**
- Consumes: `context.effectiveParty` (already folds an empty party to `.solo()`), `PartyInvariants.violations(party:items:bags:)`.
- Produces: `party: TripParty` (normalized) on `TripContextSnapshot`.

**Step 1: Write the failing tests**

```swift
@Test func emptyPartyIsAlreadySafeViaEffectiveParty() throws {
    var context = baseContext()
    context.party = TripParty(travelMode: .solo, travelers: [])
    let snapshot = TripContextCompiler.compile(context, rules: try rules())
    #expect(snapshot.party.travelers.count == 1)
    #expect(snapshot.party.travelers.first?.role == .self)
}

@Test func childWithGuardianOutsidePartyLosesTheReferenceRatherThanGuessing() throws {
    var context = baseContext()
    let ghostGuardianID = UUID() // not a real party member
    let child = Traveler(role: .child, ageGroup: .child, packingResponsibility: .guardian, guardianTravelerID: ghostGuardianID)
    context.party = TripParty(travelMode: .family, travelers: [.primarySelf(), child])
    let snapshot = TripContextCompiler.compile(context, rules: try rules())
    let normalizedChild = snapshot.party.travelers.first { $0.role == .child }
    #expect(normalizedChild?.guardianTravelerID == nil) // dropped, never reassigned to a guessed adult
    #expect(snapshot.diagnostics.contains { $0.field == "party" && $0.outcome.isUnsupportedButSafe })
}

@Test func ambiguousGuardianAmongMultipleAdultsIsNeverInferred() throws {
    var context = baseContext()
    let child = Traveler(role: .child, ageGroup: .child, packingResponsibility: .guardian, guardianTravelerID: nil)
    let extraAdult = Traveler(role: .otherAdult, ageGroup: .adult)
    context.party = TripParty(travelMode: .family, travelers: [.primarySelf(), extraAdult, child])
    let snapshot = TripContextCompiler.compile(context, rules: try rules())
    let normalizedChild = snapshot.party.travelers.first { $0.role == .child }
    #expect(normalizedChild?.guardianTravelerID == nil) // still nil — the compiler must not default to "the first adult"
}

@Test func validPartyPassesThroughWithNoDiagnostic() throws {
    var context = baseContext()
    let primary = Traveler.primarySelf()
    let child = Traveler(role: .child, ageGroup: .child, packingResponsibility: .guardian, guardianTravelerID: primary.id)
    context.party = TripParty(travelMode: .family, travelers: [primary, child])
    let snapshot = TripContextCompiler.compile(context, rules: try rules())
    #expect(snapshot.party.travelers.count == 2)
    #expect(!snapshot.diagnostics.contains { $0.field == "party" })
}
```

**Step 3: Implement**

Add `party: TripParty` field. Compiler logic — reuse `PartyInvariants`, don't reimplement its rules:

```swift
let effectiveParty = context.effectiveParty
let violations = PartyInvariants.violations(party: effectiveParty)
var normalizedParty = effectiveParty
if !violations.isEmpty {
    let ids = Set(effectiveParty.travelers.map(\.id))
    let adults = Set(effectiveParty.travelers.filter(\.ageGroup.isAdult).map(\.id))
    normalizedParty.travelers = effectiveParty.travelers.map { traveler in
        var copy = traveler
        if let guardian = copy.guardianTravelerID,
           !(copy.ageGroup.allowsGuardian && ids.contains(guardian) && adults.contains(guardian)) {
            copy.guardianTravelerID = nil // drop, never reassign to a guessed adult
        }
        return copy
    }
    diagnostics.append(ContextDiagnostic(field: "party", outcome: .unsupportedButSafe(reason: "invalid guardian reference(s) dropped, not reassigned")))
}
```

Confirm this doesn't fight `PartyInvariants.normalize(_:in:)` (which operates on `PackingItemDraft`, a different concern — item ownership, not traveler-to-guardian structure) — they're complementary, not overlapping; don't try to unify them.

**Step 4/5: Run tests, full suite, commit**

```bash
git commit -m "feat: normalize party state in context snapshot, never inferring ambiguous attribution"
```

---

### Task 5: Full-ledger fixture compilation and engine-boundary wiring

**Files:**
- Modify: `ios/PackWiseTests/GoldenEngineTests.swift` (or create `ios/PackWiseTests/TripContextSnapshotFixtureTests.swift` — inspect `GoldenEngineTests.swift` first: if it already exposes a private per-fixture "build a `TripContext` from a fixture" helper, add this test into that file and reuse the helper; only create a new file if reusing would require making that helper `internal`/duplicating a non-trivial amount of logic)
- Modify: `ios/PackWise/Domain/Packing/PackingEngine.swift`

**Interfaces:**
- Consumes: all 27 fixtures in `shared/fixtures/golden/golden-fixtures.json`, `TripContextCompiler.compile`.
- Produces: `EngineGeneration.contextDiagnostics: [ContextDiagnostic]` (additive field); proof that every fixture compiles deterministically with no crash.

**Step 1: Write the failing test — full-ledger compilation**

```swift
@Test func everyGoldenFixtureCompilesToADeterministicSnapshot() throws {
    let file = try JSONDecoder().decode(GoldenFixtureFile.self, from: Data(contentsOf: Self.fixturesFile))
    let r = try SharedLibrary.rules()
    for fixture in file.fixtures {
        let context = try buildContext(from: fixture) // reuse GoldenEngineTests' existing fixture->TripContext logic
        let first = TripContextCompiler.compile(context, rules: r)
        let second = TripContextCompiler.compile(context, rules: r)
        #expect(first == second, "\(fixture.id): compilation must be deterministic")
        // Every fixture is a real, well-formed trip — none should produce an
        // "unsupportedButSafe" dates or party diagnostic. Fixtures 18 and 25
        // (camping, cosplayConvention) are EXPECTED to carry an "activities"
        // diagnostic — that's the honest, already-published finding, not a
        // defect this task introduces.
        let unexpectedDiagnostics = first.diagnostics.filter { $0.field != "activities" }
        #expect(unexpectedDiagnostics.isEmpty, "\(fixture.id): unexpected diagnostic \(unexpectedDiagnostics)")
    }
}
```

Adapt `buildContext(from:)` to whatever the real fixture-decoding path is named in `GoldenEngineTests.swift` — read the file first. If fixture weather references a named fixture (`weatherFixture: "SeattleWetCity"` etc.), resolve it the same way the existing golden-rendering code does (`SharedLibrary.namedWeatherFixtures()` or equivalent) rather than reimplementing fixture resolution.

**Step 2: Run, verify it fails** for the right reason (missing helper access, not a real defect) — if it fails because a real fixture produces an unexpected diagnostic, STOP and investigate before proceeding; that would mean either the compiler has a bug or a fixture is more malformed than Phase 1 recorded, and either needs understanding before this task can close.

**Step 3: Implement, run until green**

**Step 4: Wire into the engine boundary — additive only**

In `PackingEngine.swift`, add to `EngineGeneration`:

```swift
struct EngineGeneration: Sendable {
    var items: [PackingItemDraft]
    var coverageSuppressions: [CoverageSuppression]
    var constraintDecisions: [ConstraintDecision]
    var contextDiagnostics: [ContextDiagnostic]
}
```

In `generateDetailed(context:existing:overrides:)`, compile the snapshot once at the top and thread its diagnostics into the return value — do not read anything else from it, do not pass it into `generateSimple`/`generateForParty`/`resolve`:

```swift
func generateDetailed(
    context: TripContext,
    existing: [PackingItemDraft] = [],
    overrides: [RecommendationOverrideDraft] = []
) -> EngineGeneration {
    let snapshot = TripContextCompiler.compile(context, rules: rules)
    let party = context.effectiveParty
    let generated = party.usesSimpleList
        ? generateSimple(context: context, existing: existing, overrides: overrides)
        : generateForParty(context: context, existing: existing, overrides: overrides)
    return EngineGeneration(
        items: generated.items.map { PartyInvariants.normalize($0, in: party) },
        coverageSuppressions: generated.suppressions,
        constraintDecisions: ConstraintResolver.decisions(from: generated.drops),
        contextDiagnostics: snapshot.diagnostics
    )
}
```

Find every other call site constructing `EngineGeneration(...)` directly (grep the file) and add `contextDiagnostics:` there too (likely none besides this one — `generate(context:...)` calls `generateDetailed` and only reads `.items`).

**Step 5: Prove zero behavior drift**

```bash
python3 scripts/report_engine_goldens.py --baseline-ref HEAD --candidate ios/PackWiseTests/Goldens
```
Expected: 27/27 unchanged, 0 changes in every category — `GoldenItem`/golden JSON never serialized `contextDiagnostics`, so this must be completely clean. If anything besides "clean" appears, you have introduced a behavior change; find and fix it before proceeding — do not weaken the assertion or relabel this as a Phase-3+ finding.

Run the full suite:
```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
Expected: `** TEST SUCCEEDED **`.

**Step 6: Commit**

```bash
git commit -m "feat: compile context snapshot for every generation behind the engine boundary"
```

---

### Task 6: Run the full audit, publish evidence, close Phase 2

**Files:**
- Create: `docs/engine-audits/2026-09-03-phase-2-context-snapshot.md`
- Modify: `docs/plans/2026-09-02-product-hardening-program.md`

**Interfaces:**
- Consumes: Tasks 1-5.
- Produces: a Phase 2 evidence report and an updated program-tracking doc.

- [ ] Run `scripts/run_engine_audit.sh` (Phase 1's one-command regression authority) — must pass clean.
- [ ] Run the full `xcodebuild test` suite — must pass clean.
- [ ] Run `python3 scripts/report_engine_goldens.py --baseline-ref fe7aca0 --candidate ios/PackWiseTests/Goldens` (the pre-Phase-1 baseline, i.e. the whole of Phase 1 + Phase 2 together) — must show 27/27 unchanged, proving Phase 2 changed zero recommendation behavior end to end, not just step-by-step.
- [ ] Write `docs/engine-audits/2026-09-03-phase-2-context-snapshot.md` covering:
  - What `TripContextSnapshot`/`TripContextCompiler` do and where they live.
  - The full edge-case coverage matrix, explicitly ticking off every case named in the Phase 2 directive: valid context, normalized context, `unsupportedButSafe`, unknown/custom activity, `BagType.notSure` with no invented constraint, missing weather, partial/seasonal weather quality, invalid/reversed dates, empty/malformed party state, legacy laundry normalization, deterministic compilation across repeated runs, ambiguous traveler context → don't infer — for each, name the test(s) that cover it.
  - Per-fixture diagnostics summary across all 27 fixtures (most should be diagnostic-free; fixtures 18/25 should show the expected "activities" diagnostic for camping/cosplayConvention; note any other fixture that surfaces a diagnostic and explain why).
  - The migration-boundary state: exactly what's compiled behind the boundary now (diagnostics only), what still reads `TripContext` directly (everything else — name `ClothingQuantity.swift:268` explicitly as the one known internal call site and record that migrating it is deliberately left to whichever phase owns clothing/quantity decisions), and why no consumer opted in during Phase 2.
  - Any new findings this task's own work surfaced (e.g. if the fixture-ledger compilation test revealed something about the 27 fixtures Phase 1 didn't catch) — route each to a specific phase using the same P0/P1/P2 rubric and format Phase 1's findings doc used (fixture/item, observed, desired, command, destination phase).
- [ ] Update `docs/plans/2026-09-02-product-hardening-program.md`: add a "Phase 2 closure — 2026-09-03" section immediately after the existing "Phase 1 closure" section, in the same style (numbered list of what was built, evidence paths, exit-gate confirmation, explicit "Phase 3 not yet started").
- [ ] Commit:

```bash
git add docs/engine-audits/2026-09-03-phase-2-context-snapshot.md docs/plans/2026-09-02-product-hardening-program.md
git commit -m "docs: close phase 2 context model hardening"
```

---

## Self-Review

- Every task is additive: new type, new fields on `TripContextSnapshot`, one additive field on `EngineGeneration`. Nothing existing is renamed, removed, or restructured.
- No task touches `ios/PackWise/Domain/Packing/ClothingQuantity.swift`, `CoverageResolver.swift`, `ConstraintResolver.swift`, `QuantityEngine.swift`, or any weather/reconciliation logic beyond reading `TripWeatherContext` structurally — those stay exactly as Phase 1 left them, reserved for Phases 3/4/6.
- The one deliberate scope decision — not migrating `ClothingQuantity.swift:268`'s `context.laundryPlan` read to the snapshot even though it's the single cleanest candidate — is stated explicitly rather than silently done or silently skipped, per the plan's own migration rule ("golden outputs remain unchanged for a behavior family until that family explicitly opts into the snapshot").
- Every required edge case from the Phase 2 directive maps to a specific test in Tasks 1-4 and is re-confirmed present in Task 6's evidence doc.
- Determinism is tested both narrowly (Task 1, a single context compiled twice) and broadly (Task 5, all 27 fixtures compiled twice).
- The exit gate's "existing golden recommendations remain stable" is proven twice: per-task in Task 5, and end-to-end against the pre-Phase-1 baseline in Task 6.
