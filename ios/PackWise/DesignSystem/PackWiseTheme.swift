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
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
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
                .background(selected ? PackWiseColor.accent : Color(.secondarySystemBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ProgressSummary: View {
    var packed: Int
    var total: Int

    var remaining: Int { max(0, total - packed) }
    var fraction: Double { total == 0 ? 0 : Double(packed) / Double(total) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: fraction)
                .tint(PackWiseColor.accent)
            HStack {
                Text("\(packed) of \(total) packed")
                Spacer()
                Text(remaining == 0 ? "Packed" : "\(remaining) items left")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(packed) of \(total) packed, \(remaining) left")
    }
}
