import SwiftData
import SwiftUI

/// What PackWise would change, and what the user actually wants.
///
/// Additions and quantity changes arrive selected; removals do not — PackWise
/// never takes something off a list on its own. Each kind of change carries a
/// glyph as well as a tint, so the three are told apart without relying on
/// colour.
struct RecommendationDiffSheet: View {
    let diff: RecommendationDiff
    var trip: TripRecord
    var title: String
    var onKeep: (() -> Void)?
    var onUpdate: (() -> Void)?
    var onFinished: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var addIDs: Set<UUID>
    @State private var removeIDs: Set<UUID> = []
    @State private var quantityIDs: Set<UUID>

    init(diff: RecommendationDiff, trip: TripRecord, title: String = "Your list changed", onKeep: (() -> Void)? = nil, onUpdate: (() -> Void)? = nil, onFinished: @escaping () -> Void) {
        self.diff = diff
        self.trip = trip
        self.title = title
        self.onKeep = onKeep
        self.onUpdate = onUpdate
        self.onFinished = onFinished
        _addIDs = State(initialValue: Set(diff.add.map(\.id)))
        _quantityIDs = State(initialValue: Set(diff.quantityChanges.map(\.item.id)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PackWiseSpacing.loose) {
                    if !diff.add.isEmpty { additions }
                    if !diff.quantityChanges.isEmpty { quantities }
                    if !diff.removeCandidates.isEmpty { removals }
                }
                .padding(PackWiseSpacing.comfortable)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { actions }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sections

    private var additions: some View {
        section(title: "Suggested", count: addIDs.count) {
            ForEach(Array(diff.add.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider() }
                changeRow(
                    symbol: "plus",
                    tint: .green,
                    title: item.displayName,
                    subtitle: item.reason.isEmpty ? nil : item.reason,
                    isOn: binding(item.id, in: $addIDs)
                )
            }
        }
    }

    private var quantities: some View {
        section(title: "Quantity", count: quantityIDs.count) {
            ForEach(Array(diff.quantityChanges.enumerated()), id: \.element.item.id) { index, change in
                if index > 0 { Divider() }
                changeRow(
                    symbol: "arrow.up.arrow.down",
                    tint: .orange,
                    title: change.item.displayName,
                    subtitle: "×\(change.item.quantity) → ×\(change.suggestedQuantity)",
                    isOn: binding(change.item.id, in: $quantityIDs)
                )
            }
        }
    }

    private var removals: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            PackWiseSectionHeader(title: "You may not need")
            Text("Keep these unless you mark them not needed. PackWise will not remove them on its own.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            PackWiseCard {
                VStack(spacing: 0) {
                    ForEach(Array(diff.removeCandidates.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider() }
                        changeRow(
                            symbol: "minus",
                            tint: .red,
                            title: item.displayName,
                            subtitle: "Remove from this trip",
                            isOn: binding(item.id, in: $removeIDs)
                        )
                    }
                }
            }
        }
    }

    private func section<Content: View>(
        title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            PackWiseSectionHeader(title: title, trailing: "\(count) selected")
            PackWiseCard {
                VStack(spacing: 0) {
                    content()
                }
            }
        }
    }

    private func changeRow(
        symbol: String,
        tint: Color,
        title: String,
        subtitle: String?,
        isOn: Binding<Bool>
    ) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: PackWiseSpacing.regular) {
                PackWiseIconBadge(symbol: symbol, tint: tint)
                VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: PackWiseSpacing.snug)
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn.wrappedValue ? PackWiseColor.accent : Color(.tertiaryLabel))
            }
            .padding(.vertical, PackWiseSpacing.regular)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn.wrappedValue ? [.isButton, .isSelected] : .isButton)
    }

    private var actions: some View {
        VStack(spacing: PackWiseSpacing.snug) {
            Button("Update List") { apply() }
                .buttonStyle(PrimaryButtonStyle())
            Button("Keep List") {
                onKeep?()
                dismiss()
                onFinished()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(PackWiseSpacing.comfortable)
        .background(.bar)
    }

    private func binding(_ id: UUID, in set: Binding<Set<UUID>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(id) },
            set: { on in
                if on { set.wrappedValue.insert(id) } else { set.wrappedValue.remove(id) }
            }
        )
    }

    private func apply() {
        TripRepository(context: modelContext).applyDiff(
            diff,
            addIDs: addIDs,
            removeIDs: removeIDs,
            quantityIDs: quantityIDs,
            on: trip
        )
        try? modelContext.save()
        onUpdate?()
        dismiss()
        onFinished()
    }
}
