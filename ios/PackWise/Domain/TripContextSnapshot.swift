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

    var diagnostics: [ContextDiagnostic]
}

enum TripContextCompiler {
    static func compile(_ context: TripContext, rules: PackingRulesFile) -> TripContextSnapshot {
        var diagnostics: [ContextDiagnostic] = []
        let (days, nights, dateDiagnostic) = normalizedDates(context)
        if let dateDiagnostic { diagnostics.append(dateDiagnostic) }

        return TripContextSnapshot(
            destination: context.destination,
            startDate: context.startDate,
            endDate: context.endDate,
            durationDays: days,
            durationNights: nights,
            tripType: context.tripType,
            diagnostics: diagnostics
        )
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
