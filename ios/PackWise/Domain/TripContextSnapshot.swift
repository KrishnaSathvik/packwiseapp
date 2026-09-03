import Foundation

/// One deterministic outcome for a single normalized field of a
/// `TripContextSnapshot`. `valid` means the raw `TripContext` value was
/// already exactly what the snapshot uses. `normalized` means the snapshot
/// derived a different (but equivalent-intent) value — e.g. recomputing
/// `durationDays` from the real dates instead of trusting a stale stored
/// value. `unsupportedButSafe` means the raw value can't be honored as
/// given, and the snapshot fell back to a documented, non-invented safe
/// default rather than guessing at the user's intent.
enum ContextOutcome: Hashable, Sendable {
    /// A field with no corresponding entry in `diagnostics` is valid by
    /// omission — that's the convention `TripContextCompiler.compile`
    /// actually follows today. This case exists for completeness/future use
    /// (e.g. a caller that wants an explicit per-field outcome list rather
    /// than a sparse diagnostics array); no compiler code constructs it yet.
    case valid
    case normalized(reason: String)
    case unsupportedButSafe(reason: String)

    var isNormalized: Bool { if case .normalized = self { true } else { false } }
    var isUnsupportedButSafe: Bool { if case .unsupportedButSafe = self { true } else { false } }
}

/// One diagnostic entry per normalized field. `field` names the
/// `TripContextSnapshot` property the diagnostic is about (e.g. "dates",
/// "activities", "bagType", "laundry", "party", "weather"), so later
/// phases and the audit tooling can filter/report on exactly what changed.
struct ContextDiagnostic: Hashable, Sendable {
    var field: String
    var outcome: ContextOutcome
}

/// Compiled once from `TripContext` behind the engine boundary. Immutable
/// and deterministic: compiling the same `TripContext` against the same
/// `PackingRulesFile` twice always produces an equal snapshot. UI,
/// SwiftData repositories, and every boundary outside `PackingEngine`'s
/// implementation continue to use `TripContext` directly — see the Phase 2
/// plan's migration rule.
struct TripContextSnapshot: Hashable, Sendable {
    var destination: Destination
    var startDate: Date
    var endDate: Date
    var durationDays: Int
    var durationNights: Int
    var tripType: TripType

    /// Activity IDs (post `ActivityVocabulary.normalize`) that have a
    /// matching entry in `rules.activities` — the engine's real activity
    /// vocabulary.
    var knownActivityIDs: [String]
    /// Activity IDs (post `ActivityVocabulary.normalize`) with no entry in
    /// `rules.activities`. Preserved verbatim, never dropped — an
    /// unrecognized ID (including `camping`, which the engine's rules file
    /// has no entry for) is a real signal the caller may still want to
    /// surface, even though the engine itself can't act on it.
    var unknownActivityIDs: [String]

    var bagType: BagType
    /// `context.bagType.appliesBagConstraint` verbatim — `.notSure` applies
    /// no bag constraint, and that is a valid, supported state, not a
    /// fallback, so it never produces a diagnostic.
    var appliesBagConstraint: Bool
    /// Passed straight through — every `PackingStyle` case is a real, closed,
    /// supported enum case, so there is no "unknown packing style" the way
    /// there's an unknown free-text activity ID.
    var packingStyle: PackingStyle

    /// The three-way laundry state with legacy signals folded in — exactly
    /// `TripContext.laundryPlan` (`TripTypes.swift:415`), never
    /// reimplemented independently. Diverging from that property even
    /// slightly would misclassify real trips, so this is a pass-through of
    /// the existing, already-trusted computation.
    var laundryPlan: LaundryAccess
    /// Structural forecast coverage classification, independent of
    /// staleness/refresh timing — the same precedence
    /// `TripWeatherContext.state()` (`WeatherDomain.swift:169`) already
    /// establishes for seasonal/none/partial-vs-complete, exposed as a pure
    /// value with no `now`/refresh-state parameters.
    var weatherQuality: WeatherQuality

    /// `context.effectiveParty` (already folds an empty `travelers` array to
    /// `.solo()`) with any structurally invalid `guardianTravelerID`
    /// reference stripped to `nil`. Never reassigned to a guessed real party
    /// member — see `PartyInvariants.violations`: a guardian reference that
    /// isn't allowed for the traveler's age group, doesn't resolve to a real
    /// party member, or resolves to a non-adult member is dropped, never
    /// replaced. This is the "don't infer ambiguous attribution" rule.
    var party: TripParty

    var diagnostics: [ContextDiagnostic]
}

/// Structural forecast coverage for a trip, independent of staleness or
/// refresh timing. Mirrors `TripWeatherContext.state()`'s precedence for
/// seasonal/missing/partial-vs-complete without the `now`/refresh-state
/// inputs that method needs for UI copy — the snapshot only cares about
/// what forecast data structurally exists.
enum WeatherQuality: Hashable, Sendable {
    case missing
    case seasonalOnly
    case partial(coveredDays: Int, tripDays: Int)
    case complete
}

enum TripContextCompiler {
    static func compile(_ context: TripContext, rules: PackingRulesFile) -> TripContextSnapshot {
        var diagnostics: [ContextDiagnostic] = []
        let (days, nights, dateDiagnostic) = normalizedDates(context)
        if let dateDiagnostic { diagnostics.append(dateDiagnostic) }

        let (known, unknown, activityDiagnostics) = normalizedActivities(context, rules: rules)
        diagnostics.append(contentsOf: activityDiagnostics)

        let laundry = context.laundryPlan // TripContext already owns this normalization — reuse it verbatim
        if laundry != context.laundryAccess {
            diagnostics.append(ContextDiagnostic(field: "laundry", outcome: .normalized(reason: "legacy chip/notes signal folded into laundryPlan")))
        }

        let weatherQuality = normalizedWeatherQuality(context.weather, tripDays: days)

        let (party, partyDiagnostic) = normalizedParty(context)
        if let partyDiagnostic { diagnostics.append(partyDiagnostic) }

        return TripContextSnapshot(
            destination: context.destination,
            startDate: context.startDate,
            endDate: context.endDate,
            durationDays: days,
            durationNights: nights,
            tripType: context.tripType,
            knownActivityIDs: known,
            unknownActivityIDs: unknown,
            bagType: context.bagType,
            appliesBagConstraint: context.bagType.appliesBagConstraint,
            packingStyle: context.packingStyle,
            laundryPlan: laundry,
            weatherQuality: weatherQuality,
            party: party,
            diagnostics: diagnostics
        )
    }

    /// Never invents a guardian. `context.effectiveParty` already folds an
    /// empty party to `.solo()`, so this only has to handle a non-empty but
    /// structurally malformed party: any `guardianTravelerID` that
    /// `PartyInvariants.violations` flags — not allowed for the traveler's
    /// age group, not a real party member, or not an adult — is set to
    /// `nil`. It is never rewritten to some other traveler's id; the only
    /// values a `guardianTravelerID` can end up holding here are `nil` or a
    /// value that was already present, verbatim, in the raw input.
    private static func normalizedParty(_ context: TripContext) -> (party: TripParty, diagnostic: ContextDiagnostic?) {
        let effectiveParty = context.effectiveParty
        let violations = PartyInvariants.violations(party: effectiveParty)
        guard !violations.isEmpty else { return (effectiveParty, nil) }

        let ids = Set(effectiveParty.travelers.map(\.id))
        let adults = Set(effectiveParty.travelers.filter(\.ageGroup.isAdult).map(\.id))
        var normalized = effectiveParty
        normalized.travelers = effectiveParty.travelers.map { traveler in
            var copy = traveler
            if let guardian = copy.guardianTravelerID,
               !(copy.ageGroup.allowsGuardian && ids.contains(guardian) && adults.contains(guardian)) {
                copy.guardianTravelerID = nil // drop, never reassign to a guessed adult
            }
            return copy
        }
        return (normalized, ContextDiagnostic(field: "party", outcome: .unsupportedButSafe(reason: "invalid guardian reference(s) dropped, not reassigned")))
    }

    /// Mirrors `TripWeatherContext.state()`'s precedence: `.seasonal` and
    /// `.none` sources are classified first regardless of any forecast
    /// data; otherwise (`.weatherKit`/`.fixture`/`.cache` — a cached
    /// forecast is structurally the same data as a live one, just tagged
    /// stale, which this value deliberately doesn't track) whole-trip
    /// coverage wins over partial, and an empty forecast with neither flag
    /// set falls back to seasonal-only, exactly as `state()`'s final two
    /// branches do.
    private static func normalizedWeatherQuality(_ weather: TripWeatherContext?, tripDays: Int) -> WeatherQuality {
        guard let weather else { return .missing }
        switch weather.source {
        case .seasonal:
            return .seasonalOnly
        case .none:
            return .missing
        case .weatherKit, .fixture, .cache:
            if weather.forecastAvailableForWholeTrip {
                return .complete
            }
            if weather.forecastAvailableForPartialTrip {
                return .partial(coveredDays: weather.dailyForecast.count, tripDays: tripDays)
            }
            if weather.dailyForecast.isEmpty {
                return .seasonalOnly
            }
            return .partial(coveredDays: weather.dailyForecast.count, tripDays: tripDays)
        }
    }

    private static func normalizedActivities(
        _ context: TripContext,
        rules: PackingRulesFile
    ) -> (known: [String], unknown: [String], diagnostics: [ContextDiagnostic]) {
        let normalizedActivityIDs = ActivityVocabulary.normalize(context.activities)
        var known: [String] = []
        var unknown: [String] = []
        for id in normalizedActivityIDs {
            if rules.activities[id] != nil {
                known.append(id)
            } else {
                unknown.append(id)
            }
        }
        let diagnostics = unknown.map { id in
            ContextDiagnostic(field: "activities", outcome: .unsupportedButSafe(reason: "\(id): no rule in the engine's activity vocabulary"))
        }
        return (known, unknown, diagnostics)
    }

    private static func normalizedDates(_ context: TripContext) -> (days: Int, nights: Int, diagnostic: ContextDiagnostic?) {
        let math = TripDateMath.daysAndNights(from: context.startDate, to: context.endDate)
        if context.endDate < context.startDate {
            return (math.days, math.nights, ContextDiagnostic(field: "dates", outcome: .unsupportedButSafe(reason: "endDate before startDate; treated as a 1-day trip")))
        }
        if math.days != context.durationDays || math.nights != context.durationNights {
            return (math.days, math.nights, ContextDiagnostic(field: "dates", outcome: .normalized(reason: "durationDays/durationNights recomputed from startDate/endDate")))
        }
        return (math.days, math.nights, nil)
    }
}
