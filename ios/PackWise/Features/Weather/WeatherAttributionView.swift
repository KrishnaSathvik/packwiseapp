import SwiftUI

struct WeatherAttributionFooter: View {
    var attribution: WeatherAttribution
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            if let url = markURL {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    Text(attribution.serviceName)
                        .font(.caption)
                }
                .frame(height: 12)
                .accessibilityHidden(true)
            } else {
                Text(attribution.serviceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let legal = attribution.legalPageURL {
                Link("Other data sources", destination: legal)
                    .font(.caption)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weather data provided by \(attribution.serviceName)")
    }

    private var markURL: URL? {
        colorScheme == .dark ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL
    }
}
