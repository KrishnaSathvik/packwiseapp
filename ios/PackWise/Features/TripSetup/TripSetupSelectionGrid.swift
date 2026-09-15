import SwiftUI

/// One option in a multi-select setup surface — trip types, activities, and
/// bags share it (design Section 11).
///
/// Selected state never depends on colour alone: the trailing square gains a
/// checkmark, the surface takes the accent wash with an accent border, and
/// VoiceOver reads the selected trait. Single-select rows keep the round
/// `PackWiseSelectionRow` so the two kinds of choice stay distinguishable.
struct MultiSelectionCard: View {
    enum Layout {
        /// Full-width row: glyph, title and subtitle, checkbox.
        case row
        /// Grid tile: glyph and checkbox on top, title below at full tile
        /// width, so no word ever breaks mid-word in a narrow column.
        case tile
    }

    var symbol: String
    var tint: Color
    var title: String
    var subtitle: String? = nil
    var isSelected: Bool
    var layout: Layout = .row
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                switch layout {
                case .row:
                    HStack(spacing: PackWiseSpacing.regular) {
                        PackWiseIconBadge(symbol: symbol, tint: tint)
                        titles
                        Spacer(minLength: 0)
                        checkbox
                    }
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                case .tile:
                    VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                        HStack(alignment: .top) {
                            PackWiseIconBadge(symbol: symbol, tint: tint)
                            Spacer(minLength: PackWiseSpacing.snug)
                            checkbox
                        }
                        titles
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                }
            }
            .padding(.horizontal, PackWiseSpacing.regular)
            .padding(.vertical, PackWiseSpacing.snug + 2)
            .background(
                isSelected ? PackWiseColor.accentWash : PackWiseColor.surface,
                in: RoundedRectangle(cornerRadius: PackWiseRadius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: PackWiseRadius.control, style: .continuous)
                    .strokeBorder(isSelected ? PackWiseColor.accent : PackWiseColor.border, lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
            Text(title)
                .font(PackWiseFont.rowTitle)
                .foregroundStyle(isSelected ? PackWiseColor.accent : PackWiseColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(PackWiseFont.rowSubtitle)
                    .foregroundStyle(PackWiseColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var checkbox: some View {
        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
            .font(PackWiseFont.selectionGlyph.weight(isSelected ? .regular : .light))
            .foregroundStyle(isSelected ? PackWiseColor.accent : PackWiseColor.textTertiary)
            .accessibilityHidden(true)
    }
}

/// Lays multi-select cards out in two columns, collapsing to one at
/// accessibility text sizes or when the caller asks for a list (bags, whose
/// cards carry a subtitle). The card closure receives the layout to use.
struct TripSetupSelectionGrid<Item: Hashable, Card: View>: View {
    var items: [Item]
    var columns: Int = 2
    @ViewBuilder var card: (Item, MultiSelectionCard.Layout) -> Card

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columnCount: Int {
        dynamicTypeSize.isAccessibilitySize ? 1 : max(1, columns)
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: PackWiseSpacing.snug, alignment: .top), count: columnCount),
            alignment: .leading,
            spacing: PackWiseSpacing.snug
        ) {
            ForEach(items, id: \.self) { item in
                card(item, columnCount > 1 ? .tile : .row)
            }
        }
    }
}
