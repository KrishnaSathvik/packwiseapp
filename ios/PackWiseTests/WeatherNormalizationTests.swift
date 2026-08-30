import Foundation
import Testing
@testable import PackWise

struct WeatherNormalizationTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private var destination: Destination {
        Destination(
            displayName: "Chicago, IL",
            city: "Chicago",
            region: "Illinois",
            country: "United States",
            countryCode: "US",
            latitude: 41.88,
            longitude: -87.63,
            timeZone: "America/Chicago",
            mapKitIdentifier: nil,
            fixtureID: nil
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func day(
        on date: Date,
        high: Double = 72,
        low: Double = 58,
        rain: Double = 0.1,
        uv: Double = 4,
        wind: Double = 8,
        snow: Bool = false
    ) -> DailyForecast {
        DailyForecast(
            date: calendar.startOfDay(for: date),
            symbol: rain >= 0.35 ? "cloud.rain" : "sun.max",
            highF: high,
            lowF: low,
            rainProbability: rain,
            uvIndex: uv,
            windMph: wind,
            snowExpected: snow,
            summary: rain >= 0.35 ? "Rain" : "Sunny"
        )
    }

    @Test func fullTripCoverage() {
        let start = date(2026, 8, 29)
        let end = date(2026, 8, 31)
        let days = [
            day(on: date(2026, 8, 29), rain: 0.7),
            day(on: date(2026, 8, 30)),
            day(on: date(2026, 8, 31))
        ]
        let fetched = date(2026, 8, 29)
        let expires = calendar.date(byAdding: .hour, value: 1, to: fetched)
        let context = WeatherForecastNormalizer.context(
            days: days,
            tripStart: start,
            tripEnd: end,
            fetchedAt: fetched,
            providerFetchedAt: fetched,
            providerExpiresAt: expires,
            source: .weatherKit,
            attribution: .applePlaceholder,
            calendar: calendar
        )
        #expect(context.forecastAvailableForWholeTrip)
        #expect(!context.forecastAvailableForPartialTrip)
        #expect(context.dailyForecast.count == 3)
        #expect(context.rainDays == 1)
        #expect(context.providerFetchedAt == fetched)
        #expect(context.providerExpiresAt == expires)
        #expect(context.coverageStart != nil)
        #expect(context.coverageEnd != nil)
        #expect(context.state(now: fetched) == .forecastComplete)
        #expect(context.showsAppleWeatherAttribution)
        #expect(context.compactHeadline(usesFahrenheit: true).contains("°"))
    }

    @Test func partialTripCoverageClipsToTripDates() {
        let start = date(2026, 8, 29)
        let end = date(2026, 9, 4)
        let days = [
            day(on: date(2026, 8, 28), high: 99),
            day(on: date(2026, 8, 29)),
            day(on: date(2026, 8, 30), rain: 0.8),
            day(on: date(2026, 8, 31))
        ]
        let context = WeatherForecastNormalizer.context(
            days: days,
            tripStart: start,
            tripEnd: end,
            fetchedAt: start,
            providerFetchedAt: start,
            providerExpiresAt: calendar.date(byAdding: .hour, value: 1, to: start),
            source: .weatherKit,
            calendar: calendar
        )
        #expect(!context.forecastAvailableForWholeTrip)
        #expect(context.forecastAvailableForPartialTrip)
        #expect(context.dailyForecast.count == 3)
        #expect(!context.dailyForecast.contains { calendar.component(.day, from: $0.date) == 28 })
        #expect(context.rainDays == 1)
        #expect(context.state(now: start) == .forecastPartial)
        #expect(context.coverageCopy.contains("part of your trip"))
        #expect(context.compactHeadline(usesFahrenheit: true) == context.coverageCopy)
    }

    @Test func farFutureIsSeasonal() {
        let now = date(2026, 8, 29)
        let start = date(2026, 10, 12)
        #expect(WeatherForecastNormalizer.isBeyondDailyHorizon(tripStart: start, now: now, calendar: calendar))
        #expect(!WeatherForecastNormalizer.isBeyondDailyHorizon(tripStart: date(2026, 8, 30), now: now, calendar: calendar))
        let snapshot = TripWeatherContext.seasonal(fetchedAt: now)
        #expect(snapshot.state(now: now) == .seasonalOnly)
        #expect(!snapshot.isPreciseForecast)
        #expect(!snapshot.showsAppleWeatherAttribution)
    }

    @Test func emptyFetchBecomesSeasonal() async {
        let now = date(2026, 8, 29)
        let service = WeatherKitWeatherService(
            client: StubWeatherClient(result: .success(RawWeatherFetch(
                days: [],
                providerFetchedAt: now,
                providerExpiresAt: now,
                alerts: []
            ))),
            now: { now }
        )
        let availability = await service.availability(
            for: destination,
            start: date(2026, 8, 29),
            end: date(2026, 8, 31)
        )
        guard case .seasonal = availability else {
            Issue.record("Expected seasonal for an empty forecast")
            return
        }
    }

    @Test func cachedFallbackWhenServiceFails() async {
        let start = date(2026, 8, 29)
        let cached = WeatherForecastNormalizer.context(
            days: [day(on: start, rain: 0.6), day(on: date(2026, 8, 30)), day(on: date(2026, 8, 31))],
            tripStart: start,
            tripEnd: date(2026, 8, 31),
            fetchedAt: start,
            providerFetchedAt: start,
            providerExpiresAt: calendar.date(byAdding: .hour, value: 1, to: start),
            source: .weatherKit,
            attribution: .applePlaceholder,
            calendar: calendar
        )
        let service = WeatherKitWeatherService(
            client: StubWeatherClient(result: .failure),
            now: { start }
        )
        let resolved = await TripWeatherResolver.resolve(
            using: service,
            destination: destination,
            start: start,
            end: date(2026, 8, 31),
            cached: cached,
            now: start
        )
        #expect(resolved.state == .failedUsingCache)
        #expect(resolved.engineWeather?.rainDays == 1)
        #expect(resolved.snapshot?.source == .cache)
        #expect(resolved.snapshot?.providerExpiresAt != nil)
    }

    @Test func serviceFailureWithoutCacheIsUnavailable() async {
        let start = date(2026, 8, 29)
        let service = WeatherKitWeatherService(
            client: StubWeatherClient(result: .failure),
            now: { start }
        )
        let resolved = await TripWeatherResolver.resolve(
            using: service,
            destination: destination,
            start: start,
            end: date(2026, 8, 31),
            cached: nil,
            now: start
        )
        #expect(resolved.state == .unavailable)
        #expect(resolved.engineWeather == nil)
    }

    @Test func farFutureServiceSkipsFetch() async {
        let now = date(2026, 8, 29)
        let probe = FetchProbe()
        let service = WeatherKitWeatherService(client: probe, now: { now })
        let availability = await service.availability(
            for: destination,
            start: date(2026, 10, 12),
            end: date(2026, 10, 16)
        )
        #expect(probe.fetchCount == 0)
        guard case .seasonal = availability else {
            Issue.record("Expected seasonal for a far-future trip")
            return
        }
    }

    @Test func fixtureWeatherStillFeedsEngine() async throws {
        let destination = try SharedLibrary.testDestinations().first { $0.city == "Chicago" }!
        let weather = try await MockWeatherService.bundled().weather(
            for: destination,
            start: Date.now,
            end: Calendar.current.date(byAdding: .day, value: 4, to: Date.now)!
        )
        guard case .forecast(let context) = weather else {
            Issue.record("Expected fixture forecast")
            return
        }
        #expect(context.source == .fixture)
        #expect(!context.showsAppleWeatherAttribution)
        let engine = PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
        var prefs = TravelerPreferences.deviceDefaults()
        prefs.homeCountryCode = "US"
        prefs.homeCountrySource = .userConfirmed
        let start = Calendar.current.startOfDay(for: Date.now)
        let end = Calendar.current.date(byAdding: .day, value: 4, to: start)!
        let math = TripDateMath.daysAndNights(from: start, to: end)
        let tripContext = TripContext(
            destination: destination,
            startDate: start,
            endDate: end,
            durationDays: math.days,
            durationNights: math.nights,
            tripType: .cityBreak,
            activities: ["sightseeing"],
            datedActivities: [DatedActivity(activityID: "sightseeing", date: nil)],
            bagType: .carryOn,
            packingStyle: .balanced,
            transportation: .unknown,
            laundryAccess: .none,
            travelerCount: 1,
            userNotes: "",
            contextChips: [],
            weather: context,
            preferences: prefs
        )
        let items = engine.generate(context: tripContext)
        #expect(items.contains { $0.canonicalItemID == "clothing.rain_jacket" })
    }

    @Test func snapshotPayloadRoundTripsCacheMetadata() throws {
        let start = date(2026, 8, 29)
        let context = WeatherForecastNormalizer.context(
            days: [day(on: start)],
            tripStart: start,
            tripEnd: start,
            fetchedAt: start,
            providerFetchedAt: start,
            providerExpiresAt: calendar.date(byAdding: .hour, value: 2, to: start),
            source: .weatherKit,
            attribution: .applePlaceholder,
            calendar: calendar
        )
        let data = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(TripWeatherContext.self, from: data)
        #expect(decoded.providerFetchedAt == context.providerFetchedAt)
        #expect(decoded.providerExpiresAt == context.providerExpiresAt)
        #expect(decoded.coverageStart != nil)
        #expect(decoded.source == .weatherKit)
    }

    @Test func generationSucceedsWhenWeatherServiceFails() throws {
        let engine = PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
        let destination = try SharedLibrary.testDestinations().first { $0.city == "Chicago" }!
        var prefs = TravelerPreferences.deviceDefaults()
        prefs.homeCountryCode = "US"
        let start = Calendar.current.startOfDay(for: Date.now)
        let end = Calendar.current.date(byAdding: .day, value: 2, to: start)!
        let math = TripDateMath.daysAndNights(from: start, to: end)
        let context = TripContext(
            destination: destination,
            startDate: start,
            endDate: end,
            durationDays: math.days,
            durationNights: math.nights,
            tripType: .cityBreak,
            activities: ["walking"],
            datedActivities: [DatedActivity(activityID: "walking", date: nil)],
            bagType: .carryOn,
            packingStyle: .balanced,
            transportation: .unknown,
            laundryAccess: .none,
            travelerCount: 1,
            userNotes: "",
            contextChips: [],
            weather: nil,
            preferences: prefs
        )
        let items = engine.generate(context: context)
        #expect(!items.isEmpty)
        #expect(items.contains { $0.canonicalItemID == "essentials.wallet" })
    }

    @Test func persistentRainUsesTripDurationNotCoveredDays() {
        let start = date(2026, 8, 29)
        let end = date(2026, 9, 11)
        let context = WeatherForecastNormalizer.context(
            days: [day(on: start, rain: 0.8), day(on: date(2026, 8, 30), rain: 0.7)],
            tripStart: start,
            tripEnd: end,
            fetchedAt: start,
            providerFetchedAt: start,
            providerExpiresAt: start,
            source: .weatherKit,
            calendar: calendar
        )
        let thresholds = WeatherThresholds(
            rainProbabilityAdd: 0.35,
            coolEveningMaxF: 62,
            coldMaxF: 48,
            hotMinF: 82,
            uvAdd: 6,
            windMphAdd: 22,
            temperatureSwingAdd: 20,
            heavyRainProbability: 0.6
        )
        let conditions = WeatherSignalExtractor.extract(
            weather: context,
            thresholds: thresholds,
            outdoorActivities: false,
            tripDays: 14
        )
        #expect(conditions.signals.contains(.meaningfulRain))
        #expect(!conditions.signals.contains(.persistentRain))
        #expect(conditions.tripDays == 14)
    }
}

private struct StubWeatherClient: WeatherProvidingClient {
    enum Outcome: Sendable {
        case success(RawWeatherFetch)
        case failure
    }

    var result: Outcome

    func fetch(
        latitude: Double,
        longitude: Double,
        start: Date,
        end: Date,
        timeZone: TimeZone
    ) async throws -> RawWeatherFetch {
        switch result {
        case .success(let fetch):
            return fetch
        case .failure:
            throw WeatherServiceError.unavailable
        }
    }

    func attribution() async -> WeatherAttribution { .applePlaceholder }
}

private final class FetchProbe: WeatherProvidingClient, @unchecked Sendable {
    var fetchCount = 0

    func fetch(
        latitude: Double,
        longitude: Double,
        start: Date,
        end: Date,
        timeZone: TimeZone
    ) async throws -> RawWeatherFetch {
        fetchCount += 1
        return RawWeatherFetch(
            days: [
                DailyForecast(
                    date: start,
                    symbol: "sun.max",
                    highF: 72,
                    lowF: 58,
                    rainProbability: 0.1,
                    uvIndex: 4,
                    windMph: 8,
                    snowExpected: false,
                    summary: "Sunny"
                )
            ],
            providerFetchedAt: start,
            providerExpiresAt: start,
            alerts: []
        )
    }

    func attribution() async -> WeatherAttribution { .applePlaceholder }
}
