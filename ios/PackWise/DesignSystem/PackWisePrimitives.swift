import SwiftUI

/// A flat section title with an optional trailing accessory.
///
/// Replaces `.insetGrouped` section headers, which wrap every group in a
/// rounded container and make a packing list read like a stack of cards.
struct PackWiseSectionHeader: View {
    var title: String
    var trailing: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)
            Spacer(minLength: PackWiseSpacing.snug)
            if let trailing {
                if let action {
                    Button(action: action) {
                        HStack(spacing: PackWiseSpacing.hairline) {
                            Text(trailing)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .font(.subheadline.weight(.medium))
                } else {
                    Text(trailing)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }
}

/// Small tinted glyph tile. The board leans on these for scannability in
/// otherwise text-heavy rows.
struct PackWiseIconBadge: View {
    var symbol: String
    var tint: Color
    var size: CGFloat = PackWiseSize.badge

    var body: some View {
        RoundedRectangle(cornerRadius: PackWiseRadius.badge, style: .continuous)
            .fill(tint.opacity(0.16))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(tint)
            }
            .accessibilityHidden(true)
    }
}

/// Progress track. `ProgressView` cannot be made this short without fighting
/// its intrinsic metrics, and the board's bar is a defining element of both
/// Trips Home and Trip Detail.
struct PackWiseProgressBar: View {
    var fraction: Double
    var tint: Color = PackWiseColor.accent
    var height: CGFloat = PackWiseSize.progressBarHeight

    private var clamped: Double { min(max(fraction, 0), 1) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.tertiarySystemFill))
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * clamped)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Compact status pill — "Completed", "3 items affected", "Packing list ready".
///
/// Always carries a label, and optionally a glyph, so state never depends on
/// colour alone.
struct PackWiseStatusBadge: View {
    var title: String
    var symbol: String?
    var tint: Color = PackWiseColor.accent

    var body: some View {
        HStack(spacing: PackWiseSpacing.tight) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
            }
            Text(title)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, PackWiseSpacing.snug)
        .padding(.vertical, PackWiseSpacing.tight)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

/// Trip progress block: count, percentage, bar, and what is left.
///
/// Shared by Trips Home and Trip Detail so the two never drift.
struct ProgressSummary: View {
    var packed: Int
    var total: Int

    var remaining: Int { max(0, total - packed) }
    var fraction: Double { total == 0 ? 0 : Double(packed) / Double(total) }
    private var percentage: Int { Int((fraction * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(packed) of \(total) packed")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(percentage)%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PackWiseColor.accent)
                    .monospacedDigit()
            }
            PackWiseProgressBar(fraction: fraction)
            Text(remaining == 0 ? "Everything packed" : "\(remaining) items left")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            remaining == 0
                ? "All \(total) items packed"
                : "\(packed) of \(total) packed, \(remaining) left"
        )
    }
}
