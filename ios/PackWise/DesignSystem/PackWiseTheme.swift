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

/// The type ramp. SF Pro at fixed sheet sizes; `.rounded` is never used.
enum PackWiseFont {
    /// "Where are you going?"
    static let screenTitle = Font.system(size: 28, weight: .bold)
    /// The gray line under a screen title.
    static let screenSubtitle = Font.system(size: 15, weight: .regular)
    static let cardTitle = Font.system(size: 17, weight: .semibold)
    /// "Upcoming", "Past Trips" — title case on list screens.
    static let sectionTitle = Font.system(size: 16, weight: .semibold)
    /// "WEATHER", "PACKING" — uppercase, only inside a long detail screen.
    static let microLabel = Font.system(size: 12, weight: .semibold)
    static let rowTitle = Font.system(size: 16, weight: .medium)
    static let rowSubtitle = Font.system(size: 13, weight: .regular)
    static let button = Font.system(size: 17, weight: .semibold)
    /// "74%", "4 / 6".
    static let numeral = Font.system(size: 15, weight: .semibold)
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

/// The navigation bar's `Next`: a filled blue pill, not plain text.
///
/// Disabled it turns to a border-gray pill with tertiary text rather than
/// disappearing into the bar.
struct NavPillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isEnabled ? PackWiseColor.onAccent : PackWiseColor.textTertiary)
            .padding(.horizontal, 18)
            .frame(height: 34)
            .background(
                isEnabled
                    ? PackWiseColor.accent.opacity(configuration.isPressed ? 0.85 : 1)
                    : PackWiseColor.border
            )
            .clipShape(Capsule())
            .lineLimit(1)
            .fixedSize()
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
