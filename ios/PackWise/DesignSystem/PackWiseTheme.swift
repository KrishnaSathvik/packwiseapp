import SwiftUI

enum PackWiseColor {
    /// Central accent token. Matches the mock's blue direction; not a permanently authoritative hex.
    static let accent = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)
}

enum PackWiseImageSlot {
    static let welcome = "OnboardingWelcome"
    static let howItWorks = "OnboardingTrip"
    static let personal = "OnboardingPersonal"
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .foregroundStyle(.white)
            .background(PackWiseColor.accent.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .foregroundStyle(PackWiseColor.accent)
            .background(PackWiseColor.accent.opacity(configuration.isPressed ? 0.12 : 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct PackWiseCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            // `.background` resolves to near-black in Dark Mode, which is the
            // same value as the grouped background these cards sit on — every
            // edge disappears and the screen flattens. This is the semantic
            // pair for content raised above a grouped background, so it stays
            // white in light and elevates in dark.
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
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
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .foregroundStyle(selected ? .white : .primary)
                // secondarySystemBackground is the same value as the grouped
                // background these chips sit on, so unselected ones vanished
                // into the page. A system fill reads on any background.
                .background(selected ? PackWiseColor.accent : Color(.tertiarySystemFill))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
