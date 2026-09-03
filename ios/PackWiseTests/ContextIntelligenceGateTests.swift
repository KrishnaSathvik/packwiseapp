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

/// Always throws — proves the gate's resilience without a mock that could
/// coincidentally succeed.
private final class ThrowingIntelligenceService: ContextIntelligenceService, @unchecked Sendable {
    struct Boom: Error {}
    var interpretCalls = 0

    func interpretTripNote(_ note: String, context: TripContext) async throws -> TripContextEnrichment {
        interpretCalls += 1
        throw Boom()
    }

    func findPackingGaps(context: TripContext, items: [PackingItemDraft]) async throws -> [PackingSuggestion] {
        throw Boom()
    }

    func optimizePacking(context: TripContext, items: [PackingItemDraft]) async throws -> [PackingOptimization] {
        throw Boom()
    }
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

    // MARK: - Task 4: throwing service, deterministic generation, attribution

    /// A service that always throws is exactly as safe to inject as one
    /// that always succeeds: the gate is closed before the service is ever
    /// reached, so the throw never happens and `noteEnrichment` never
    /// propagates an error.
    @Test func noteEnrichmentNeverThrowsEvenWhenTheServiceDoes() async throws {
        let throwing = ThrowingIntelligenceService()

        let enrichment = await ContextIntelligenceGate.noteEnrichment(
            notes: "lots of walking and sightseeing",
            context: try context(),
            intelligence: throwing
        )

        #expect(enrichment == nil)
        #expect(throwing.interpretCalls == 0, "the gate must short-circuit before the service is called")
    }

    /// `PackingEngine.generate` doesn't take an intelligence service at all,
    /// so deterministic generation succeeds regardless of what a throwing
    /// service would have done with the same note.
    @Test func deterministicGenerationSucceedsAlongsideAThrowingIntelligenceService() async throws {
        let throwing = ThrowingIntelligenceService()
        var noted = try context()
        noted.userNotes = "my daughter needs medication"
        _ = await ContextIntelligenceGate.noteEnrichment(notes: noted.userNotes, context: noted, intelligence: throwing)

        let engine = PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
        let items = engine.generate(context: noted)
        #expect(!items.isEmpty)
    }

    /// A family note about a daughter's medication cannot become the
    /// primary traveler's medication chip: `userNotes` is free text the
    /// engine never parses, chips only ever come from explicit selection
    /// (`TripContext.contextChips` / `TravelerPreferences`), and the one
    /// path that could turn a note into a chip — enrichment — is off.
    @Test func familyNoteAboutMedicationNeverBecomesThePrimaryTravelersChip() throws {
        var noted = try context()
        noted.userNotes = "my daughter needs medication"
        let engine = PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
        let items = engine.generate(context: noted)
        #expect(!items.contains { $0.canonicalItemID == "health.daily_medication" })
        #expect(!items.contains { $0.canonicalItemID == "health.prescription_copy" })
    }
}
