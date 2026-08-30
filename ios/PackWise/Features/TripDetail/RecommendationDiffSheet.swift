import SwiftData
import SwiftUI

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
            List {
                if !diff.add.isEmpty {
                    Section("Suggested") {
                        ForEach(diff.add) { item in
                            Toggle(isOn: binding(item.id, in: $addIDs)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("+ \(item.displayName)")
                                    if !item.reason.isEmpty {
                                        Text(item.reason)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                if !diff.quantityChanges.isEmpty {
                    Section("Quantity") {
                        ForEach(diff.quantityChanges, id: \.item.id) { change in
                            Toggle(isOn: binding(change.item.id, in: $quantityIDs)) {
                                Text("\(change.item.displayName)  ×\(change.item.quantity) → ×\(change.suggestedQuantity)")
                            }
                        }
                    }
                }
                if !diff.removeCandidates.isEmpty {
                    Section("You may not need") {
                        Text("Keep these unless you mark them not needed. PackWise will not remove them on its own.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ForEach(diff.removeCandidates) { item in
                            Toggle(isOn: binding(item.id, in: $removeIDs)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.displayName)
                                    Text("Not needed")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep List") {
                        onKeep?()
                        dismiss()
                        onFinished()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Update List") {
                        apply()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
