import Foundation
import Testing
@testable import PackWise

/// Coverage resolver tests — Engine V2 plan, Step 3 (footwear + outerwear).
struct CoverageTests {
    private func makeEngine() throws -> PackingEngine {
        PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
    }

    private func destination(_ name: String) throws -> Destination {
        try SharedLibrary.testDestinations().first { $0.city == name }!
    }

    /// A synthetic forecast: every day identical, span matching the trip.
    private func weather(
        days: Int,
        start: Date,
        highF: Double,
        lowF: Double,
        rain: Double = 0,
        uv: Double = 4,
        wind: Double = 8,
        snow: Bool = false,
        swingDay: Bool = false
    ) -> TripWeatherContext {
        let fixture = WeatherFixture(
            id: "synthetic",
            summary: "Synthetic",
            days: [WeatherFixtureDay(
                offset: 0,
                symbol: "cloud",
                highF: highF,
                lowF: swingDay ? highF - 25 : lowF,
                rainProbability: rain,
                uvIndex: uv,
                windMph: wind,
                snowExpected: snow,
                summary: "Synthetic"
            )]
        )
        let end = Calendar.current.date(byAdding: .day, value: days - 1, to: start)!
        return MockWeatherService.context(from: fixture, start: start, end: end, fixtureID: "synthetic")
    }

    private func context(
        destination: Destination,
        days: Int = 5,
        type: TripType = .cityBreak,
        activities: [String] = ["sightseeing", "walking"],
        bag: BagType = .carryOn,
        style: PackingStyle = .balanced,
        weather: TripWeatherContext? = nil
    ) -> TripContext {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        let end = Calendar.current.date(byAdding: .day, value: days - 1, to: start)!
        let math = TripDateMath.daysAndNights(from: start, to: end)
        var prefs = TravelerPreferences.deviceDefaults()
        prefs.homeCountryCode = "US"
        prefs.homeCountrySource = .userConfirmed
        return TripContext(
            destination: destination,
            startDate: start,
            endDate: end,
            durationDays: math.days,
            durationNights: math.nights,
            tripType: type,
            activities: activities,
            datedActivities: [],
            bagType: bag,
            packingStyle: style,
            transportation: .unknown,
            laundryAccess: .none,
            travelerCount: 1,
            userNotes: "",
            contextChips: [],
            weather: weather,
            preferences: prefs
        )
    }

    /// The budget the vocabulary must not silently drift past: two families
    /// use ten capabilities. Growing this number is a design decision — make
    /// it deliberately, then update this test in the same commit.
    @Test func capabilityVocabularyStaysClosed() {
        #expect(PackingCapability.allCases.count == 10)
        for id in CoverageResolver.priority {
            #expect(CoverageResolver.itemCapabilities[id]?.isEmpty == false, "\(id) is prioritized but has no capabilities")
        }
        #expect(Set(CoverageResolver.priority) == Set(CoverageResolver.itemCapabilities.keys))
    }

    /// Warm rain is umbrella weather: the wearable shell dies, the umbrella
    /// survives, and the suppression names the refuted need.
    @Test func hotRainDropsShellKeepsUmbrella() throws {
        let dest = try destination("Miami")
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 6))!
        let hotRain = weather(days: 5, start: start, highF: 91, lowF: 78, rain: 0.45, uv: 10)
        let generation = try makeEngine().generateDetailed(
            context: context(destination: dest, type: .beach, activities: ["swimming", "beachDays"], bag: .personalItem, style: .light, weather: hotRain)
        )
        let ids = Set(generation.items.compactMap(\.canonicalItemID))
        #expect(!ids.contains("clothing.rain_jacket"))
        #expect(ids.contains("essentials.umbrella_compact"))
        let suppression = generation.coverageSuppressions.first { $0.canonicalItemID == "clothing.rain_jacket" }
        #expect(suppression?.coveredBy.isEmpty == true, "the shell should die for lack of need, not by being covered")
    }

    @Test func coldRainKeepsShell() throws {
        let dest = try destination("Seattle")
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5))!
        let coldRain = weather(days: 5, start: start, highF: 57, lowF: 48, rain: 0.6, uv: 2)
        let items = try makeEngine().generate(context: context(destination: dest, weather: coldRain))
        #expect(items.contains { $0.canonicalItemID == "clothing.rain_jacket" })
    }

    /// A rain shell already blocks wind; a windbreaker on top is duplicate
    /// outerwear and the record must say what covered it.
    @Test func rainShellCoversWind() throws {
        let dest = try destination("Seattle")
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5))!
        let rainAndWind = weather(days: 5, start: start, highF: 55, lowF: 45, rain: 0.6, wind: 26)
        let generation = try makeEngine().generateDetailed(context: context(destination: dest, weather: rainAndWind))
        let ids = Set(generation.items.compactMap(\.canonicalItemID))
        #expect(ids.contains("clothing.rain_jacket"))
        #expect(!ids.contains("clothing.windbreaker"))
        let suppression = generation.coverageSuppressions.first { $0.canonicalItemID == "clothing.windbreaker" }
        #expect(suppression?.coveredBy == ["clothing.rain_jacket"])
    }

    /// A large temperature swing suggests a warm layer, not two of them.
    @Test func temperatureSwingKeepsOneLightLayer() throws {
        let dest = try destination("Denver")
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        let swingy = weather(days: 5, start: start, highF: 85, lowF: 60, swingDay: true)
        let items = try makeEngine().generate(context: context(destination: dest, weather: swingy))
        let layers = items.filter { ["clothing.light_sweater", "clothing.light_jacket"].contains($0.canonicalItemID ?? "") }
        #expect(layers.count == 1, "expected one light layer, got \(layers.compactMap(\.canonicalItemID))")
    }

    /// A winter coat is not a substitute for the layer underneath it: snow
    /// trips keep the coat, the sweater, and the boots.
    @Test func winterLayeringSurvivesCoverage() throws {
        let dest = try destination("Denver")
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 12))!
        let snowy = weather(days: 5, start: start, highF: 30, lowF: 14, rain: 0.1, wind: 18, snow: true)
        let ids = Set(try makeEngine().generate(
            context: context(destination: dest, type: .outdoor, activities: ["sightseeing"], bag: .checked, weather: snowy)
        ).compactMap(\.canonicalItemID))
        #expect(ids.contains("clothing.winter_coat"))
        #expect(ids.contains("clothing.light_sweater"))
        #expect(ids.contains("footwear.boots"))
    }

    /// Running and hiking each keep their own shoe; the walking pair is the
    /// one that goes, and the suppression names its coverer.
    @Test func runningAndHikingKeepBothSuppressWalking() throws {
        let generation = try makeEngine().generateDetailed(
            context: context(destination: try destination("Chicago"), type: .outdoor, activities: ["running", "hiking", "sightseeing"])
        )
        let ids = Set(generation.items.compactMap(\.canonicalItemID))
        #expect(ids.contains("footwear.running_shoes"))
        #expect(ids.contains("footwear.hiking_shoes"))
        #expect(!ids.contains("footwear.walking_shoes"))
        let suppression = generation.coverageSuppressions.first { $0.canonicalItemID == "footwear.walking_shoes" }
        #expect(suppression?.coveredBy == ["footwear.running_shoes"])
        #expect(suppression?.capabilities == [PackingCapability.everydayWalking.rawValue])
    }

    /// A user-added item is never suppressed, but it claims coverage: the
    /// suggested walking shoes become redundant next to the user's runners.
    @Test func userAddedItemClaimsCoverageWithoutBeingSuppressed() throws {
        let userRunners = PackingItemDraft(
            canonicalItemID: "footwear.running_shoes",
            displayName: "Running shoes",
            category: .footwear,
            quantity: 1,
            importance: .normal,
            sourceSignals: [.userPreference],
            reason: "Added by you",
            isUserAdded: true
        )
        let generation = try makeEngine().generateDetailed(
            context: context(destination: try destination("Chicago")),
            existing: [userRunners]
        )
        let ids = generation.items.compactMap(\.canonicalItemID)
        #expect(ids.contains("footwear.running_shoes"))
        #expect(!ids.contains("footwear.walking_shoes"))
    }
}
