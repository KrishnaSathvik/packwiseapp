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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Query private var preferenceRecords: [PackingPreferenceRecord]

    @State private var expandedImpactID: String?
    @State private var reviewingWeatherChange = false
    @State private var isRefreshingWeather = false
    @State private var editing = false
    @State private var openList: PackingListDestination?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: PackWiseSpacing.loose) {
                    progress
                    weatherChanged
                    weather
                    impact
                    categories
                }
                .padding(.horizontal, PackWiseSpacing.comfortable)
                // The progress card overlaps the hero's bottom edge, which is
                // what stitches the photo and the content into one screen.
                .padding(.top, -PackWiseSpacing.loose)
            }
            .padding(.bottom, PackWiseSpacing.section)
        }
        .ignoresSafeArea(edges: .top)
        .background(PackWiseColor.screen)
        .navigationBarTitleDisplayMode(.inline)
        // A pushed screen with a full-bleed hero. The root tabs floating over
        // it belong to the root experience, not to one trip.
        .toolbar(.hidden, for: .tabBar)
        // Circular translucent chrome over the photo, in place of the
        // default bar buttons.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    heroChromeCircle("chevron.left")
                }
                .accessibilityLabel("Back")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit Trip") { editing = true }
                    if trip.status != .completed && trip.status != .archived {
                        Button("Complete Trip") { completeTrip() }
                    }
                } label: {
                    heroChromeCircle("ellipsis")
                }
                .accessibilityLabel("Trip options")
            }
        }
        .fullScreenCover(isPresented: $editing) {
            TripSetupView(existingTrip: trip)
        }
        // A pushed screen, not a bottom sheet — reviewing a proposal is a
        // full job with three sections and a decision at the end.
        .navigationDestination(isPresented: $reviewingWeatherChange) {
            if let proposal = pendingWeatherChange {
                RecommendationDiffScreen(
                    diff: proposal.diff,
                    trip: trip,
                    trigger: proposal.headline,
                    signalChanges: proposal.signalChanges,
                    onKeep: { setWeatherChangeStatus(proposal, .dismissed) },
                    onUpdate: { setWeatherChangeStatus(proposal, .applied) },
                    onFinished: { reviewingWeatherChange = false }
                )
            }
        }
        .task {
            guard !isFinished else { return }
            await refreshWeather()
        }
        .onChange(of: scenePhase) { _, phase in
            guard !isFinished, phase == .active else { return }
            Task { await refreshWeather() }
        }
    }

    // MARK: - Hero

    private func heroChromeCircle(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(.black.opacity(0.3), in: Circle())
    }

    private var hero: some View {
        DestinationVisualView(
            destination: trip.destination,
            purpose: .tripHero,
            overlaysText: true
        )
        .frame(height: PackWiseSize.heroHeight)
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: PackWiseSpacing.tight) {
                if isFinished {
                    PackWiseStatusBadge(
                        title: "Completed",
                        symbol: "checkmark.circle.fill",
                        tint: PackWiseColor.success,
                        style: .onPhoto
                    )
                }
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
            // be covered, so the trip text clears it — and clears the
            // progress card overlapping the hero's bottom edge.
            .padding(.bottom, PackWiseSpacing.section + PackWiseSpacing.snug)
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

    /// A finished trip is a record, not a task: no weather proposal, and the
    /// progress block reads as a result rather than something to act on.
    private var isFinished: Bool {
        trip.status == .completed || trip.status == .archived
    }

    private var dateLine: String {
        let start = trip.startDate.formatted(.dateTime.month(.abbreviated).day())
        let end = trip.endDate.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end) · \(trip.durationDays) days"
    }

    // MARK: - Progress

    @ViewBuilder
    private var progress: some View {
        if isFinished {
            PackWiseCard {
                HStack(spacing: PackWiseSpacing.regular) {
                    PackWiseIconBadge(symbol: "checkmark.seal", tint: PackWiseColor.success)
                    VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                        Text("Trip complete")
                            .font(.headline)
                        Text("\(trip.packedCount) of \(trip.items.count) packed")
                            .font(.subheadline)
                            .foregroundStyle(PackWiseColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        } else {
            PackWiseCard {
                ProgressSummary(packed: trip.packedCount, total: trip.items.count)
            }
        }
    }

    // MARK: - Weather

    /// Weather is half of what PackWise promises, so this surface is always
    /// drawn.
    ///
    /// It used to render only when a precise forecast existed, which meant a
    /// trip far enough out — or one whose forecast had not landed yet — showed
    /// no weather at all and Trip Detail read as a checklist screen with a
    /// photo on top. Having no forecast yet is a state worth designing, not a
    /// reason to remove the section.
    private var weather: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            PackWiseSectionHeader(title: "Weather", style: .micro)
            PackWiseCard {
                if let snapshot = weatherSnapshot, snapshot.isPreciseForecast {
                    forecastWeather(snapshot)
                } else {
                    pendingWeather(weatherSnapshot)
                }
            }
        }
    }

    private func forecastWeather(_ snapshot: TripWeatherContext) -> some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
            HStack(alignment: .center, spacing: PackWiseSpacing.regular) {
                Image(systemName: snapshot.headlineSymbol(rainThreshold: weatherThresholds.rainProbabilityAdd))
                    .font(.system(size: 34))
                    .weatherGlyphStyle(snapshot.headlineSymbol(rainThreshold: weatherThresholds.rainProbabilityAdd))
                    .frame(width: 42)
                VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                    Text(snapshot.highLowLabel(usesFahrenheit: usesFahrenheit))
                        .font(.title.weight(.semibold))
                        .monospacedDigit()
                    if let detail = snapshot.detailLine(rainThreshold: weatherThresholds.rainProbabilityAdd) {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(PackWiseColor.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if !snapshot.dailyForecast.isEmpty {
                PackWiseRowDivider(inset: 0)
                WeatherStripView(
                    forecast: snapshot.dailyForecast,
                    usesFahrenheit: usesFahrenheit,
                    rainThreshold: weatherThresholds.rainProbabilityAdd
                )
            }

            PackWiseRowDivider(inset: 0)
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

    /// Seasonal, partial, or nothing yet — drawn in the shape of the forecast
    /// it will become, so the section never blinks out of the screen.
    private func pendingWeather(_ snapshot: TripWeatherContext?) -> some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
            HStack(alignment: .top, spacing: PackWiseSpacing.regular) {
                PackWiseIconBadge(symbol: "calendar", tint: PackWiseColor.accent, size: 42)
                VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                    Text("Forecast closer to departure")
                        .font(.headline)
                    Text(pendingWeatherDetail(snapshot))
                        .font(.subheadline)
                        .foregroundStyle(PackWiseColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            // A partial forecast still has days worth showing.
            if let snapshot, !snapshot.dailyForecast.isEmpty {
                PackWiseRowDivider(inset: 0)
                WeatherStripView(
                    forecast: snapshot.dailyForecast,
                    usesFahrenheit: usesFahrenheit,
                    rainThreshold: weatherThresholds.rainProbabilityAdd
                )
                PackWiseRowDivider(inset: 0)
                HStack {
                    Spacer()
                    viewWeatherLink
                }
            }
        }
    }

    private func pendingWeatherDetail(_ snapshot: TripWeatherContext?) -> String {
        guard let snapshot else {
            return "Your list currently uses seasonal conditions for \(trip.destinationDisplayName)."
        }
        return snapshot.coverageCopy
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
        if !isFinished, let proposal = pendingWeatherChange {
            PackWiseCard {
                WeatherChangedCard(proposal: proposal) {
                    reviewingWeatherChange = true
                }
            }
        }
    }

    @ViewBuilder
    private var impact: some View {
        // Packing Impact reads in the present tense — "rain expected" — which
        // is wrong on a trip that has already happened.
        if !isFinished, !packingImpacts.isEmpty {
            VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                PackWiseSectionHeader(title: "Packing Impact", style: .micro)
                PackWiseCard {
                    PackingImpactCard(impacts: packingImpacts, expandedID: $expandedImpactID)
                }
            }
        }
    }

    // MARK: - Packing

    private var categories: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            PackWiseSectionHeader(title: "Packing", style: .micro, trailing: "See All") {
                openList = PackingListDestination(category: nil)
            }
            PackWiseCard {
                VStack(spacing: 0) {
                    // Every category with progress — the overview does not
                    // truncate; "See All" is the full-checklist path.
                    ForEach(Array(categorySummaries.enumerated()), id: \.element.category) { index, summary in
                        if index > 0 {
                            PackWiseRowDivider()
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
                            .foregroundStyle(PackWiseColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .navigationDestination(item: $openList) { destination in
            PackingListView(trip: trip, focusedCategory: destination.category)
        }
    }

    /// The board draws each category with its own short bar, not just a
    /// fraction — the bar is what makes the block scannable at a glance,
    /// which a column of "4 / 6" is not.
    private func categoryRow(_ summary: CategorySummary) -> some View {
        HStack(spacing: PackWiseSpacing.regular) {
            PackWiseIconBadge(
                symbol: summary.category.style.symbol,
                tint: summary.category.style.tint
            )
            Text(summary.category.title)
                .font(.body)
                .lineLimit(1)
            Spacer(minLength: PackWiseSpacing.snug)
            Text("\(summary.packed) / \(summary.total)")
                .font(.subheadline)
                .foregroundStyle(PackWiseColor.textSecondary)
                .monospacedDigit()
            PackWiseProgressBar(
                fraction: summary.total == 0 ? 0 : Double(summary.packed) / Double(summary.total),
                tint: PackWiseColor.success,
                height: 6
            )
            .frame(width: 52)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PackWiseColor.textTertiary)
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
