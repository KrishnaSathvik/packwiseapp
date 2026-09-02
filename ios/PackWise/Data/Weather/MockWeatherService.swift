import Foundation

struct WeatherFixtureFile: Codable, Sendable {
    var fixtures: [String: WeatherFixture]
}

struct WeatherFixture: Codable, Sendable {
    var id: String
    var summary: String
    var days: [WeatherFixtureDay]
}

struct WeatherFixtureDay: Codable, Sendable {
    var offset: Int
    var symbol: String
    var highF: Double
    var lowF: Double
    var rainProbability: Double
    var uvIndex: Double
    var windMph: Double
    var snowExpected: Bool
    var summary: String
}

struct MockWeatherService: WeatherService {
    var fixtures: [String: WeatherFixture]
    var forceUnavailable: Bool
    var calendar: Calendar

    init(fixtures: [String: WeatherFixture], forceUnavailable: Bool = false, calendar: Calendar = .current) {
        self.fixtures = fixtures
        self.forceUnavailable = forceUnavailable
        self.calendar = calendar
    }

    static func bundled(bundle: Bundle = .main) throws -> MockWeatherService {
        MockWeatherService(fixtures: try SharedLibrary.weatherFixtures(bundle: bundle))
    }

    func weather(for destination: Destination, start: Date, end: Date) async throws -> WeatherAvailability {
        await availability(for: destination, start: start, end: end)
    }

    func attribution() async -> WeatherAttribution {
        .applePlaceholder
    }

    func availability(for destination: Destination, start: Date, end: Date) async -> WeatherAvailability {
        if forceUnavailable { return .unavailable }
        let daysOut = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: start)).day ?? 0
        if daysOut > 10 {
            return .seasonal("Forecast isn't available yet. Your list currently uses seasonal conditions and trip details.")
        }
        guard let fixture = fixtures[destination.fixtureID ?? ""] ?? fixtures.values.first else {
            return .unavailable
        }
        return .forecast(Self.context(from: fixture, start: start, end: end, calendar: calendar, fixtureID: fixture.id))
    }

    static func context(
        from fixture: WeatherFixture,
        start: Date,
        end: Date,
        calendar: Calendar = .current,
        fixtureID: String
    ) -> TripWeatherContext {
        let span = TripDateMath.daysAndNights(from: start, to: end, calendar: calendar).days
        let days: [DailyForecast] = (0..<span).map { index in
            let template = fixture.days[index % fixture.days.count]
            let date = calendar.date(byAdding: .day, value: index, to: calendar.startOfDay(for: start)) ?? start
            return DailyForecast(
                date: date,
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
        let rainDays = days.filter { WeatherForecastNormalizer.isRainDay($0) }.count
        return TripWeatherContext(
            minTemperatureF: days.map(\.lowF).min() ?? 60,
            maxTemperatureF: days.map(\.highF).max() ?? 75,
            dailyForecast: days,
            rainDays: rainDays,
            heavyRainDays: days.filter { $0.rainProbability >= WeatherForecastNormalizer.defaultHeavyRainProbability && $0.highF > WeatherForecastNormalizer.defaultFreezingMaxF }.count,
            snowDays: days.filter { WeatherForecastNormalizer.isWinterPrecipDay($0) }.count,
            outdoorRainOverlapDays: rainDays,
            maxDailyTemperatureSwing: days.map(\.swingF).max() ?? 0,
            uvRange: days.map(\.uvIndex).max() ?? 0,
            windRange: days.map(\.windMph).max() ?? 0,
            weatherSummary: fixture.summary,
            fetchedAt: .now,
            providerFetchedAt: .now,
            providerExpiresAt: calendar.date(byAdding: .hour, value: 1, to: .now),
            coverageStart: days.first?.date,
            coverageEnd: days.last?.date,
            forecastAvailableForWholeTrip: true,
            forecastAvailableForPartialTrip: false,
            isPreciseForecast: true,
            source: .fixture,
            fixtureID: fixtureID,
            alerts: [],
            attribution: nil
        )
    }
}
