import SwiftUI

/// Renders a destination image for a surface, resolving Look Around → map →
/// graphical without ever showing a spinner or a broken-image state.
///
/// The graphical tier is what a first launch offline looks like, so it has to
/// read as a designed surface rather than a placeholder.
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
            case .lookAround(let image), .map(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            case .graphical, nil:
                GraphicalDestinationTile(seed: destination.id, compact: purpose == .tripThumbnail)
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

/// The third tier: a soft tinted field with a travel glyph.
///
/// The hue is derived from the destination so two trips on the same screen do
/// not look like the same missing image.
struct GraphicalDestinationTile: View {
    var seed: String
    var compact: Bool = false

    private var hue: Double {
        let hash = seed.unicodeScalars.reduce(into: UInt32(7)) { total, scalar in
            total = total &* 31 &+ scalar.value
        }
        return Double(hash % 360) / 360
    }

    var body: some View {
        LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.32, brightness: 0.78),
                Color(hue: hue, saturation: 0.46, brightness: 0.52)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: compact ? 22 : 38, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
