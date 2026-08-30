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
            if context.dailyForecast.isEmpty {
                return .seasonal(WeatherForecastNormalizer.farFutureCopy)
            }
            return .forecast(context)
        } catch {
            return .unavailable
        }
    }
}
