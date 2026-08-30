import CoreLocation
import Foundation
import WeatherKit

struct LiveWeatherKitClient: WeatherProvidingClient {
    func fetch(
        latitude: Double,
        longitude: Double,
        start: Date,
        end: Date,
        timeZone: TimeZone
    ) async throws -> RawWeatherFetch {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startDay = calendar.startOfDay(for: start)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let daily = try await WeatherKit.WeatherService.shared.weather(
            for: location,
            including: WeatherKit.WeatherQuery.daily(startDate: startDay, endDate: endExclusive)
        )
        let days = daily.forecast.map { Self.day($0, calendar: calendar) }
        let alerts = await Self.alerts(for: location)
        return RawWeatherFetch(
            days: days,
            providerFetchedAt: daily.metadata.date,
            providerExpiresAt: daily.metadata.expirationDate,
            alerts: alerts
        )
    }

    func attribution() async -> PackWise.WeatherAttribution {
        do {
            let apple = try await WeatherKit.WeatherService.shared.attribution
            return PackWise.WeatherAttribution(
                legalPageURL: apple.legalPageURL,
                combinedMarkLightURL: apple.combinedMarkLightURL,
                combinedMarkDarkURL: apple.combinedMarkDarkURL,
                squareMarkURL: apple.squareMarkURL,
                markImageName: "AppleWeatherMark",
                serviceName: apple.serviceName.isEmpty ? "Weather" : apple.serviceName
            )
        } catch {
            return .applePlaceholder
        }
    }

    private static func day(_ day: DayWeather, calendar: Calendar) -> DailyForecast {
        let high = day.highTemperature.converted(to: .fahrenheit).value
        let low = day.lowTemperature.converted(to: .fahrenheit).value
        let snowInches = day.precipitationAmountByType.snowfallAmount.amount.converted(to: .inches).value
        let snowExpected = snowInches > 0.05 || day.precipitation == .snow
        return DailyForecast(
            date: calendar.startOfDay(for: day.date),
            symbol: day.symbolName,
            highF: high,
            lowF: low,
            rainProbability: day.precipitationChance,
            uvIndex: Double(day.uvIndex.value),
            windMph: day.wind.speed.converted(to: .milesPerHour).value,
            snowExpected: snowExpected,
            summary: summary(for: day, snowExpected: snowExpected)
        )
    }

    private static func summary(for day: DayWeather, snowExpected: Bool) -> String {
        if snowExpected { return "Snow" }
        if day.precipitationChance >= WeatherForecastNormalizer.defaultRainProbability { return "Rain likely" }
        return "Forecast"
    }

    private static func alerts(for location: CLLocation) async -> [TripWeatherAlert] {
        let query: WeatherKit.WeatherQuery<[WeatherKit.WeatherAlert]?> = .alerts
        do {
            if let alerts = try await WeatherKit.WeatherService.shared.weather(for: location, including: query) {
                return alerts.map { alert in
                    TripWeatherAlert(
                        severity: String(describing: alert.severity),
                        title: alert.summary,
                        sourceURL: alert.detailsURL.absoluteString
                    )
                }
            }
        } catch {
            return []
        }
        return []
    }
}
