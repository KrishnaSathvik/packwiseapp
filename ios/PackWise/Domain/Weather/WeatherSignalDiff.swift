import Foundation

enum WeatherSignalChangeImportance: String, Codable, Sendable {
    case high
    case medium
    case low
}

struct WeatherSignalChange: Hashable, Identifiable, Codable, Sendable {
    var id: String { signal.rawValue }
    var signal: WeatherSignal
    var wasActive: Bool
    var isActive: Bool
    var importance: WeatherSignalChangeImportance

    var appeared: Bool { !wasActive && isActive }
    var disappeared: Bool { wasActive && !isActive }
    var isMeaningful: Bool { wasActive != isActive }
}

enum WeatherSignalDiffer {
    static func importance(for signal: WeatherSignal) -> WeatherSignalChangeImportance {
        switch signal {
        case .meaningfulRain, .persistentRain, .snowExposure, .freezingCold:
            return .high
        case .coldEvenings, .coldRain, .sustainedCold, .hotOutdoorExposure, .highUVExposure, .largeTemperatureSwing:
            return .medium
        case .highWindExposure:
            return .low
        }
    }

    static func packingConditions(
        weather: TripWeatherContext?,
        tripDays: Int,
        outdoorActivities: Bool,
        thresholds: WeatherThresholds
    ) -> PackingConditions {
        guard let weather, weather.isPreciseForecast || !weather.dailyForecast.isEmpty else {
            return PackingConditions(signals: [], rainDays: 0, tripDays: max(1, tripDays), swing: 0)
        }
        return WeatherSignalExtractor.extract(
            weather: weather,
            thresholds: thresholds,
            outdoorActivities: outdoorActivities,
            tripDays: tripDays
        )
    }

    static func changes(from old: PackingConditions, to new: PackingConditions) -> [WeatherSignalChange] {
        WeatherSignal.allCases.compactMap { signal in
            let wasActive = old.signals.contains(signal)
            let isActive = new.signals.contains(signal)
            guard wasActive != isActive else { return nil }
            return WeatherSignalChange(
                signal: signal,
                wasActive: wasActive,
                isActive: isActive,
                importance: importance(for: signal)
            )
        }
        .sorted { lhs, rhs in
            if lhs.importance != rhs.importance {
                return rank(lhs.importance) < rank(rhs.importance)
            }
            return lhs.signal.rawValue < rhs.signal.rawValue
        }
    }

    private static func rank(_ importance: WeatherSignalChangeImportance) -> Int {
        switch importance {
        case .high: 0
        case .medium: 1
        case .low: 2
        }
    }
}

enum WeatherChangeCopy {
    static func headline(
        changes: [WeatherSignalChange],
        newWeather: TripWeatherContext,
        rainThreshold: Double,
        templates: [String: String]
    ) -> String {
        let appeared = changes.filter(\.appeared)
        let focus = appeared.first { $0.importance == .high }
            ?? appeared.first
            ?? changes.first { $0.importance == .high }
            ?? changes.first
        guard let focus else {
            return ReasonRenderer.render(
                code: "weather_change.generic",
                arguments: [:],
                templates: templates,
                fallback: "The forecast for this trip changed."
            )
        }
        switch (focus.signal, focus.appeared) {
        case (.meaningfulRain, true), (.persistentRain, true), (.coldRain, true):
            if let weekday = newWeather.dailyForecast.first(where: { $0.rainProbability >= rainThreshold })?
                .date.formatted(.dateTime.weekday(.wide))
            {
                return ReasonRenderer.render(
                    code: "weather_change.rain.now",
                    arguments: ["weekday": weekday],
                    templates: templates,
                    fallback: "Rain is now expected \(weekday)."
                )
            }
            return ReasonRenderer.render(
                code: "weather_change.rain.now_generic",
                arguments: [:],
                templates: templates,
                fallback: "Rain is now expected."
            )
        case (.meaningfulRain, false), (.persistentRain, false), (.coldRain, false):
            return ReasonRenderer.render(
                code: "weather_change.rain.ended",
                arguments: [:],
                templates: templates,
                fallback: "Rain is no longer expected."
            )
        case (.coldEvenings, true):
            return ReasonRenderer.render(
                code: "weather_change.cold_evenings.now",
                arguments: [:],
                templates: templates,
                fallback: "Evenings now look cooler."
            )
        case (.coldEvenings, false):
            return ReasonRenderer.render(
                code: "weather_change.cold_evenings.ended",
                arguments: [:],
                templates: templates,
                fallback: "Evenings no longer look as cool."
            )
        case (.highUVExposure, true):
            return ReasonRenderer.render(
                code: "weather_change.uv.now",
                arguments: [:],
                templates: templates,
                fallback: "Sun exposure is now high."
            )
        case (.snowExposure, true):
            return ReasonRenderer.render(
                code: "weather_change.snow.now",
                arguments: [:],
                templates: templates,
                fallback: "Snow is now expected."
            )
        case (.snowExposure, false):
            return ReasonRenderer.render(
                code: "weather_change.snow.ended",
                arguments: [:],
                templates: templates,
                fallback: "Snow is no longer expected."
            )
        case (.freezingCold, true):
            return ReasonRenderer.render(
                code: "weather_change.freezing.now",
                arguments: [:],
                templates: templates,
                fallback: "Sub-freezing temperatures are now expected."
            )
        case (.freezingCold, false):
            return ReasonRenderer.render(
                code: "weather_change.freezing.ended",
                arguments: [:],
                templates: templates,
                fallback: "Temperatures no longer look sub-freezing."
            )
        case (.sustainedCold, true):
            return ReasonRenderer.render(
                code: "weather_change.sustained_cold.now",
                arguments: [:],
                templates: templates,
                fallback: "Cold is now expected for your whole trip."
            )
        case (.highWindExposure, true):
            return ReasonRenderer.render(
                code: "weather_change.wind.now",
                arguments: [:],
                templates: templates,
                fallback: "It's now looking windy."
            )
        case (.hotOutdoorExposure, true):
            return ReasonRenderer.render(
                code: "weather_change.hot.now",
                arguments: [:],
                templates: templates,
                fallback: "It's now looking hotter."
            )
        case (.largeTemperatureSwing, true):
            return ReasonRenderer.render(
                code: "weather_change.swing.now",
                arguments: [:],
                templates: templates,
                fallback: "Larger temperature swings are now expected."
            )
        default:
            return ReasonRenderer.render(
                code: "weather_change.generic",
                arguments: [:],
                templates: templates,
                fallback: "The forecast for this trip changed."
            )
        }
    }
}
