import SwiftUI

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
                ForEach(forecast) { day in
                    VStack(spacing: PackWiseSpacing.tight) {
                        Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: day.symbol)
                            .font(.title3)
                            .symbolRenderingMode(.multicolor)
                            .frame(height: 24)
                        Text(temperature(day.highF))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Text(temperature(day.lowF))
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
        let notable = dailyForecast.first { day in
            day.snowExpected || day.rainProbability >= rainThreshold
        }
        return notable?.symbol ?? dailyForecast.first?.symbol ?? "cloud.sun"
    }

    /// The line under the temperature range.
    ///
    /// `compactHeadline` leads with the range, which the temperature already
    /// shows, so this is just the part that adds something.
    func detailLine(rainThreshold: Double) -> String? {
        guard isPreciseForecast, !forecastAvailableForPartialTrip else {
            return coverageCopy
        }
        guard let rainDay = dailyForecast.first(where: { $0.rainProbability >= rainThreshold }) else {
            return nil
        }
        return "Rain \(rainDay.date.formatted(.dateTime.weekday(.wide)))"
    }
}
