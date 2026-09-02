import Foundation

struct DailyForecast: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var date: Date
    var symbol: String
    var highF: Double
    var lowF: Double
    var rainProbability: Double
    var uvIndex: Double
    var windMph: Double
    var snowExpected: Bool
    var summary: String

    init(
        id: UUID = UUID(),
        date: Date,
        symbol: String,
        highF: Double,
        lowF: Double,
        rainProbability: Double,
        uvIndex: Double,
        windMph: Double,
        snowExpected: Bool,
        summary: String
    ) {
        self.id = id
        self.date = date
        self.symbol = symbol
        self.highF = highF
        self.lowF = lowF
        self.rainProbability = rainProbability
        self.uvIndex = uvIndex
        self.windMph = windMph
        self.snowExpected = snowExpected
        self.summary = summary
    }

    var swingF: Double { max(0, highF - lowF) }
}

struct TripWeatherAlert: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var severity: String
    var title: String
    var sourceURL: String?

    init(id: UUID = UUID(), severity: String, title: String, sourceURL: String? = nil) {
        self.id = id
        self.severity = severity
        self.title = title
        self.sourceURL = sourceURL
    }
}

struct WeatherAttribution: Codable, Hashable, Sendable {
    var legalPageURL: URL?
    var combinedMarkLightURL: URL?
    var combinedMarkDarkURL: URL?
    var squareMarkURL: URL?
    var markImageName: String
    var serviceName: String

    static let applePlaceholder = WeatherAttribution(
        legalPageURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html"),
        combinedMarkLightURL: nil,
        combinedMarkDarkURL: nil,
        squareMarkURL: nil,
        markImageName: "AppleWeatherMark",
        serviceName: "Weather"
    )
}

enum WeatherSource: String, Codable, Sendable {
    case weatherKit
    case fixture
    case cache
    case seasonal
    case none
}

/// Internal rendering state. Do not show these names in UI.
enum TripWeatherState: String, Equatable, Sendable {
    case unavailable
    case seasonalOnly
    case forecastPartial
    case forecastComplete
    case stale
    case refreshing
    case failedUsingCache
}

struct TripWeatherContext: Codable, Hashable, Sendable {
    var minTemperatureF: Double
    var maxTemperatureF: Double
    var dailyForecast: [DailyForecast]
    var rainDays: Int
    var heavyRainDays: Int
    var snowDays: Int
    var outdoorRainOverlapDays: Int
    var maxDailyTemperatureSwing: Double
    var uvRange: Double
    var windRange: Double
    var weatherSummary: String
    var fetchedAt: Date
    var providerFetchedAt: Date?
    var providerExpiresAt: Date?
    var coverageStart: Date?
    var coverageEnd: Date?
    var forecastAvailableForWholeTrip: Bool
    var forecastAvailableForPartialTrip: Bool
    var isPreciseForecast: Bool
    var source: WeatherSource
    var fixtureID: String?
    var alerts: [TripWeatherAlert]
    var attribution: WeatherAttribution?

    var highLowLabelFahrenheit: String {
        "\(Int(minTemperatureF.rounded()))° – \(Int(maxTemperatureF.rounded()))°"
    }

    func highLowLabel(usesFahrenheit: Bool) -> String {
        if usesFahrenheit { return highLowLabelFahrenheit }
        let minC = Int(((minTemperatureF - 32) * 5 / 9).rounded())
        let maxC = Int(((maxTemperatureF - 32) * 5 / 9).rounded())
        return "\(minC)° – \(maxC)°"
    }

    var showsAppleWeatherAttribution: Bool {
        (source == .weatherKit || source == .cache) && attribution != nil
    }

    var coverageCopy: String {
        switch state() {
        case .forecastPartial:
            if let end = coverageEnd {
                return "Forecast available for part of your trip, through \(end.formatted(.dateTime.month().day()))."
            }
            return "Forecast available for part of your trip."
        case .seasonalOnly:
            return weatherSummary.isEmpty
                ? "Detailed forecast isn't available yet."
                : weatherSummary
        case .unavailable:
            return "Forecast isn't available right now."
        case .forecastComplete, .stale, .refreshing, .failedUsingCache:
            return weatherSummary
        }
    }

    func compactHeadline(usesFahrenheit: Bool, rainThreshold: Double = 0.35) -> String {
        if forecastAvailableForPartialTrip || !isPreciseForecast {
            return coverageCopy
        }
        let range = highLowLabel(usesFahrenheit: usesFahrenheit)
        if let rainDay = dailyForecast.first(where: { $0.rainProbability >= rainThreshold }) {
            let weekday = rainDay.date.formatted(.dateTime.weekday(.wide))
            return "\(range) · Rain \(weekday)"
        }
        return range
    }

    func markingAsCache() -> TripWeatherContext {
        var copy = self
        copy.source = .cache
        return copy
    }

    func state(now: Date = .now, isRefreshing: Bool = false, lastFetchFailed: Bool = false) -> TripWeatherState {
        if isRefreshing { return .refreshing }
        if lastFetchFailed { return .failedUsingCache }
        switch source {
        case .seasonal:
            return .seasonalOnly
        case .none:
            return .unavailable
        case .cache:
            return .failedUsingCache
        case .weatherKit, .fixture:
            if let expires = providerExpiresAt, expires < now {
                return .stale
            }
            if forecastAvailableForWholeTrip { return .forecastComplete }
            if forecastAvailableForPartialTrip { return .forecastPartial }
            if dailyForecast.isEmpty { return .seasonalOnly }
            return .forecastPartial
        }
    }

    static func seasonal(
        summary: String = "Detailed forecast isn't available yet. Your list currently uses seasonal conditions and trip details.",
        fetchedAt: Date = .now
    ) -> TripWeatherContext {
        TripWeatherContext(
            minTemperatureF: 0,
            maxTemperatureF: 0,
            dailyForecast: [],
            rainDays: 0,
            heavyRainDays: 0,
            snowDays: 0,
            outdoorRainOverlapDays: 0,
            maxDailyTemperatureSwing: 0,
            uvRange: 0,
            windRange: 0,
            weatherSummary: summary,
            fetchedAt: fetchedAt,
            providerFetchedAt: nil,
            providerExpiresAt: nil,
            coverageStart: nil,
            coverageEnd: nil,
            forecastAvailableForWholeTrip: false,
            forecastAvailableForPartialTrip: false,
            isPreciseForecast: false,
            source: .seasonal,
            fixtureID: nil,
            alerts: [],
            attribution: nil
        )
    }
}

enum WeatherAvailability: Equatable, Sendable {
    case forecast(TripWeatherContext)
    case seasonal(String)
    case cached(TripWeatherContext)
    case unavailable
}

protocol WeatherService: Sendable {
    func weather(for destination: Destination, start: Date, end: Date) async throws -> WeatherAvailability
    func attribution() async -> WeatherAttribution
    func availability(for destination: Destination, start: Date, end: Date) async -> WeatherAvailability
}

/// WeatherKit types stay behind this client. Domain and tests use `RawWeatherFetch`.
protocol WeatherProvidingClient: Sendable {
    func fetch(latitude: Double, longitude: Double, start: Date, end: Date, timeZone: TimeZone) async throws -> RawWeatherFetch
    func attribution() async -> WeatherAttribution
}

struct RawWeatherFetch: Sendable, Equatable {
    var days: [DailyForecast]
    var providerFetchedAt: Date
    var providerExpiresAt: Date
    var alerts: [TripWeatherAlert]
}

enum WeatherServiceError: Error, Sendable {
    case unavailable
}

enum WeatherSignal: String, Codable, CaseIterable, Sendable {
    case meaningfulRain
    case persistentRain
    case coldRain
    case highUVExposure
    case hotOutdoorExposure
    case coldEvenings
    /// The warmest day of the trip is still cold: layers rotate, they
    /// don't just exist.
    case sustainedCold
    /// The warmest day is at or below freezing: base layers and a scarf.
    case freezingCold
    case highWindExposure
    case snowExposure
    case largeTemperatureSwing
}

struct PackingConditions: Hashable, Sendable {
    var signals: Set<WeatherSignal>
    var rainDays: Int
    var tripDays: Int
    var swing: Int
}

enum WeatherSignalExtractor {
    static func extract(
        weather: TripWeatherContext,
        thresholds: WeatherThresholds,
        outdoorActivities: Bool,
        tripDays: Int
    ) -> PackingConditions {
        var signals: Set<WeatherSignal> = []
        let resolvedTripDays = max(1, tripDays)
        if weather.rainDays > 0 {
            signals.insert(.meaningfulRain)
        }
        if Double(weather.rainDays) / Double(resolvedTripDays) >= thresholds.persistentRainRatio {
            signals.insert(.persistentRain)
        }
        if weather.rainDays > 0 && weather.minTemperatureF <= thresholds.coolEveningMaxF {
            signals.insert(.coldRain)
        }
        if weather.snowDays > 0 {
            signals.insert(.snowExposure)
        }
        if weather.minTemperatureF <= thresholds.coolEveningMaxF {
            signals.insert(.coldEvenings)
        }
        if weather.maxTemperatureF <= thresholds.coldMaxF {
            signals.insert(.sustainedCold)
        }
        if weather.maxTemperatureF <= thresholds.freezingMaxF {
            signals.insert(.freezingCold)
        }
        if weather.maxTemperatureF >= thresholds.hotMinF && outdoorActivities {
            signals.insert(.hotOutdoorExposure)
        } else if weather.maxTemperatureF >= thresholds.hotMinF {
            signals.insert(.hotOutdoorExposure)
        }
        if weather.uvRange >= thresholds.uvAdd {
            signals.insert(.highUVExposure)
        }
        if weather.windRange >= thresholds.windMphAdd {
            signals.insert(.highWindExposure)
        }
        if weather.maxDailyTemperatureSwing >= thresholds.temperatureSwingAdd {
            signals.insert(.largeTemperatureSwing)
        }
        return PackingConditions(
            signals: signals,
            rainDays: weather.rainDays,
            tripDays: resolvedTripDays,
            swing: Int(weather.maxDailyTemperatureSwing.rounded())
        )
    }
}
