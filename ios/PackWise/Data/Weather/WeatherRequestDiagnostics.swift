import Foundation

#if DEBUG
/// Debug-only evidence for one WeatherKit refresh attempt.
///
/// This exists because the only way to tell "WeatherKit genuinely has no
/// forecast for this trip" apart from "our own date math missed it" is to
/// see the raw request/response boundary. The UI must never guess between
/// those from absence alone, so this captures the boundary explicitly:
/// destination and device timezones, the dates actually sent to the
/// provider, what the provider actually returned, how normalization
/// matched that against the trip's own days, the cache decision, and the
/// final state the packing engine consumed.
///
/// No user-authored text (trip notes, custom item names, search queries)
/// is ever captured here — only coordinates, a curated destination name
/// from the destination catalog, dates, timezone identifiers, and
/// pipeline-internal enums. `WeatherRequestDiagnosticsTests` pins that
/// boundary.
///
/// Every producer and consumer of this type — this file included — lives
/// behind `#if DEBUG`, so the whole mechanism compiles out of Release,
/// TestFlight, and App Store builds.
struct WeatherRequestDiagnostics: Sendable, Equatable, Identifiable {
    struct DateBounds: Sendable, Equatable {
        /// What the caller asked for — `TripRecord.startDate`/`endDate`,
        /// unmodified.
        var requestedStart: Date
        var requestedEnd: Date
        /// What was actually sent to the provider: the destination-
        /// timezone start of the start day, and the destination-timezone
        /// exclusive end (one day past the start of the end day) — the
        /// exact bounds `LiveWeatherKitClient` and `WeatherForecastNormalizer`
        /// agree on via `WeatherForecastNormalizer.queryBounds`.
        var normalizedStart: Date
        var normalizedEndExclusive: Date
    }

    struct ProviderResult: Sendable, Equatable {
        enum Kind: String, Sendable {
            case success
            case thrown
        }
        var kind: Kind
        var returnedDayCount: Int
        var returnedCoverageStart: Date?
        var returnedCoverageEnd: Date?
        var providerFetchedAt: Date?
        var providerExpiresAt: Date?
        /// Populated only when `kind == .thrown`. `NSError` domain/code is
        /// generic enough to capture any thrown error (WeatherKit's typed
        /// errors included) without this Domain-layer-adjacent file
        /// importing WeatherKit.
        var errorDomain: String?
        var errorCode: Int?
    }

    struct NormalizationResult: Sendable, Equatable {
        /// Trip days normalization matched to a returned provider day,
        /// in the destination calendar.
        var preciseCoveredDates: [Date]
        /// Trip days with no matching provider day — the ones that fall
        /// back to seasonal/partial treatment.
        var seasonalUncoveredDates: [Date]
        var forecastAvailableForWholeTrip: Bool
        var forecastAvailableForPartialTrip: Bool
        var isPreciseForecast: Bool
    }

    /// Where this entry's weather came from. Kept distinct from
    /// `skipReason` (which only ever describes a *live* fetch that was
    /// skipped or declined) so a Debug fixture injection — which always has
    /// `fetchAttempted == true` because it always produces data — never has
    /// to overload `skipReason` to say so.
    enum Origin: Sendable, Equatable {
        case live
        case fixtureInjection(fixtureID: String)
    }

    struct CacheDecision: Sendable, Equatable {
        var hit: Bool
        var ageSeconds: Double?
        var coverageStart: Date?
        var coverageEnd: Date?
        /// True when the resolved snapshot actually shown to the user
        /// came from this cache rather than a fresh provider fetch.
        var selectedAsFinal: Bool
    }

    var id = UUID()
    var recordedAt: Date
    var origin: Origin

    var destinationName: String
    var destinationLatitude: Double
    var destinationLongitude: Double
    var destinationTimeZoneIdentifier: String

    var deviceTimeZoneIdentifier: String
    var deviceCalendarIdentifier: String

    var bounds: DateBounds
    /// False when a fetch never reached the provider — beyond the daily
    /// horizon, or the refresh policy decided an existing cache was still
    /// valid. `skipReason` is a fixed diagnostic phrase, never user text.
    var fetchAttempted: Bool
    var skipReason: String?

    var provider: ProviderResult?
    var normalization: NormalizationResult?
    var cache: CacheDecision?

    var finalState: TripWeatherState
    /// Whether `PackingEngine` actually received a precise/partial forecast
    /// for this refresh (`ResolvedTripWeather.engineWeather != nil`), as
    /// opposed to falling back to seasonal/no-weather context.
    var engineReceivedPreciseWeather: Bool
}

extension WeatherRequestDiagnostics {
    /// Configured once and only read afterward; safe to share across the
    /// concurrent contexts that build a `reportText`.
    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .gmt
        return formatter
    }()

    private static func fmt(_ date: Date?) -> String {
        guard let date else { return "—" }
        return formatter.string(from: date)
    }

    /// Plain-text report for the Xcode console or a Developer Tools "Copy
    /// diagnostics" button. Every value is a coordinate, a date, a
    /// timezone/calendar identifier, or a pipeline enum — never user text.
    var reportText: String {
        var lines: [String] = []
        lines.append("WeatherRequestDiagnostics @ \(Self.fmt(recordedAt))")
        switch origin {
        case .live:
            lines.append("source: live WeatherKit refresh")
        case .fixtureInjection(let fixtureID):
            lines.append("source: Debug fixture injection (\(fixtureID)) — never the live provider")
        }
        lines.append(
            "destination: \(destinationName) (\(destinationLatitude), \(destinationLongitude)) tz=\(destinationTimeZoneIdentifier)"
        )
        lines.append("device: tz=\(deviceTimeZoneIdentifier) calendar=\(deviceCalendarIdentifier)")
        lines.append("requested: \(Self.fmt(bounds.requestedStart)) … \(Self.fmt(bounds.requestedEnd))")
        lines.append("normalized: [\(Self.fmt(bounds.normalizedStart)), \(Self.fmt(bounds.normalizedEndExclusive)))")
        lines.append("fetchAttempted: \(fetchAttempted)" + (skipReason.map { " (\($0))" } ?? ""))
        if let provider {
            lines.append(
                "provider: \(provider.kind.rawValue) days=\(provider.returnedDayCount) coverage=[\(Self.fmt(provider.returnedCoverageStart)), \(Self.fmt(provider.returnedCoverageEnd))]"
            )
            lines.append(
                "providerMetadata: fetchedAt=\(Self.fmt(provider.providerFetchedAt)) expiresAt=\(Self.fmt(provider.providerExpiresAt))"
            )
            if let domain = provider.errorDomain {
                lines.append("providerError: \(domain)#\(provider.errorCode ?? -1)")
            }
        }
        if let normalization {
            lines.append("normalization.precise: \(normalization.preciseCoveredDates.map(Self.fmt))")
            lines.append("normalization.seasonalUncovered: \(normalization.seasonalUncoveredDates.map(Self.fmt))")
            lines.append(
                "normalization.coverage: whole=\(normalization.forecastAvailableForWholeTrip) partial=\(normalization.forecastAvailableForPartialTrip) precise=\(normalization.isPreciseForecast)"
            )
        }
        if let cache {
            let age = cache.ageSeconds.map { String(format: "%.0f", $0) } ?? "—"
            lines.append(
                "cache: hit=\(cache.hit) ageSeconds=\(age) coverage=[\(Self.fmt(cache.coverageStart)), \(Self.fmt(cache.coverageEnd))] selectedAsFinal=\(cache.selectedAsFinal)"
            )
        }
        lines.append("finalState: \(finalState.rawValue)")
        lines.append("engineReceivedPreciseWeather: \(engineReceivedPreciseWeather)")
        return lines.joined(separator: "\n")
    }
}

/// Holds recent diagnostics for Developer Tools / Xcode console access.
///
/// `WeatherKitWeatherService.availability` stages the provider/normalization
/// half of the envelope as soon as it knows it; `TripWeatherRefresh.run`
/// (which owns the cache decision and the engine outcome) completes and
/// commits it, or records a skipped-fetch entry directly when no provider
/// call happens at all.
///
/// This is best-effort diagnostic tooling, not a correctness path: if two
/// different trips refresh weather concurrently, `commit` only merges a
/// staged entry that matches the destination/date bounds it expects, so a
/// race can drop a diagnostic entry but can never attribute one trip's
/// cache/engine outcome to a different trip's request.
actor WeatherRequestDiagnosticsStore {
    static let shared = WeatherRequestDiagnosticsStore()

    private var staged: WeatherRequestDiagnostics?
    private(set) var history: [WeatherRequestDiagnostics] = []
    private let historyLimit = 25

    func stage(_ diagnostics: WeatherRequestDiagnostics) {
        staged = diagnostics
    }

    /// Returns the currently staged (not yet committed) entry, for tests
    /// that want to assert on the service layer in isolation.
    func stagedEntry() -> WeatherRequestDiagnostics? { staged }

    @discardableResult
    func commit(
        matchingDestination destinationName: String,
        requestedStart: Date,
        requestedEnd: Date,
        cache: WeatherRequestDiagnostics.CacheDecision?,
        finalState: TripWeatherState,
        engineReceivedPreciseWeather: Bool
    ) -> WeatherRequestDiagnostics? {
        guard var entry = staged,
              entry.destinationName == destinationName,
              entry.bounds.requestedStart == requestedStart,
              entry.bounds.requestedEnd == requestedEnd
        else { return nil }
        entry.cache = cache
        entry.finalState = finalState
        entry.engineReceivedPreciseWeather = engineReceivedPreciseWeather
        staged = nil
        append(entry)
        return entry
    }

    @discardableResult
    func recordSkippedFetch(_ diagnostics: WeatherRequestDiagnostics) -> WeatherRequestDiagnostics {
        append(diagnostics)
        return diagnostics
    }

    /// Records a fully-built entry directly — used by Debug fixture
    /// injection, which never goes through the stage/commit sequence
    /// above since it never calls the live provider.
    @discardableResult
    func record(_ diagnostics: WeatherRequestDiagnostics) -> WeatherRequestDiagnostics {
        append(diagnostics)
        return diagnostics
    }

    private func append(_ entry: WeatherRequestDiagnostics) {
        history.append(entry)
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
    }

    func latest() -> WeatherRequestDiagnostics? { history.last }
    func all() -> [WeatherRequestDiagnostics] { history }

    /// All recorded entries, oldest first, as one copyable report — for a
    /// repro that spans several refreshes (first open, backgrounding,
    /// pull-to-refresh) so nothing before the very last one is lost.
    func allReportText() -> String {
        guard !history.isEmpty else { return "" }
        return history
            .map(\.reportText)
            .joined(separator: "\n\n———\n\n")
    }

    func clear() {
        history.removeAll()
        staged = nil
    }
}
#endif
