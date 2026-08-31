import SwiftUI

/// How a weather glyph is drawn, so the four surfaces that show one agree.
///
/// `.multicolor` resolves only on the filled variants, and the filled cloud is
/// near-white: on a white card it disappeared completely and left three blue
/// rain streaks floating in space, while the same glyph looked correct in dark
/// mode. Hierarchical rendering with an explicit tint is legible on either
/// background and still carries the condition in its colour, which is what the
/// board's weather chips actually do.
enum WeatherGlyph {
    static func tint(for symbol: String) -> Color {
        if symbol.contains("snow") || symbol.contains("sleet") || symbol.contains("hail") { return .teal }
        if symbol.contains("bolt") { return .purple }
        if symbol.contains("rain") || symbol.contains("drizzle") { return .blue }
        if symbol.contains("fog") || symbol.contains("haze") || symbol.contains("smoke") || symbol.contains("wind") { return .gray }
        // Checked after rain so "cloud.sun.rain" stays a rain glyph.
        if symbol.contains("sun") || symbol.contains("moon") { return .orange }
        if symbol.contains("cloud") { return .gray }
        return .blue
    }
}

extension View {
    func weatherGlyphStyle(_ symbol: String) -> some View {
        symbolVariant(.fill)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(WeatherGlyph.tint(for: symbol))
    }
}

/// The trip's days at a glance.
///
/// This is the concise strip that lives on Trip Detail. `WeatherDetailView`
/// still owns the deep surface — precipitation, UV, wind, snow, coverage — so
/// the two are not duplicates of each other.
struct WeatherStripView: View {
    var forecast: [DailyForecast]
    var usesFahrenheit: Bool
    var rainThreshold: Double

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: PackWiseSpacing.regular) {
                ForEach(forecast.sorted { $0.date < $1.date }) { day in
                    VStack(spacing: PackWiseSpacing.tight) {
                        Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption)
                            .foregroundStyle(PackWiseColor.textSecondary)
                        Image(systemName: day.symbol)
                            .font(.title3)
                            .weatherGlyphStyle(day.symbol)
                            .frame(height: 24)
                        Text(temperature(day.highF))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Text(temperature(day.lowF))
                            .font(.caption)
                            .foregroundStyle(PackWiseColor.textSecondary)
                            .monospacedDigit()
                    }
                    .frame(minWidth: PackWiseSize.tapTarget)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(day))
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func temperature(_ fahrenheit: Double) -> String {
        if usesFahrenheit { return "\(Int(fahrenheit.rounded()))°" }
        return "\(Int(((fahrenheit - 32) * 5 / 9).rounded()))°"
    }

    private func accessibilityLabel(_ day: DailyForecast) -> String {
        let weekday = day.date.formatted(.dateTime.weekday(.wide))
        var label = "\(weekday), high \(temperature(day.highF)), low \(temperature(day.lowF))"
        if day.rainProbability >= rainThreshold {
            label += ", rain likely"
        }
        if day.snowExpected {
            label += ", snow expected"
        }
        return label
    }
}

/// Trip-level weather presentation, shared by Trips Home and Trip Detail so
/// the two never disagree about what the forecast is saying.
///
/// `Domain/` is out of scope for the conformance pass, so these live here
/// rather than as new accessors on `TripWeatherContext`.
extension TripWeatherContext {
    /// The glyph for the trip as a whole, not for whichever day happens to be
    /// first — a rainy Sunday matters more than a clear Saturday.
    func headlineSymbol(rainThreshold: Double) -> String {
        let days = dailyForecast.sorted { $0.date < $1.date }
        let notable = days.first { day in
            day.snowExpected || day.rainProbability >= rainThreshold
        }
        return notable?.symbol ?? days.first?.symbol ?? "cloud.sun"
    }

    /// The line under the temperature range.
    ///
    /// `compactHeadline` leads with the range, which the temperature already
    /// shows, so this is just the part that adds something. Always derived
    /// from the current daily forecast, never from the stored provider
    /// summary — a stale sentence is worse than no sentence.
    func detailLine(rainThreshold: Double) -> String? {
        guard isPreciseForecast, !forecastAvailableForPartialTrip else {
            return coverageCopy
        }
        let firstRainDay = dailyForecast
            .filter { $0.rainProbability >= rainThreshold }
            .min { $0.date < $1.date }
        guard let firstRainDay else { return nil }
        return "Rain \(firstRainDay.date.formatted(.dateTime.weekday(.wide)))"
    }
}
