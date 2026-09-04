import Foundation

/// Assembled entirely from an item's own stored, structured facts —
/// `PackingItemDraft`/`PackingItemRecord` fields populated once, at
/// generation time, by `PackingEngine`/`ConstraintResolver`/
/// `CoverageResolver` (Phase 8, Tasks 1–2). No function in this type calls
/// `PackingEngine`, `ConstraintResolver`, `CoverageResolver`, or
/// `WeatherSignalExtractor` — every fact here is a field read, not a
/// re-derivation. This is the boundary the design's required amendment made
/// explicit after the original `ConstraintFacet` design violated it: no
/// facet function in this file takes a `catalog`, `rules`, `context`, or
/// `party` parameter — a structural, not just conventional, guarantee.
enum RecommendationTrace {
    enum InclusionFamily: String, Hashable, Sendable {
        case baseEssential, tripType, activity, weatherPrecise, weatherSeasonal
        case party, dependency, personalPreference, destination, documents
        case flight, substitution, userAuthority
    }

    /// Pure derivation over the closed reasonCode/signal vocabulary — no new
    /// stored field. Never re-calls anything; inclusion was never the part
    /// of this design that live-recalled a decision.
    static func inclusionFamily(reasonCode: String, signals: [RecommendationSignal]) -> InclusionFamily {
        if reasonCode.isEmpty { return .userAuthority }
        if reasonCode.hasPrefix("base.essential.") { return .baseEssential }
        if reasonCode.hasPrefix("weather.seasonal") { return .weatherSeasonal }
        if reasonCode.hasPrefix("weather.") { return .weatherPrecise }
        if reasonCode.hasPrefix("activity.") { return .activity }
        if reasonCode.hasPrefix("party.") { return .party }
        if reasonCode.hasPrefix("dependency.") { return .dependency }
        if reasonCode.hasPrefix("preference.") { return .personalPreference }
        if reasonCode.hasPrefix("trip_type.") { return .tripType }
        if reasonCode.hasPrefix("destination.") { return .destination }
        if reasonCode.hasPrefix("documents.") { return .documents }
        if reasonCode.hasPrefix("flight.") { return .flight }
        if reasonCode.hasPrefix("substitution.") { return .substitution }
        return .tripType // closed fallback; a test walks every reasons.json inclusion key to prove this branch is unreachable today
    }

    struct QuantityFacet: Hashable, Sendable {
        var value: Int
        var isFixedSingleton: Bool
        var clothingEvidence: ClothingQuantityEvidence?
        var reason: String
        var reasonArguments: [String: String]
    }

    /// A field read, never a second call — see the design doc's
    /// "constraints" section.
    struct ConstraintFacet: Hashable, Sendable {
        var bagStyle: BagStyleConstraintFact?
        var sharing: ConstraintResolver.SharingResolution?

        static func read(from item: PackingItemDraft) -> ConstraintFacet {
            ConstraintFacet(
                bagStyle: item.bagStyleConstraintFact,
                sharing: item.ownershipType == .shared
                    ? .shared(quantity: item.quantity, reason: item.quantityReason)
                    : nil
            )
        }
    }

    /// `itemCapabilities ∩ activeNeeds`, read directly off the stored field
    /// — see the design doc's "needs/capabilities and coverage" section.
    struct CoverageFacet: Hashable, Sendable {
        var satisfiedCapabilities: [String]
    }

    struct Authority: Hashable, Sendable {
        var isUserAdded: Bool
        var isUserModified: Bool
        var isCustomItem: Bool
    }
}

extension RecommendationTrace {
    static func quantityFacet(for item: PackingItemDraft) -> QuantityFacet {
        let isFixedSingleton = item.quantity == 1
            && item.ownershipType != .shared
            && item.quantityEvidence == nil
            && item.quantityReasonArguments.isEmpty
        return QuantityFacet(
            value: item.quantity,
            isFixedSingleton: isFixedSingleton,
            clothingEvidence: item.quantityEvidence,
            reason: item.quantityReason,
            reasonArguments: item.quantityReasonArguments
        )
    }

    static func coverageFacet(for item: PackingItemDraft) -> CoverageFacet {
        CoverageFacet(satisfiedCapabilities: item.satisfiedCapabilities)
    }

    static func authority(for item: PackingItemDraft) -> Authority {
        Authority(
            isUserAdded: item.isUserAdded,
            isUserModified: item.isUserModified,
            isCustomItem: item.canonicalItemID?.hasPrefix("custom.") ?? (item.canonicalItemID == nil)
        )
    }
}
