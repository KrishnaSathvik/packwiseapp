import Foundation
import SwiftData
import Testing
@testable import PackWise

/// Focused tests for the Debug diagnostics envelope (`WeatherRequestDiagnostics`)
/// and the request/normalization boundaries it pins down: current-trip precise
/// coverage, partial coverage, future-seasonal skip, cache reuse, provider
/// failure with and without a usable cache, Debug fixture rebasing, and the
/// destination-timezone query bounds themselves.
struct WeatherKitRequestTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func destination() throws -> Destination {
        try SharedLibrary.testDestinations().first { $0.city == "Chicago" }!
    }

    private func engine() throws -> PackingEngine {
        PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
    }

    private func rules() throws -> PackingRulesFile { try SharedLibrary.rules() }

    private func day(on date: Date, high: Double = 72, low: Double = 58, rain: Double = 0.1) -> DailyForecast {
        DailyForecast(
            date: calendar.startOfDay(for: date),
            symbol: "sun.max",
            highF: high,
            lowF: low,
            rainProbability: rain,
            uvIndex: 4,
            windMph: 8,
            snowExpected: false,
            summary: "Sunny"
        )
    }

    @MainActor
    private func makeTrip(
        in model: ModelContext,
        start: Date,
        end: Date,
        days: Int,
        nights: Int,
        status: TripStatus = .planning
    ) throws -> TripRecord {
        let trip = TripRecord(
            destination: try destination(),
            startDate: start,
            endDate: end,
            durationDays: days,
            durationNights: nights,
            tripType: .cityBreak,
            activities: ["sightseeing"],
            bagType: .carryOn,
            packingStyle: .balanced,
            status: status
        )
        model.insert(trip)
        return trip
    }

    private func preciseContext(start: Date, end: Date, expiresAt: Date, fetchedAt: Date) -> TripWeatherContext {
        let span = (0...4).map { calendar.date(byAdding: .day, value: $0, to: start)! }
        let days = span.map { day(on: $0) }
        return WeatherForecastNormalizer.context(
            days: days,
            tripStart: start,
            tripEnd: end,
            fetchedAt: fetchedAt,
            providerFetchedAt: fetchedAt,
            providerExpiresAt: expiresAt,
            source: .weatherKit,
            calendar: calendar
        )
    }

    // MARK: - 1. Current-trip precise coverage

    @Test @MainActor func currentTripPreciseCoverageIsDiagnosedComplete() async throws {
        await WeatherRequestDiagnosticsStore.shared.clear()
        let now = date(2026, 9, 4)
        let start = now
        let end = calendar.date(byAdding: .day, value: 4, to: start)!
        let container = try PackWisePersistence.container(inMemory: true)
        let model = ModelContext(container)
        let trip = try makeTrip(in: model, start: start, end: end, days: 5, nights: 4)
        let repo = TripRepository(context: model)
        let fetchDays = (0..<5).map { day(on: calendar.date(byAdding: .day, value: $0, to: start)!) }
        let client = StubFetchClient.success(fetchDays)
        let service = WeatherKitWeatherService(client: client, now: { now })

        await TripWeatherRefresh.run(
            trip: trip,
            preferences: .deviceDefaults(),
            weatherService: service,
            engine: try engine(),
            rules: try rules(),
            repository: repo,
            now: now
        )

        let diag = try #require(await WeatherRequestDiagnosticsStore.shared.latest())
        #expect(diag.origin == .live)
        #expect(diag.destinationName == trip.destination.displayName)
        #expect(diag.destinationLatitude == trip.destination.latitude)
        #expect(diag.destinationLongitude == trip.destination.longitude)
        #expect(diag.bounds.requestedStart == start)
        #expect(diag.bounds.requestedEnd == end)
        #expect(diag.fetchAttempted)
        #expect(diag.skipReason == nil)
        #expect(diag.provider?.kind == .success)
        #expect(diag.provider?.returnedDayCount == 5)
        #expect(diag.normalization?.isPreciseForecast == true)
        #expect(diag.normalization?.forecastAvailableForWholeTrip == true)
        #expect(diag.normalization?.seasonalUncoveredDates.isEmpty == true)
        #expect(diag.cache?.hit == false)
        #expect(diag.finalState == .forecastComplete)
        #expect(diag.engineReceivedPreciseWeather == true)
        #expect(client.fetchCount == 1)
    }

    // MARK: - 2. Partial coverage

    @Test @MainActor func partialCoverageRecordsUncoveredTripDays() async throws {
        await WeatherRequestDiagnosticsStore.shared.clear()
        let now = date(2026, 9, 4)
        let start = now
        let end = calendar.date(byAdding: .day, value: 4, to: start)!
        let container = try PackWisePersistence.container(inMemory: true)
        let model = ModelContext(container)
        let trip = try makeTrip(in: model, start: start, end: end, days: 5, nights: 4)
        let repo = TripRepository(context: model)
        // Provider only has the first 3 of the 5 requested days.
        let fetchDays = (0..<3).map { day(on: calendar.date(byAdding: .day, value: $0, to: start)!) }
        let client = StubFetchClient.success(fetchDays)
        let service = WeatherKitWeatherService(client: client, now: { now })

        await TripWeatherRefresh.run(
            trip: trip,
            preferences: .deviceDefaults(),
            weatherService: service,
            engine: try engine(),
            rules: try rules(),
            repository: repo,
            now: now
        )

        let diag = try #require(await WeatherRequestDiagnosticsStore.shared.latest())
        #expect(diag.provider?.returnedDayCount == 3)
        #expect(diag.normalization?.forecastAvailableForPartialTrip == true)
        #expect(diag.normalization?.forecastAvailableForWholeTrip == false)
        #expect(diag.normalization?.seasonalUncoveredDates.count == 2)
        #expect(diag.finalState == .forecastPartial)
        #expect(diag.engineReceivedPreciseWeather == true)
    }

    // MARK: - 3. Future seasonal trip

    @Test @MainActor func futureSeasonalTripSkipsProviderCall() async throws {
        await WeatherRequestDiagnosticsStore.shared.clear()
        let now = date(2026, 9, 4)
        let start = date(2026, 10, 12) // well beyond the 10-day daily horizon
        let end = calendar.date(byAdding: .day, value: 4, to: start)!
        let container = try PackWisePersistence.container(inMemory: true)
        let model = ModelContext(container)
        let trip = try makeTrip(in: model, start: start, end: end, days: 5, nights: 4)
        let repo = TripRepository(context: model)
        let client = StubFetchClient.success([])
        let service = WeatherKitWeatherService(client: client, now: { now })

        await TripWeatherRefresh.run(
            trip: trip,
            preferences: .deviceDefaults(),
            weatherService: service,
            engine: try engine(),
            rules: try rules(),
            repository: repo,
            now: now
        )

        let diag = try #require(await WeatherRequestDiagnosticsStore.shared.latest())
        #expect(diag.fetchAttempted == false)
        #expect(diag.skipReason?.contains("horizon") == true)
        #expect(diag.provider == nil)
        #expect(diag.finalState == .seasonalOnly)
        #expect(diag.engineReceivedPreciseWeather == false)
        #expect(client.fetchCount == 0)
    }

    // MARK: - 4. Cache success (existing valid cache skips the fetch entirely)

    @Test @MainActor func validCacheSkipsFetchEntirely() async throws {
        await WeatherRequestDiagnosticsStore.shared.clear()
        let now = date(2026, 9, 4)
        let start = now
        let end = calendar.date(byAdding: .day, value: 4, to: start)!
        let container = try PackWisePersistence.container(inMemory: true)
        let model = ModelContext(container)
        let trip = try makeTrip(in: model, start: start, end: end, days: 5, nights: 4, status: .packing)
        let repo = TripRepository(context: model)
        let farFuture = date(2026, 9, 4).addingTimeInterval(60 * 60 * 24 * 365)
        let cached = preciseContext(start: start, end: end, expiresAt: farFuture, fetchedAt: now)
        repo.storeWeather(cached, on: trip)
        let client = StubFetchClient.success([])
        let service = WeatherKitWeatherService(client: client, now: { now })

        await TripWeatherRefresh.run(
            trip: trip,
            preferences: .deviceDefaults(),
            weatherService: service,
            engine: try engine(),
            rules: try rules(),
            repository: repo,
            now: now
        )

        #expect(client.fetchCount == 0)
        let diag = try #require(await WeatherRequestDiagnosticsStore.shared.latest())
        #expect(diag.fetchAttempted == false)
        #expect(diag.cache?.hit == true)
        #expect(diag.cache?.selectedAsFinal == true)
        #expect(diag.finalState == .forecastComplete)
        #expect(diag.engineReceivedPreciseWeather == true)
    }

    // MARK: - 5. Provider failure with a usable (expired) cache

    @Test @MainActor func providerFailureFallsBackToUsableCache() async throws {
        await WeatherRequestDiagnosticsStore.shared.clear()
        let now = date(2026, 9, 4)
        let start = now
        let end = calendar.date(byAdding: .day, value: 4, to: start)!
        let container = try PackWisePersistence.container(inMemory: true)
        let model = ModelContext(container)
        let trip = try makeTrip(in: model, start: start, end: end, days: 5, nights: 4, status: .packing)
        let repo = TripRepository(context: model)
        // Expired, so the policy will still call the provider.
        let expired = now.addingTimeInterval(-3600)
        let cached = preciseContext(start: start, end: end, expiresAt: expired, fetchedAt: now.addingTimeInterval(-7200))
        repo.storeWeather(cached, on: trip)
        let client = StubFetchClient.failing()
        let service = WeatherKitWeatherService(client: client, now: { now })

        await TripWeatherRefresh.run(
            trip: trip,
            preferences: .deviceDefaults(),
            weatherService: service,
            engine: try engine(),
            rules: try rules(),
            repository: repo,
            now: now
        )

        #expect(client.fetchCount == 1)
        let diag = try #require(await WeatherRequestDiagnosticsStore.shared.latest())
        #expect(diag.fetchAttempted)
        #expect(diag.provider?.kind == .thrown)
        #expect(diag.provider?.errorDomain != nil)
        #expect(diag.cache?.hit == true)
        #expect(diag.cache?.selectedAsFinal == true)
        #expect(diag.finalState == .failedUsingCache)
        #expect(diag.engineReceivedPreciseWeather == true)
    }

    // MARK: - 6. Provider failure without any cache

    @Test @MainActor func providerFailureWithoutCacheIsUnavailable() async throws {
        await WeatherRequestDiagnosticsStore.shared.clear()
        let now = date(2026, 9, 4)
        let start = now
        let end = calendar.date(byAdding: .day, value: 4, to: start)!
        let container = try PackWisePersistence.container(inMemory: true)
        let model = ModelContext(container)
        let trip = try makeTrip(in: model, start: start, end: end, days: 5, nights: 4)
        let repo = TripRepository(context: model)
        let client = StubFetchClient.failing()
        let service = WeatherKitWeatherService(client: client, now: { now })

        await TripWeatherRefresh.run(
            trip: trip,
            preferences: .deviceDefaults(),
            weatherService: service,
            engine: try engine(),
            rules: try rules(),
            repository: repo,
            now: now
        )

        let diag = try #require(await WeatherRequestDiagnosticsStore.shared.latest())
        #expect(diag.provider?.kind == .thrown)
        #expect(diag.cache?.hit == false)
        #expect(diag.finalState == .unavailable)
        #expect(diag.engineReceivedPreciseWeather == false)
    }

    // MARK: - 7. Debug fixture date remapping

    @Test @MainActor func debugFixtureRebasesOntoAnyTripDateRange() async throws {
        await WeatherRequestDiagnosticsStore.shared.clear()
        let container = try PackWisePersistence.container(inMemory: true)
        let model = ModelContext(container)
        // Deliberately far beyond the live-service horizon, and nowhere near
        // whatever relative "offset" the bundled fixture's days carry — the
        // old MockWeatherService-backed path failed here.
        let farFutureStart = date(2026, 12, 1)
        let farFutureEnd = calendar.date(byAdding: .day, value: 4, to: farFutureStart)!
        let trip = try makeTrip(in: model, start: farFutureStart, end: farFutureEnd, days: 5, nights: 4)
        let repo = TripRepository(context: model)

        let outcome = await DebugWeatherInjection.inject(
            .rain,
            trip: trip,
            preferences: .deviceDefaults(),
            engine: try engine(),
            rules: try rules(),
            repository: repo,
            now: date(2026, 8, 1)
        )

        #expect(!outcome.detail.contains("produced no forecast for these dates"))
        let stored = try #require(trip.weatherSnapshots.first?.weatherContext)
        #expect(stored.source == .fixture)
        #expect(stored.fixtureID == DebugWeatherInjection.Scenario.rain.rawValue)
        #expect(stored.dailyForecast.count == 5)
        #expect(stored.isPreciseForecast)
        let coveredDays = Set(stored.dailyForecast.map { calendar.startOfDay(for: $0.date) })
        let expectedDays = Set((0..<5).map { calendar.startOfDay(for: calendar.date(byAdding: .day, value: $0, to: farFutureStart)!) })
        #expect(coveredDays == expectedDays)

        // The diagnostic entry must say *how* this data was produced without
        // repurposing `skipReason` (which means something else entirely: a
        // live fetch that was skipped or declined).
        let diag = try #require(await WeatherRequestDiagnosticsStore.shared.latest())
        #expect(diag.origin == .fixtureInjection(fixtureID: DebugWeatherInjection.Scenario.rain.rawValue))
        #expect(diag.skipReason == nil)
        #expect(diag.fetchAttempted)
    }

    // MARK: - 8. Timezone / date-boundary normalization

    @Test func destinationTimezoneQueryBoundsAreDestinationAnchored() throws {
        let start = date(2026, 9, 4)
        let end = date(2026, 9, 8)
        let bounds = WeatherForecastNormalizer.queryBounds(start: start, end: end, calendar: calendar)
        #expect(bounds.start == calendar.startOfDay(for: start))
        #expect(bounds.endExclusive == calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)))
        // The end bound is exclusive: the last calendar day covered is the
        // day before it, i.e. the trip's own end day, never one past it.
        let lastCoveredDay = calendar.date(byAdding: .day, value: -1, to: bounds.endExclusive)!
        #expect(calendar.isDate(lastCoveredDay, inSameDayAs: end))
    }

    /// Documents, rather than fixes, a latent risk this task's evidence
    /// surfaced: `TripRecord.startDate`/`endDate` are captured as the
    /// *device* calendar's midnight for the day the traveller tapped
    /// (`PackWiseDateRangePicker`, `TripDraft`), then re-read as a
    /// *destination*-calendar day here. When the two timezones disagree by
    /// enough hours, the same instant can land on a different calendar day
    /// in each calendar — this pins that the disagreement is real in pure
    /// date math, not a claim about what physical hardware will show. See
    /// the task report for why no fix was applied without hardware evidence
    /// discriminating this from other candidate causes.
    @Test func deviceAnchoredMidnightCanLandOnADifferentDestinationDay() {
        var indiaCalendar = Calendar(identifier: .gregorian)
        indiaCalendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        var chicagoCalendar = Calendar(identifier: .gregorian)
        chicagoCalendar.timeZone = TimeZone(identifier: "America/Chicago")!

        // The traveller taps "Sep 4" on a device set to India time — this is
        // exactly what `PackWiseDateRangePicker.select` and `TripDraft`
        // produce: the device calendar's midnight for the tapped day.
        let deviceAnchoredStart = indiaCalendar.date(from: DateComponents(year: 2026, month: 9, day: 4))!

        let destinationDay = chicagoCalendar.component(.day, from: deviceAnchoredStart)
        // India is UTC+5:30, Chicago is UTC-5 during daylight time — an
        // 10.5-hour gap, enough to push device midnight back a full
        // calendar day once re-read in the destination's timezone.
        #expect(destinationDay == 3, "documents the shift; not an assertion about correct behavior")
    }

    // MARK: - 9. Current-day trip in another timezone: provider auth failure

    /// Physical-device evidence (2026-09-08, Chicago, Sep 8–12) plus the
    /// entitled-simulator reproduction recorded in
    /// `docs/device-evidence/product-v2/weatherkit.md`: the live provider
    /// threw `WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors` code 2
    /// before returning any forecast, and the trip-creation path
    /// (`TripSetupView.saveTrip`) resolved weather without ever committing a
    /// diagnostics entry, so the very first live attempt was invisible.
    ///
    /// Pins that a trip beginning today — captured as the *device*
    /// calendar's midnight — in a destination timezone other than the
    /// device's still attempts the fetch (it is not horizon-gated), sends
    /// destination-anchored bounds, records the exact provider error domain
    /// and code, lands on `.unavailable` with no snapshot for the engine,
    /// and commits that evidence from the setup path.
    @Test @MainActor func currentDayTripInAnotherTimezoneRecordsProviderAuthFailure() async throws {
        await WeatherRequestDiagnosticsStore.shared.clear()
        let destination = try SharedLibrary.testDestinations().first { $0.city == "Tokyo" }!
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: destination.timeZone)!
        // The traveller taps "today" on a device in Chicago at 09:23 local —
        // the instant of the recorded device reproduction.
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 9, minute: 23))!
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 4, to: start)!
        let authError = NSError(domain: "WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors", code: 2)
        let client = StubFetchClient.failing(with: authError)
        let service = WeatherKitWeatherService(client: client, now: { now })

        let resolved = await TripWeatherRefresh.resolveForSetup(
            using: service,
            destination: destination,
            start: start,
            end: end,
            cached: nil,
            now: now
        )

        #expect(client.fetchCount == 1)
        #expect(resolved.state == .unavailable)
        #expect(resolved.snapshot == nil)
        #expect(resolved.engineWeather == nil)

        let diag = try #require(await WeatherRequestDiagnosticsStore.shared.latest())
        #expect(diag.origin == .live)
        #expect(diag.fetchAttempted)
        #expect(diag.skipReason == nil)
        #expect(diag.destinationTimeZoneIdentifier == "Asia/Tokyo")
        #expect(diag.bounds.requestedStart == start)
        #expect(diag.bounds.requestedEnd == end)
        #expect(diag.bounds.normalizedStart == tokyo.startOfDay(for: start))
        #expect(diag.bounds.normalizedEndExclusive == tokyo.date(byAdding: .day, value: 1, to: tokyo.startOfDay(for: end)))
        #expect(diag.provider?.kind == .thrown)
        #expect(diag.provider?.errorDomain == "WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors")
        #expect(diag.provider?.errorCode == 2)
        #expect(diag.provider?.returnedDayCount == 0)
        #expect(diag.normalization == nil)
        #expect(diag.cache?.hit == false)
        #expect(diag.cache?.selectedAsFinal == false)
        #expect(diag.finalState == .unavailable)
        #expect(diag.engineReceivedPreciseWeather == false)
        // The staged half was consumed by the commit — nothing dangles for
        // the next refresh to mis-merge into.
        #expect(await WeatherRequestDiagnosticsStore.shared.stagedEntry() == nil)
    }

    // MARK: - 10. A failed live fetch is never presented as a far-future forecast

    /// The device showed "Forecast closer to departure / Your list currently
    /// uses seasonal conditions for Chicago." for a trip beginning *today*.
    /// That copy belongs to the far-future seasonal state; with no stored
    /// snapshot it was actually a provider failure, and the wording sent the
    /// investigation toward date gating. Pins that the two states read
    /// differently.
    @Test func unavailableWeatherIsNotPresentedAsCloserToDeparture() {
        let unavailable = TripDetailWeatherCopy.pending(snapshot: nil, destinationName: "Chicago")
        #expect(unavailable.headline == "Forecast isn't available right now")
        #expect(!unavailable.headline.localizedCaseInsensitiveContains("closer to departure"))
        #expect(unavailable.detail.contains("Chicago"))
        #expect(unavailable.detail.contains("seasonal conditions"))

        let seasonal = TripWeatherContext.seasonal()
        let farFuture = TripDetailWeatherCopy.pending(snapshot: seasonal, destinationName: "Chicago")
        #expect(farFuture.headline == "Forecast closer to departure")
        #expect(farFuture.detail == seasonal.coverageCopy)
    }

    // MARK: - 11. Debug fixture controls cannot be mistaken for live weather

    @Test func debugFixtureScenariosAreLabeledAsFixtures() {
        for scenario in DebugWeatherInjection.Scenario.allCases {
            #expect(scenario.title.contains("Fixture"), "\(scenario.rawValue) must say it is a fixture")
        }
        #expect(DebugWeatherInjection.Scenario.rain.title == "Meaningful Rain Fixture")
    }
}

private final class StubFetchClient: WeatherProvidingClient, @unchecked Sendable {
    enum Behavior {
        case success([DailyForecast])
        case failure(Error)
    }

    private let behavior: Behavior
    private(set) var fetchCount = 0

    private init(behavior: Behavior) {
        self.behavior = behavior
    }

    static func success(_ days: [DailyForecast]) -> StubFetchClient { StubFetchClient(behavior: .success(days)) }
    static func failing() -> StubFetchClient {
        StubFetchClient(behavior: .failure(NSError(domain: "WeatherKitRequestTests.StubFetchClient", code: 42)))
    }
    static func failing(with error: Error) -> StubFetchClient { StubFetchClient(behavior: .failure(error)) }

    func fetch(
        latitude: Double,
        longitude: Double,
        start: Date,
        end: Date,
        timeZone: TimeZone
    ) async throws -> RawWeatherFetch {
        fetchCount += 1
        switch behavior {
        case .success(let days):
            return RawWeatherFetch(
                days: days,
                providerFetchedAt: start,
                providerExpiresAt: start.addingTimeInterval(60 * 60 * 24 * 365),
                alerts: []
            )
        case .failure(let error):
            throw error
        }
    }

    func attribution() async -> WeatherAttribution { .applePlaceholder }
}
