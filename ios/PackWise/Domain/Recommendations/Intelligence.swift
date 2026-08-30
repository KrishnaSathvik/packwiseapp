import Foundation

struct TripContextEnrichment: Hashable, Sendable {
    var inferredActivities: [String]
    var inferredChips: [ContextChip]
    var noteSummary: String
}

enum PackingSuggestionAction: String, Codable, CaseIterable, Sendable {
    case recommend
    case removeCandidate = "remove_candidate"
    case quantityChange = "quantity_change"
}

/// A candidate, never a decision. Suggestions pass through the Recommendation
/// Resolver and an explicit user choice before anything reaches SwiftData.
///
/// `reasonCode` plus `reasonArguments` is the durable identifier PackWise
/// renders from a localized template. `reason` is fallback prose and must never
/// be treated as a stable key.
struct PackingSuggestion: Hashable, Identifiable, Sendable {
    var id: UUID
    var canonicalItemID: String
    var action: PackingSuggestionAction
    var reasonCode: String?
    var reasonArguments: [String: String]
    var reason: String?
    /// Internal only: ranking and suppression. Never rendered — the customer
    /// sees Important / Recommended / Optional, never a percentage.
    var confidence: Double?
    var signals: [RecommendationSignal]

    init(
        id: UUID = UUID(),
        canonicalItemID: String,
        action: PackingSuggestionAction,
        reasonCode: String? = nil,
        reasonArguments: [String: String] = [:],
        reason: String? = nil,
        confidence: Double? = nil,
        signals: [RecommendationSignal]
    ) {
        self.id = id
        self.canonicalItemID = canonicalItemID
        self.action = action
        self.reasonCode = reasonCode
        self.reasonArguments = reasonArguments
        self.reason = reason
        self.confidence = confidence
        self.signals = signals
    }
}

struct PackingOptimization: Hashable, Identifiable, Sendable {
    var id: UUID
    var canonicalItemID: String
    var reasonCode: String?
    var reasonArguments: [String: String]
    var reason: String?
    var confidence: Double?
    var suggestedQuantity: Int?

    init(
        id: UUID = UUID(),
        canonicalItemID: String,
        reasonCode: String? = nil,
        reasonArguments: [String: String] = [:],
        reason: String? = nil,
        confidence: Double? = nil,
        suggestedQuantity: Int? = nil
    ) {
        self.id = id
        self.canonicalItemID = canonicalItemID
        self.reasonCode = reasonCode
        self.reasonArguments = reasonArguments
        self.reason = reason
        self.confidence = confidence
        self.suggestedQuantity = suggestedQuantity
    }
}

enum IntelligenceError: Error, Equatable, Sendable {
    /// The only failure the app ever reacts to. Callers fall back to the
    /// deterministic list rather than surfacing an error during generation.
    case unavailable
}

protocol ContextIntelligenceService: Sendable {
    func interpretTripNote(_ note: String, context: TripContext) async throws -> TripContextEnrichment
    func findPackingGaps(context: TripContext, items: [PackingItemDraft]) async throws -> [PackingSuggestion]
    func optimizePacking(context: TripContext, items: [PackingItemDraft]) async throws -> [PackingOptimization]
}
