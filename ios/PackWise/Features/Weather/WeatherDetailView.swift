import SwiftUI

/// The deep weather surface.
///
/// Trip Detail carries a concise strip; this owns the rest — the day by day
/// detail, the conditions that actually changed the list, and the coverage
/// state when the forecast does not reach the whole trip. Apple Weather
/// attribution is mandatory wherever this data appears.
struct WeatherDetailView: View {
    var destinationName: String
    var dateLine: String
    var weather: TripWeatherContext
    var impacts: [PackingImpact]
    var usesFahrenheit: Bool
    var rainThreshold: Double
    var uvThreshold: Double
    var windThreshold: Double

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PackWiseSpacing.loose) {
                summary
                if !weather.dailyForecast.isEmpty { forecast }
                if !relevantDetails.isEmpty { details }
                if !impacts.isEmpty { impact }
                if weather.showsAppleWeatherAttribution, let attribution = weather.attribution {
                    WeatherAttributionFooter(attribution: attribution)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(PackWiseSpacing.comfortable)
        }
        .background(PackWiseColor.screen)
        .navigationTitle("Weather")
        .navigationBarTitleDisplayMode(.inline)
        // Pushed inside the Trips stack; the root tabs stay with the root.
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: - Summary

    private var summary: some View {
        PackWiseCard {
            VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
                HStack(alignment: .top, spacing: PackWiseSpacing.regular) {
                    Image(systemName: weather.headlineSymbol(rainThreshold: rainThreshold))
                        .font(.largeTitle)
                        .weatherGlyphStyle(weather.headlineSymbol(rainThreshold: rainThreshold))
                    VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                        Text(destinationName)
                            .font(.title3.weight(.semibold))
                        Text(dateLine)
                            .font(.subheadline)
                            .foregroundStyle(PackWiseColor.textSecondary)
                        if weather.isPreciseForecast {
                            Text(weather.highLowLabel(usesFahrenheit: usesFahrenheit))
                                .font(.title2.weight(.semibold))
                                .padding(.top, PackWiseSpacing.tight)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if let coverage = coverageBadge {
                    PackWiseRowDivider(inset: 0)
                    PackWiseStatusBadge(
                        title: coverage.title,
                        symbol: coverage.symbol,
                        tint: coverage.tint
                    )
                }
                // The stored provider summary is a snapshot-time sentence and
                // can contradict the forecast below it once days shift. With
                // a complete forecast on screen, the days speak for
                // themselves; the prose earns its place only when it explains
                // missing coverage.
                if weather.state() != .forecastComplete, !weather.coverageCopy.isEmpty {
                    Text(weather.coverageCopy)
                        .font(.subheadline)
                        .foregroundStyle(PackWiseColor.textSecondary)
                }
            }
        }
    }

    private struct Coverage {
        var title: String
        var symbol: String
        var tint: Color
    }

    /// Anything other than a complete forecast is stated plainly rather than
    /// left for the user to infer from missing days.
    private var coverageBadge: Coverage? {
        switch weather.state() {
        case .forecastPartial:
            Coverage(title: "Partial forecast", symbol: "clock", tint: .orange)
        case .seasonalOnly:
            Coverage(title: "Seasonal averages", symbol: "calendar", tint: .orange)
        case .stale, .failedUsingCache:
            Coverage(title: "Last known forecast", symbol: "arrow.clockwise", tint: .orange)
        case .unavailable:
            Coverage(title: "Forecast unavailable", symbol: "exclamationmark.triangle", tint: .red)
        case .forecastComplete, .refreshing:
            nil
        }
    }

    // MARK: - Sections

    private var forecast: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            PackWiseSectionHeader(title: "Trip forecast")
            PackWiseCard {
                WeatherStripView(
                    forecast: weather.dailyForecast,
                    usesFahrenheit: usesFahrenheit,
                    rainThreshold: rainThreshold
                )
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            PackWiseSectionHeader(title: "Details that matter")
            PackWiseCard {
                VStack(spacing: 0) {
                    ForEach(Array(relevantDetails.enumerated()), id: \.element.text) { index, detail in
                        if index > 0 { PackWiseRowDivider() }
                        HStack(spacing: PackWiseSpacing.regular) {
                            PackWiseIconBadge(symbol: detail.symbol, tint: detail.tint)
                            Text(detail.text)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, PackWiseSpacing.regular)
                    }
                }
            }
        }
    }

    private var impact: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            PackWiseSectionHeader(title: "Packing Impact")
            PackWiseCard {
                VStack(alignment: .leading, spacing: PackWiseSpacing.comfortable) {
                    ForEach(impacts) { item in
                        HStack(alignment: .top, spacing: PackWiseSpacing.regular) {
                            PackWiseIconBadge(
                                symbol: item.symbol,
                                tint: item.isSeasonal ? .gray : PackWiseColor.accent
                            )
                            VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(item.summary)
                                    .font(.subheadline)
                                    .foregroundStyle(PackWiseColor.textSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Details

    private struct Detail {
        var symbol: String
        var tint: Color
        var text: String
    }

    private var relevantDetails: [Detail] {
        var lines: [Detail] = []
        // Chronological, whatever order the provider returned the days in —
        // "Wed, Mon, Sat" reads as noise.
        let rainDays = weather.dailyForecast
            .filter { $0.rainProbability >= rainThreshold }
            .sorted { $0.date < $1.date }
        if !rainDays.isEmpty {
            let names = rainDays.map { $0.date.formatted(.dateTime.weekday(.abbreviated)) }.joined(separator: ", ")
            lines.append(Detail(symbol: "umbrella", tint: .blue, text: "Rain likely \(names)"))
        }
        if weather.uvRange >= uvThreshold {
            lines.append(Detail(symbol: "sun.max", tint: .orange, text: "UV up to \(Int(weather.uvRange.rounded()))"))
        }
        if weather.windRange >= windThreshold {
            lines.append(Detail(symbol: "wind", tint: .teal, text: "Wind up to \(Int(weather.windRange.rounded())) mph"))
        }
        if weather.snowDays > 0 {
            lines.append(Detail(symbol: "snowflake", tint: .cyan, text: "Snow expected"))
        }
        return lines
    }
}
