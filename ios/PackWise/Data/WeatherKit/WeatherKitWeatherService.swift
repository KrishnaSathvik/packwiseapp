import Foundation

struct WeatherKitWeatherService: WeatherService {
    var client: any WeatherProvidingClient
    var now: @Sendable () -> Date

    init(
        client: any WeatherProvidingClient = LiveWeatherKitClient(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.client = client
        self.now = now
    }

    func weather(for destination: Destination, start: Date, end: Date) async throws -> WeatherAvailability {
        await availability(for: destination, start: start, end: end)
    }

    func attribution() async -> WeatherAttribution {
        await client.attribution()
    }

    func availability(for destination: Destination, start: Date, end: Date) async -> WeatherAvailability {
        let calendar = WeatherForecastNormalizer.calendar(for: destination)
        let fetchedAt = now()
        if WeatherForecastNormalizer.isBeyondDailyHorizon(tripStart: start, now: fetchedAt, calendar: calendar) {
            #if DEBUG
            await Self.stageDiagnostics(
                destination: destination,
                start: start,
                end: end,
                calendar: calendar,
                fetchAttempted: false,
                skipReason: "beyond \(WeatherForecastNormalizer.dailyHorizonDays)-day daily horizon"
            )
            #endif
            return .seasonal(WeatherForecastNormalizer.farFutureCopy)
        }
        do {
            let fetch = try await client.fetch(
                latitude: destination.latitude,
                longitude: destination.longitude,
                start: start,
                end: end,
                timeZone: TimeZone(identifier: destination.timeZone) ?? .gmt
            )
            let attribution = await client.attribution()
            let context = WeatherForecastNormalizer.context(
                days: fetch.days,
                tripStart: start,
                tripEnd: end,
                fetchedAt: fetchedAt,
                providerFetchedAt: fetch.providerFetchedAt,
                providerExpiresAt: fetch.providerExpiresAt,
                source: .weatherKit,
                alerts: fetch.alerts,
                attribution: attribution,
                calendar: calendar
            )
            #if DEBUG
            await Self.stageDiagnostics(
                destination: destination,
                start: start,
                end: end,
                calendar: calendar,
                fetchAttempted: true,
                skipReason: nil,
                provider: WeatherRequestDiagnostics.ProviderResult(
                    kind: .success,
                    returnedDayCount: fetch.days.count,
                    returnedCoverageStart: fetch.days.map(\.date).min(),
                    returnedCoverageEnd: fetch.days.map(\.date).max(),
                    providerFetchedAt: fetch.providerFetchedAt,
                    providerExpiresAt: fetch.providerExpiresAt,
                    errorDomain: nil,
                    errorCode: nil
                ),
                normalization: Self.normalizationResult(context: context, start: start, end: end, calendar: calendar)
            )
            #endif
            if context.dailyForecast.isEmpty {
                return .seasonal(WeatherForecastNormalizer.farFutureCopy)
            }
            return .forecast(context)
        } catch {
            #if DEBUG
            let nsError = error as NSError
            await Self.stageDiagnostics(
                destination: destination,
                start: start,
                end: end,
                calendar: calendar,
                fetchAttempted: true,
                skipReason: nil,
                provider: WeatherRequestDiagnostics.ProviderResult(
                    kind: .thrown,
                    returnedDayCount: 0,
                    returnedCoverageStart: nil,
                    returnedCoverageEnd: nil,
                    providerFetchedAt: nil,
                    providerExpiresAt: nil,
                    errorDomain: nsError.domain,
                    errorCode: nsError.code
                ),
                normalization: nil
            )
            #endif
            return .unavailable
        }
    }

    #if DEBUG
    private static func normalizationResult(
        context: TripWeatherContext,
        start: Date,
        end: Date,
        calendar: Calendar
    ) -> WeatherRequestDiagnostics.NormalizationResult {
        let tripDays = WeatherForecastNormalizer.tripDays(start: start, end: end, calendar: calendar)
        let covered = Set(context.dailyForecast.map { calendar.startOfDay(for: $0.date) })
        let uncovered = tripDays
            .map { calendar.startOfDay(for: $0) }
            .filter { !covered.contains($0) }
        return WeatherRequestDiagnostics.NormalizationResult(
            preciseCoveredDates: context.dailyForecast.map(\.date),
            seasonalUncoveredDates: uncovered,
            forecastAvailableForWholeTrip: context.forecastAvailableForWholeTrip,
            forecastAvailableForPartialTrip: context.forecastAvailableForPartialTrip,
            isPreciseForecast: context.isPreciseForecast
        )
    }

    private static func stageDiagnostics(
        destination: Destination,
        start: Date,
        end: Date,
        calendar: Calendar,
        fetchAttempted: Bool,
        skipReason: String?,
        provider: WeatherRequestDiagnostics.ProviderResult? = nil,
        normalization: WeatherRequestDiagnostics.NormalizationResult? = nil
    ) async {
        let bounds = WeatherForecastNormalizer.queryBounds(start: start, end: end, calendar: calendar)
        let entry = WeatherRequestDiagnostics(
            recordedAt: .now,
            destinationName: destination.displayName,
            destinationLatitude: destination.latitude,
            destinationLongitude: destination.longitude,
            destinationTimeZoneIdentifier: destination.timeZone,
            deviceTimeZoneIdentifier: TimeZone.current.identifier,
            deviceCalendarIdentifier: String(describing: Calendar.current.identifier),
            bounds: WeatherRequestDiagnostics.DateBounds(
                requestedStart: start,
                requestedEnd: end,
                normalizedStart: bounds.start,
                normalizedEndExclusive: bounds.endExclusive
            ),
            fetchAttempted: fetchAttempted,
            skipReason: skipReason,
            provider: provider,
            normalization: normalization,
            cache: nil,
            finalState: .unavailable,
            engineReceivedPreciseWeather: false
        )
        await WeatherRequestDiagnosticsStore.shared.stage(entry)
    }
    #endif
}
