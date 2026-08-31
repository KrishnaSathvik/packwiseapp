import SwiftData
import SwiftUI

/// What PackWise would change, and what the user actually wants.
///
/// A pushed screen, not a bottom sheet — reviewing a proposal is a full job.
/// Additions and quantity changes arrive selected; removals do not — PackWise
/// never takes something off a list on its own, so the user must deliberately
/// approve each one. Each kind of change carries a glyph as well as a tint,
/// so the three are told apart without relying on colour.
///
/// "Keep list" dismisses *this proposal only* and preserves the new forecast.
/// It is not a per-item "Not Needed".
struct RecommendationDiffScreen: View {
    let diff: RecommendationDiff
    var trip: TripRecord
    /// The line under the headline saying what triggered the proposal.
    var trigger: String
    /// The forecast movement behind the proposal: old signal → new signal.
    var signalChanges: [WeatherSignalChange]
    var onKeep: (() -> Void)?
    var onUpdate: (() -> Void)?
    var onFinished: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var addIDs: Set<UUID>
    @State private var removeIDs: Set<UUID> = []
    @State private var quantityIDs: Set<UUID>

    init(
        diff: RecommendationDiff,
        trip: TripRecord,
        trigger: String = "You updated your trip details.",
        signalChanges: [WeatherSignalChange] = [],
        onKeep: (() -> Void)? = nil,
        onUpdate: (() -> Void)? = nil,
        onFinished: @escaping () -> Void
    ) {
        self.diff = diff
        self.trip = trip
        self.trigger = trigger
        self.signalChanges = signalChanges
        self.onKeep = onKeep
        self.onUpdate = onUpdate
        self.onFinished = onFinished
        _addIDs = State(initialValue: Set(diff.add.map(\.id)))
        _quantityIDs = State(initialValue: Set(diff.quantityChanges.map(\.item.id)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PackWiseSpacing.loose) {
                heading
                forecastChange
                if !diff.add.isEmpty { additions }
                if !diff.quantityChanges.isEmpty { quantities }
                if !diff.removeCandidates.isEmpty { removals }
            }
            .padding(PackWiseSpacing.comfortable)
        }
        .background(PackWiseColor.screen)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                    onFinished()
                }
            }
        }
        .safeAreaInset(edge: .bottom) { actions }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            Text("Review changes")
                .font(PackWiseFont.screenTitle)
                .foregroundStyle(PackWiseColor.textPrimary)
            Text(trigger)
                .font(PackWiseFont.screenSubtitle)
                .foregroundStyle(PackWiseColor.textSecondary)
        }
    }

    /// The forecast movement, old signal → new signal, so the proposal is
    /// grounded in what actually changed.
    @ViewBuilder
    private var forecastChange: some View {
        let meaningful = signalChanges.filter(\.isMeaningful)
        if !meaningful.isEmpty {
            PackWiseCard {
                VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                    ForEach(meaningful) { change in
                        HStack(spacing: PackWiseSpacing.snug) {
                            Text(signalLabel(change.signal, active: change.wasActive))
                                .foregroundStyle(PackWiseColor.textSecondary)
                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PackWiseColor.textTertiary)
                            Text(signalLabel(change.signal, active: change.isActive))
                                .foregroundStyle(PackWiseColor.textPrimary)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }

    private func signalLabel(_ signal: WeatherSignal, active: Bool) -> String {
        switch signal {
        case .meaningfulRain, .persistentRain: active ? "Rain expected" : "No rain"
        case .coldRain: active ? "Cold rain" : "No cold rain"
        case .highUVExposure: active ? "High sun exposure" : "Moderate sun"
        case .hotOutdoorExposure: active ? "Hot days" : "Milder days"
        case .coldEvenings: active ? "Cool evenings" : "Mild evenings"
        case .highWindExposure: active ? "Windy" : "Calm winds"
        case .snowExposure: active ? "Snow expected" : "No snow"
        case .largeTemperatureSwing: active ? "Big day-night swings" : "Steady temperatures"
        }
    }

    // MARK: - Sections

    private var additions: some View {
        section(title: "Add", count: addIDs.count) {
            ForEach(Array(diff.add.enumerated()), id: \.element.id) { index, item in
                if index > 0 { PackWiseRowDivider() }
                changeRow(
                    symbol: "plus",
                    tint: PackWiseColor.success,
                    title: item.displayName,
                    subtitle: item.reason.isEmpty ? nil : item.reason,
                    isOn: binding(item.id, in: $addIDs)
                )
            }
        }
    }

    private var quantities: some View {
        section(title: "Quantity changes", count: quantityIDs.count) {
            ForEach(Array(diff.quantityChanges.enumerated()), id: \.element.item.id) { index, change in
                if index > 0 { PackWiseRowDivider() }
                changeRow(
                    symbol: "arrow.up.arrow.down",
                    tint: PackWiseColor.important,
                    title: change.item.displayName,
                    subtitle: quantitySubtitle(change),
                    isOn: binding(change.item.id, in: $quantityIDs)
                )
            }
        }
    }

    private func quantitySubtitle(_ change: QuantityChangeSuggestion) -> String {
        let movement = "\(change.item.quantity) → \(change.suggestedQuantity)"
        let reason = change.item.quantityReason
        return reason.isEmpty ? movement : "\(movement) · \(reason)"
    }

    private var removals: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            PackWiseSectionHeader(title: "Remove", trailing: "\(removeIDs.count) selected")
            Text("Off by default. PackWise will not remove items on its own.")
                .font(.footnote)
                .foregroundStyle(PackWiseColor.textSecondary)
            PackWiseCard {
                VStack(spacing: 0) {
                    ForEach(Array(diff.removeCandidates.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { PackWiseRowDivider() }
                        changeRow(
                            symbol: "minus",
                            tint: PackWiseColor.danger,
                            title: item.displayName,
                            subtitle: item.reason.isEmpty ? "No longer suggested for this trip" : item.reason,
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
                            .foregroundStyle(PackWiseColor.textSecondary)
                    }
                }
                Spacer(minLength: PackWiseSpacing.snug)
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn.wrappedValue ? PackWiseColor.accent : PackWiseColor.textTertiary)
            }
            .padding(.vertical, PackWiseSpacing.regular)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn.wrappedValue ? [.isButton, .isSelected] : .isButton)
    }

    private var actions: some View {
        VStack(spacing: PackWiseSpacing.regular) {
            Button("Apply changes") { apply() }
                .buttonStyle(PrimaryButtonStyle())
            // A text link, not a second big button: keeping the list is
            // declining this proposal, and the copy must not read as a
            // per-item action.
            Button("Keep list") {
                onKeep?()
                dismiss()
                onFinished()
            }
            .font(PackWiseFont.button)
            .foregroundStyle(PackWiseColor.accent)
        }
        .padding(PackWiseSpacing.comfortable)
        .background(PackWiseColor.screen)
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
