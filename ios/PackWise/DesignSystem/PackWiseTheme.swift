import SwiftUI

/// The palette, verbatim from the 10-screen reference sheet.
///
/// The sheet is drawn light-only and the app now renders light-only to match
/// (`.preferredColorScheme(.light)` at the root). Nothing outside this file
/// may introduce a raw color; a hue that is not here is not in the design.
enum PackWiseColor {
    /// Buttons, selection, links, the active tab.
    static let accent = Color(hex: 0x2563EB)
    /// Selected row background, info pills.
    static let accentWash = Color(hex: 0xEFF6FF)
    /// Progress fill, "ready", completed.
    static let success = Color(hex: 0x16A34A)
    /// Critical importance, warnings, quantity movements.
    static let important = Color(hex: 0xF59E0B)
    static let info = Color(hex: 0x8B5CF6)
    /// Removals and destructive actions. Derived (red-600) — the sheet has
    /// no destructive surface to sample from.
    static let danger = Color(hex: 0xDC2626)

    /// Screen background. White, never grouped gray.
    static let screen = Color.white
    /// Card fill.
    static let surface = Color.white
    /// Chip rest state, inset panels.
    static let surfaceAlt = Color(hex: 0xF8FAFC)
    /// Card border and hairline dividers.
    static let border = Color(hex: 0xE5E7EB)

    static let textPrimary = Color(hex: 0x0F172A)
    static let textSecondary = Color(hex: 0x6B7280)
    static let textTertiary = Color(hex: 0x9CA3AF)
    static let onAccent = Color.white

    /// The branded destination fallback: brand blue family, never a muddy
    /// gradient.
    static let brandPanelTop = Color(hex: 0x2563EB)
    static let brandPanelBottom = Color(hex: 0x1E40AF)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// The type ramp. SF Pro; `.rounded` is never used.
///
/// Every role is anchored to a Dynamic Type text style whose default size is
/// the sheet size (Task 8.1), so the hierarchy is unchanged at the standard
/// setting and scales together at every other one. Screens never set a
/// point size of their own.
enum PackWiseFont {
    /// "Where are you going?" — title, 28pt at the default size.
    static let screenTitle = Font.system(.title, design: .default, weight: .bold)
    /// The gray line under a screen title — subheadline, 15pt.
    static let screenSubtitle = Font.system(.subheadline, design: .default, weight: .regular)
    /// Card and hero titles — headline, 17pt semibold.
    static let cardTitle = Font.system(.headline, design: .default, weight: .semibold)
    /// "Upcoming", "Past Trips" — callout, 16pt semibold.
    static let sectionTitle = Font.system(.callout, design: .default, weight: .semibold)
    /// "WEATHER", "PACKING", setup step count — caption, 12pt semibold.
    static let microLabel = Font.system(.caption, design: .default, weight: .semibold)
    /// Row and option titles, field values — callout, 16pt medium.
    static let rowTitle = Font.system(.callout, design: .default, weight: .medium)
    /// Row secondary copy and helpers — footnote, 13pt.
    static let rowSubtitle = Font.system(.footnote, design: .default, weight: .regular)
    /// Primary and secondary buttons — headline, 17pt semibold.
    static let button = Font.system(.headline, design: .default, weight: .semibold)
    /// "74%", "4 / 6" — subheadline, 15pt semibold.
    static let numeral = Font.system(.subheadline, design: .default, weight: .semibold)
    /// Selection state glyphs (check circles and squares) — title2, 22pt.
    static let selectionGlyph = Font.system(.title2, design: .default, weight: .regular)
    /// Destination name on the full-bleed Trip Detail hero — largeTitle, 34pt bold.
    static let heroTitle = Font.system(.largeTitle, design: .default, weight: .bold)
    /// Destination name on a card-sized hero (Trips Home, Review) — title2, 22pt bold.
    static let heroCardTitle = Font.system(.title2, design: .default, weight: .bold)
    /// Dates and party under a destination name on imagery — subheadline, 15pt medium.
    static let heroMetadata = Font.system(.subheadline, design: .default, weight: .medium)
}

enum PackWiseImageSlot {
    static let welcome = "OnboardingWelcome"
    static let howItWorks = "OnboardingTrip"
    static let personal = "OnboardingPersonal"
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PackWiseFont.button)
            .frame(maxWidth: .infinity)
            .frame(minHeight: PackWiseSize.buttonHeight)
            .foregroundStyle(isEnabled ? PackWiseColor.onAccent : PackWiseColor.textTertiary)
            .background(
                isEnabled
                    ? PackWiseColor.accent.opacity(configuration.isPressed ? 0.85 : 1)
                    : PackWiseColor.border
            )
            .clipShape(RoundedRectangle(cornerRadius: PackWiseRadius.button, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PackWiseFont.button)
            .frame(maxWidth: .infinity)
            .frame(minHeight: PackWiseSize.buttonHeight)
            .foregroundStyle(PackWiseColor.accent)
            .background(configuration.isPressed ? PackWiseColor.accentWash : PackWiseColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: PackWiseRadius.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PackWiseRadius.button, style: .continuous)
                    .strokeBorder(PackWiseColor.accent, lineWidth: 1)
            }
    }
}

struct PackWiseCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(PackWiseSpacing.comfortable)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PackWiseColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: PackWiseRadius.card, style: .continuous))
            // On a white screen a white card needs its hairline border; the
            // shadow alone is too soft to draw an edge.
            .overlay {
                RoundedRectangle(cornerRadius: PackWiseRadius.card, style: .continuous)
                    .strokeBorder(PackWiseColor.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}

struct SelectableChip: View {
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, PackWiseSpacing.comfortable)
                .frame(minHeight: 40)
                .foregroundStyle(selected ? PackWiseColor.onAccent : PackWiseColor.textPrimary)
                .background(selected ? PackWiseColor.accent : PackWiseColor.surface)
                .clipShape(Capsule())
                .overlay {
                    if !selected {
                        Capsule().strokeBorder(PackWiseColor.border, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
