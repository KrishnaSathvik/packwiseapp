# PackWise Product Hardening Phase 6 — Weather Need Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Map normalized weather (precise, partial, seasonal, cached, failed) into conservative packing needs without inventing precision the forecast doesn't have; blend a partial forecast's uncovered remainder with the same seasonal heuristic a fully-unforecast trip already gets; decide and test the cold-without-snow glove question the Phase 5 closure routed here; give each of the eight named exit scenarios execution evidence, existing or new.

**Architecture:** Route `PackingEngine.addWeather` and `CoverageResolver.CoverageContext` through the existing `TripContextSnapshot.weatherQuality` classification (`WeatherQuality`: `.missing`/`.seasonalOnly`/`.partial(coveredDays:tripDays:)`/`.complete`, Phase 2) instead of each re-deriving its own inline "do I have a forecast" check — a natural extension of the surface Phase 4/5 already read weather through, not a new mechanism. A partial forecast keeps its exact precise-day signals and additionally runs the existing `addSeasonal` heuristic for the trip, unconditionally safe because `addSeasonal` already only fills gaps `collected[id] == nil` never overwrites. Cold-without-snow gloves close by adding `clothing.gloves` to `signalAdds.sustainedCold` — the broader signal that already subsumes `freezingCold` — reusing `CoverageResolver`'s existing `.coldHands` need and ski-glove suppression ordering with no new capability, code, or ID-pair table. The WeatherKit fetch/cache/proposal pipeline (`WeatherChangeReconciler`, `TripWeatherRefresh`, `TripWeatherResolver`, `WeatherRefreshPolicy`, `MockWeatherService`) is untouched; it already reaches every behavior change through `PackingEngine.recommendationDiff` → `generateDetailed`.

**Tech Stack:** Swift 6, Swift Testing, JSON shared catalog/rules, JSON golden fixtures, JSON named weather fixtures, Python audit/report tooling, Xcode/iOS 18 simulator tests.

## Global Constraints

- Work on `product-hardening-phase1` from `e958c07`; preserve every Phase 1–5 commit and the unrelated signing change in the main checkout.
- Follow the approved design at `docs/superpowers/specs/2026-09-04-product-hardening-phase-6-weather-need-hardening-design.md`.
- Do not rebuild, rewire, or add a second mechanism alongside `WeatherChangeReconciler`, `TripWeatherRefresh`, `TripWeatherResolver`, `WeatherRefreshPolicy`, or `MockWeatherService`. Phase 11 owns running V2 needs/coverage through the reconciler as its own integration step; Phase 6 changes only what `generateDetailed` produces.
- No new `WeatherSignal` case (stays at 11), no new `PackingCapability` case (stays at 12), no new `ActivityNeed` case (stays at 8, Phase 5's). Every gap in scope closes with the existing closed vocabularies.
- No threshold in `shared/rules/weather.json`'s `thresholds` block moves. `rainProbabilityAdd`, `coolEveningMaxF`, `coldMaxF`, `hotMinF`, `uvAdd`, `windMphAdd`, `temperatureSwingAdd`, `heavyRainProbability`, `freezingMaxF`, `persistentRainRatio` stay exactly as they are.
- The cold-without-snow glove behavior must be decided and tested this phase, not left routed a third time (Phase 4 named it, Phase 5's closure routed it here explicitly).
- `WeatherQuality` routing (Task 1) must be a zero-diff refactor: `.complete`, `.seasonalOnly`, and `.missing` reproduce today's output exactly before Task 2 changes `.partial`'s behavior.
- `addSeasonal`'s existing gap-filling guard (`collected[id] == nil`) is the only safety mechanism a partial-forecast blend may rely on. Do not add a second overwrite-prevention check; if the guard is insufficient, that is a finding, not a new mechanism to invent silently.
- Four guards, reviewed and required before this phase closes: (1) seasonal fallback fills only the uncovered remainder of a partial forecast, never overwriting or duplicating a precise-day item; (2) seasonal-remainder items keep `addSeasonal`'s own seasonal reason codes (`weather.seasonal_sun`, `weather.seasonal_layer`) and never take on a precise weather reason code that would imply day-level data nobody forecast — pinned by an explicit reason-code assertion in Task 2, not left for Phase 8's trace work; (3) precise-day and seasonal-remainder candidates compose through the one existing `collected`/`CoverageResolver` pipeline before final suppression, never as two independently-resolved checklists; (4) a cached forecast generates identically to the same data fresh (Task 6), while only a genuine fetch failure with no usable cache degrades to no-weather behavior — cached and missing are not the same case.
- Existing green evidence is cited, not re-implemented: `CoverageTests.hotRainDropsShellKeepsUmbrella`, `coldRainKeepsShell`, `rainShellCoversWind`, `temperatureSwingKeepsOneLightLayer`, `winterLayeringSurvivesCoverage`, `skiGlovesCoverColdHandsWithoutAnIDPairRule`, `coldNonSkiTripNeedsColdHandsButNotSnowSportHands`, `skiIntentResolvesHandOverlapWithoutForecastWeather`; `WeatherChangeTests.partialForecastDoesNotCoverA30DayTrip`, `noWeatherStillGenerates`, `existingUserRainCoveragePreventsADuplicateProposal`, `completedTripsDoNotRefresh`; golden fixtures `11-couple-5d-rain` and `19-phoenix-5d-city-walking-hot`.
- User authority is preserved: Not Needed stays Not Needed, manual quantity stays authoritative, user-added items survive, packed state survives, explicit owner/carrier survive. A new glove or seasonal-remainder candidate can never resurrect an explicitly rejected item.
- Golden regressions include any clothing/footwear/quantity/coverage/constraint/ownership/carrier change outside the fixtures each task names. `report_engine_goldens.py --baseline-ref e958c07` runs after every task.
- Phase 6 does not own Phase 7 (central constraints/party sharing, F-5), Phase 8 (trace productization), Phase 9+ (context intelligence), or presentation/lifecycle work. Presentation stays frozen, physical-device verification stays deferred, M3B/M3C remain blocked.
- Do not edit `docs/plans/2026-09-02-product-hardening-program.md` before Task 7. Stop at the Phase 6 exit gate; do not begin Phase 7.

---

## File Map

- Modify `ios/PackWise/Domain/Packing/PackingEngine.swift`: `addWeather(context:snapshot:into:)` signature change and `WeatherQuality` routing (Task 1), the partial-remainder `addSeasonal` call (Task 2).
- Modify `ios/PackWise/Domain/Packing/CoverageResolver.swift`: `CoverageContext.init(snapshot:thresholds:)` routed through `weatherQuality` (Task 1), `usesSeasonalWarmthFallback` widened to `.partial` (Task 2). No change to `PackingCapability`, `itemCapabilities`, or `priority`.
- Modify `shared/rules/weather.json`: `signalAdds.sustainedCold` gains `"clothing.gloves"` (Task 3). No threshold changes.
- Create `ios/PackWiseTests/WeatherNeedHardeningTests.swift`: the Phase 6 focused suite — quality-routing regression, partial-blend behavior, cold-without-snow gloves, and the wind+mild/heat+strong-sun/hot-day-cool-night matrix (Tasks 1, 2, 3, 4).
- Modify `ios/PackWiseTests/WeatherChangeTests.swift`: cached/failed generation-equivalence tests (Task 6).
- Modify `shared/fixtures/golden/golden-fixtures.json`: fixtures 33–36 (Tasks 2, 3, 5).
- Create new JSON outputs under `ios/PackWiseTests/Goldens/33..36*.json` after semantic review (Tasks 2, 3, 5).
- Create `docs/engine-audits/2026-09-04-phase-6-weather-need-hardening.md`: exit evidence (Task 7).
- Modify `docs/plans/2026-09-02-product-hardening-program.md`: close Phase 6 only after all gates pass, in Task 7 only.

---

### Task 1: Route weather generation through the existing `WeatherQuality` classification

**Files:**
- Modify: `ios/PackWise/Domain/Packing/PackingEngine.swift`
- Modify: `ios/PackWise/Domain/Packing/CoverageResolver.swift`
- Create: `ios/PackWiseTests/WeatherNeedHardeningTests.swift`

**Interfaces:**
- Consumes: `TripContextSnapshot.weatherQuality: WeatherQuality` (`ios/PackWise/Domain/TripContextSnapshot.swift:112`), unchanged.
- Produces: `PackingEngine.addWeather(context:snapshot:into:)` (signature widened from `(context:into:)`), `CoverageContext.init(snapshot:thresholds:)` unchanged signature, both routed through one `switch` on `weatherQuality` instead of two independent inline checks.

- [ ] **Step 1: Write the failing routing test.** This pins the mapping table itself as living documentation, independent of any specific candidate item, so a future edit to either function cannot silently diverge from `WeatherQuality`'s own cases.

```swift
import Foundation
import Testing
@testable import PackWise

/// Phase 6 — normalized weather (precise, partial, seasonal, cached, failed)
/// maps to conservative packing needs without inventing precision.
struct WeatherNeedHardeningTests {
    private func rules() throws -> PackingRulesFile { try SharedLibrary.rules() }
    private func makeEngine() throws -> PackingEngine {
        PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
    }
    private func destination(_ name: String) throws -> Destination {
        try #require(try SharedLibrary.testDestinations().first { $0.city == name })
    }
    private func weather(fixture name: String, start: Date, days: Int) throws -> TripWeatherContext {
        let fixture = try #require(try SharedLibrary.weatherFixtures()[name])
        let end = Calendar.current.date(byAdding: .day, value: days - 1, to: start)!
        return MockWeatherService.context(from: fixture, start: start, end: end, fixtureID: fixture.id)
    }
    private func context(
        destination: Destination, days: Int = 5, type: TripType = .cityBreak,
        activities: [String] = ["sightseeing", "walking"], bag: BagType = .carryOn,
        style: PackingStyle = .balanced, weather: TripWeatherContext? = nil,
        start: Date = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 14))!
    ) -> TripContext {
        let end = Calendar.current.date(byAdding: .day, value: days - 1, to: start)!
        let math = TripDateMath.daysAndNights(from: start, to: end)
        var prefs = TravelerPreferences.deviceDefaults()
        prefs.homeCountryCode = "US"; prefs.homeCountrySource = .userConfirmed
        return TripContext(
            destination: destination, startDate: start, endDate: end,
            durationDays: math.days, durationNights: math.nights, tripType: type,
            activities: activities, datedActivities: [], bagType: bag,
            packingStyle: style, transportation: .unknown, laundryAccess: .none,
            travelerCount: 1, userNotes: "", contextChips: [], weather: weather,
            preferences: prefs, party: .solo()
        )
    }

    /// Every `WeatherQuality` case must be handled by exactly one branch in
    /// both `addWeather` and `CoverageContext` — this is the seam Task 1
    /// introduces and Task 2 extends. `.complete` and `.seasonalOnly` are
    /// reproduced unchanged here; `.partial`'s new blended behavior is
    /// Task 2's test, not this one.
    @Test func completeForecastStillProducesExactlyTodaysSignals() throws {
        let dest = try destination("Seattle")
        let rainy = try weather(fixture: "SeattleWetCity", start: Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5))!, days: 5)
        let generation = try makeEngine().generateDetailed(context: context(destination: dest, days: 5, weather: rainy))
        let ids = Set(generation.items.compactMap(\.canonicalItemID))
        #expect(ids.contains("clothing.rain_jacket"))
        #expect(!ids.contains("clothing.light_jacket"))  // no seasonal fallback on a complete forecast
    }

    @Test func seasonalOnlyStillRoutesThroughAddSeasonalOnly() throws {
        let dest = try destination("Reykjavik")  // 64.1°N — a January start is winter
        let winter = Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 10))!
        let items = try makeEngine().generate(context: context(destination: dest, days: 5, weather: nil, start: winter))
        #expect(items.contains { $0.canonicalItemID == "clothing.light_jacket" })
        #expect(items.allSatisfy { $0.reasonCode != "weather.rain_days" })
    }
}
```

- [ ] **Step 2: Run and verify RED.** Run:

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/WeatherNeedHardeningTests
```

Expected: compile succeeds (nothing new is referenced yet), tests pass immediately — this step's real purpose is establishing the pre-refactor baseline these two tests characterize, not driving new code. Record the pass as the characterization baseline the refactor must not disturb.

- [ ] **Step 3: Route `CoverageContext` through `weatherQuality`.** Replace the inline `if let weather = snapshot.weather, weather.isPreciseForecast || !weather.dailyForecast.isEmpty` branch with:

```swift
let outdoor = !activityIDs.isDisjoint(with: ["hiking", "sightseeing", "walking", "running", "beachDays"])
let month = Calendar.current.component(.month, from: snapshot.startDate)
let latitude = snapshot.destination.latitude
let northWinter = latitude >= 0 && [12, 1, 2].contains(month)
let southWinter = latitude < 0 && [6, 7, 8].contains(month)
let seasonalWarmthEligible = (northWinter || southWinter) && abs(latitude) > 30

switch snapshot.weatherQuality {
case .complete, .partial:
    // weatherQuality is derived from snapshot.weather, so a non-nil value
    // here is guaranteed by construction (TripContextSnapshot.swift:201).
    let forecast = snapshot.weather ?? .seasonal()
    weatherSignals = WeatherSignalExtractor.extract(
        weather: forecast, thresholds: thresholds,
        outdoorActivities: outdoor, tripDays: snapshot.durationDays
    ).signals
    hasForecastWeather = true
    usesColdMinimumHeavyWarmth = forecast.minTemperatureF <= thresholds.coldMaxF
    // Task 1: identical to today — a complete forecast never falls back.
    // Task 2 widens this to true for `.partial`.
    usesSeasonalWarmthFallback = false
case .seasonalOnly, .missing:
    weatherSignals = []
    hasForecastWeather = false
    usesColdMinimumHeavyWarmth = false
    usesSeasonalWarmthFallback = seasonalWarmthEligible
}
```

- [ ] **Step 4: Route `addWeather` through `weatherQuality`.** Change the signature to `addWeather(context: TripContext, snapshot: TripContextSnapshot, into collected: inout [String: RuleSuggestion])` and replace the entry guard:

```swift
private func addWeather(context: TripContext, snapshot: TripContextSnapshot, into collected: inout [String: RuleSuggestion]) {
    switch snapshot.weatherQuality {
    case .missing, .seasonalOnly:
        addSeasonal(context: context, into: &collected)
        return
    case .partial, .complete:
        break
    }
    guard let weather = context.weather else {
        addSeasonal(context: context, into: &collected)
        return
    }
    let conditions = WeatherSignalExtractor.extract(
        weather: weather, thresholds: rules.weather.thresholds,
        outdoorActivities: context.outdoorActivities, tripDays: context.durationDays
    )
    // ... every existing `add(...)` call below this line is unchanged ...
}
```

Update the one call site in `ruleSuggestions(for:snapshot:)` from `addWeather(context: context, into: &collected)` to `addWeather(context: context, snapshot: snapshot, into: &collected)`.

- [ ] **Step 5: Verify GREEN and zero behavior drift.** Run:

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/WeatherNeedHardeningTests \
  -only-testing:PackWiseTests/CoverageTests \
  -only-testing:PackWiseTests/WeatherChangeTests \
  -only-testing:PackWiseTests/PackingEngineTests \
  -only-testing:PackWiseTests/ActivityContractTests
PYTHONDONTWRITEBYTECODE=1 python3 scripts/report_engine_goldens.py \
  --baseline-ref e958c07 --candidate ios/PackWiseTests/Goldens --format markdown
```

Expected: every focused suite passes unchanged, including every test named in the Global Constraints' cited-evidence list. The golden diff must show **zero** row changes across all 32 fixtures — this is the zero-diff gate proving the `weatherQuality` switch reproduces exactly the two inline checks it replaced.

- [ ] **Step 6: Commit the routing refactor.**

```bash
git add ios/PackWise/Domain/Packing/PackingEngine.swift \
  ios/PackWise/Domain/Packing/CoverageResolver.swift \
  ios/PackWiseTests/WeatherNeedHardeningTests.swift
git commit -m "refactor: route weather generation through the existing WeatherQuality classification"
```

---

### Task 2: Blend a partial forecast's uncovered remainder with seasonal fallback

**Files:**
- Modify: `ios/PackWise/Domain/Packing/PackingEngine.swift`
- Modify: `ios/PackWise/Domain/Packing/CoverageResolver.swift`
- Modify: `shared/fixtures/golden/golden-fixtures.json`
- Test: `ios/PackWiseTests/WeatherNeedHardeningTests.swift`
- Test: `ios/PackWiseTests/WeatherChangeTests.swift`

**Interfaces:**
- Consumes: `WeatherQuality.partial(coveredDays:tripDays:)`, `PackingEngine.addSeasonal(context:into:)` (unchanged).
- Produces: a partial forecast's covered days keep exact signals; its uncovered remainder gets the same conservative month/latitude check a fully-unforecast trip already gets.

- [ ] **Step 1: Write the failing blend test.** A 10-day Chicago trip in July against `ChicagoRainyFall`'s 5 days of data must show the covered-day rain signal **and** the seasonal remainder's sun items. Chicago, not Seattle, and summer, not winter, are deliberate: Chicago's precise window (highs 69–78°F, UV 3–5) never triggers `hotOutdoorExposure`/`highUVExposure` on its own, and `toiletries.sunscreen`/`essentials.sunglasses` map to no `PackingCapability` at all — so the seasonal candidate can never collide with Phase 4's coverage dedup. A winter-fallback version of this test would have picked a location whose precise days already trip `coldEvenings`, and the seasonal candidate (also mapped to `.warmthLight`) would be correctly *suppressed* by the item the precise days already justified — a real result, but the wrong one to build a first demonstration around.

```swift
/// A partial forecast keeps its exact covered-day signals and, for the
/// trip's genuinely unforecast remainder, gets the same conservative
/// seasonal check a fully-unforecast trip already gets — never zero,
/// never invented day-level precision for days nobody forecast.
@Test func partialForecastBlendsCoveredSignalsWithSeasonalRemainder() throws {
    let dest = try destination("Chicago")
    let start = Calendar.current.date(from: DateComponents(year: 2027, month: 7, day: 5))!
    let rainy = try weather(fixture: "ChicagoRainyFall", start: start, days: 10)  // only 5 days of data exist
    // The trip's own start must land in the same July window as the
    // weather data above — addSeasonal's summer check reads
    // `context.startDate`, not the weather object's dates.
    let snapshot = TripContextCompiler.compile(context(destination: dest, days: 10, weather: rainy, start: start), rules: try rules())
    guard case .partial(let covered, let total) = snapshot.weatherQuality else {
        Issue.record("expected partial coverage, got \(snapshot.weatherQuality)")
        return
    }
    #expect(covered == 5)
    #expect(total == 10)

    let generation = try makeEngine().generateDetailed(context: context(destination: dest, days: 10, weather: rainy, start: start))
    let ids = Set(generation.items.compactMap(\.canonicalItemID))
    // The covered days' exact rain signal, unchanged from today.
    #expect(ids.contains("clothing.rain_jacket"))
    // The uncovered remainder's seasonal summer check — new this task.
    // Neither id maps to a `PackingCapability`, so neither can be
    // suppressed by coverage: this is an unambiguous presence check.
    #expect(ids.contains("toiletries.sunscreen"))
    #expect(ids.contains("essentials.sunglasses"))
    // addSeasonal never overwrites: exactly one rain jacket, not a
    // seasonal-tier duplicate competing with the precise-tier one.
    #expect(generation.items.filter { $0.canonicalItemID == "clothing.rain_jacket" }.count == 1)
    // Seasonal evidence must never masquerade as precise-forecast evidence:
    // the uncovered remainder's items carry addSeasonal's existing seasonal
    // reason code, not a precise weather code that implies day-level data
    // nobody forecast. This is provenance, not UI prose — `addSeasonal`
    // already renders "Seasonal sun is likely." for this exact code.
    let sunscreenRow = try #require(generation.items.first { $0.canonicalItemID == "toiletries.sunscreen" })
    #expect(sunscreenRow.reasonCode == "weather.seasonal_sun")
    let sunglassesRow = try #require(generation.items.first { $0.canonicalItemID == "essentials.sunglasses" })
    #expect(sunglassesRow.reasonCode == "weather.seasonal_sun")
}

/// The `.partial` branch calls `addSeasonal` unconditionally; `addSeasonal`
/// itself is the only safety mechanism (`collected[id] == nil`) preventing
/// it from downgrading an item the precise days already justified with a
/// higher-tier reason. This test pins that specific guarantee directly.
@Test func seasonalRemainderNeverDowngradesAPreciseDayItem() throws {
    let dest = try destination("Chicago")
    let start = Calendar.current.date(from: DateComponents(year: 2027, month: 7, day: 5))!
    let rainy = try weather(fixture: "ChicagoRainyFall", start: start, days: 10)
    let generation = try makeEngine().generateDetailed(context: context(destination: dest, days: 10, weather: rainy, start: start))
    let rainJacket = try #require(generation.items.first { $0.canonicalItemID == "clothing.rain_jacket" })
    #expect(rainJacket.reasonCode.hasPrefix("weather."))
    #expect(rainJacket.reasonCode != "weather.seasonal_layer")
}
```

- [ ] **Step 2: Run and verify RED.** Expected: `covered == 5` and `total == 10` already pass (Phase 2's classification); `ids.contains("toiletries.sunscreen")` and `ids.contains("essentials.sunglasses")` fail — Task 1 left `.partial` behaving exactly like `.complete`, so the uncovered remainder still gets nothing.

- [ ] **Step 3: Widen `addWeather`'s `.partial` branch.** After the existing precise-day `add(...)` calls (unchanged) at the end of the function body:

```swift
    // Task 2: a partial forecast's uncovered remainder gets the same
    // conservative seasonal check a fully-unforecast trip already gets.
    // Safe by construction — addSeasonal only fills `collected[id] == nil`
    // gaps, so it can never overwrite or duplicate a precise-day item.
    if case .partial = snapshot.weatherQuality {
        addSeasonal(context: context, into: &collected)
    }
}
```

- [ ] **Step 4: Widen `CoverageContext`'s `usesSeasonalWarmthFallback`.** In the `.complete, .partial` branch from Task 1:

```swift
usesSeasonalWarmthFallback = {
    if case .partial = snapshot.weatherQuality { return seasonalWarmthEligible }
    return false  // .complete never falls back
}()
```

- [ ] **Step 5: Verify GREEN.** Run the Task 1 command set again. Expected: both new tests pass; every cited-evidence test from Global Constraints stays green (none of them use a partial forecast, so none are affected).

- [ ] **Step 6: Add the partial-forecast golden fixture.** Add fixture 33 to `shared/fixtures/golden/golden-fixtures.json`:

| ID | Scenario | Measures |
| --- | --- | --- |
| 33 | Chicago · 10d · vacation · walking+sightseeing · July · `ChicagoRainyFall` (5 days of provider data) | partial-forecast coverage blends the precise rain signal with the seasonal summer-sun fallback for the remaining 5 days, no invented daily precision, no coverage-suppression ambiguity |

```json
{
  "id": "33-chicago-10d-partial-forecast-seasonal-remainder",
  "proves": "A forecast covering less than the trip keeps exact precise-day signals and blends the uncovered remainder with the same seasonal heuristic a fully-unforecast trip gets — no invented daily precision",
  "destination": "Chicago",
  "weatherFixture": "ChicagoRainyFall",
  "startDate": "2027-07-05",
  "days": 10,
  "tripType": "vacation",
  "activities": ["walking", "sightseeing"],
  "bag": "checked",
  "style": "balanced",
  "laundry": "none",
  "homeCountryCode": "US"
}
```

Run `python3 scripts/validate_shared.py`, then:

```bash
PACKWISE_RECORD_GOLDENS=1 xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/GoldenEngineTests
```

The recorder intentionally fails after writing. Then run the semantic report against `e958c07`: expected exactly one new fixture (33), zero changes to fixtures 1–32.

- [ ] **Step 7: Commit the blend.**

```bash
git add ios/PackWise/Domain/Packing/PackingEngine.swift \
  ios/PackWise/Domain/Packing/CoverageResolver.swift \
  ios/PackWiseTests/WeatherNeedHardeningTests.swift \
  shared/fixtures/golden/golden-fixtures.json ios/PackWiseTests/Goldens
git commit -m "feat: blend partial-forecast coverage with seasonal fallback for the uncovered remainder"
```

---

### Task 3: Decide and test cold-without-snow gloves

**Files:**
- Modify: `shared/rules/weather.json`
- Modify: `shared/fixtures/golden/golden-fixtures.json`
- Test: `ios/PackWiseTests/WeatherNeedHardeningTests.swift`
- Test: `ios/PackWiseTests/CoverageTests.swift`

**Interfaces:**
- Consumes: `WeatherSignal.sustainedCold`, `CoverageResolver.itemCapabilities["clothing.gloves"] == [.coldHands]` (unchanged), `CoverageResolver.priority` ordering (unchanged).
- Produces: `clothing.gloves` reaches `addWeather` on any `sustainedCold` trip, not only `snowExposure`.

- [ ] **Step 1: Write the failing generation-level test.** `CoverageTests.coldNonSkiTripNeedsColdHandsButNotSnowSportHands` already proves the *need* exists using an injected candidate; this test proves the engine actually emits one.

```swift
/// Decision: `clothing.gloves` reaches `sustainedCold` trips, not only
/// `snowExposure` ones. `sustainedCold` is the broader signal — `freezingCold`
/// is a strict subset of it in `WeatherSignalExtractor` — so this single
/// change also covers every `freezingCold` trip without a second row.
/// `coldEvenings` is deliberately NOT the gating signal: it fires on merely
/// cool evenings (min ≤ 62°F) that are not a cold-hands trip.
@Test func sustainedColdWithoutSnowProducesOrdinaryGlovesNotSkiGloves() throws {
    let dest = try destination("Denver")
    let start = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 12))!
    let coldNoSnow = weather(days: 5, start: start, highF: 44, lowF: 28, rain: 0.1, wind: 12, snow: false)
    let generation = try makeEngine().generateDetailed(
        context: context(destination: dest, type: .cityBreak, activities: ["sightseeing"], weather: coldNoSnow)
    )
    let ids = Set(generation.items.compactMap(\.canonicalItemID))
    #expect(ids.contains("clothing.gloves"))
    #expect(!ids.contains("activities.ski_gloves"))  // no ski intent on a city trip
    let gloveRow = try #require(generation.items.first { $0.canonicalItemID == "clothing.gloves" })
    #expect(gloveRow.reasonCode == "weather.sustained_cold")
}

/// A merely cool-evening trip (not sustained cold) still gets no gloves —
/// the gate is deliberately narrower than `coldEvenings`.
@Test func merelyCoolEveningsDoNotProduceGloves() throws {
    let dest = try destination("Chicago")
    let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5))!
    let cool = weather(days: 5, start: start, highF: 70, lowF: 55, rain: 0.1)  // coldEvenings, not sustainedCold
    let ids = Set(try makeEngine().generate(context: context(destination: dest, weather: cool)).compactMap(\.canonicalItemID))
    #expect(!ids.contains("clothing.gloves"))
}
```

(`weather(days:start:highF:lowF:rain:uv:wind:snow:swingDay:)` and `destination(_:)`/`context(...)` are `CoverageTests`'s existing private helpers — add these two tests to `CoverageTests.swift` directly, next to `coldNonSkiTripNeedsColdHandsButNotSnowSportHands`, rather than duplicating the helpers into `WeatherNeedHardeningTests.swift`.)

- [ ] **Step 2: Extend the existing boundary test to close the loop.** Amend `coldNonSkiTripNeedsColdHandsButNotSnowSportHands` with one line proving the synthetic candidate it injects is no longer synthetic — the real engine now produces the same conclusion:

```swift
    #expect(needs.contains(.coldHands))
    #expect(!needs.contains(.snowSportHands))
    #expect(resolution.kept.compactMap(\.canonicalItemID) == ["clothing.gloves"])
    #expect(resolution.suppressions.isEmpty)
    // Phase 6: the candidate this test injects is no longer synthetic —
    // the real engine now emits it on the same trip.
    let real = Set(try makeEngine().generate(context: raw).compactMap(\.canonicalItemID))
    #expect(real.contains("clothing.gloves"))
```

- [ ] **Step 3: Run and verify RED.** Expected: both new tests fail (`clothing.gloves` absent), the amended assertion fails (`real.contains(...)` false); `merelyCoolEveningsDoNotProduceGloves` passes immediately (already true today) — confirm rather than assume, per Phase 5's precedent for a test that passes on first run.

- [ ] **Step 4: Make the decision.** In `shared/rules/weather.json`, `signalAdds.sustainedCold`:

```json
"sustainedCold": [
  "clothing.light_sweater",
  "clothing.hoodie",
  "clothing.gloves"
]
```

`signalAdds.snowExposure` and `signalAdds.freezingCold` are untouched. `trip-types.json`'s `skiSnow` row and `CoverageResolver.priority`'s ski-glove-before-ordinary-glove ordering are untouched.

- [ ] **Step 5: Verify GREEN.** Run `CoverageTests` and `WeatherNeedHardeningTests` in full, then the golden semantic report against `e958c07`. Expected: every fixture using a `sustainedCold`-triggering forecast without `snowExposure` may gain a `clothing.gloves` row — check `15-minneapolis-6d-deep-winter` and `16-minneapolis-7d-winter-family` (both `MinneapolisDeepWinter`, which has snow days, so `snowExposure` already covers them — confirm no change) and `18-reykjavik-64d-roadtrip-camping-seasonal` (seasonal fallback, no forecast signals — confirm no change). Read the actual diff; do not assume which fixtures move.

- [ ] **Step 6: Add the cold-without-snow golden fixture.** Fixture 34, using `ReykjavikColdWindy` (currently unused by any golden fixture — highs 39–44°F, zero snow days across all 5 days, one rain day, wind to 32 mph):

| ID | Scenario | Measures |
| --- | --- | --- |
| 34 | Reykjavik · 5d · city · sightseeing · `ReykjavikColdWindy` (cold, windy, one rain day, zero snow) | cold-without-snow gloves; coldRain rain shell; wind suppressed by rain shell; no ski gloves |

```json
{
  "id": "34-reykjavik-5d-cold-windy-no-snow",
  "proves": "Sustained cold without snow produces ordinary gloves, not ski gloves; coldRain still forces a rain shell that also covers the wind need",
  "destination": "Reykjavik",
  "weatherFixture": "ReykjavikColdWindy",
  "startDate": "2026-11-09",
  "days": 5,
  "tripType": "cityBreak",
  "activities": ["sightseeing", "walking"],
  "bag": "carryOn",
  "style": "balanced",
  "laundry": "none",
  "homeCountryCode": "US"
}
```

Expected new rows: exactly one `clothing.gloves` (`weather.sustained_cold`), one `clothing.rain_jacket` (`coldRain`), `clothing.windbreaker` suppressed and covered by the rain jacket (per the existing `rainShellCoversWind` pattern), no `activities.ski_gloves`. Record, review the semantic diff, confirm the only fixtures that moved are the ones Step 5 predicted and this one.

- [ ] **Step 7: Commit the decision.**

```bash
git add shared/rules/weather.json ios/PackWiseTests/CoverageTests.swift \
  ios/PackWiseTests/WeatherNeedHardeningTests.swift \
  shared/fixtures/golden/golden-fixtures.json ios/PackWiseTests/Goldens
git commit -m "feat: generate ordinary gloves for sustained cold without snow"
```

---

### Task 4: Pin the weather composition matrix — wind+mild, heat+strong-sun, hot-day/cool-night

**Files:**
- Test: `ios/PackWiseTests/WeatherNeedHardeningTests.swift`

**Interfaces:**
- Consumes: `WeatherSignalExtractor.extract`, `CoverageResolver.needs`/`resolve` (unchanged this task — this task is regression-pinning, not behavior change).
- Produces: executable evidence for three of the eight named exit scenarios that had no isolated test before Phase 6, plus a citation-only regression for the two the design doc found already green.

- [ ] **Step 1: Write the three matrix tests.** These use `CoverageTests`'s `weather(days:start:highF:lowF:rain:uv:wind:snow:swingDay:)`-style synthetic helper, added locally to `WeatherNeedHardeningTests.swift` (same shape, new file — Phase 6's own focused suite owns its own helper rather than reaching into `CoverageTests`'s private one).

```swift
private func syntheticWeather(
    days: Int, start: Date, highF: Double, lowF: Double,
    rain: Double = 0, uv: Double = 4, wind: Double = 8, snow: Bool = false
) -> TripWeatherContext {
    let fixture = WeatherFixture(id: "synthetic", summary: "Synthetic", days: [WeatherFixtureDay(
        offset: 0, symbol: "cloud", highF: highF, lowF: lowF, rainProbability: rain,
        uvIndex: uv, windMph: wind, snowExpected: snow, summary: "Synthetic"
    )])
    let end = Calendar.current.date(byAdding: .day, value: days - 1, to: start)!
    return MockWeatherService.context(from: fixture, start: start, end: end, fixtureID: "synthetic")
}

/// Wind alone, mild temperatures: the windbreaker is a real, surviving
/// candidate, not only ever visible as a loser suppressed by a rain shell
/// (`rainShellCoversWind` only proves the suppression half).
@Test func windAloneAtMildTemperaturesKeepsTheWindbreaker() throws {
    let dest = try destination("Chicago")
    let start = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 10))!
    let windyMild = syntheticWeather(days: 5, start: start, highF: 68, lowF: 54, rain: 0.1, wind: 26)
    let generation = try makeEngine().generateDetailed(context: context(destination: dest, days: 5, weather: windyMild))
    let ids = Set(generation.items.compactMap(\.canonicalItemID))
    #expect(ids.contains("clothing.windbreaker"))
    #expect(!ids.contains("clothing.rain_jacket"))
    #expect(!ids.contains("clothing.gloves"))
    #expect(generation.coverageSuppressions.first { $0.canonicalItemID == "clothing.windbreaker" } == nil)
}

/// Heat and strong sun both nominate sunscreen independently
/// (`hotOutdoorExposure` and `highUVExposure` each carry their own
/// `signalAdds` row) — they must merge into one row, not duplicate.
@Test func heatAndStrongSunMergeIntoOneSunscreenRow() throws {
    let dest = try destination("Phoenix")
    let start = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 1))!
    let hotAndSunny = syntheticWeather(days: 5, start: start, highF: 95, lowF: 75, uv: 10)
    let items = try makeEngine().generate(context: context(destination: dest, days: 5, activities: ["walking"], weather: hotAndSunny))
    #expect(items.filter { $0.canonicalItemID == "toiletries.sunscreen" }.count == 1)
    #expect(items.contains { $0.canonicalItemID == "essentials.sunglasses" })
    #expect(items.contains { $0.canonicalItemID == "clothing.hat_sun" })
}

/// A desert day/night swing: hot by day, cool by night, a large swing
/// between them — three signals firing together are not contradictory.
@Test func hotDayCoolNightKeepsBothDayAndEveningLayers() throws {
    let dest = try destination("Phoenix")
    let start = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 15))!
    let desertSwing = syntheticWeather(days: 5, start: start, highF: 85, lowF: 58, uv: 8)
    let items = try makeEngine().generate(context: context(destination: dest, days: 5, weather: desertSwing))
    let ids = Set(items.compactMap(\.canonicalItemID))
    #expect(ids.contains("clothing.shorts"))       // hotOutdoorExposure
    #expect(ids.contains("clothing.light_sweater")) // coldEvenings / largeTemperatureSwing, deduplicated to one layer
    let layers = items.filter { ["clothing.light_sweater", "clothing.light_jacket"].contains($0.canonicalItemID ?? "") }
    #expect(layers.count == 1)
}
```

- [ ] **Step 2: Run and verify RED, then GREEN with no production change.** Run:

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/WeatherNeedHardeningTests
```

Expected: all three pass on first run with **no production code change** — the composition machinery (`CoverageResolver.needs`, the `collected[id]` merge in `addWeather`) already handles these correctly; Task 4 converts an unproven assumption into a guarded contract, exactly as Phase 5's Task 4 did for `tripType.other`. If any fails, that is a real defect — fix the minimal cause in `PackingEngine.swift` or `CoverageResolver.swift`, not the test.

- [ ] **Step 3: Cite the two already-green scenarios in the test file's header comment**, naming them so a future reader does not go looking for tests that were deliberately not duplicated:

```swift
// Phase 6 exit-scenario evidence, complete list:
//   hot+rain          → CoverageTests.hotRainDropsShellKeepsUmbrella (existing, unchanged)
//   cold+rain         → CoverageTests.coldRainKeepsShell (existing, unchanged)
//   wind+mild         → windAloneAtMildTemperaturesKeepsTheWindbreaker (this file)
//   heat+strong-sun   → heatAndStrongSunMergeIntoOneSunscreenRow (this file)
//   hot-day/cool-night→ hotDayCoolNightKeepsBothDayAndEveningLayers (this file)
//   snow+business     → golden fixture 35 (Task 5)
//   rain+hiking       → golden fixture 36 (Task 5)
//   rain+couple       → golden fixture 11-couple-5d-rain (existing, unchanged, re-pinned in Task 6)
```

- [ ] **Step 4: Commit the matrix.**

```bash
git add ios/PackWiseTests/WeatherNeedHardeningTests.swift
git commit -m "test: pin the wind, heat-and-sun, and day-night-swing weather composition matrix"
```

---

### Task 5: New composite golden fixtures — snow+business and rain+hiking

**Files:**
- Modify: `shared/fixtures/golden/golden-fixtures.json`
- Test: `ios/PackWiseTests/WeatherNeedHardeningTests.swift`

**Interfaces:**
- Consumes: `ActivityContracts.needs(for:)` (Phase 5, unchanged), `trip-types.json`'s `business` row (unchanged), `CoverageResolver.itemCapabilities` (unchanged).
- Produces: reviewed golden evidence for the two exit scenarios that combine a weather signal with trip type or activity contracts, not threshold arithmetic alone.

- [ ] **Step 1: Write the failing unit-level previews before recording the goldens.** Fast, specific, and reviewable before the full engine/golden cycle.

```swift
/// Snow and business do not conflict: dress shoes claim `.formal`, boots
/// claim `.coldFootwear` — distinct capabilities, so both survive alongside
/// the walking-shoes base essential, which neither claims.
@Test func snowAndBusinessKeepDistinctFootwearForEachNeed() throws {
    let dest = try destination("Denver")
    let start = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 12))!
    let snowy = weather(days: 5, start: start, highF: 36, lowF: 18, rain: 0.15, wind: 12, snow: true)
    let generation = try makeEngine().generateDetailed(
        context: context(destination: dest, type: .business, activities: ["work"], bag: .checked, weather: snowy)
    )
    let ids = Set(generation.items.compactMap(\.canonicalItemID))
    #expect(ids.contains("footwear.dress_shoes"))
    #expect(ids.contains("footwear.boots"))
    #expect(ids.contains("footwear.walking_shoes"))
    #expect(ids.contains("clothing.gloves"))       // sustainedCold, Task 3
    #expect(ids.contains("clothing.winter_coat"))  // snowExposure, existing
    #expect(ids.contains("clothing.blazer"))       // business, existing
}

/// Hiking's four needs and the rain shell coexist; the only suppression is
/// the pre-existing hiking-covers-walking one, and there is exactly one
/// rain item.
@Test func rainAndHikingComposeWithoutDuplication() throws {
    let dest = try destination("Seattle")
    let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5))!
    let wetHike = try weather(fixture: "SeattleWetCity", start: start, days: 5)
    let generation = try makeEngine().generateDetailed(
        context: context(destination: dest, days: 5, type: .outdoor, activities: ["hiking"], weather: wetHike)
    )
    let ids = Set(generation.items.compactMap(\.canonicalItemID))
    #expect(ids.contains("footwear.hiking_shoes"))
    #expect(ids.contains("activities.daypack"))
    #expect(ids.contains("hydration.water_bottle"))
    #expect(ids.contains("health.blister_pads"))
    #expect(ids.contains("clothing.rain_jacket"))
    #expect(generation.items.filter { $0.canonicalItemID == "clothing.rain_jacket" }.count == 1)
    let suppression = try #require(generation.coverageSuppressions.first { $0.canonicalItemID == "footwear.walking_shoes" })
    #expect(suppression.covered == [CapabilityCoverage(capability: .everydayWalking, coveringItemID: "footwear.hiking_shoes")])
}
```

- [ ] **Step 2: Run and verify RED or honest GREEN.** These may pass immediately — the design doc's read of `itemCapabilities` found no structural conflict on paper. Run them and record the actual result rather than assuming; if either fails, the minimal fix belongs in `CoverageResolver.swift`, not a fixture tweak.

- [ ] **Step 3: Add the two golden fixtures.**

| ID | Scenario | Measures |
| --- | --- | --- |
| 35 | Denver · 5d · business · work · checked · `DenverColdOutdoor` (snow) | snow+business: distinct footwear per need, gloves (Task 3), no conflict with business formalwear |
| 36 | Seattle · 5d · outdoor · hiking · `SeattleWetCity` (rain) | rain+hiking: activity-contract needs and rain shell compose, one suppression, one rain item |

```json
{
  "id": "35-denver-5d-business-snow",
  "proves": "Snow and business trip-type needs compose without footwear conflict; cold-without-snow gloves, Task 3, also apply here",
  "destination": "Denver",
  "weatherFixture": "DenverColdOutdoor",
  "startDate": "2026-01-12",
  "days": 5,
  "tripType": "business",
  "activities": ["work"],
  "bag": "checked",
  "style": "prepared",
  "laundry": "none",
  "homeCountryCode": "US"
},
{
  "id": "36-seattle-5d-rain-hiking",
  "proves": "Hiking's activity-contract needs and the weather rain shell compose without duplication; footwear suppression is unchanged from Phase 4/5's evidence",
  "destination": "Seattle",
  "weatherFixture": "SeattleWetCity",
  "startDate": "2026-10-05",
  "days": 5,
  "tripType": "outdoor",
  "activities": ["hiking"],
  "bag": "checked",
  "style": "balanced",
  "laundry": "none",
  "homeCountryCode": "US"
}
```

Run `python3 scripts/validate_shared.py`, record with `PACKWISE_RECORD_GOLDENS=1`, run the semantic report against `e958c07`. Expected: exactly two new fixtures (35, 36), zero changes to 1–34.

- [ ] **Step 4: Commit.**

```bash
git add shared/fixtures/golden/golden-fixtures.json ios/PackWiseTests/Goldens \
  ios/PackWiseTests/WeatherNeedHardeningTests.swift
git commit -m "test: add snow-and-business and rain-and-hiking composite golden fixtures"
```

---

### Task 6: Cached/failed weather generation-equivalence and the rain+couple pin

**Files:**
- Modify: `ios/PackWiseTests/WeatherChangeTests.swift`

**Interfaces:**
- Consumes: `TripWeatherContext.markingAsCache()`, `TripWeatherResolver.fallback`, `PackingEngine.generate` (all unchanged).
- Produces: proof that `source == .cache` does not change what a trip generates, and that a failed fetch with no usable cache degrades to the existing no-weather behavior — closing the "cached" and "failed" halves of the normalized-weather matrix the design doc names, using the existing WeatherChangeTests suite rather than a new one, since these are lifecycle/resolver-boundary questions that suite already owns.

- [ ] **Step 1: Write the failing cache-equivalence test.** `addWeather`/`CoverageContext` gate on `weatherQuality`/`isPreciseForecast`, neither of which reads `source` — this should already hold, and the test either confirms that honestly or finds a real leak.

```swift
/// A cached forecast is structurally the same data as a live one, just
/// tagged stale (`WeatherDomain.swift:163`) — generation must not depend on
/// `source`, only on the daily data and coverage flags it already reads.
@Test func cachedForecastGeneratesIdenticallyToTheSameDataFresh() throws {
    let fresh = forecast(start: date(2026, 10, 5), days: 5, high: 57, low: 48, rain: 0.6)
    let cached = fresh.markingAsCache()
    #expect(cached.source == .cache)

    let freshItems = try engine().generate(context: try context(weather: fresh, days: 5))
    let cachedItems = try engine().generate(context: try context(weather: cached, days: 5))
    #expect(Set(freshItems.compactMap(\.canonicalItemID)) == Set(cachedItems.compactMap(\.canonicalItemID)))
}

/// A failed fetch with no usable cache falls back to `.unavailable` in
/// `TripWeatherResolver`, which the engine already treats as no weather at
/// all (`noWeatherStillGenerates`). This test exercises that path through
/// the resolver directly rather than re-deriving the assumption.
@Test func failedFetchWithNoCacheDegradesToNoWeatherGeneration() async throws {
    let failing = MockWeatherService(fixtures: [:], forceUnavailable: true)
    let resolved = await TripWeatherResolver.resolve(
        using: failing, destination: try destination("Seattle"),
        start: date(2026, 10, 5), end: date(2026, 10, 9), cached: nil
    )
    #expect(resolved.state == .unavailable)
    #expect(resolved.engineWeather == nil)
    let items = try engine().generate(context: try context(weather: resolved.engineWeather, days: 5))
    #expect(!items.contains { $0.canonicalItemID == "clothing.rain_jacket" })
    #expect(!items.isEmpty)
}
```

- [ ] **Step 2: Run and verify RED or honest GREEN.** Both are expected to pass immediately — the design doc's read of `addWeather`/`CoverageContext` found no `source` dependency. Record the actual result. If `cachedForecastGeneratesIdenticallyToTheSameDataFresh` fails, that is a real, previously-unnoticed defect and must be fixed in the minimal place, not routed forward again.

- [ ] **Step 3: Re-verify the rain+couple citation.** Run the golden semantic report scoped to fixture 11 only (or the full report, reading only that row) against `e958c07`: `11-couple-5d-rain` must show zero changes across every Phase 6 task. This is a citation, not new work — record the confirmation in the exit report rather than adding a redundant test.

- [ ] **Step 4: Commit.**

```bash
git add ios/PackWiseTests/WeatherChangeTests.swift
git commit -m "test: pin cached and failed weather generation equivalence"
```

---

### Task 7: Close Phase 6

**Files:**
- Create: `docs/engine-audits/2026-09-04-phase-6-weather-need-hardening.md`
- Modify: `docs/plans/2026-09-02-product-hardening-program.md`

**Interfaces:**
- Consumes: Tasks 1–6.
- Produces: full audit evidence, a per-scenario table for all eight named exit scenarios, and the Phase 6 closure section.

- [ ] **Step 1: Run the full gate set.**

```bash
scripts/run_engine_audit.sh
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
python3 scripts/validate_shared.py
npm --prefix api run preflight
PYTHONDONTWRITEBYTECODE=1 python3 scripts/report_engine_goldens.py --baseline-ref e958c07 --candidate ios/PackWiseTests/Goldens --format markdown
```

- [ ] **Step 2: Write the exit report.** Cover, at minimum: the eight-scenario evidence table (existing-cited vs. new, matching Task 4's header comment plus fixtures 33–36); the partial-forecast blend's exact before/after on fixture 33; the cold-without-snow decision and the fixtures it moved (Task 3, Step 5's list, verified not assumed); the full reviewed golden diff (fixtures 33–36 new, zero unexpected changes to 1–32, and any glove-row additions Task 3 predicted on `sustainedCold`-without-`snowExposure` fixtures found among the existing 32); mechanical scope confirmation (`WeatherSignal` still 11 cases, `PackingCapability` still 12, `ActivityNeed` still 8, no threshold in `weather.json` moved, `WeatherChangeReconciler`/`TripWeatherRefresh`/`TripWeatherResolver`/`WeatherRefreshPolicy`/`MockWeatherService` byte-unchanged); routed findings (Phase 11's reconciler integration question, the possible `CoverageContext` double-construction cleanup, F-1, F-5).

- [ ] **Step 3: Close Phase 6 in the program tracker.** Update `docs/plans/2026-09-02-product-hardening-program.md`: change the header status line, add a "Phase 6 closure" section in the style of the Phase 1–5 closure sections, update the "Program order" table's Phase 6 exit-evidence cell, and add the routed findings this phase produces to the next phase's "has not started" note — matching exactly how the Phase 5 closure section named what Phase 6 inherited.

- [ ] **Step 4: Commit the closure.**

```bash
git add docs/engine-audits/2026-09-04-phase-6-weather-need-hardening.md \
  docs/plans/2026-09-02-product-hardening-program.md
git commit -m "docs: close product hardening phase 6 weather need hardening"
```

---

## Self-Review

- Spec coverage: Task 1 builds the shared routing seam without a behavior change (zero-diff gated). Task 2 is the partial-forecast/seasonal-remainder blend the master roadmap names directly. Task 3 is the cold-without-snow glove decision Phase 4 first noticed and Phase 5's closure routed here explicitly — decided, not routed a third time. Task 4 pins the three composition scenarios that had no isolated test and cites the two the design doc found already green. Task 5 covers the two scenarios that needed a full golden fixture rather than a threshold-only unit test. Task 6 closes the cached/failed half of the matrix and re-confirms rain+couple. Task 7 is one reproducible exit command set and a separate evidence commit.
- Every one of the eight named exit scenarios (hot+rain, cold+rain, wind+mild, heat+strong-sun, hot-day/cool-night, snow+business, rain+hiking, rain+couple) maps to a named task and a named test or fixture, not prose: Task 4 (wind+mild, heat+strong-sun, hot-day/cool-night, citing hot+rain/cold+rain), Task 5 (snow+business, rain+hiking), Task 6 (rain+couple). Precise, partial, seasonal, cached, and failed forecast states each map to a task too: precise/seasonal (Task 1, characterized), partial (Task 2), cached/failed (Task 6).
- Architecture boundary: `WeatherQuality` is Phase 2's existing classification, read by no decision logic until this phase — Task 1 is the natural-extension check the master roadmap asked for, not a new mechanism. `addSeasonal`'s existing `collected[id] == nil` guard is the only safety net Task 2 relies on; it is not re-implemented or duplicated. Task 3 reuses `CoverageResolver`'s existing `.coldHands` capability, priority ordering, and item-capability table with a one-line JSON change — no new capability, no ID-pair table.
- Vocabulary counts pinned and unmoved: `WeatherSignal` (11), `PackingCapability` (12), `ActivityNeed` (8, Phase 5's). No threshold in `shared/rules/weather.json`'s `thresholds` block changes.
- Infrastructure boundary: `WeatherChangeReconciler`, `TripWeatherRefresh`, `TripWeatherResolver`, `WeatherRefreshPolicy`, and `MockWeatherService` are read (Task 6) but never modified. Phase 11 owns wiring V2 needs/coverage through the reconciler as its own step; Phase 6 changes only `generateDetailed`'s output, which the reconciler already consumes.
- Evidence honesty: the design doc and this plan separately name nine existing green tests and two golden fixtures as cited baseline rather than re-implementing them, and flag three test steps (Task 4 Step 2, Task 5 Step 2, Task 6 Step 2) as *expected* to pass on first run with no production change — following Phase 5's precedent that a test passing immediately is still the right test, and that the actual result must be recorded, not assumed, before moving on.
- Design-doc decision: written, because Phase 6 carries three genuine semantic decisions with real alternatives (partial-forecast blend timing and safety, the `sustainedCold` vs. `coldEvenings` gloves gate with a documented rejected alternative, and which composition scenarios need a full golden fixture versus a threshold-only unit test) — the same bar Phase 4 and 5 used, not a smaller change that could skip straight to a plan.
- Type/name consistency: Task 1 introduces the `addWeather(context:snapshot:into:)` signature and the `weatherQuality` switch in `CoverageContext.init`; Task 2 extends both without renaming; Tasks 3–6 consume the exact names Task 1–2 establish and change no signature further.
- Placeholder scan: complete; no unresolved markers. Phase 7 (central constraints, F-5), Phase 8 (trace productization), and Phase 11 (reconciler V2 integration) are routed, not started inside Phase 6.
