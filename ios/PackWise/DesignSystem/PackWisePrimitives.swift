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

/// Chips that wrap onto as many lines as they need.
///
/// The existing `FlexibleChipWrap` is a `VStack` despite the name, so every
/// chip gets its own row — which is why the activities step reads as a column
/// of text rather than the compact field the board draws.
struct PackWiseFlowLayout: Layout {
    var spacing: CGFloat = PackWiseSpacing.snug
    var lineSpacing: CGFloat = PackWiseSpacing.snug

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let rows = layout(subviews: subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } +
            lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in layout(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var height: CGFloat = 0
    }

    private func layout(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        var x: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !row.indices.isEmpty, x + size.width > width {
                rows.append(row)
                row = Row()
                x = 0
            }
            row.indices.append(index)
            row.height = max(row.height, size.height)
            x += size.width + spacing
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
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
