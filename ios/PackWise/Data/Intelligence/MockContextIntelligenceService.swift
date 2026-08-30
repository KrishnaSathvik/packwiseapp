import Foundation

/// Deterministic stand-in used by previews, tests, and any build without a
/// configured API base URL. It never reaches the network.
struct MockContextIntelligenceService: ContextIntelligenceService {
    var available: Bool = true

    func interpretTripNote(_ note: String, context: TripContext) async throws -> TripContextEnrichment {
        guard available else { throw IntelligenceError.unavailable }
        let lowered = note.lowercased()
        var activities: [String] = []
        var chips: [ContextChip] = []
        if lowered.contains("laundry") { chips.append(.laundryAvailable) }
        if lowered.contains("hike") { activities.append("hiking") }
        if lowered.contains("laptop") { chips.append(.bringingLaptop) }
        return TripContextEnrichment(
            inferredActivities: activities,
            inferredChips: chips,
            noteSummary: note
        )
    }

    func findPackingGaps(context: TripContext, items: [PackingItemDraft]) async throws -> [PackingSuggestion] {
        _ = context
        _ = items
        guard available else { throw IntelligenceError.unavailable }
        return []
    }

    func optimizePacking(context: TripContext, items: [PackingItemDraft]) async throws -> [PackingOptimization] {
        _ = context
        _ = items
        guard available else { throw IntelligenceError.unavailable }
        return []
    }
}
