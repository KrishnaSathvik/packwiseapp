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
