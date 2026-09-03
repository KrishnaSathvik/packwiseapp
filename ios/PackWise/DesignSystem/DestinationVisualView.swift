import SwiftUI

/// Renders a destination image for a surface, resolving bundled photo →
/// Look Around → branded panel without ever showing a spinner or a
/// broken-image state.
struct DestinationVisualView: View {
    var destination: Destination
    var purpose: DestinationVisualPurpose
    /// Darkens the lower portion so overlaid text stays legible on any image.
    var overlaysText: Bool = false

    @Environment(\.destinationVisuals) private var service
    @State private var visual: DestinationVisual?

    var body: some View {
        ZStack {
            switch visual {
            case .bundled(let image), .lookAround(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            case .graphical, nil:
                BrandedDestinationPanel(destination: destination, compact: purpose == .tripThumbnail)
            }

            if overlaysText {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.15), .black.opacity(0.6)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
        }
        .clipped()
        .animation(.easeOut(duration: 0.2), value: visual == nil)
        .accessibilityHidden(true)
        .task(id: destination.id) {
            visual = await service.visual(for: destination, purpose: purpose)
        }
    }
}

/// The last tier is a destination-aware travel poster, not a generic location
/// placeholder. A regional globe and route motif make unavailable imagery a
/// deliberate visual state.
struct BrandedDestinationPanel: View {
    var destination: Destination? = nil
    var compact: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [PackWiseColor.brandPanelTop, PackWiseColor.brandPanelBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            GeometryReader { proxy in
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.13), lineWidth: 1)
                        .frame(width: proxy.size.height * 0.9)
                    Circle()
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                        .frame(width: proxy.size.height * 0.62)
                    Image(systemName: globeSymbol)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white.opacity(0.16))
                        .frame(width: min(proxy.size.width, proxy.size.height) * (compact ? 0.68 : 0.72))
                    Image(systemName: "airplane")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .offset(
                            x: compact ? 0 : -proxy.size.width * 0.23,
                            y: compact ? 0 : proxy.size.height * 0.2
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .rotationEffect(.degrees(-7))
            }

            if compact {
                Text(monogram)
                    .font(PackWiseFont.cardTitle)
                    .foregroundStyle(.white)
            }
        }
    }

    private var monogram: String {
        guard let destination else { return "P" }
        return String((destination.city.isEmpty ? destination.country : destination.city).prefix(1)).uppercased()
    }

    private var globeSymbol: String {
        guard let destination else { return "globe.americas.fill" }
        if destination.longitude > 60 || destination.longitude < -150 {
            return "globe.asia.australia.fill"
        }
        if destination.longitude >= -30 {
            return "globe.europe.africa.fill"
        }
        return "globe.americas.fill"
    }
}
