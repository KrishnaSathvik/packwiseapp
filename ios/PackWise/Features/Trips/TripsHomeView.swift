import SwiftData
import SwiftUI

struct TripsHomeView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.destinationVisuals) private var destinationVisuals
    @Query(sort: \TripRecord.startDate) private var trips: [TripRecord]
    @Query private var preferenceRecords: [PackingPreferenceRecord]
    @State private var creating = false
    @State private var path = NavigationPath()
    @State private var createdTripID: UUID?

    private var upcoming: [TripRecord] {
        trips.filter { $0.status != .completed && $0.status != .archived }
    }

    private var past: [TripRecord] {
        trips.filter { $0.status == .completed || $0.status == .archived }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if upcoming.isEmpty && past.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("PackWise")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        creating = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New Trip")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let trip = trips.first(where: { $0.id == id }) {
                    TripDetailView(trip: trip)
                }
            }
            .sheet(isPresented: $creating, onDismiss: openCreatedTripIfNeeded) {
                NavigationStack {
                    TripSetupView { tripID in
                        createdTripID = tripID
                    }
                }
            }
            .task(id: trips.count) { await prewarmVisuals() }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PackWiseSpacing.loose) {
                if !upcoming.isEmpty {
                    section(title: "Upcoming") {
                        ForEach(upcoming, id: \.id) { trip in
                            NavigationLink(value: trip.id) {
                                UpcomingTripCard(
                                    trip: trip,
                                    usesFahrenheit: preferenceRecords.first?.usesFahrenheit ?? true,
                                    rainThreshold: dependencies.rules.weather.thresholds.rainProbabilityAdd
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !past.isEmpty {
                    section(title: "Past Trips") {
                        PackWiseCard {
                            VStack(spacing: 0) {
                                ForEach(Array(past.enumerated()), id: \.element.id) { index, trip in
                                    if index > 0 {
                                        Divider()
                                            .padding(.leading, PackWiseSize.tripThumbnail * 0.6 + PackWiseSpacing.regular)
                                    }
                                    NavigationLink(value: trip.id) {
                                        PastTripRow(trip: trip)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .padding(PackWiseSpacing.comfortable)
        }
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            PackWiseSectionHeader(title: title)
            content()
        }
    }

    /// Destination imagery is fetched as soon as the trips are known, so
    /// opening one does not wait on the network.
    private func prewarmVisuals() async {
        for trip in trips.prefix(8) {
            await destinationVisuals.prewarm(
                trip.destination,
                purposes: [.tripThumbnail, .tripHero]
            )
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No trips yet", systemImage: "suitcase")
        } description: {
            Text("Tell PackWise where you're going and it will build a list for this trip — not every trip.")
        } actions: {
            Button("New Trip") { creating = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private func openCreatedTripIfNeeded() {
        guard let id = createdTripID else { return }
        createdTripID = nil
        path.append(id)
    }
}

/// A trip card: compact destination thumbnail, when, what the weather will
/// do, and how far along. The board uses a small tile here rather than a hero
/// — density comes from the imagery being small, not from dropping it.
struct UpcomingTripCard: View {
    let trip: TripRecord
    var usesFahrenheit: Bool
    var rainThreshold: Double

    private var weather: TripWeatherContext? {
        guard let context = trip.weatherSnapshots.first?.weatherContext,
              context.isPreciseForecast else { return nil }
        return context
    }

    /// A generated list nobody has started yet. A progress bar reading zero
    /// says less here than simply saying the list is waiting.
    private var listReady: Bool {
        !trip.items.isEmpty && trip.packedCount == 0
    }

    var body: some View {
        PackWiseCard {
            VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
                HStack(alignment: .top, spacing: PackWiseSpacing.regular) {
                    DestinationVisualView(destination: trip.destination, purpose: .tripThumbnail)
                        .frame(width: PackWiseSize.tripThumbnail, height: PackWiseSize.tripThumbnail)
                        .clipShape(RoundedRectangle(cornerRadius: PackWiseRadius.control, style: .continuous))

                    VStack(alignment: .leading, spacing: PackWiseSpacing.tight) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(trip.destinationDisplayName)
                                .font(.title3.weight(.semibold))
                            Spacer(minLength: PackWiseSpacing.snug)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        Text(dateLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let weather {
                            HStack(spacing: PackWiseSpacing.tight) {
                                Image(systemName: weather.headlineSymbol(rainThreshold: rainThreshold))
                                    .symbolRenderingMode(.multicolor)
                                if let detail = weather.detailLine(rainThreshold: rainThreshold) {
                                    Text("\(weather.highLowLabel(usesFahrenheit: usesFahrenheit)) · \(detail)")
                                } else {
                                    Text(weather.highLowLabel(usesFahrenheit: usesFahrenheit))
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        if listReady {
                            PackWiseStatusBadge(title: "Packing list ready", symbol: "checkmark")
                        }
                    }
                }

                if trip.packedCount > 0 {
                    Divider()
                    ProgressSummary(packed: trip.packedCount, total: trip.items.count)
                }

                if let weather, weather.showsAppleWeatherAttribution, let attribution = weather.attribution {
                    WeatherAttributionFooter(attribution: attribution)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var dateLine: String {
        let start = trip.startDate.formatted(.dateTime.month(.abbreviated).day())
        let end = trip.endDate.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end) · \(trip.durationDays) days"
    }
}

struct PastTripRow: View {
    let trip: TripRecord

    var body: some View {
        HStack(spacing: PackWiseSpacing.regular) {
            DestinationVisualView(destination: trip.destination, purpose: .tripThumbnail)
                .frame(width: PackWiseSize.tripThumbnail * 0.6, height: PackWiseSize.tripThumbnail * 0.6)
                .clipShape(RoundedRectangle(cornerRadius: PackWiseRadius.badge, style: .continuous))

            VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                Text(trip.destinationDisplayName)
                    .font(.headline)
                Text(dateLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: PackWiseSpacing.snug)
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
        }
        .padding(.vertical, PackWiseSpacing.snug)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(trip.destinationDisplayName), \(dateLine), completed")
        .accessibilityAddTraits(.isButton)
    }

    private var dateLine: String {
        let start = trip.startDate.formatted(.dateTime.month(.abbreviated).day())
        let end = trip.endDate.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end)"
    }
}
