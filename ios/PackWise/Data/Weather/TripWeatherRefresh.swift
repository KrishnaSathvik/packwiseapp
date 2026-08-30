import Foundation
import SwiftData

enum TripWeatherRefresh {
    @MainActor
    static func run(
        trip: TripRecord,
        preferences: TravelerPreferences,
        weatherService: any WeatherService,
        engine: PackingEngine,
        rules: PackingRulesFile,
        repository: TripRepository,
        now: Date = .now
    ) async {
        let cached = trip.weatherSnapshots.first?.weatherContext
        repository.syncPendingWeatherChange(on: trip)
        guard WeatherRefreshPolicy.shouldFetch(
            existing: cached,
            tripStart: trip.startDate,
            tripStatus: trip.status,
            now: now
        ) else {
            try? repository.save()
            return
        }

        let resolved = await TripWeatherResolver.resolve(
            using: weatherService,
            destination: trip.destination,
            start: trip.startDate,
            end: trip.endDate,
            cached: cached,
            now: now
        )
        guard let snapshot = resolved.snapshot else { return }
        repository.storeWeather(snapshot, on: trip)
        repository.syncPendingWeatherChange(on: trip)

        var context = trip.context(preferences: preferences, weather: snapshot)
        context.party = trip.party
        let outcome = WeatherChangeReconciler.reconcile(
            tripID: trip.id,
            oldWeather: cached,
            newWeather: snapshot,
            context: context,
            existing: trip.items.map(\.draft),
            overrides: trip.overrides.map(\.draft),
            engine: engine,
            thresholds: rules.weather.thresholds,
            templates: rules.reasons.templates,
            now: now
        )
        if case .proposal(let proposal) = outcome {
            repository.replacePendingWeatherChange(proposal, on: trip)
        }
        try? repository.save()
    }
}
