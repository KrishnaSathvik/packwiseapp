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

    private var active: [TripRecord] {
        trips.filter { $0.status != .completed && $0.status != .archived }
    }

    /// A trip happening now — its date range contains today. Being on a trip
    /// is a different mental state from preparing for one, so it sorts to the
    /// top in its own section.
    private var current: [TripRecord] {
        let today = Calendar.current.startOfDay(for: .now)
        return active.filter {
            Calendar.current.startOfDay(for: $0.startDate) <= today
                && today <= Calendar.current.startOfDay(for: $0.endDate)
        }
    }

    private var upcoming: [TripRecord] {
        let currentIDs = Set(current.map(\.id))
        return active.filter { !currentIDs.contains($0.id) }
    }

    private var past: [TripRecord] {
        trips.filter { $0.status == .completed || $0.status == .archived }
    }

    private var isEmpty: Bool {
        current.isEmpty && upcoming.isEmpty && past.isEmpty
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .background(PackWiseColor.screen)
            .navigationTitle("PackWise")
            .toolbar {
                // In the empty state the invitation below is the one action;
                // a second + in the corner would compete with it.
                if !isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            creating = true
                        } label: {
                            // A solid blue disc with a white plus — the sheet
                            // never inverts this button.
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(PackWiseColor.onAccent)
                                .frame(width: 32, height: 32)
                                .background(PackWiseColor.accent, in: Circle())
                        }
                        .accessibilityLabel("New Trip")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let trip = trips.first(where: { $0.id == id }) {
                    TripDetailView(trip: trip)
                }
            }
            // The primary flow deserves the whole screen — a sheet leaves the
            // parent bleeding through behind an eight-step wizard.
            .fullScreenCover(isPresented: $creating, onDismiss: openCreatedTripIfNeeded) {
                TripSetupView { tripID in
                    createdTripID = tripID
                }
            }
            .task(id: trips.count) { await prewarmVisuals() }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PackWiseSpacing.loose) {
                if !current.isEmpty {
                    section(title: "Current") {
                        tripCards(current, heroFirst: true)
                    }
                }

                if !upcoming.isEmpty {
                    section(title: "Upcoming") {
                        // The trip in progress owns the hero when there is
                        // one; otherwise the next trip is the hero.
                        tripCards(upcoming, heroFirst: current.isEmpty)
                    }
                }

                if !past.isEmpty {
                    section(title: "Past Trips") {
                        ForEach(past, id: \.id) { trip in
                            NavigationLink(value: trip.id) {
                                CompactTripCard(
                                    trip: trip,
                                    usesFahrenheit: usesFahrenheit,
                                    rainThreshold: rainThreshold
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(PackWiseSpacing.comfortable)
        }
    }

    private var usesFahrenheit: Bool {
        preferenceRecords.first?.usesFahrenheit ?? true
    }

    private var rainThreshold: Double {
        dependencies.rules.weather.thresholds.rainProbabilityAdd
    }

    @ViewBuilder
    private func tripCards(_ trips: [TripRecord], heroFirst: Bool) -> some View {
        ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
            NavigationLink(value: trip.id) {
                if heroFirst && index == 0 {
                    HeroTripCard(
                        trip: trip,
                        usesFahrenheit: usesFahrenheit,
                        rainThreshold: rainThreshold
                    )
                } else {
                    CompactTripCard(
                        trip: trip,
                        usesFahrenheit: usesFahrenheit,
                        rainThreshold: rainThreshold
                    )
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
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

    /// Sits at roughly 40% of the screen, not centered in the full frame —
    /// centering left a void between the title and the content.
    private var emptyState: some View {
        GeometryReader { proxy in
            VStack(spacing: PackWiseSpacing.comfortable) {
                // A journey, not a lone briefcase: destination pin ahead,
                // luggage in hand, sun out.
                ZStack {
                    Circle()
                        .fill(PackWiseColor.accentWash)
                        .frame(width: 104, height: 104)
                    Image(systemName: "airplane.departure")
                        .font(.system(size: 40))
                        .foregroundStyle(PackWiseColor.accent)
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(PackWiseColor.important)
                        .offset(x: 44, y: -40)
                    Image(systemName: "suitcase.rolling.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(PackWiseColor.textSecondary)
                        .offset(x: -40, y: 40)
                }
                .accessibilityHidden(true)

                Text("No trips yet")
                    .font(PackWiseFont.cardTitle)
                    .foregroundStyle(PackWiseColor.textPrimary)
                Text("Tell PackWise where you're going and it will build a list for this trip — not every trip.")
                    .font(PackWiseFont.screenSubtitle)
                    .foregroundStyle(PackWiseColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, PackWiseSpacing.section)

                // A compact pill — an invitation, not a form submit.
                Button {
                    creating = true
                } label: {
                    Text("New Trip")
                        .font(PackWiseFont.button)
                        .foregroundStyle(PackWiseColor.onAccent)
                        .padding(.horizontal, PackWiseSpacing.section)
                        .frame(minHeight: PackWiseSize.buttonHeight)
                        .background(PackWiseColor.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, PackWiseSpacing.snug)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, proxy.size.height * 0.16)
        }
    }

    private func openCreatedTripIfNeeded() {
        guard let id = createdTripID else { return }
        createdTripID = nil
        path.append(id)
    }
}

/// The next upcoming trip: destination photo filling the top of the card,
/// city and dates overlaid in white, then weather, packed count, the green
/// bar, and the items-left pill.
struct HeroTripCard: View {
    let trip: TripRecord
    var usesFahrenheit: Bool
    var rainThreshold: Double

    private var forecast: TripWeatherContext? {
        guard let weather = trip.weatherSnapshots.first?.weatherContext,
              weather.isPreciseForecast else { return nil }
        return weather
    }

    /// A trip whose list has not been built yet.
    private var awaitingList: Bool { trip.items.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            DestinationVisualView(destination: trip.destination, purpose: .tripHero, overlaysText: true)
                .frame(height: PackWiseSize.tripCardPhotoHeight)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                        Text(trip.destinationDisplayName)
                            .font(.title3.weight(.semibold))
                        Text(dateLine)
                            .font(PackWiseFont.rowSubtitle)
                            .opacity(0.92)
                    }
                    .foregroundStyle(.white)
                    .padding(PackWiseSpacing.comfortable)
                }

            VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
                weatherRow

                if awaitingList {
                    PackWiseStatusBadge(title: "No items yet", symbol: "tray")
                } else {
                    // Packed count, percentage, the green bar, and items
                    // left — the hero always carries its progress block,
                    // even pinned at zero.
                    ProgressSummary(packed: trip.packedCount, total: trip.items.count)
                }

                if let forecast, forecast.showsAppleWeatherAttribution, let attribution = forecast.attribution {
                    WeatherAttributionFooter(attribution: attribution)
                }
            }
            .padding(PackWiseSpacing.comfortable)
        }
        .background(PackWiseColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: PackWiseRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PackWiseRadius.card, style: .continuous)
                .strokeBorder(PackWiseColor.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var weatherRow: some View {
        HStack(spacing: PackWiseSpacing.snug) {
            if let forecast {
                Image(systemName: forecast.headlineSymbol(rainThreshold: rainThreshold))
                    .font(.title3)
                    .weatherGlyphStyle(forecast.headlineSymbol(rainThreshold: rainThreshold))
                if let detail = forecast.detailLine(rainThreshold: rainThreshold) {
                    Text("\(forecast.highLowLabel(usesFahrenheit: usesFahrenheit)) · \(detail)")
                } else {
                    Text(forecast.highLowLabel(usesFahrenheit: usesFahrenheit))
                }
            } else {
                Image(systemName: "calendar")
                    .foregroundStyle(PackWiseColor.textSecondary)
                Text("Forecast closer to departure")
            }
            Spacer(minLength: PackWiseSpacing.snug)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PackWiseColor.textTertiary)
        }
        .font(.subheadline)
        .foregroundStyle(PackWiseColor.textSecondary)
    }

    private var dateLine: String {
        let start = trip.startDate.formatted(.dateTime.month(.abbreviated).day())
        let end = trip.endDate.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end) · \(trip.durationDays) days"
    }
}

/// Every other trip, upcoming or past: a 56pt photo thumbnail, the title and
/// dates, one status line, and a chevron.
struct CompactTripCard: View {
    let trip: TripRecord
    var usesFahrenheit: Bool
    var rainThreshold: Double

    private var isFinished: Bool {
        trip.status == .completed || trip.status == .archived
    }

    private var forecast: TripWeatherContext? {
        guard let weather = trip.weatherSnapshots.first?.weatherContext,
              weather.isPreciseForecast else { return nil }
        return weather
    }

    var body: some View {
        PackWiseCard {
            HStack(spacing: PackWiseSpacing.regular) {
                DestinationVisualView(destination: trip.destination, purpose: .tripThumbnail)
                    .frame(width: PackWiseSize.tripThumbnail, height: PackWiseSize.tripThumbnail)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: PackWiseSpacing.tight) {
                    Text(trip.destinationDisplayName)
                        .font(PackWiseFont.rowTitle)
                        .foregroundStyle(PackWiseColor.textPrimary)
                        .lineLimit(1)
                    Text(dateLine)
                        .font(PackWiseFont.rowSubtitle)
                        .foregroundStyle(PackWiseColor.textSecondary)
                    statusLine
                }
                Spacer(minLength: PackWiseSpacing.snug)
                if isFinished {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(PackWiseColor.success)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PackWiseColor.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusLine: some View {
        if isFinished {
            Text("Completed")
                .font(PackWiseFont.rowSubtitle.weight(.medium))
                .foregroundStyle(PackWiseColor.success)
        } else if trip.items.isEmpty {
            Text("No items yet")
                .font(PackWiseFont.rowSubtitle)
                .foregroundStyle(PackWiseColor.textSecondary)
        } else if trip.packedCount == 0 {
            Text("Packing list ready")
                .font(PackWiseFont.rowSubtitle.weight(.medium))
                .foregroundStyle(PackWiseColor.success)
        } else if let forecast {
            HStack(spacing: PackWiseSpacing.tight) {
                Image(systemName: forecast.headlineSymbol(rainThreshold: rainThreshold))
                    .font(.caption)
                    .weatherGlyphStyle(forecast.headlineSymbol(rainThreshold: rainThreshold))
                Text(forecast.highLowLabel(usesFahrenheit: usesFahrenheit))
            }
            .font(PackWiseFont.rowSubtitle)
            .foregroundStyle(PackWiseColor.textSecondary)
        } else {
            Text("\(trip.packedCount) of \(trip.items.count) packed")
                .font(PackWiseFont.rowSubtitle)
                .foregroundStyle(PackWiseColor.textSecondary)
        }
    }

    private var dateLine: String {
        let start = trip.startDate.formatted(.dateTime.month(.abbreviated).day())
        let end = trip.endDate.formatted(.dateTime.month(.abbreviated).day())
        return isFinished ? "\(start) – \(end)" : "\(start) – \(end) · \(trip.durationDays) days"
    }
}
