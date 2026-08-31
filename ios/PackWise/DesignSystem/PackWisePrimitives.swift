import SwiftUI

/// A flat section title with an optional trailing accessory.
///
/// The sheet uses two modes and only two: title case on list screens
/// ("Upcoming", "Past Trips"), and small uppercase inside the long Trip
/// Detail scroll ("WEATHER", "PACKING"). Nothing else is ever uppercase.
struct PackWiseSectionHeader: View {
    enum Style {
        /// Title case, 16pt semibold, dark — list screens and setup sections.
        case list
        /// Uppercase, 12pt semibold, gray — Trip Detail only.
        case micro
    }

    var title: String
    var style: Style = .list
    var trailing: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            switch style {
            case .list:
                Text(title)
                    .font(PackWiseFont.sectionTitle)
                    .foregroundStyle(PackWiseColor.textPrimary)
            case .micro:
                Text(title)
                    .font(PackWiseFont.microLabel)
                    .foregroundStyle(PackWiseColor.textSecondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
            }
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
                    .foregroundStyle(PackWiseColor.accent)
                } else {
                    Text(trailing)
                        .font(PackWiseFont.numeral)
                        .foregroundStyle(PackWiseColor.textSecondary)
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
            .fill(tint.opacity(0.12))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.47, weight: .medium))
                    .foregroundStyle(tint)
            }
            .accessibilityHidden(true)
    }
}

/// Progress track. `ProgressView` cannot be made this short without fighting
/// its intrinsic metrics, and the board's bar is a defining element of both
/// Trips Home and Trip Detail.
///
/// The fill is green — progress is a success story on every surface of the
/// sheet — and the track always renders, even at 0%.
struct PackWiseProgressBar: View {
    var fraction: Double
    var tint: Color = PackWiseColor.success
    var height: CGFloat = PackWiseSize.progressBarHeight

    private var clamped: Double { min(max(fraction, 0), 1) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(PackWiseColor.border)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * clamped)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.25), value: clamped)
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
        .background(
            tint == PackWiseColor.accent ? PackWiseColor.accentWash : tint.opacity(0.12),
            in: Capsule()
        )
    }
}

/// Bare page dots — active blue, inactive at 40% of whatever they sit on.
/// Never wrapped in a gray capsule.
struct PackWisePageDots: View {
    var count: Int
    var current: Int
    /// White over photography, tertiary gray on a white page.
    var inactive: Color = PackWiseColor.textTertiary.opacity(0.6)

    var body: some View {
        HStack(spacing: PackWiseSpacing.snug) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? PackWiseColor.accent : inactive)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

/// Hairline divider between rows in a card, inset to the left edge of the
/// text — not the card edge.
struct PackWiseRowDivider: View {
    /// Defaults to clearing an icon tile.
    var inset: CGFloat = PackWiseSize.badge + PackWiseSpacing.regular

    var body: some View {
        Rectangle()
            .fill(PackWiseColor.border)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// Chips that wrap onto as many lines as they need.
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

/// Trip progress block: count, percentage, green bar, and what is left.
///
/// Shared by Trips Home and Trip Detail so the two never drift. The remaining
/// count sits in a wash pill, as the sheet's hero card draws it.
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
                    .foregroundStyle(PackWiseColor.textPrimary)
                Spacer()
                Text("\(percentage)%")
                    .font(PackWiseFont.numeral)
                    .foregroundStyle(PackWiseColor.accent)
                    .monospacedDigit()
            }
            PackWiseProgressBar(fraction: fraction)
            PackWiseStatusBadge(
                title: remaining == 0 ? "Everything packed" : "\(remaining) items left",
                tint: remaining == 0 ? PackWiseColor.success : PackWiseColor.accent
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            remaining == 0
                ? "All \(total) items packed"
                : "\(packed) of \(total) packed, \(remaining) left"
        )
    }
}

/// One option in a setup step: glyph, name, what it means, and its state.
///
/// Selection is the whole row's state: wash fill, the title turning blue, and
/// a filled blue check. The sheet never leaves the title black on a selected
/// row.
struct PackWiseSelectionRow: View {
    var symbol: String
    var tint: Color
    var title: String
    var subtitle: String?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PackWiseSpacing.regular) {
                PackWiseIconBadge(symbol: symbol, tint: tint)
                VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                    Text(title)
                        .font(PackWiseFont.rowTitle)
                        .foregroundStyle(isSelected ? PackWiseColor.accent : PackWiseColor.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(PackWiseFont.rowSubtitle)
                            .foregroundStyle(PackWiseColor.textSecondary)
                    }
                }
                Spacer(minLength: PackWiseSpacing.snug)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(PackWiseColor.onAccent, PackWiseColor.accent)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(PackWiseColor.textTertiary)
                }
            }
            .padding(.vertical, 9)
            .padding(.horizontal, PackWiseSpacing.snug)
            // Selection is a state of the whole row, not of a glyph at its
            // end. The fill is inset inside the card rather than bleeding to
            // its edge, so a run of rows still reads as one group.
            .background {
                RoundedRectangle(cornerRadius: PackWiseRadius.badge, style: .continuous)
                    .fill(isSelected ? PackWiseColor.accentWash : .clear)
            }
            .padding(.horizontal, -PackWiseSpacing.snug)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A chip carrying a glyph as well as a label.
///
/// Rest state is white with a hairline border and the glyph in its own colour;
/// selected is solid blue with everything white. Height 40, padded out to a
/// 44pt hit target.
struct PackWiseChip: View {
    var title: String
    var symbol: String?
    var tint: Color = PackWiseColor.accent
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PackWiseSpacing.tight + 2) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(isSelected ? PackWiseColor.onAccent : tint)
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isSelected ? PackWiseColor.onAccent : PackWiseColor.textPrimary)
            }
            .padding(.horizontal, PackWiseSpacing.comfortable)
            .frame(minHeight: 40)
            .background {
                Capsule().fill(isSelected ? PackWiseColor.accent : PackWiseColor.surface)
            }
            .overlay {
                if !isSelected {
                    Capsule().strokeBorder(PackWiseColor.border, lineWidth: 1)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A chip that removes itself, used for the activities already chosen.
/// Rests on the alt surface with no border, `×` in tertiary.
struct PackWiseRemovableChip: View {
    var title: String
    var symbol: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PackWiseSpacing.tight + 2) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PackWiseColor.textSecondary)
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PackWiseColor.textPrimary)
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PackWiseColor.textTertiary)
            }
            .padding(.horizontal, PackWiseSpacing.comfortable)
            .frame(minHeight: 40)
            .background { Capsule().fill(PackWiseColor.surfaceAlt) }
            .overlay { Capsule().strokeBorder(PackWiseColor.border, lineWidth: 1) }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(title)")
    }
}
