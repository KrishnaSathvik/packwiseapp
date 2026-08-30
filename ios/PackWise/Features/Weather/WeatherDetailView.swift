import SwiftUI

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
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(destinationName)
                        .font(.title2.bold())
                    Text(dateLine)
                        .foregroundStyle(.secondary)
                    if weather.isPreciseForecast {
                        Text(weather.highLowLabel(usesFahrenheit: usesFahrenheit))
                            .font(.title3.bold())
                    }
                    Text(weather.coverageCopy)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if !weather.dailyForecast.isEmpty {
                Section("Trip forecast") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(weather.dailyForecast) { day in
                                VStack(spacing: 4) {
                                    Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                                        .font(.caption)
                                    Image(systemName: day.symbol)
                                    Text(temperatureLabel(day.highF))
                                        .font(.caption.bold())
                                    Text(temperatureLabel(day.lowF))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(minWidth: 44)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if !relevantDetails.isEmpty {
                Section("Details that matter") {
                    ForEach(relevantDetails, id: \.self) { line in
                        Text(line)
                    }
                }
            }

            if !impacts.isEmpty {
                Section("Packing Impact") {
                    ForEach(impacts) { impact in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(impact.title, systemImage: impact.symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(impact.isSeasonal ? Color.secondary : PackWiseColor.accent)
                            Text(impact.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if weather.showsAppleWeatherAttribution, let attribution = weather.attribution {
                Section {
                    WeatherAttributionFooter(attribution: attribution)
                }
            }
        }
        .navigationTitle("Weather")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var relevantDetails: [String] {
        var lines: [String] = []
        let rainDays = weather.dailyForecast.filter { $0.rainProbability >= rainThreshold }
        if !rainDays.isEmpty {
            let names = rainDays.map { $0.date.formatted(.dateTime.weekday(.abbreviated)) }.joined(separator: ", ")
            lines.append("Rain likely \(names)")
        }
        if weather.uvRange >= uvThreshold {
            lines.append("UV up to \(Int(weather.uvRange.rounded()))")
        }
        if weather.windRange >= windThreshold {
            lines.append("Wind up to \(Int(weather.windRange.rounded())) mph")
        }
        if weather.snowDays > 0 {
            lines.append("Snow expected")
        }
        return lines
    }

    private func temperatureLabel(_ fahrenheit: Double) -> String {
        if usesFahrenheit { return "\(Int(fahrenheit.rounded()))" }
        return "\(Int(((fahrenheit - 32) * 5 / 9).rounded()))"
    }
}
