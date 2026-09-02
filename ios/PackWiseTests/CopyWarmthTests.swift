import Foundation
import Testing
@testable import PackWise

/// Slice 10 — base-essential copy warmth.
///
/// The audit counted "A core item for almost every trip" on ~60-70% of a
/// typical list. Base essentials now render one warm line per category
/// (specific tier of the ladder, so the template test still guards it),
/// short trips stop packing organizers that claim to be core to almost
/// every trip, and the shared-umbrella copy pluralizes both placeholders
/// and stops calling a couple a family.
struct CopyWarmthTests {
    private func makeEngine() throws -> PackingEngine {
        PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
    }

    private func destination(_ name: String) throws -> Destination {
        try SharedLibrary.testDestinations().first { $0.city == name }!
    }

    private func weather(days: Int, start: Date, highF: Double, lowF: Double, rain: Double) -> TripWeatherContext {
        let fixture = WeatherFixture(
            id: "synthetic",
            summary: "Synthetic",
            days: [WeatherFixtureDay(
                offset: 0, symbol: "cloud.rain", highF: highF, lowF: lowF,
                rainProbability: rain, uvIndex: 2, windMph: 8, snowExpected: false, summary: "Rain"
            )]
        )
        let end = Calendar.current.date(byAdding: .day, value: days - 1, to: start)!
        return MockWeatherService.context(from: fixture, start: start, end: end, fixtureID: "synthetic")
    }

    private func context(
        destination: Destination,
        days: Int = 6,
        weather: TripWeatherContext? = nil,
        party: TripParty? = nil
    ) -> TripContext {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5))!
        let end = Calendar.current.date(byAdding: .day, value: days - 1, to: start)!
        let math = TripDateMath.daysAndNights(from: start, to: end)
        var prefs = TravelerPreferences.deviceDefaults()
        prefs.homeCountryCode = "US"
        prefs.homeCountrySource = .userConfirmed
        var ctx = TripContext(
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
            travelerCount: party?.travelers.count ?? 1,
            userNotes: "",
            contextChips: [],
            weather: weather,
            preferences: prefs
        )
        if let party { ctx.party = party }
        return ctx
    }

    @Test func baseEssentialsSpeakPerCategory() throws {
        let items = try makeEngine().generate(context: context(destination: try destination("Chicago")))
        #expect(!items.contains { $0.reason == "A core item for almost every trip." })
        let byID = Dictionary(uniqueKeysWithValues: items.compactMap { i in i.canonicalItemID.map { ($0, i) } })
        #expect(byID["documents.id"]?.reason == "Easy to forget, hard to replace.")
        #expect(byID["documents.id"]?.reasonCode == "base.essential.documents")
        #expect(byID["toiletries.toothbrush"]?.reason == "Small to pack, annoying to replace mid-trip.")
        #expect(byID["essentials.wallet"]?.reason == "The pocket check before you head out.")
    }

    /// Packing cubes and a laundry bag claimed to be core to almost every
    /// trip; a one-day trip proves they aren't. The toiletry bag stays —
    /// one night still brushes its teeth.
    @Test func oneDayTripSkipsBagOrganizers() throws {
        let dayTrip = try makeEngine().generate(context: context(destination: try destination("Chicago"), days: 1))
        let dayIDs = Set(dayTrip.compactMap(\.canonicalItemID))
        #expect(!dayIDs.contains("travel_comfort.compression_packing"))
        #expect(!dayIDs.contains("travel_comfort.laundry_bag"))
        #expect(dayIDs.contains("travel_comfort.toiletry_bag"))

        let twoDays = try makeEngine().generate(context: context(destination: try destination("Chicago"), days: 2))
        let twoIDs = Set(twoDays.compactMap(\.canonicalItemID))
        #expect(twoIDs.contains("travel_comfort.compression_packing"))
        #expect(twoIDs.contains("travel_comfort.laundry_bag"))
    }

    /// The audit's P2: a 3-of-5-rain-days trip summarized as "Rain is
    /// expected Sunday." The count is the information; the first day is
    /// the anchor.
    @Test func summaryCountsRainDaysInsteadOfNamingOnlyTheFirst() throws {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!)
        let probabilities = [0.6, 0.2, 0.7, 0.1, 0.6]
        let days = probabilities.enumerated().map { index, rain in
            DailyForecast(
                date: calendar.date(byAdding: .day, value: index, to: start)!,
                symbol: "cloud", highF: 58, lowF: 48, rainProbability: rain,
                uvIndex: 2, windMph: 8, snowExpected: false, summary: "d"
            )
        }
        let ctx = WeatherForecastNormalizer.context(
            days: days,
            tripStart: start,
            tripEnd: calendar.date(byAdding: .day, value: 4, to: start)!,
            fetchedAt: start,
            providerFetchedAt: start,
            providerExpiresAt: calendar.date(byAdding: .hour, value: 1, to: start),
            source: .weatherKit,
            calendar: calendar
        )
        #expect(ctx.rainDays == 3)
        #expect(ctx.weatherSummary.contains("Rain is expected on 3 days"))

        // A single rain day keeps the plain weekday form.
        let oneRainDays = [0.6, 0.2, 0.1, 0.1, 0.2].enumerated().map { index, rain in
            DailyForecast(
                date: calendar.date(byAdding: .day, value: index, to: start)!,
                symbol: "cloud", highF: 58, lowF: 48, rainProbability: rain,
                uvIndex: 2, windMph: 8, snowExpected: false, summary: "d"
            )
        }
        let oneRain = WeatherForecastNormalizer.context(
            days: oneRainDays,
            tripStart: start,
            tripEnd: calendar.date(byAdding: .day, value: 4, to: start)!,
            fetchedAt: start,
            providerFetchedAt: start,
            providerExpiresAt: calendar.date(byAdding: .hour, value: 1, to: start),
            source: .weatherKit,
            calendar: calendar
        )
        #expect(oneRain.weatherSummary.contains("Rain is expected Monday"))
        #expect(!oneRain.weatherSummary.contains("1 days"))
    }

    @Test func sharedUmbrellaCopyReadsPlainly() throws {
        let dest = try destination("Seattle")
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5))!

        // One rain day, a couple, one umbrella: singular everywhere, and a
        // couple is not a "family".
        var oneRain = weather(days: 5, start: start, highF: 57, lowF: 48, rain: 0.2)
        // Tile: only make the middle day rainy by rebuilding with a rainy
        // single-day fixture clipped to one day of rain via probability.
        oneRain = weather(days: 1, start: start, highF: 57, lowF: 48, rain: 0.6)
        var days = oneRain.dailyForecast
        let dry = weather(days: 5, start: start, highF: 57, lowF: 48, rain: 0.1).dailyForecast
        days = [days[0]] + dry.dropFirst()
        var mixed = weather(days: 5, start: start, highF: 57, lowF: 48, rain: 0.1)
        mixed.rainDays = 1
        mixed.dailyForecast = days
        let couple = TripParty(travelMode: .couple, travelers: [
            Traveler.primarySelf(),
            Traveler(name: "Maya", role: .partner, ageGroup: .adult)
        ])
        let items = try makeEngine().generate(context: context(destination: dest, days: 5, weather: mixed, party: couple))
        let umbrella = try #require(items.first { $0.canonicalItemID == "essentials.umbrella_compact" })
        #expect(umbrella.quantityReason.contains("1 day."))
        #expect(umbrella.quantityReason.contains("One umbrella"))
        #expect(!umbrella.quantityReason.contains("1 days"))
        #expect(!umbrella.quantityReason.contains("family"))

        // Persistent rain, three travelers, two umbrellas: plural both ways.
        let rainy = weather(days: 5, start: start, highF: 57, lowF: 48, rain: 0.6)
        let family = TripParty(travelMode: .family, travelers: [
            Traveler.primarySelf(),
            Traveler(name: "Maya", role: .partner, ageGroup: .adult),
            Traveler(name: "Sam", role: .child, ageGroup: .child)
        ])
        let familyItems = try makeEngine().generate(context: context(destination: dest, days: 5, weather: rainy, party: family))
        let sharedUmbrella = try #require(familyItems.first { $0.canonicalItemID == "essentials.umbrella_compact" })
        #expect(sharedUmbrella.quantityReason.contains("5 days"))
        #expect(sharedUmbrella.quantityReason.contains("2 umbrellas"))
    }
}
