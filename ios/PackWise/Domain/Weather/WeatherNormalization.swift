import Foundation

enum WeatherForecastNormalizer {
    static let dailyHorizonDays = 10

    /// Single source for precipitation thresholds: shared/rules/weather.json.
    /// Trip Detail reads the same file to pick rainy-day glyphs, so the
    /// screen and the engine can never disagree about which day counts as
    /// rainy. The literals below are last-resort fallbacks for a bundle
    /// that failed to load, and a test pins the loaded values to the file.
    private static let ruleThresholds = try? SharedLibrary.rules().weather.thresholds
    static let defaultRainProbability = ruleThresholds?.rainProbabilityAdd ?? 0.35
    static let defaultHeavyRainProbability = ruleThresholds?.heavyRainProbability ?? 0.6
    static let defaultFreezingMaxF = ruleThresholds?.freezingMaxF ?? 32
    static let farFutureCopy =
        "Detailed forecast isn't available yet. Your list currently uses seasonal conditions and trip details."

    static func calendar(for destination: Destination) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: destination.timeZone) ?? .gmt
        return calendar
    }

    static func tripDays(start: Date, end: Date, calendar: Calendar) -> [Date] {
        let span = TripDateMath.daysAndNights(from: start, to: end, calendar: calendar).days
        let startDay = calendar.startOfDay(for: start)
        return (0..<span).compactMap { calendar.date(byAdding: .day, value: $0, to: startDay) }
    }

    static func isBeyondDailyHorizon(tripStart: Date, now: Date, calendar: Calendar) -> Bool {
        let daysOut = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: tripStart)
        ).day ?? 0
        return daysOut >= dailyHorizonDays
    }

    static func clip(
        _ days: [DailyForecast],
        tripStart: Date,
        tripEnd: Date,
        calendar: Calendar
    ) -> [DailyForecast] {
        let trip = Set(tripDays(start: tripStart, end: tripEnd, calendar: calendar).map { calendar.startOfDay(for: $0) })
        return days
            .filter { trip.contains(calendar.startOfDay(for: $0.date)) }
            .sorted { $0.date < $1.date }
    }

    static func context(
        days: [DailyForecast],
        tripStart: Date,
        tripEnd: Date,
        fetchedAt: Date,
        providerFetchedAt: Date?,
        providerExpiresAt: Date?,
        source: WeatherSource,
        fixtureID: String? = nil,
        alerts: [TripWeatherAlert] = [],
        attribution: WeatherAttribution? = nil,
        calendar: Calendar,
        rainProbability: Double = defaultRainProbability,
        heavyRainProbability: Double = defaultHeavyRainProbability,
        freezingMaxF: Double = defaultFreezingMaxF
    ) -> TripWeatherContext {
        let clipped = clip(days, tripStart: tripStart, tripEnd: tripEnd, calendar: calendar)
        let trip = tripDays(start: tripStart, end: tripEnd, calendar: calendar)
        let covered = Set(clipped.map { calendar.startOfDay(for: $0.date) })
        let coveredCount = trip.filter { covered.contains(calendar.startOfDay(for: $0)) }.count
        let whole = !trip.isEmpty && coveredCount == trip.count
        let partial = coveredCount > 0 && !whole
        let isRainDay = { self.isRainDay($0, rainProbability: rainProbability, freezingMaxF: freezingMaxF) }
        let rainDays = clipped.filter(isRainDay).count
        let summary: String
        if clipped.isEmpty {
            summary = farFutureCopy
        } else if partial {
            summary = "Forecast available for part of your trip."
        } else {
            summary = makeSummary(from: clipped, isRainDay: isRainDay)
        }
        return TripWeatherContext(
            minTemperatureF: clipped.map(\.lowF).min() ?? 0,
            maxTemperatureF: clipped.map(\.highF).max() ?? 0,
            dailyForecast: clipped,
            rainDays: rainDays,
            heavyRainDays: clipped.filter { $0.rainProbability >= heavyRainProbability && $0.highF > freezingMaxF }.count,
            snowDays: clipped.filter { isWinterPrecipDay($0, rainProbability: rainProbability, freezingMaxF: freezingMaxF) }.count,
            outdoorRainOverlapDays: rainDays,
            maxDailyTemperatureSwing: clipped.map(\.swingF).max() ?? 0,
            uvRange: clipped.map(\.uvIndex).max() ?? 0,
            windRange: clipped.map(\.windMph).max() ?? 0,
            weatherSummary: summary,
            fetchedAt: fetchedAt,
            providerFetchedAt: providerFetchedAt,
            providerExpiresAt: providerExpiresAt,
            coverageStart: clipped.first?.date,
            coverageEnd: clipped.last?.date,
            forecastAvailableForWholeTrip: whole,
            forecastAvailableForPartialTrip: partial,
            isPreciseForecast: !clipped.isEmpty,
            source: source,
            fixtureID: fixtureID,
            alerts: alerts,
            attribution: attribution
        )
    }

    /// Precipitation on a sub-freezing day is sleet or snow, not rain: it
    /// belongs to the winter kit (parka, boots), never the umbrella-and-
    /// shell path. Every aggregator — this normalizer, the mock service,
    /// anything counting rainy days — must classify through these two, so
    /// the counts can never drift apart.
    static func isRainDay(
        _ day: DailyForecast,
        rainProbability: Double = defaultRainProbability,
        freezingMaxF: Double = defaultFreezingMaxF
    ) -> Bool {
        day.rainProbability >= rainProbability && day.highF > freezingMaxF
    }

    static func isWinterPrecipDay(
        _ day: DailyForecast,
        rainProbability: Double = defaultRainProbability,
        freezingMaxF: Double = defaultFreezingMaxF
    ) -> Bool {
        day.snowExpected || (day.rainProbability >= rainProbability && day.highF <= freezingMaxF)
    }

    private static func makeSummary(from days: [DailyForecast], isRainDay: (DailyForecast) -> Bool) -> String {
        guard !days.isEmpty else { return farFutureCopy }
        let high = Int((days.map(\.highF).max() ?? 0).rounded())
        let low = Int((days.map(\.lowF).min() ?? 0).rounded())
        var parts = ["Highs around \(high)° with lows near \(low)°."]
        if let rainDay = days.first(where: isRainDay) {
            parts.append("Rain is expected \(rainDay.date.formatted(.dateTime.weekday(.wide))).")
        }
        return parts.joined(separator: " ")
    }
}

struct ResolvedTripWeather: Equatable, Sendable {
    var state: TripWeatherState
    var snapshot: TripWeatherContext?
    var engineWeather: TripWeatherContext?
}

enum TripWeatherResolver {
    static func resolve(
        using service: any WeatherService,
        destination: Destination,
        start: Date,
        end: Date,
        cached: TripWeatherContext?,
        now: Date = .now
    ) async -> ResolvedTripWeather {
        let availability: WeatherAvailability
        do {
            availability = try await service.weather(for: destination, start: start, end: end)
        } catch {
            return fallback(cached: cached, now: now)
        }
        return interpret(availability, cached: cached, now: now)
    }

    static func interpret(
        _ availability: WeatherAvailability,
        cached: TripWeatherContext?,
        now: Date = .now
    ) -> ResolvedTripWeather {
        switch availability {
        case .forecast(let context):
            return ResolvedTripWeather(
                state: context.state(now: now),
                snapshot: context,
                engineWeather: context.isPreciseForecast ? context : nil
            )
        case .seasonal(let message):
            let snapshot = TripWeatherContext.seasonal(summary: message, fetchedAt: now)
            return ResolvedTripWeather(state: .seasonalOnly, snapshot: snapshot, engineWeather: nil)
        case .cached(let context):
            let cachedContext = context.source == .cache ? context : context.markingAsCache()
            return ResolvedTripWeather(
                state: .failedUsingCache,
                snapshot: cachedContext,
                engineWeather: cachedContext.isPreciseForecast ? cachedContext : nil
            )
        case .unavailable:
            return fallback(cached: cached, now: now)
        }
    }

    private static func fallback(cached: TripWeatherContext?, now: Date) -> ResolvedTripWeather {
        if let cached, cached.isPreciseForecast {
            let snapshot = cached.markingAsCache()
            return ResolvedTripWeather(
                state: .failedUsingCache,
                snapshot: snapshot,
                engineWeather: snapshot
            )
        }
        if let cached, cached.source == .seasonal {
            return ResolvedTripWeather(state: .seasonalOnly, snapshot: cached, engineWeather: nil)
        }
        _ = now
        return ResolvedTripWeather(state: .unavailable, snapshot: nil, engineWeather: nil)
    }
}
