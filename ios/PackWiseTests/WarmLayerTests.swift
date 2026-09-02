import Foundation
import Testing
@testable import PackWise

/// Slice 9 — the temperature dimension for warm layers.
///
/// The cold-weather human read (fixtures 15/16) found an 8°F week packing
/// six t-shirts and one light sweater: cold added accessories but never
/// scaled warm layers, and the catalog's thermals were reachable only via
/// the skiSnow trip type.
struct WarmLayerTests {
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
        wind: Double = 8,
        snow: Bool = false
    ) -> TripWeatherContext {
        let fixture = WeatherFixture(
            id: "synthetic",
            summary: "Synthetic",
            days: [WeatherFixtureDay(
                offset: 0,
                symbol: "cloud",
                highF: highF,
                lowF: lowF,
                rainProbability: rain,
                uvIndex: 2,
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
        days: Int = 6,
        weather: TripWeatherContext? = nil
    ) -> TripContext {
        let start = Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 18))!
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
            tripType: .cityBreak,
            activities: ["sightseeing", "walking"],
            datedActivities: [],
            bagType: .checked,
            packingStyle: .balanced,
            transportation: .flight,
            laundryAccess: .none,
            travelerCount: 1,
            userNotes: "",
            contextChips: [],
            weather: weather,
            preferences: prefs
        )
    }

    /// A sub-freezing week gets a warm-layer rotation and base layers, not
    /// six t-shirts and one sweater.
    @Test func sustainedFreezingColdPacksAWarmLayerRotation() throws {
        let dest = try destination("Minneapolis")
        let start = Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 18))!
        let deepWinter = weather(days: 6, start: start, highF: 20, lowF: 2, rain: 0.05, snow: true)
        let items = try makeEngine().generate(context: context(destination: dest, weather: deepWinter))
        let byID = Dictionary(uniqueKeysWithValues: items.compactMap { i in i.canonicalItemID.map { ($0, i) } })
        #expect((byID["clothing.light_sweater"]?.quantity ?? 0) >= 2)
        #expect(byID["clothing.hoodie"] != nil)
        #expect((byID["clothing.thermal_top"]?.quantity ?? 0) >= 2)
        #expect(byID["clothing.thermal_bottom"] != nil)
        #expect(byID["clothing.scarf"] != nil)
    }

    /// The rotation keys off sustained cold, not any cool day: a mild wet
    /// fall trip keeps exactly the single light layer it has today.
    @Test func coolFallTripKeepsASingleLightLayer() throws {
        let dest = try destination("Seattle")
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5))!
        let coolRain = weather(days: 5, start: start, highF: 57, lowF: 48, rain: 0.6)
        let items = try makeEngine().generate(context: context(destination: dest, days: 5, weather: coolRain))
        let byID = Dictionary(uniqueKeysWithValues: items.compactMap { i in i.canonicalItemID.map { ($0, i) } })
        #expect(byID["clothing.light_sweater"]?.quantity == 1)
        #expect(byID["clothing.thermal_top"] == nil)
        #expect(byID["clothing.scarf"] == nil)
    }

    /// Precipitation on a sub-freezing day is winter precipitation: the
    /// parka handles it. No umbrella, no rain shell beside the winter coat.
    @Test func freezingDrizzleIsWinterPrecipitationNotRain() throws {
        let dest = try destination("Minneapolis")
        let start = Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 18))!
        let sleet = weather(days: 6, start: start, highF: 24, lowF: 10, rain: 0.55)
        #expect(sleet.rainDays == 0)
        #expect(sleet.snowDays == 6)
        let items = try makeEngine().generate(context: context(destination: dest, weather: sleet))
        let ids = Set(items.compactMap(\.canonicalItemID))
        #expect(!ids.contains("essentials.umbrella_compact"))
        #expect(!ids.contains("clothing.rain_jacket"))
        #expect(ids.contains("clothing.winter_coat"))
    }

    /// Above freezing, cold rain still earns the shell — the temperature
    /// gate must not swallow the behavior coldRainKeepsShell protects.
    @Test func coldRainAboveFreezingStillPacksTheShell() throws {
        let dest = try destination("Seattle")
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5))!
        let coldRain = weather(days: 5, start: start, highF: 45, lowF: 36, rain: 0.6)
        let items = try makeEngine().generate(context: context(destination: dest, days: 5, weather: coldRain))
        let ids = Set(items.compactMap(\.canonicalItemID))
        #expect(ids.contains("clothing.rain_jacket"))
    }

    /// One source for the weather thresholds: the normalizer's defaults are
    /// the shared rules values, so the screen and the engine can never
    /// disagree about which day counts as rainy.
    @Test func normalizerThresholdsComeFromSharedRules() throws {
        let thresholds = try SharedLibrary.rules().weather.thresholds
        #expect(WeatherForecastNormalizer.defaultRainProbability == thresholds.rainProbabilityAdd)
        #expect(WeatherForecastNormalizer.defaultHeavyRainProbability == thresholds.heavyRainProbability)
        #expect(WeatherForecastNormalizer.defaultFreezingMaxF == thresholds.freezingMaxF)
    }
}
