import SwiftData
import SwiftUI

/// The category chooser's contract (Product Experience V2, Task 12): every
/// supported category once, in the canonical order, with exactly one
/// current selection. Shared by Add Item and Item Detail; nothing here
/// persists anything.
struct CategorySelection: Hashable {
    var current: PackingCategory

    /// The one ordering authority — no selector-specific table. Every
    /// category stays selectable whether or not the trip has rows in it.
    static var options: [PackingCategory] {
        PackingCategory.displayOrder(international: false, outdoor: false)
    }

    func isSelected(_ category: PackingCategory) -> Bool {
        category == current
    }

    func accessibilityValue(for category: PackingCategory) -> String? {
        isSelected(category) ? "Selected" : nil
    }
}

/// What Add Item holds until Save: choosing a category changes this draft
/// and nothing else. Canceling creates nothing.
struct AddItemDraft: Hashable {
    var name: String = ""
    var quantity: Int = 1
    var category: PackingCategory = .clothing
    var owner: PartyListFilter = .all
    var important: Bool = false
}

/// The one write for a category the user chose on an existing record. It
/// touches the category column only: quantity, packed state, owner, carrier,
/// and `isUserModified` (which governs quantity proposals) are not its
/// business. Regeneration refreshes a record through `apply(_:)`, which
/// never writes the category, so the choice stands.
enum ItemCategoryEdit {
    static func apply(_ category: PackingCategory, to record: PackingItemRecord) {
        guard record.categoryRaw != category.rawValue else { return }
        record.categoryRaw = category.rawValue
        record.updatedAt = .now
        record.trip?.updatedAt = .now
    }
}

/// Choose Category: a pushed screen of plain rows — icon, name, checkmark —
/// in the design system's list treatment. Choosing pops back.
struct CategorySelectorView: View {
    @Binding var selection: PackingCategory
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let state = CategorySelection(current: selection)
        List(CategorySelection.options) { category in
            Button {
                selection = category
                dismiss()
            } label: {
                HStack(alignment: .center, spacing: PackWiseSpacing.regular) {
                    PackWiseIconBadge(symbol: category.style.symbol, tint: category.style.tint)
                    Text(category.title)
                        .foregroundStyle(PackWiseColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: PackWiseSpacing.snug)
                    if state.isSelected(category) {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(PackWiseColor.accent)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.vertical, PackWiseSpacing.snug)
                .frame(minHeight: PackWiseSize.tapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 0, leading: PackWiseSpacing.comfortable, bottom: 0, trailing: PackWiseSpacing.comfortable))
            .alignmentGuide(.listRowSeparatorLeading) { _ in PackWiseSize.badge + PackWiseSpacing.regular }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(category.title)
            .accessibilityValue(state.accessibilityValue(for: category) ?? "")
            .accessibilityAddTraits(state.isSelected(category) ? [.isButton, .isSelected] : .isButton)
        }
        .listStyle(.plain)
        .background(PackWiseColor.screen)
        .navigationTitle("Choose Category")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The "Category · Toiletries ›" row Add Item and Item Detail both show; it
/// opens `CategorySelectorView`. Wraps at accessibility sizes.
struct CategoryRowLabel: View {
    let category: PackingCategory
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: PackWiseSpacing.tight) {
                    Text("Category")
                        .foregroundStyle(PackWiseColor.textPrimary)
                    HStack(spacing: PackWiseSpacing.snug) {
                        value
                        chevron
                    }
                }
            } else {
                HStack(spacing: PackWiseSpacing.snug) {
                    Text("Category")
                        .foregroundStyle(PackWiseColor.textPrimary)
                    Spacer(minLength: PackWiseSpacing.snug)
                    value
                    chevron
                }
            }
        }
        .frame(minHeight: PackWiseSize.tapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Category")
        .accessibilityValue(category.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Choose a category")
    }

    private var value: some View {
        HStack(spacing: PackWiseSpacing.snug) {
            Image(systemName: category.style.symbol)
                .font(.subheadline)
                .foregroundStyle(category.style.tint)
            Text(category.title)
                .foregroundStyle(PackWiseColor.textSecondary)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(PackWiseColor.textTertiary)
    }
}
