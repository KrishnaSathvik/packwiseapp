import SwiftUI

/// Three screens: what PackWise promises, how it gets there, and that it
/// improves with use.
///
/// Panel one is two zones — a white top with the wordmark, dark headline and
/// gray subtitle, and destination photography below with the benefits and the
/// button over it. The two explanatory panels are white card screens with no
/// hero imagery, exactly as the sheet draws them.
///
/// The habits shown on the third screen are an illustration of the idea, the
/// same way the Chicago example on the second is. They are not the user's
/// data: PackWise has not observed anything yet, and Me shows only what the
/// user has actually set.
struct OnboardingView: View {
    var onFinished: () -> Void
    /// Where the flow opens. Always the first page in the app; the Debug
    /// capture harness uses it to photograph a page without swiping to it.
    var initialPage = 0

    @State private var page = 0

    private static let lastPage = 2

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $page) {
                welcome.tag(0)
                howItWorks.tag(1)
                personal.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // The welcome photo runs edge to edge, under the status bar and
            // behind the floating button.
            .ignoresSafeArea()

            VStack(spacing: PackWiseSpacing.regular) {
                Button(action: advance) {
                    HStack(spacing: PackWiseSpacing.snug) {
                        Text(buttonTitle)
                        if page == 0 {
                            // The only arrow in the flow — the sheet draws it
                            // on "Get Started" and nowhere else.
                            Image(systemName: "arrow.right")
                                .font(.body.weight(.semibold))
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())

                PackWisePageDots(
                    count: Self.lastPage + 1,
                    current: page,
                    inactive: page == 0 ? .white.opacity(0.4) : PackWiseColor.border
                )
            }
            .padding(.horizontal, PackWiseSpacing.loose)
            .padding(.bottom, PackWiseSpacing.snug)
        }
        .background(PackWiseColor.screen)
        .onAppear { page = initialPage }
    }

    private var buttonTitle: String {
        switch page {
        case 0: "Get Started"
        case 1: "Next"
        default: "Create My First Trip"
        }
    }

    private func advance() {
        if page < Self.lastPage {
            withAnimation { page += 1 }
        } else {
            onFinished()
        }
    }

    /// Clears the floating button and dots on the two scrolling pages.
    private var floatingControlsClearance: CGFloat {
        PackWiseSize.buttonHeight + 60
    }

    // MARK: - Welcome

    /// Two zones: a white top (~40%) carrying the identity and headline in
    /// dark text, and the photograph below (~60%) carrying the benefits and
    /// the floating button. The white top also keeps the status bar legible
    /// without fighting the photo's luminance.
    private var welcome: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                VStack(spacing: PackWiseSpacing.regular) {
                    Spacer(minLength: 0)
                    HStack(spacing: PackWiseSpacing.snug) {
                        Image(systemName: "suitcase.fill")
                            .font(.title2)
                            .foregroundStyle(PackWiseColor.accent)
                            .accessibilityHidden(true)
                        Text("PackWise")
                            .font(.title.bold())
                            .foregroundStyle(PackWiseColor.textPrimary)
                    }
                    Text("Pack what this trip actually needs.")
                        .font(PackWiseFont.screenTitle)
                        .foregroundStyle(PackWiseColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Weather, activities, trip length and the way you travel — all considered.")
                        .font(PackWiseFont.screenSubtitle)
                        .foregroundStyle(PackWiseColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, PackWiseSpacing.loose)
                .frame(maxWidth: .infinity)
                .frame(height: proxy.size.height * 0.4)
                .background(PackWiseColor.screen)

                ZStack(alignment: .bottomLeading) {
                    OnboardingImage(slot: PackWiseImageSlot.welcome)

                    VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
                        benefit("checkmark", "Smarter packing lists")
                        benefit("cloud.sun.fill", "Weather-aware suggestions")
                        benefit("person.fill", "Personalized over time")
                    }
                    .foregroundStyle(.white)
                    .padding(PackWiseSpacing.loose)
                    // Clears the button and dots floating at the bottom of
                    // the ZStack.
                    .padding(.bottom, floatingControlsClearance)
                }
                .frame(height: proxy.size.height * 0.6)
                .clipped()
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func benefit(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: PackWiseSpacing.snug) {
            Circle()
                .fill(.black.opacity(0.35))
                .frame(width: 24, height: 24)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 15, weight: .medium))
        }
    }

    // MARK: - How it works

    /// The content group stretches to the height the floating controls leave
    /// free, so the screen does not end at 60% with a void below — the
    /// spacers distribute the slack around the teaching device.
    private var howItWorks: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: PackWiseSpacing.loose) {
                    VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                        Text("Built around your trip.")
                            .font(PackWiseFont.screenTitle)
                            .foregroundStyle(PackWiseColor.textPrimary)
                        Text("Tell us about your trip and PackWise creates a personalized packing list.")
                            .font(PackWiseFont.screenSubtitle)
                            .foregroundStyle(PackWiseColor.textSecondary)
                    }

                    Spacer(minLength: 0)

                    PackWiseCard {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                                Text("Chicago")
                                    .font(PackWiseFont.cardTitle)
                                    .foregroundStyle(PackWiseColor.textPrimary)
                                Text("5 days · City trip")
                                    .font(PackWiseFont.rowSubtitle)
                                    .foregroundStyle(PackWiseColor.textSecondary)
                            }
                            Spacer()
                            // Weather sits inline in the card, not in its own
                            // divided row.
                            HStack(spacing: PackWiseSpacing.snug) {
                                Image(systemName: "cloud.rain.fill")
                                    .font(.title3)
                                    .weatherGlyphStyle("cloud.rain.fill")
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("61° – 78°")
                                        .font(PackWiseFont.numeral)
                                        .foregroundStyle(PackWiseColor.textPrimary)
                                    Text("Rain Saturday")
                                        .font(PackWiseFont.rowSubtitle)
                                        .foregroundStyle(PackWiseColor.textSecondary)
                                }
                            }
                        }
                    }

                    Image(systemName: "arrow.down")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(PackWiseColor.accent)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)

                    PackWiseCard {
                        VStack(spacing: 0) {
                            outcome("cloud.rain", .green, "Rain jacket", "Added for expected rain")
                            outcomeDivider
                            outcome("wind", .teal, "Light layer", "Cool evenings")
                            outcomeDivider
                            outcome("shoe", .brown, "Walking shoes", "For sightseeing")
                            outcomeDivider
                            outcome("number", .purple, "5-day quantities", "Based on your trip length")
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(PackWiseSpacing.loose)
                .safeAreaPadding(.top)
                .padding(.bottom, floatingControlsClearance)
                // Stretch the group to the visible height so the slack
                // distributes through the spacers instead of pooling at the
                // bottom. Two cards and an arrow are the teaching device — a
                // third card is not the fix for a void.
                .frame(minHeight: proxy.size.height)
            }
            .background(PackWiseColor.screen)
        }
    }

    private var outcomeDivider: some View {
        PackWiseRowDivider()
    }

    private func outcome(_ symbol: String, _ tint: Color, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: PackWiseSpacing.regular) {
            PackWiseIconBadge(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PackWiseColor.textPrimary)
                Text(subtitle)
                    .font(PackWiseFont.rowSubtitle)
                    .foregroundStyle(PackWiseColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, PackWiseSpacing.regular)
    }

    // MARK: - Personalization

    private var personal: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: PackWiseSpacing.loose) {
                    VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                        Text("It gets more personal.")
                            .font(PackWiseFont.screenTitle)
                            .foregroundStyle(PackWiseColor.textPrimary)
                        Text("PackWise remembers what you bring, skip and actually use, so future trips fit you better.")
                            .font(PackWiseFont.screenSubtitle)
                            .foregroundStyle(PackWiseColor.textSecondary)
                    }

                    Spacer(minLength: 0)

                    PackWiseCard {
                        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                            // Title case, inside the card — never a floating
                            // uppercase label.
                            Text("Your Packing Habits")
                                .font(PackWiseFont.sectionTitle)
                                .foregroundStyle(PackWiseColor.textPrimary)
                            VStack(spacing: 0) {
                                habit("arrow.down.circle", .green, "Usually bring", "Portable charger · Running shoes")
                                habit("xmark.circle", .red, "Tend to skip", "Travel pillow · Extra jeans")
                                habit("circle.lefthalf.filled", .orange, "Typical style", "Balanced")
                                habit("suitcase", .blue, "Often travel", "Carry-on")
                            }
                        }
                    }

                    // Sample values, not the user's — nothing has been
                    // observed yet.
                    Text("An example. PackWise starts learning after your first trip.")
                        .font(.system(size: 13))
                        .foregroundStyle(PackWiseColor.textTertiary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)

                    Spacer(minLength: 0)
                }
                .padding(PackWiseSpacing.loose)
                .safeAreaPadding(.top)
                .padding(.bottom, floatingControlsClearance)
                .frame(minHeight: proxy.size.height)
            }
            .background(PackWiseColor.screen)
        }
    }

    private func habit(_ symbol: String, _ tint: Color, _ title: String, _ value: String) -> some View {
        HStack(spacing: PackWiseSpacing.regular) {
            PackWiseIconBadge(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PackWiseColor.textPrimary)
                Text(value)
                    .font(PackWiseFont.rowSubtitle)
                    .foregroundStyle(PackWiseColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, PackWiseSpacing.regular)
    }
}

/// The bundled welcome photograph, or a branded stand-in if the asset is ever
/// missing — never a broken image.
private struct OnboardingImage: View {
    var slot: String

    private var bundled: UIImage? { UIImage(named: slot) }

    var body: some View {
        ZStack {
            if let bundled {
                GeometryReader { proxy in
                    Image(uiImage: bundled)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            } else {
                BrandedDestinationPanel()
            }
            // Keeps the overlaid copy legible on any photograph. The ramp
            // starts below the midpoint so the sky stays open while the text
            // band gets enough weight to survive bright water.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.25),
                    .init(color: .black.opacity(0.45), location: 0.58),
                    .init(color: .black.opacity(0.82), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
