import SwiftUI

/// Three screens: what PackWise promises, how it gets there, and that it
/// improves with use.
///
/// Panel one wants full-bleed destination photography. `PackWiseImageSlot`
/// names the asset, but the imageset is empty — the art has not been supplied
/// — so the layout renders over a designed gradient until it is. That is a
/// deliberate placeholder, not a broken image.
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
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                howItWorks.tag(1)
                personal.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            // Without a backing pill the dots are near-invisible on the two
            // light-background pages.
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            // The welcome image is full-bleed, so the pages extend under the
            // status bar; the two text pages pad themselves back down.
            .ignoresSafeArea(edges: .top)

            Button(page == Self.lastPage ? "Create My First Trip" : "Get Started") {
                if page < Self.lastPage {
                    withAnimation { page += 1 }
                } else {
                    onFinished()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, PackWiseSpacing.loose)
            .padding(.bottom, PackWiseSpacing.section)
        }
        .background(Color(.systemBackground))
        .onAppear { page = initialPage }
    }

    // MARK: - Welcome

    private var welcome: some View {
        ZStack(alignment: .bottomLeading) {
            OnboardingImage(slot: PackWiseImageSlot.welcome)

            VStack(alignment: .leading, spacing: PackWiseSpacing.comfortable) {
                Spacer()
                HStack(spacing: PackWiseSpacing.snug) {
                    Image(systemName: "suitcase.fill")
                        .font(.title2)
                        .accessibilityHidden(true)
                    Text("PackWise")
                        .font(.title.bold())
                }
                Text("Pack what this trip actually needs.")
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text("Weather, activities, trip length and the way you travel — all considered.")
                    .font(.body)
                    .opacity(0.9)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                    benefit("checkmark.circle.fill", "Smarter packing lists")
                    benefit("cloud.sun.fill", "Weather-aware suggestions")
                    benefit("person.crop.circle.fill", "Personalized over time")
                }
                .padding(.top, PackWiseSpacing.tight)
            }
            .foregroundStyle(.white)
            .padding(PackWiseSpacing.loose)
            .padding(.bottom, PackWiseSpacing.section)
        }
    }

    /// Contextual imagery for the two explanatory screens. Deliberately a
    /// band rather than a background — the cards are the content here.
    private func banner(_ slot: String) -> some View {
        OnboardingImage(slot: slot, scrim: false, alignment: .bottom)
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: PackWiseRadius.card, style: .continuous))
    }

    private func benefit(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: PackWiseSpacing.snug) {
            Image(systemName: symbol)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.medium))
        }
    }

    // MARK: - How it works

    private var howItWorks: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PackWiseSpacing.loose) {
                VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                    Text("Built around your trip.")
                        .font(.largeTitle.bold())
                    Text("Tell us about your trip and PackWise creates a personalized packing list.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                banner(PackWiseImageSlot.howItWorks)

                PackWiseCard {
                    VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                                Text("Chicago")
                                    .font(.title3.weight(.semibold))
                                Text("5 days · City trip")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "cloud.rain.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.secondary, .blue)
                        }
                        Divider()
                        HStack(spacing: PackWiseSpacing.snug) {
                            Image(systemName: "thermometer.medium")
                                .foregroundStyle(.orange)
                            Text("61° – 78°")
                            Text("·").foregroundStyle(.secondary)
                            Text("Rain Saturday")
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }

                Image(systemName: "arrow.down")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(PackWiseColor.accent)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                PackWiseCard {
                    VStack(spacing: 0) {
                        outcome("cloud.rain", .blue, "Rain jacket", "Added for expected rain")
                        Divider()
                        outcome("wind", .teal, "Light layer", "Cool evenings")
                        Divider()
                        outcome("shoe", .brown, "Walking shoes", "For sightseeing")
                        Divider()
                        outcome("number", .purple, "5-day quantities", "Based on your trip length")
                    }
                }
            }
            .padding(PackWiseSpacing.loose)
            .safeAreaPadding(.top)
            .padding(.bottom, PackWiseSpacing.section)
        }
    }

    private func outcome(_ symbol: String, _ tint: Color, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: PackWiseSpacing.regular) {
            PackWiseIconBadge(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, PackWiseSpacing.regular)
    }

    // MARK: - Personalization

    private var personal: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PackWiseSpacing.loose) {
                VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                    Text("It gets more personal.")
                        .font(.largeTitle.bold())
                    Text("PackWise remembers what you bring, skip and actually use, so future trips fit you better.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                banner(PackWiseImageSlot.personal)

                VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                    PackWiseSectionHeader(title: "Your packing habits")
                    PackWiseCard {
                        VStack(spacing: 0) {
                            habit("arrow.down.circle", .green, "Usually bring", "Portable charger · Running shoes")
                            Divider()
                            habit("xmark.circle", .red, "Tend to skip", "Travel pillow · Extra jeans")
                            Divider()
                            habit("circle.lefthalf.filled", .blue, "Typical style", "Balanced")
                            Divider()
                            habit("suitcase", .indigo, "Often travel", "Carry-on")
                        }
                    }
                    // Sample values, not the user's — nothing has been
                    // observed yet.
                    Text("An example. PackWise starts learning after your first trip.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(PackWiseSpacing.loose)
            .safeAreaPadding(.top)
            .padding(.bottom, PackWiseSpacing.section)
        }
    }

    private func habit(_ symbol: String, _ tint: Color, _ title: String, _ value: String) -> some View {
        HStack(spacing: PackWiseSpacing.regular) {
            PackWiseIconBadge(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(value)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, PackWiseSpacing.regular)
    }
}

/// A bundled onboarding image, or a designed stand-in while the art is
/// missing.
///
/// The three imagesets in Assets.xcassets contain only Contents.json — no
/// image has been supplied — so `Image(slot)` would render nothing at all.
private struct OnboardingImage: View {
    var slot: String
    /// Only the welcome hero has text over it.
    var scrim: Bool = true
    /// Which part of the frame survives the crop.
    var alignment: Alignment = .center

    private var bundled: UIImage? { UIImage(named: slot) }

    var body: some View {
        ZStack {
            if let bundled {
                GeometryReader { proxy in
                    Image(uiImage: bundled)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: alignment)
                        .clipped()
                }
            } else {
                LinearGradient(
                    colors: [
                        Color(hue: 0.58, saturation: 0.55, brightness: 0.55),
                        Color(hue: 0.62, saturation: 0.70, brightness: 0.28)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            if scrim {
                // Keeps the overlaid copy legible on any photograph. The
                // ramp starts below the midpoint so the sky stays open while
                // the text band gets enough weight to survive bright water.
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
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
