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
                BrandedDestinationPanel(compact: purpose == .tripThumbnail)
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

/// The last tier: a branded panel in the blue family with a large low-opacity
/// location glyph. It looks deliberate — never a muddy gradient or a loading
/// failure.
struct BrandedDestinationPanel: View {
    var compact: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [PackWiseColor.brandPanelTop, PackWiseColor.brandPanelBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            GeometryReader { proxy in
                Image(systemName: "location.fill")
                    .font(.system(size: min(proxy.size.width, proxy.size.height) * (compact ? 0.5 : 0.42), weight: .regular))
                    .foregroundStyle(.white.opacity(0.16))
                    .rotationEffect(.degrees(-8))
                    .position(x: proxy.size.width * 0.7, y: proxy.size.height * 0.42)
            }

            if compact {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
    }
}
