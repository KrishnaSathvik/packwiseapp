#if DEBUG
import Foundation

/// Injects a materially different forecast so the weather-change path can be
/// exercised on demand.
///
/// Waiting for a real forecast to move is not a test. This rebases a named
/// fixture's day templates onto the *target trip's own date range* — cycling
/// through the fixture's days in order so any trip length is covered — and
/// runs the result through the same normalization (`WeatherForecastNormalizer`)
/// and reconciliation (`WeatherChangeReconciler`) the live path uses, so what
/// appears on screen is a real `WeatherChangeProposal`, not fabricated UI
/// state. A trip's date range can never make injection fail — only a
/// missing/corrupt bundled fixture can — because the fixture supplies a
/// weather *pattern* (highs/lows/rain/etc. per day-of-trip), never absolute
/// dates.
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
        guard let fixture = (try? SharedLibrary.weatherFixtures())?[scenario.rawValue] else {
            return Outcome(passed: false, detail: "bundled weather fixtures unavailable")
        }
        guard !fixture.days.isEmpty else {
            return Outcome(passed: false, detail: "fixture \(scenario.rawValue) has no day templates")
        }

        let injected = rebase(fixture, onto: trip, now: now)
        await recordDiagnostics(scenario: scenario, trip: trip, injected: injected, now: now)

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

    /// Rebases a named fixture's local day templates onto the target trip's
    /// own date range and runs the result through the real normalization
    /// path (`WeatherForecastNormalizer.context`), so coverage/precision/
    /// summary derive exactly the way a live fetch's days would. The
    /// fixture's own day count never has to match the trip's length: day
    /// templates cycle in order, matching how `MockWeatherService` always
    /// treated a fixture as a repeatable pattern rather than a fixed
    /// calendar.
    static func rebase(_ fixture: WeatherFixture, onto trip: TripRecord, now: Date) -> TripWeatherContext {
        let calendar = WeatherForecastNormalizer.calendar(for: trip.destination)
        let tripDays = WeatherForecastNormalizer.tripDays(start: trip.startDate, end: trip.endDate, calendar: calendar)
        let days: [DailyForecast] = tripDays.enumerated().map { index, tripDay in
            let template = fixture.days[index % fixture.days.count]
            return DailyForecast(
                date: calendar.startOfDay(for: tripDay),
                symbol: template.symbol,
                highF: template.highF,
                lowF: template.lowF,
                rainProbability: template.rainProbability,
                uvIndex: template.uvIndex,
                windMph: template.windMph,
                snowExpected: template.snowExpected,
                summary: template.summary
            )
        }
        return WeatherForecastNormalizer.context(
            days: days,
            tripStart: trip.startDate,
            tripEnd: trip.endDate,
            fetchedAt: now,
            providerFetchedAt: now,
            providerExpiresAt: calendar.date(byAdding: .hour, value: 1, to: now),
            source: .fixture,
            fixtureID: fixture.id,
            calendar: calendar
        )
    }

    /// Injection never calls the live provider, so it never goes through
    /// `WeatherKitWeatherService`'s stage/commit sequence — this records a
    /// complete entry directly so injected scenarios show up in the same
    /// Developer Tools diagnostics log as live refreshes.
    private static func recordDiagnostics(scenario: Scenario, trip: TripRecord, injected: TripWeatherContext, now: Date) async {
        let calendar = WeatherForecastNormalizer.calendar(for: trip.destination)
        let bounds = WeatherForecastNormalizer.queryBounds(start: trip.startDate, end: trip.endDate, calendar: calendar)
        let tripDays = WeatherForecastNormalizer.tripDays(start: trip.startDate, end: trip.endDate, calendar: calendar)
        let covered = Set(injected.dailyForecast.map { calendar.startOfDay(for: $0.date) })
        let uncovered = tripDays.map { calendar.startOfDay(for: $0) }.filter { !covered.contains($0) }
        let entry = WeatherRequestDiagnostics(
            recordedAt: now,
            origin: .fixtureInjection(fixtureID: scenario.rawValue),
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
            fetchAttempted: true,
            // Not a skipped/declined live fetch — `origin` above already
            // says this came from Debug fixture injection.
            skipReason: nil,
            provider: WeatherRequestDiagnostics.ProviderResult(
                kind: .success,
                returnedDayCount: injected.dailyForecast.count,
                returnedCoverageStart: injected.coverageStart,
                returnedCoverageEnd: injected.coverageEnd,
                providerFetchedAt: injected.providerFetchedAt,
                providerExpiresAt: injected.providerExpiresAt,
                errorDomain: nil,
                errorCode: nil
            ),
            normalization: WeatherRequestDiagnostics.NormalizationResult(
                preciseCoveredDates: injected.dailyForecast.map(\.date),
                seasonalUncoveredDates: uncovered,
                forecastAvailableForWholeTrip: injected.forecastAvailableForWholeTrip,
                forecastAvailableForPartialTrip: injected.forecastAvailableForPartialTrip,
                isPreciseForecast: injected.isPreciseForecast
            ),
            cache: nil,
            finalState: injected.state(now: injected.fetchedAt),
            engineReceivedPreciseWeather: injected.isPreciseForecast
        )
        await WeatherRequestDiagnosticsStore.shared.record(entry)
    }
}
#endif
