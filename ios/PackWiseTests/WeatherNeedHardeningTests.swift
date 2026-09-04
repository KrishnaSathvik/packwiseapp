import Foundation
import Testing
@testable import PackWise

// Phase 6 exit-scenario evidence, complete list:
//   hot+rain          → CoverageTests.hotRainDropsShellKeepsUmbrella (existing, unchanged)
//   cold+rain         → CoverageTests.coldRainKeepsShell (existing, unchanged)
//   wind+mild         → windAloneAtMildTemperaturesKeepsTheWindbreaker (this file)
//   heat+strong-sun   → heatAndStrongSunMergeIntoOneSunscreenRow (this file)
//   hot-day/cool-night→ hotDayCoolNightKeepsBothDayAndEveningLayers (this file)
//   snow+business     → golden fixture 35 (Task 5)
//   rain+hiking       → golden fixture 36 (Task 5)
//   rain+couple       → golden fixture 11-couple-5d-rain (existing, unchanged, re-pinned in Task 6)

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

    /// Builds a `TripWeatherContext` from a named fixture's own real days
    /// (no tiling beyond what the fixture actually has) via
    /// `WeatherForecastNormalizer.context`, so a trip longer than the
    /// fixture's day count is genuinely partial — `coveredCount` is the
    /// fixture's real day count, not an invented, tiled-out full trip.
    ///
    /// Deviation from the plan's literal snippet, recorded in the Phase 6
    /// exit report: `MockWeatherService.context(from:start:end:fixtureID:)`
    /// tiles a fixture's days cyclically to fill however many days are
    /// requested and always sets `forecastAvailableForWholeTrip: true`, so
    /// it can never itself produce a `.partial` `WeatherQuality` from a
    /// short named fixture — using it as the plan's snippet does would
    /// invent daily precision for the uncovered days, which is exactly what
    /// this phase's design forbids. `WeatherForecastNormalizer.context` is
    /// the function that already computes whole-vs-partial coverage
    /// correctly (see `WeatherChangeTests.partialForecastDoesNotCoverA30DayTrip`)
    /// and is reused here directly instead.
    private func weather(fixture name: String, start: Date, days: Int) throws -> TripWeatherContext {
        let fixture = try #require(try SharedLibrary.weatherFixtures()[name])
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: days - 1, to: start)!
        let rawDays: [DailyForecast] = fixture.days.enumerated().map { index, template in
            DailyForecast(
                date: calendar.date(byAdding: .day, value: index, to: calendar.startOfDay(for: start)) ?? start,
                symbol: template.symbol,
                highF: template.highF,
                lowF: template.lowF,
                rainProbability: template.rainProbability,
                uvIndex: template.uvIndex,
                windMph: template.windMph,
                snowExpected: template.snowExpected,
                summary: template.summary
            )
        }
        return WeatherForecastNormalizer.context(
            days: rawDays,
            tripStart: start,
            tripEnd: end,
            fetchedAt: .now,
            providerFetchedAt: .now,
            providerExpiresAt: calendar.date(byAdding: .hour, value: 1, to: .now),
            source: .fixture,
            fixtureID: fixture.id,
            calendar: calendar
        )
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

    /// Deviation from the plan's literal snippet, recorded in the Phase 6
    /// exit report: the plan asserted `clothing.light_jacket` survives, but
    /// on the actual pre-Phase-6 baseline `addSeasonal` adds both
    /// `clothing.light_sweater` (from `coldEvenings`'s `signalAdds` row,
    /// prepended) and `clothing.light_jacket` for a winter/high-latitude
    /// trip; both map to `.warmthLight` in `CoverageResolver.itemCapabilities`,
    /// `clothing.light_sweater` sits earlier in `CoverageResolver.priority`,
    /// so it claims `.warmthLight` first and `clothing.light_jacket` is
    /// correctly suppressed as redundant — pre-existing coverage-dedup
    /// behavior, not something Task 1's routing refactor changes. The
    /// verified baseline observable is `clothing.light_sweater`.
    @Test func seasonalOnlyStillRoutesThroughAddSeasonalOnly() throws {
        let dest = try destination("Reykjavik")  // 64.1°N — a January start is winter
        let winter = Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 10))!
        let items = try makeEngine().generate(context: context(destination: dest, days: 5, weather: nil, start: winter))
        #expect(items.contains { $0.canonicalItemID == "clothing.light_sweater" })
        #expect(!items.contains { $0.canonicalItemID == "clothing.light_jacket" })  // suppressed as redundant .warmthLight coverage
        #expect(items.allSatisfy { $0.reasonCode != "weather.rain_days" })
    }

    /// A partial forecast keeps its exact covered-day signals and, for the
    /// trip's genuinely unforecast remainder, gets the same conservative
    /// seasonal check a fully-unforecast trip already gets — never zero,
    /// never invented day-level precision for days nobody forecast.
    ///
    /// Deviation from the plan's literal snippet, recorded in the Phase 6
    /// exit report: the plan's default trip type (`.cityBreak`, this test
    /// file's `context()` default) already adds `essentials.sunglasses` via
    /// `trip-types.json`'s own generic add list, so by the time `addSeasonal`
    /// runs the item is already `collected` with a `trip_type.generic`
    /// reason — `addSeasonal`'s `collected[id] == nil` guard correctly
    /// leaves it alone (working exactly as designed: never overwrite),
    /// which means the item's presence no longer demonstrates the
    /// seasonal-remainder mechanism at all. `.vacation` (also golden fixture
    /// 33's trip type) adds neither `essentials.sunglasses` nor
    /// `toiletries.sunscreen` generically, so both items' presence and
    /// reason code genuinely exercise the new seasonal-remainder path.
    @Test func partialForecastBlendsCoveredSignalsWithSeasonalRemainder() throws {
        let dest = try destination("Chicago")
        let start = Calendar.current.date(from: DateComponents(year: 2027, month: 7, day: 5))!
        let rainy = try weather(fixture: "ChicagoRainyFall", start: start, days: 10)  // only 5 days of data exist
        // The trip's own start must land in the same July window as the
        // weather data above — addSeasonal's summer check reads
        // `context.startDate`, not the weather object's dates.
        let snapshot = TripContextCompiler.compile(context(destination: dest, days: 10, type: .vacation, weather: rainy, start: start), rules: try rules())
        guard case .partial(let covered, let total) = snapshot.weatherQuality else {
            Issue.record("expected partial coverage, got \(snapshot.weatherQuality)")
            return
        }
        #expect(covered == 5)
        #expect(total == 10)

        let generation = try makeEngine().generateDetailed(context: context(destination: dest, days: 10, type: .vacation, weather: rainy, start: start))
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
        let generation = try makeEngine().generateDetailed(context: context(destination: dest, days: 10, type: .vacation, weather: rainy, start: start))
        let rainJacket = try #require(generation.items.first { $0.canonicalItemID == "clothing.rain_jacket" })
        #expect(rainJacket.reasonCode.hasPrefix("weather."))
        #expect(rainJacket.reasonCode != "weather.seasonal_layer")
    }

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

    /// Snow and business do not conflict: dress shoes claim `.formal`, boots
    /// claim `.coldFootwear` — distinct capabilities, so both survive alongside
    /// the walking-shoes base essential, which neither claims.
    @Test func snowAndBusinessKeepDistinctFootwearForEachNeed() throws {
        let dest = try destination("Denver")
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 12))!
        let snowy = syntheticWeather(days: 5, start: start, highF: 36, lowF: 18, rain: 0.15, wind: 12, snow: true)
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
}
