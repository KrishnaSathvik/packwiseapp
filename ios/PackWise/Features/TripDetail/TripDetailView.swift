import SwiftData
import SwiftUI

/// Trip overview.
///
/// Understanding the trip and doing the packing are separate jobs, so this
/// screen answers the first — where, when, how far along, what the weather
/// will do — and hands the checklist to `PackingListView`. Opening a trip used
/// to drop straight into a wall of item rows with no context above them.
struct TripDetailView: View {
    @Bindable var trip: TripRecord
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var preferenceRecords: [PackingPreferenceRecord]

    @State private var expandedImpactID: String?
    @State private var reviewingWeatherChange = false
    @State private var isRefreshingWeather = false
    @State private var editing = false
    @State private var openList: PackingListDestination?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PackWiseSpacing.loose) {
                hero
                VStack(alignment: .leading, spacing: PackWiseSpacing.loose) {
                    progress
                    weatherChanged
                    weather
                    impact
                    categories
                }
                .padding(.horizontal, PackWiseSpacing.comfortable)
            }
            .padding(.bottom, PackWiseSpacing.section)
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit Trip") { editing = true }
                    if trip.status != .completed && trip.status != .archived {
                        Button("Complete Trip") { completeTrip() }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Trip options")
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                TripSetupView(existingTrip: trip)
            }
        }
        .sheet(isPresented: $reviewingWeatherChange) {
            if let proposal = pendingWeatherChange {
                RecommendationDiffSheet(
                    diff: proposal.diff,
                    trip: trip,
                    title: "Review changes",
                    onKeep: { setWeatherChangeStatus(proposal, .dismissed) },
                    onUpdate: { setWeatherChangeStatus(proposal, .applied) },
                    onFinished: { reviewingWeatherChange = false }
                )
            }
        }
        .task {
            await refreshWeather()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refreshWeather() }
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        DestinationVisualView(
            destination: trip.destination,
            purpose: .tripHero,
            overlaysText: true
        )
        .frame(height: PackWiseSize.heroHeight)
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: PackWiseSpacing.tight) {
                Text(trip.destinationDisplayName)
                    .font(.largeTitle.bold())
                Text(dateLine)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                if !trip.party.usesSimpleList {
                    Text(trip.party.summary)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .foregroundStyle(.white)
            .padding(PackWiseSpacing.comfortable)
            // Look Around snapshots carry Apple's Maps attribution in the
            // bottom-left corner. It is a licensing requirement and must not
            // be covered, so the trip text clears it.
            .padding(.bottom, PackWiseSpacing.loose)
        }
        .overlay(alignment: .top) {
            // Keeps the back button legible over a bright image.
            LinearGradient(
                colors: [.black.opacity(0.35), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 110)
            .allowsHitTesting(false)
        }
    }

    private var dateLine: String {
        let start = trip.startDate.formatted(.dateTime.month(.abbreviated).day())
        let end = trip.endDate.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end) · \(trip.durationDays) days"
    }

    // MARK: - Progress

    private var progress: some View {
        PackWiseCard {
            ProgressSummary(packed: trip.packedCount, total: trip.items.count)
        }
    }

    // MARK: - Weather

    @ViewBuilder
    private var weather: some View {
        if let snapshot = weatherSnapshot, snapshot.state() != .unavailable {
            PackWiseCard {
                VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
                    HStack(alignment: .top, spacing: PackWiseSpacing.regular) {
                        Image(systemName: snapshot.headlineSymbol(rainThreshold: weatherThresholds.rainProbabilityAdd))
                            .font(.title)
                            .symbolRenderingMode(.multicolor)
                        VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                            if snapshot.isPreciseForecast {
                                Text(snapshot.highLowLabel(usesFahrenheit: usesFahrenheit))
                                    .font(.title3.weight(.semibold))
                            }
                            if let detail = snapshot.detailLine(rainThreshold: weatherThresholds.rainProbabilityAdd) {
                                Text(detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !snapshot.dailyForecast.isEmpty {
                        Divider()
                        WeatherStripView(
                            forecast: snapshot.dailyForecast,
                            usesFahrenheit: usesFahrenheit,
                            rainThreshold: weatherThresholds.rainProbabilityAdd
                        )
                    }

                    Divider()
                    HStack {
                        if affectedItemCount > 0 {
                            PackWiseStatusBadge(
                                title: affectedItemCount == 1
                                    ? "1 item affected"
                                    : "\(affectedItemCount) items affected",
                                symbol: "exclamationmark.circle"
                            )
                        }
                        Spacer()
                        viewWeatherLink
                    }

                    if snapshot.showsAppleWeatherAttribution, let attribution = snapshot.attribution {
                        WeatherAttributionFooter(attribution: attribution)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var viewWeatherLink: some View {
        if let snapshot = weatherSnapshot {
            NavigationLink {
                WeatherDetailView(
                    destinationName: trip.destinationDisplayName,
                    dateLine: dateLine,
                    weather: snapshot,
                    impacts: packingImpacts,
                    usesFahrenheit: usesFahrenheit,
                    rainThreshold: weatherThresholds.rainProbabilityAdd,
                    uvThreshold: weatherThresholds.uvAdd,
                    windThreshold: weatherThresholds.windMphAdd
                )
            } label: {
                HStack(spacing: PackWiseSpacing.hairline) {
                    Text("View Weather")
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline.weight(.medium))
            }
        }
    }

    @ViewBuilder
    private var weatherChanged: some View {
        if let proposal = pendingWeatherChange {
            PackWiseCard {
                WeatherChangedCard(proposal: proposal) {
                    reviewingWeatherChange = true
                }
            }
        }
    }

    @ViewBuilder
    private var impact: some View {
        if !packingImpacts.isEmpty {
            VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                PackWiseSectionHeader(title: "Packing Impact")
                PackWiseCard {
                    PackingImpactCard(impacts: packingImpacts, expandedID: $expandedImpactID)
                }
            }
        }
    }

    // MARK: - Packing

    private var categories: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            PackWiseSectionHeader(title: "Packing", trailing: "See All") {
                openList = PackingListDestination(category: nil)
            }
            PackWiseCard {
                VStack(spacing: 0) {
                    ForEach(Array(categorySummaries.enumerated()), id: \.element.category) { index, summary in
                        if index > 0 {
                            Divider().padding(.leading, PackWiseSize.badge + PackWiseSpacing.regular)
                        }
                        Button {
                            openList = PackingListDestination(category: summary.category)
                        } label: {
                            categoryRow(summary)
                        }
                        .buttonStyle(.plain)
                    }
                    if categorySummaries.isEmpty {
                        Text("No items yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .navigationDestination(item: $openList) { destination in
            PackingListView(trip: trip, focusedCategory: destination.category)
        }
    }

    private func categoryRow(_ summary: CategorySummary) -> some View {
        HStack(spacing: PackWiseSpacing.regular) {
            PackWiseIconBadge(
                symbol: summary.category.style.symbol,
                tint: summary.category.style.tint
            )
            Text(summary.category.title)
                .font(.body)
            Spacer(minLength: PackWiseSpacing.snug)
            Text("\(summary.packed) / \(summary.total)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, PackWiseSpacing.regular)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(summary.category.title), \(summary.packed) of \(summary.total) packed")
        .accessibilityAddTraits(.isButton)
    }

    private struct CategorySummary {
        var category: PackingCategory
        var packed: Int
        var total: Int
    }

    private var categorySummaries: [CategorySummary] {
        let order = PackingCategory.displayOrder(
            international: trip.contextChips.contains(.travelingInternationally) || isInternational,
            outdoor: trip.tripType == .outdoor
        )
        return order.compactMap { category in
            let items = trip.items.filter { $0.category == category }
            guard !items.isEmpty else { return nil }
            return CategorySummary(
                category: category,
                packed: items.filter(\.isPacked).count,
                total: items.count
            )
        }
    }

    private var isInternational: Bool {
        let home = preferenceRecords.first?.homeCountryCode ?? Locale.current.region?.identifier ?? "US"
        return trip.destinationCountryCode.uppercased() != home.uppercased()
    }

    // MARK: - Weather plumbing

    private var weatherSnapshot: TripWeatherContext? {
        trip.weatherSnapshots.first?.weatherContext
    }

    private var packingImpacts: [PackingImpact] {
        PackingImpactBuilder.build(
            items: trip.items.map(\.draft),
            party: trip.party,
            signalAdds: dependencies.rules.weather.signalAdds,
            templates: dependencies.rules.reasons.templates
        )
    }

    private var affectedItemCount: Int {
        Set(packingImpacts.flatMap { $0.affectedItems.map(\.id) }).count
    }

    private var usesFahrenheit: Bool {
        preferenceRecords.first?.usesFahrenheit ?? true
    }

    private var weatherThresholds: WeatherThresholds {
        dependencies.rules.weather.thresholds
    }

    private var pendingWeatherChange: WeatherChangeProposal? {
        let signature = WeatherChangeProposalLifecycle.tripContextSignature(
            trip.context(
                preferences: preferenceRecords.first?.preferences ?? .deviceDefaults(),
                weather: nil
            )
        )
        return trip.weatherChangeProposals
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap(\.proposal)
            .first { $0.status == .pending }
            .flatMap { proposal in
                WeatherChangeProposalLifecycle.actionable(
                    proposal,
                    tripContextSignature: signature,
                    existing: trip.items.map(\.draft),
                    overrides: trip.overrides.map(\.draft)
                )
            }
    }

    private func refreshWeather() async {
        guard !isRefreshingWeather else { return }
        isRefreshingWeather = true
        defer { isRefreshingWeather = false }
        let repository = TripRepository(context: modelContext)
        repository.syncPendingWeatherChange(on: trip)
        await TripWeatherRefresh.run(
            trip: trip,
            preferences: preferenceRecords.first?.preferences ?? .deviceDefaults(),
            weatherService: dependencies.weatherService,
            engine: dependencies.engine,
            rules: dependencies.rules,
            repository: repository
        )
    }

    private func setWeatherChangeStatus(_ proposal: WeatherChangeProposal, _ status: WeatherChangeProposalStatus) {
        var updated = proposal
        updated.status = status
        let repository = TripRepository(context: modelContext)
        repository.updateWeatherChange(updated, on: trip)
        try? modelContext.save()
    }

    private func completeTrip() {
        TripRepository(context: modelContext).complete(trip)
        try? modelContext.save()
    }
}

/// Navigation payload so both "See All" and a category row reach the same
/// screen, differing only in where it opens.
struct PackingListDestination: Hashable, Identifiable {
    var category: PackingCategory?
    var id: String { category?.rawValue ?? "all" }
}
