#if DEBUG
import Foundation

/// Injects a materially different forecast so the weather-change path can be
/// exercised on demand.
///
/// Waiting for a real forecast to move is not a test. This goes through the
/// same seams `TripWeatherRefresh` uses — the bundled fixtures are normalized by
/// `MockWeatherService`, stored by the repository, and reconciled by
/// `WeatherChangeReconciler` — so what appears on screen is a real
/// `WeatherChangeProposal`, not fabricated UI state.
///
/// Debug builds only.
@MainActor
enum DebugWeatherInjection {
    struct Outcome: Sendable {
        var passed: Bool
        var detail: String
    }

    /// Fixtures whose packing signals differ enough to produce a proposal.
    enum Scenario: String, CaseIterable, Identifiable {
        case rain = "ChicagoRainyFall"
        case coldAndWindy = "ReykjavikColdWindy"
        case hotAndSunny = "MiamiHotBeach"
        case mild = "TokyoMildSpring"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .rain: "Meaningful rain"
            case .coldAndWindy: "Cold and windy"
            case .hotAndSunny: "Hot and sunny"
            case .mild: "Mild — clears signals"
            }
        }
    }

    static func inject(
        _ scenario: Scenario,
        trip: TripRecord,
        preferences: TravelerPreferences,
        engine: PackingEngine,
        rules: PackingRulesFile,
        repository: TripRepository,
        now: Date = .now
    ) async -> Outcome {
        guard let service = try? MockWeatherService.bundled() else {
            return Outcome(passed: false, detail: "bundled weather fixtures unavailable")
        }

        // Normalize through the real weather path rather than hand-building a
        // TripWeatherContext, so coverage and signals are derived the same way.
        var destination = trip.destination
        destination.fixtureID = scenario.rawValue
        let availability = await service.availability(
            for: destination,
            start: trip.startDate,
            end: trip.endDate
        )
        guard case .forecast(let injected) = availability else {
            return Outcome(passed: false, detail: "fixture \(scenario.rawValue) produced no forecast for these dates")
        }

        let cached = trip.weatherSnapshots.first?.weatherContext
        repository.storeWeather(injected, on: trip)
        repository.syncPendingWeatherChange(on: trip)

        var context = trip.context(preferences: preferences, weather: injected)
        context.party = trip.party

        let outcome = WeatherChangeReconciler.reconcile(
            tripID: trip.id,
            oldWeather: cached,
            newWeather: injected,
            context: context,
            existing: trip.items.map(\.draft),
            overrides: trip.overrides.map(\.draft),
            engine: engine,
            thresholds: rules.weather.thresholds,
            templates: rules.reasons.templates,
            now: now
        )

        switch outcome {
        case .proposal(let proposal):
            repository.replacePendingWeatherChange(proposal, on: trip)
            try? repository.save()
            return Outcome(
                passed: true,
                detail: """
                    proposal created — \(proposal.diff.add.count) addition(s), \
                    \(proposal.diff.removeCandidates.count) removal candidate(s), \
                    \(proposal.diff.quantityChanges.count) quantity change(s)
                    """
            )
        default:
            try? repository.save()
            return Outcome(
                passed: false,
                detail: "snapshot stored, but the signals did not differ enough to propose anything. Try a scenario further from the current forecast."
            )
        }
    }
}
#endif
