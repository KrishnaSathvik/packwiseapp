import Foundation
import Testing

@testable import PackWise

/// Counts calls instead of answering them, so the tests prove the gate
/// short-circuits before the service — not that a mock returned nothing.
private final class SpyIntelligenceService: ContextIntelligenceService, @unchecked Sendable {
    var interpretCalls = 0

    func interpretTripNote(_ note: String, context: TripContext) async throws -> TripContextEnrichment {
        interpretCalls += 1
        return TripContextEnrichment(
            inferredActivities: ["walking"],
            inferredChips: [.getColdEasily],
            noteSummary: "should never surface"
        )
    }

    func findPackingGaps(context: TripContext, items: [PackingItemDraft]) async throws -> [PackingSuggestion] { [] }
    func optimizePacking(context: TripContext, items: [PackingItemDraft]) async throws -> [PackingOptimization] { [] }
}

struct ContextIntelligenceGateTests {
    private func context() throws -> TripContext {
        let destinations = try SharedLibrary.testDestinations()
        let destination = destinations.first { $0.city == "Tokyo" }!
        let start = Calendar.current.startOfDay(for: Date.now)
        let end = Calendar.current.date(byAdding: .day, value: 5, to: start)!
        let math = TripDateMath.daysAndNights(from: start, to: end)
        return TripContext(
            destination: destination,
            startDate: start,
            endDate: end,
            durationDays: math.days,
            durationNights: math.nights,
            tripType: .cityBreak,
            activities: ["sightseeing", "walking"],
            datedActivities: [],
            bagType: .carryOn,
            packingStyle: .balanced,
            transportation: .flight,
            laundryAccess: .none,
            travelerCount: 1,
            userNotes: "",
            contextChips: [],
            weather: nil,
            preferences: .deviceDefaults()
        )
    }

    /// AGENTS.md non-negotiables: GPT never writes SwiftData, and don't infer.
    /// Until M3B adds the user-acceptance step and a traveler-attribution
    /// guard, the enrichment path must be off — a real note must not reach
    /// the interpret service at all.
    @Test func noteEnrichmentIsOffUntilM3BAcceptanceExists() async throws {
        let spy = SpyIntelligenceService()

        let enrichment = await ContextIntelligenceGate.noteEnrichment(
            notes: "my daughter needs medication",
            context: try context(),
            intelligence: spy
        )

        #expect(enrichment == nil)
        #expect(spy.interpretCalls == 0)
    }
}
