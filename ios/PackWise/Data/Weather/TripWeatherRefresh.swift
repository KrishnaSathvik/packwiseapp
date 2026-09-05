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
            #if DEBUG
            await Self.recordSkippedFetch(trip: trip, cached: cached, now: now)
            #endif
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
        #if DEBUG
        await Self.commitDiagnostics(trip: trip, cached: cached, resolved: resolved, now: now)
        #endif
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

    #if DEBUG
    /// The refresh policy declined to fetch — an existing cache is still
    /// valid, or the trip's status excludes weather. No provider call was
    /// made, so this is recorded directly rather than staged by the
    /// service layer.
    @MainActor
    private static func recordSkippedFetch(trip: TripRecord, cached: TripWeatherContext?, now: Date) async {
        let calendar = WeatherForecastNormalizer.calendar(for: trip.destination)
        let bounds = WeatherForecastNormalizer.queryBounds(start: trip.startDate, end: trip.endDate, calendar: calendar)
        let entry = WeatherRequestDiagnostics(
            recordedAt: now,
            destinationName: trip.destination.displayName,
            destinationLatitude: trip.destination.latitude,
            destinationLongitude: trip.destination.longitude,
            destinationTimeZoneIdentifier: trip.destination.timeZone,
            deviceTimeZoneIdentifier: TimeZone.current.identifier,
            deviceCalendarIdentifier: String(describing: Calendar.current.identifier),
            bounds: WeatherRequestDiagnostics.DateBounds(
                requestedStart: trip.startDate,
                requestedEnd: trip.endDate,
                normalizedStart: bounds.start,
                normalizedEndExclusive: bounds.endExclusive
            ),
            fetchAttempted: false,
            skipReason: "WeatherRefreshPolicy.shouldFetch declined (trip status \(trip.status.rawValue), existing cache still valid, or archived/completed)",
            provider: nil,
            normalization: nil,
            cache: WeatherRequestDiagnostics.CacheDecision(
                hit: cached != nil,
                ageSeconds: cached.map { now.timeIntervalSince($0.fetchedAt) },
                coverageStart: cached?.coverageStart,
                coverageEnd: cached?.coverageEnd,
                selectedAsFinal: cached != nil
            ),
            finalState: cached?.state(now: now) ?? .unavailable,
            engineReceivedPreciseWeather: cached?.isPreciseForecast ?? false
        )
        await WeatherRequestDiagnosticsStore.shared.recordSkippedFetch(entry)
    }

    /// Merges the cache decision and the engine's final consumption of the
    /// resolved weather onto whatever `WeatherKitWeatherService.availability`
    /// staged for this same destination/date bounds during `resolve` above.
    @MainActor
    private static func commitDiagnostics(
        trip: TripRecord,
        cached: TripWeatherContext?,
        resolved: ResolvedTripWeather,
        now: Date
    ) async {
        let cacheDecision = WeatherRequestDiagnostics.CacheDecision(
            hit: cached != nil,
            ageSeconds: cached.map { now.timeIntervalSince($0.fetchedAt) },
            coverageStart: cached?.coverageStart,
            coverageEnd: cached?.coverageEnd,
            selectedAsFinal: resolved.snapshot?.source == .cache
        )
        await WeatherRequestDiagnosticsStore.shared.commit(
            matchingDestination: trip.destination.displayName,
            requestedStart: trip.startDate,
            requestedEnd: trip.endDate,
            cache: cacheDecision,
            finalState: resolved.state,
            engineReceivedPreciseWeather: resolved.engineWeather != nil
        )
    }
    #endif
}
