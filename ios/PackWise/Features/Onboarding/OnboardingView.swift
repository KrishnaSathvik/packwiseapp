import SwiftUI

/// The three onboarding messages (Task 9). Copy lives here, not in views, so
/// it is testable: every claim describes what PackWise does today. Nothing
/// promises learning or memory until Packing Memory ships.
enum OnboardingPage: Int, CaseIterable, Identifiable {
    case trip
    case composition
    case authority

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .trip: "Pack for the trip you're actually taking."
        case .composition: "One trip can be many things."
        case .authority: "Your choices stay yours."
        }
    }

    var subtitle: String {
        switch self {
        case .trip: "Destination, dates, weather and plans shape your list."
        case .composition: "Beach, city, business, activities and luggage work together."
        case .authority: "Change quantities, skip items and add your own without losing your decisions."
        }
    }

    var primaryTitle: String {
        self == .authority ? "Create My First Trip" : "Continue"
    }

    /// What the illustration shows, read once in place of its parts.
    var heroAccessibilityLabel: String {
        switch self {
        case .trip: "Illustration: a trip's destination, dates, weather and plans."
        case .composition: "Illustration: one trip that is a beach, city and business trip, with its activities and bags."
        case .authority: "Illustration: a list with a quantity you changed, an item you skipped, and an item you added."
        }
    }
}

/// One branded shell for every page: the PackWise mark in the same place, a
/// framed hero, the title and supporting copy, then page dots and the
/// primary action pinned to the bottom safe area. Only the hero differs.
struct OnboardingView: View {
    var onFinished: () -> Void
    /// Where the flow opens. Always the first page in the app; the Debug
    /// capture harness uses it to photograph a page without swiping to it.
    var initialPage = 0

    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var current: OnboardingPage { OnboardingPage(rawValue: page) ?? .trip }

    var body: some View {
        VStack(spacing: 0) {
            PackWiseBrandMark()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PackWiseSpacing.comfortable)
                .padding(.top, PackWiseSpacing.snug)
                .padding(.bottom, PackWiseSpacing.regular)

            TabView(selection: $page) {
                ForEach(OnboardingPage.allCases) { page in
                    OnboardingPageLayout(page: page)
                        .tag(page.rawValue)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: page)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        .background(PackWiseColor.screen)
        .preferredColorScheme(.light)
        .onAppear { page = initialPage }
    }

    private var controls: some View {
        VStack(spacing: PackWiseSpacing.regular) {
            PackWisePageDots(count: OnboardingPage.allCases.count, current: page, inactive: PackWiseColor.border)
            Button(current.primaryTitle, action: advance)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, PackWiseSpacing.comfortable)
        .padding(.top, PackWiseSpacing.regular)
        .padding(.bottom, PackWiseSpacing.snug)
        .background(PackWiseColor.screen)
    }

    private func advance() {
        guard page < OnboardingPage.allCases.count - 1 else {
            onFinished()
            return
        }
        if reduceMotion {
            page += 1
        } else {
            withAnimation(.easeInOut(duration: 0.3)) { page += 1 }
        }
    }
}

/// The wordmark every onboarding page shares.
struct PackWiseBrandMark: View {
    @ScaledMetric(relativeTo: .headline) private var tile: CGFloat = 28

    var body: some View {
        HStack(spacing: PackWiseSpacing.snug) {
            Image(systemName: "suitcase.fill")
                .font(.system(size: tile * 0.5, weight: .semibold))
                .foregroundStyle(PackWiseColor.onAccent)
                .frame(width: tile, height: tile)
                .background(PackWiseColor.accent, in: RoundedRectangle(cornerRadius: PackWiseRadius.badge, style: .continuous))
            Text("PackWise")
                .font(PackWiseFont.cardTitle)
                .foregroundStyle(PackWiseColor.textPrimary)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PackWise")
        .accessibilityAddTraits(.isHeader)
    }
}

/// Hero, title, supporting copy — scrolling as one, so an accessibility text
/// size never clips the title or collides with the illustration.
private struct OnboardingPageLayout: View {
    var page: OnboardingPage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: PackWiseSpacing.loose) {
                    OnboardingHeroFrame(height: OnboardingHeroMetrics.height(forPage: proxy.size.height, accessibilitySize: dynamicTypeSize.isAccessibilitySize)) {
                        switch page {
                        case .trip: TripShapesListHero()
                        case .composition: ComposedTripHero()
                        case .authority: UserAuthorityHero()
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(page.heroAccessibilityLabel)

                    VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                        Text(page.title)
                            .font(PackWiseFont.screenTitle)
                            .foregroundStyle(PackWiseColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(page.subtitle)
                            .font(PackWiseFont.screenSubtitle)
                            .foregroundStyle(PackWiseColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, PackWiseSpacing.comfortable)
                .padding(.bottom, PackWiseSpacing.loose)
            }
            .scrollIndicators(.hidden)
        }
    }
}

enum OnboardingHeroMetrics {
    /// About half the page, within bounds, at every text size — the copy
    /// below scrolls instead of the illustration shrinking.
    /// At accessibility sizes the illustration yields height so the title
    /// and supporting copy are on screen without scrolling.
    static func height(forPage pageHeight: CGFloat, accessibilitySize: Bool = false) -> CGFloat {
        accessibilitySize ? min(max(pageHeight * 0.34, 200), 300) : min(max(pageHeight * 0.62, 250), 440)
    }
}

/// The frame every hero sits in: one height rule, one radius, one border.
private struct OnboardingHeroFrame<Content: View>: View {
    var height: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(PackWiseColor.accentWash)
            .clipShape(RoundedRectangle(cornerRadius: PackWiseRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PackWiseRadius.card, style: .continuous)
                    .strokeBorder(PackWiseColor.border, lineWidth: 1)
            }
            // Illustrations are examples, not content: they keep their
            // composition at every size while the real copy scales freely.
            .dynamicTypeSize(...DynamicTypeSize.large)
    }
}

// MARK: - Heroes

/// Page 1: a travel photograph with the four inputs that shape a list.
private struct TripShapesListHero: View {
    private let inputs: [(String, String)] = [
        ("mappin.and.ellipse", "Destination"),
        ("calendar", "Dates"),
        ("cloud.sun.fill", "Weather"),
        ("figure.walk", "Plans"),
    ]

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let photo = UIImage(named: PackWiseImageSlot.welcome) {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                } else {
                    DestinationGraphicalFallback()
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .clipped()
            DestinationScrim()

            PackWiseFlowLayout {
                ForEach(inputs, id: \.1) { symbol, title in
                    PackWiseStatusBadge(title: title, symbol: symbol, tint: PackWiseColor.accent, style: .onPhoto)
                }
            }
            .padding(PackWiseSpacing.comfortable)
        }
    }
}

/// Page 2: one trip that is three kinds of trip, with its plans and bags.
private struct ComposedTripHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
            Text("THIS TRIP")
                .font(PackWiseFont.microLabel)
                .foregroundStyle(PackWiseColor.textSecondary)
            PackWiseFlowLayout {
                ForEach([TripType.beach, .cityBreak, .business], id: \.self) { type in
                    PackWiseChip(title: type.title, symbol: type.symbol, tint: type.tint, isSelected: true) {}
                }
            }
            PackWiseRowDivider(inset: 0)
            demoRow(symbol: "figure.open.water.swim", tint: .cyan, title: "Activities", value: "Snorkeling · Museums")
            demoRow(symbol: "suitcase", tint: .blue, title: "Bags", value: "Carry-on · Personal item")
        }
        .padding(PackWiseSpacing.comfortable)
        .background(PackWiseColor.surface, in: RoundedRectangle(cornerRadius: PackWiseRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PackWiseRadius.card, style: .continuous)
                .strokeBorder(PackWiseColor.border, lineWidth: 1)
        }
        .padding(PackWiseSpacing.comfortable)
        .allowsHitTesting(false)
    }
}

/// Page 3: a changed quantity, a skipped item, and an added one.
private struct UserAuthorityHero: View {
    var body: some View {
        VStack(spacing: 0) {
            row(symbol: PackingCategory.clothing.style.symbol, tint: PackingCategory.clothing.style.tint,
                title: "T-shirts", detail: "Quantity 5", tag: "Your quantity", strike: false)
            PackWiseRowDivider()
            row(symbol: PackingCategory.travelComfort.style.symbol, tint: PackingCategory.travelComfort.style.tint,
                title: "Travel pillow", detail: "Not needed", tag: "Skipped", strike: true)
            PackWiseRowDivider()
            row(symbol: PackingCategory.electronics.style.symbol, tint: PackingCategory.electronics.style.tint,
                title: "Film camera", detail: "Quantity 1", tag: "Added by you", strike: false)
        }
        .padding(.horizontal, PackWiseSpacing.comfortable)
        .padding(.vertical, PackWiseSpacing.snug)
        .background(PackWiseColor.surface, in: RoundedRectangle(cornerRadius: PackWiseRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PackWiseRadius.card, style: .continuous)
                .strokeBorder(PackWiseColor.border, lineWidth: 1)
        }
        .padding(PackWiseSpacing.comfortable)
    }

    private func row(symbol: String, tint: Color, title: String, detail: String, tag: String, strike: Bool) -> some View {
        HStack(spacing: PackWiseSpacing.regular) {
            PackWiseIconBadge(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                Text(title)
                    .font(PackWiseFont.rowTitle)
                    .strikethrough(strike)
                    .foregroundStyle(strike ? PackWiseColor.textTertiary : PackWiseColor.textPrimary)
                Text(detail)
                    .font(PackWiseFont.rowSubtitle)
                    .foregroundStyle(PackWiseColor.textSecondary)
            }
            Spacer(minLength: PackWiseSpacing.snug)
            PackWiseStatusBadge(title: tag, symbol: nil, tint: strike ? PackWiseColor.textSecondary : PackWiseColor.accent)
        }
        .padding(.vertical, PackWiseSpacing.regular)
    }
}

private func demoRow(symbol: String, tint: Color, title: String, value: String) -> some View {
    HStack(spacing: PackWiseSpacing.regular) {
        PackWiseIconBadge(symbol: symbol, tint: tint)
        VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
            Text(title)
                .font(PackWiseFont.rowSubtitle)
                .foregroundStyle(PackWiseColor.textSecondary)
            Text(value)
                .font(PackWiseFont.rowTitle)
                .foregroundStyle(PackWiseColor.textPrimary)
        }
        Spacer(minLength: 0)
    }
}
