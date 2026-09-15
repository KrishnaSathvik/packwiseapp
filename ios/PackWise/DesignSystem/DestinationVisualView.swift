import SwiftUI

/// The four display states of a destination visual (Task 9). Loading is
/// explicit and occupies the final geometry, so nothing moves when the
/// visual resolves.
enum DestinationVisualDisplayState: String, Equatable {
    case loading
    case image
    case map
    case graphical

    init(_ visual: DestinationVisual?) {
        switch visual {
        case nil: self = .loading
        case .trusted, .lookAround: self = .image
        case .map: self = .map
        case .graphical: self = .graphical
        }
    }
}

/// Renders a destination visual for a surface through the shared policy:
/// trusted imagery → street imagery (policy-gated) → map → graphical.
///
/// Decorative by default: the destination is always named in text beside
/// or over it. Pass `accessibilityLabel` where the visual itself carries
/// meaning.
struct DestinationVisualView: View {
    var destination: Destination
    var purpose: DestinationVisualPurpose
    /// Height of the top band the graphical fallback may decorate. Nil draws
    /// no decoration (thumbnails show a monogram instead).
    var decorationBandHeight: CGFloat? = nil
    var decorationTop: CGFloat = 0
    var accessibilityLabel: String? = nil

    @Environment(\.destinationVisuals) private var service
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visual: DestinationVisual?
    @State private var resolvedID: String?

    private var taskID: String { "\(destination.id)|\(purpose.rawValue)" }

    var body: some View {
        let state = DestinationVisualDisplayState(resolvedID == taskID ? visual : nil)
        ZStack {
            switch resolvedID == taskID ? visual : nil {
            case .trusted(let image), .lookAround(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            case .map(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .overlay { mapMarker(imageSize: image.size) }
                    .transition(.opacity)
            case .graphical:
                DestinationGraphicalFallback(
                    destination: destination,
                    decorationBandHeight: decorationBandHeight,
                    decorationTop: decorationTop,
                    showsMonogram: purpose == .tripThumbnail
                )
                .transition(.opacity)
            case nil:
                DestinationLoadingSurface()
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: state)
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(accessibilityLabel == nil)
        .accessibilityLabel(accessibilityLabel ?? "")
        .accessibilityAddTraits(.isImage)
        .task(id: taskID) {
            let resolved = await service.visual(for: destination, purpose: purpose)
            guard !Task.isCancelled else { return }
            visual = resolved
            resolvedID = taskID
        }
    }
}

extension DestinationVisualView {
    /// The destination marker, positioned where fill cropping puts the
    /// destination, and shown only inside the decoration band — below any
    /// controls and above the text safe region.
    fileprivate func mapMarker(imageSize: CGSize) -> some View {
        GeometryReader { proxy in
            let point = DestinationVisualLayout.markerPoint(
                imageSize: imageSize, frame: proxy.size, heightFraction: purpose.markerHeightFraction
            )
            if DestinationVisualLayout.showsMarker(at: point, bandHeight: decorationBandHeight, top: decorationTop) {
                DestinationMarker(compact: purpose == .tripThumbnail)
                    .position(point)
            }
        }
    }
}

/// One marker for maps and the graphical motif alike.
struct DestinationMarker: View {
    /// Thumbnail size: no halo, a small ringed dot.
    var compact = false

    var body: some View {
        ZStack {
            if !compact {
                Circle().fill(PackWiseColor.accent.opacity(0.22)).frame(width: 34, height: 34)
            }
            Circle().fill(PackWiseColor.onAccent).frame(width: compact ? 10 : 16, height: compact ? 10 : 16)
            Circle().fill(PackWiseColor.accent).frame(width: compact ? 7 : 11, height: compact ? 7 : 11)
        }
        .accessibilityHidden(true)
    }
}

/// Quiet placeholder while a visual resolves: the brand gradient without
/// decoration, so the resolved fallback does not flash a different layout.
struct DestinationLoadingSurface: View {
    var body: some View {
        LinearGradient(
            colors: [PackWiseColor.brandPanelTop, PackWiseColor.brandPanelBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Where decoration may and may not go on a destination visual.
///
/// Text always lives in the bottom-leading safe region below
/// `decorationBandHeight`; decoration is confined to the trailing part of the
/// band above it. The two rectangles never intersect by construction, and
/// `DestinationHero` reserves the band above its text, so a larger text size
/// grows the hero downward instead of into the decoration.
enum DestinationVisualLayout {
    /// Fraction of a hero's minimum height reserved for decoration.
    static let decorationBandFraction: CGFloat = 0.42
    static let minimumDecorationHeight: CGFloat = 56
    /// Room under hero text for Apple's imagery attribution.
    static let attributionClearance: CGFloat = 18

    /// `top` excludes controls drawn over the hero from the band.
    static func decorationRect(in size: CGSize, bandHeight: CGFloat, top: CGFloat = 0) -> CGRect {
        let band = min(bandHeight, size.height)
        let inset = min(16, band * 0.12)
        let x = size.width * 0.52
        let y = min(band, top + inset)
        return CGRect(x: x, y: y, width: max(0, size.width - x - inset), height: max(0, band - inset - y))
    }

    /// Marker radius including its halo.
    static let markerRadius: CGFloat = 17

    /// Where `scaledToFill` puts a point that sits horizontally centered at
    /// `heightFraction` of the image.
    static func markerPoint(imageSize: CGSize, frame: CGSize, heightFraction: Double) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else { return CGPoint(x: frame.width / 2, y: frame.height / 2) }
        let scale = max(frame.width / imageSize.width, frame.height / imageSize.height)
        let offsetY = (frame.height - imageSize.height * scale) / 2
        return CGPoint(x: frame.width / 2, y: offsetY + imageSize.height * scale * heightFraction)
    }

    /// Without a band (thumbnails carry no text) the marker always shows.
    /// With one, its whole halo must sit below `top` and above the band's end.
    static func showsMarker(at point: CGPoint, bandHeight: CGFloat?, top: CGFloat) -> Bool {
        guard let bandHeight else { return true }
        return point.y - markerRadius >= top && point.y + markerRadius <= bandHeight
    }

    static func textSafeRect(in size: CGSize, bandHeight: CGFloat) -> CGRect {
        let top = min(bandHeight, size.height)
        return CGRect(x: 0, y: top, width: size.width, height: max(0, size.height - top))
    }
}

/// The last tier: brand blue with one restrained route motif in the
/// decoration band, or a monogram on a thumbnail. Works offline; never a
/// globe, never an airplane crossing the destination name.
struct DestinationGraphicalFallback: View {
    var destination: Destination? = nil
    var decorationBandHeight: CGFloat? = nil
    var decorationTop: CGFloat = 0
    var showsMonogram: Bool = false

    var body: some View {
        ZStack {
            DestinationLoadingSurface()
            if showsMonogram {
                Text(monogram)
                    .font(PackWiseFont.cardTitle)
                    .foregroundStyle(PackWiseColor.onAccent)
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            } else if let decorationBandHeight {
                GeometryReader { proxy in
                    let rect = DestinationVisualLayout.decorationRect(in: proxy.size, bandHeight: decorationBandHeight, top: decorationTop)
                    RouteMotif()
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var monogram: String {
        guard let destination else { return "P" }
        let name = destination.city.isEmpty ? destination.displayName : destination.city
        return String(name.prefix(1)).uppercased()
    }
}

/// A dashed arc ending at a marker: travel, drawn with the map marker's
/// vocabulary so the graphical and map tiers read as the same product.
private struct RouteMotif: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let end = CGPoint(x: w * 0.78, y: h * 0.34)
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: w * 0.06, y: h * 0.92))
                    path.addQuadCurve(to: end, control: CGPoint(x: w * 0.2, y: h * 0.18))
                }
                .stroke(PackWiseColor.onAccent.opacity(0.42), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))
                DestinationMarker()
                    .position(end)
            }
        }
    }
}

/// The one scrim over destination imagery. Bottom-weighted for the text
/// safe region, optional top shade for hero controls; stronger with
/// Increase Contrast.
struct DestinationScrim: View {
    var topShade: Bool = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let strong = contrast == .increased
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: strong ? 0.2 : 0.35),
                    .init(color: .black.opacity(strong ? 0.45 : 0.22), location: 0.62),
                    .init(color: .black.opacity(strong ? 0.82 : 0.62), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            if topShade {
                LinearGradient(
                    colors: [.black.opacity(strong ? 0.5 : 0.32), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The shared destination hero (Task 9): Review, the Trips Home card, and
/// Trip Detail are sizes of this one primitive.
///
/// It standardizes the visual policy, scrim, text safe region, destination
/// typography, and metadata treatment. The visual is a background, so the
/// text sets the height above `minHeight` and nothing reflows when the
/// visual loads. The band above the text is reserved for decoration.
struct DestinationHero<Accessory: View>: View {
    enum Style {
        /// Full-bleed at the top of Trip Detail.
        case hero
        /// Inside a card: Trips Home, setup Review.
        case card

        var titleFont: Font {
            self == .hero ? PackWiseFont.heroTitle : PackWiseFont.heroCardTitle
        }

        var purpose: DestinationVisualPurpose {
            self == .hero ? .tripHero : .tripCard
        }
    }

    var destination: Destination
    var style: Style
    var title: String
    var metadata: [String]
    var minHeight: CGFloat
    /// Clearance above the decoration band for controls drawn over the
    /// hero (Trip Detail's back and options buttons).
    var reservedTop: CGFloat = 0
    var topShade: Bool = false
    @ViewBuilder var accessory: () -> Accessory

    /// Everything above the text: controls, then at least a minimal band.
    private var bandHeight: CGFloat {
        max(minHeight * DestinationVisualLayout.decorationBandFraction, reservedTop + DestinationVisualLayout.minimumDecorationHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.tight) {
            Spacer(minLength: bandHeight)
            accessory()
            Text(title)
                .font(style.titleFont)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ForEach(metadata, id: \.self) { line in
                Text(line)
                    .font(PackWiseFont.heroMetadata)
                    .foregroundStyle(PackWiseColor.onAccent.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(PackWiseColor.onAccent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PackWiseSpacing.comfortable)
        // The imagery's attribution sits in the bottom-left corner; the
        // clearance is constant so text never moves when a visual loads.
        .padding(.bottom, PackWiseSpacing.comfortable + DestinationVisualLayout.attributionClearance)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .bottomLeading)
        .background {
            DestinationVisualView(destination: destination, purpose: style.purpose, decorationBandHeight: bandHeight, decorationTop: reservedTop)
            DestinationScrim(topShade: topShade)
        }
        .clipped()
    }
}

extension DestinationHero where Accessory == EmptyView {
    init(destination: Destination, style: Style, title: String, metadata: [String], minHeight: CGFloat, reservedTop: CGFloat = 0, topShade: Bool = false) {
        self.init(destination: destination, style: style, title: title, metadata: metadata, minHeight: minHeight, reservedTop: reservedTop, topShade: topShade) {
            EmptyView()
        }
    }
}
