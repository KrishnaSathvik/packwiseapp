import SwiftData
import SwiftUI

struct TripsHomeView: View {
    @Environment(AppDependencies.self) private var dependencies
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
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if upcoming.isEmpty && past.isEmpty {
                        emptyState
                    }

                    if !upcoming.isEmpty {
                        Text("Upcoming")
                            .font(.title2.bold())
                        ForEach(upcoming, id: \.id) { trip in
                            NavigationLink(value: trip.id) {
                                UpcomingTripCard(
                                    trip: trip,
                                    usesFahrenheit: preferenceRecords.first?.usesFahrenheit ?? true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !past.isEmpty {
                        Text("Past Trips")
                            .font(.title2.bold())
                        ForEach(past, id: \.id) { trip in
                            NavigationLink(value: trip.id) {
                                PastTripRow(trip: trip)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
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
        }
    }

    private func openCreatedTripIfNeeded() {
        guard let id = createdTripID else { return }
        createdTripID = nil
        path.append(id)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No trips yet")
                .font(.title2.bold())
            Text("Tell PackWise where you're going and it will build a list for this trip — not every trip.")
                .foregroundStyle(.secondary)
            Button("New Trip") { creating = true }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.top, 24)
    }
}

struct UpcomingTripCard: View {
    let trip: TripRecord
    var usesFahrenheit: Bool

    var body: some View {
        PackWiseCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(trip.destinationDisplayName)
                    .font(.title3.bold())
                Text(dateLine)
                    .foregroundStyle(.secondary)
                if let weather = trip.weatherSnapshots.first?.weatherContext, weather.isPreciseForecast {
                    HStack {
                        Image(systemName: weather.dailyForecast.first?.symbol ?? "cloud.sun")
                        Text(weather.highLowLabel(usesFahrenheit: usesFahrenheit))
                        if weather.rainDays > 0 {
                            Text("Rain during the trip")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if weather.showsAppleWeatherAttribution, let attribution = weather.attribution {
                        WeatherAttributionFooter(attribution: attribution)
                    }
                }
                ProgressSummary(packed: trip.packedCount, total: trip.items.count)
            }
        }
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
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.destinationDisplayName).font(.headline)
                Text(trip.startDate.formatted(.dateTime.month(.abbreviated).day()) + " – " + trip.endDate.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Completed")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}
