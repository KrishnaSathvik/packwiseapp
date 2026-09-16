import Foundation
import SwiftData
import Testing
@testable import PackWise

/// Product Experience V2, Task 4 — one trace authority for provenance.
///
/// The Phase 8 `RecommendationTrace` reads every explanation fact off the
/// item's own structured fields. Multi-source provenance joins those fields as
/// `PackingItemDraft.provenance`; `PackingItemRecord.recommendationTraceRaw` is
/// only its persisted encoding, never a second source of truth.
@Suite(.serialized)
struct RecommendationProvenanceTests {
    private func engine() throws -> PackingEngine {
        PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
    }

    private func context(tripTypes: Set<TripType>, activities: [String]) throws -> TripContext {
        let destination = try #require(try SharedLibrary.testDestinations().first { $0.city == "Miami" })
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5))!
        let end = Calendar.current.date(byAdding: .day, value: 4, to: start)!
        var preferences = TravelerPreferences.deviceDefaults()
        preferences.homeCountryCode = "US"
        preferences.homeCountrySource = .userConfirmed
        return TripContext(
            destination: destination, startDate: start, endDate: end, durationDays: 5, durationNights: 4,
            tripTypes: tripTypes, activities: activities, datedActivities: [], bagTypes: [.checked],
            packingStyle: .balanced, transportation: .unknown, laundryAccess: .none, travelerCount: 1,
            userNotes: "", contextChips: [], weather: nil, preferences: preferences
        )
    }

    // MARK: - The engine records every contributing fact

    @Test func anItemFromATripTypeAndASelectedActivityCarriesBothFacts() throws {
        let items = try engine().generate(context: try context(tripTypes: [.beach], activities: ["swimming"]))
        let swimsuit = try #require(items.first { $0.canonicalItemID == "clothing.swimsuit" })
        #expect(swimsuit.provenance.contains(.tripType(.beach)))
        #expect(swimsuit.provenance.contains { $0.reasonCode == "activity.swimming" && $0.sourceSignals == [.activity] })
        #expect(RecommendationTrace.provenance(for: swimsuit) == swimsuit.provenance, "the trace reads the field, nothing else")
    }

    @Test func everyGeneratedEngineItemHasAtLeastOneProvenanceFact() throws {
        let items = try engine().generate(context: try context(tripTypes: [.beach], activities: ["swimming", "walking"]))
        #expect(!items.isEmpty)
        for item in items {
            #expect(!item.provenance.isEmpty, "\(item.canonicalItemID ?? item.displayName) has no provenance")
        }
    }

    @Test func provenanceOrderIsCanonicalAndDeterministic() throws {
        let engine = try engine()
        let first = engine.generate(context: try context(tripTypes: [.beach], activities: ["swimming", "beachDays"]))
        let second = engine.generate(context: try context(tripTypes: [.beach], activities: ["beachDays", "swimming"]))
        func facts(_ items: [PackingItemDraft]) -> [String: [RecommendationProvenance]] {
            Dictionary(uniqueKeysWithValues: items.compactMap { item in item.canonicalItemID.map { ($0, item.provenance) } })
        }
        #expect(facts(first) == facts(second))
        for item in first {
            #expect(item.provenance == RecommendationProvenance.canonicalOrder(item.provenance))
        }
    }

    // MARK: - Persistence is an encoding of the same model

    @Test @MainActor func combinedProvenancePersistsAndReloadsWithoutDivergence() throws {
        let container = try PackWisePersistence.container(inMemory: true)
        let modelContext = ModelContext(container)
        let facts = RecommendationProvenance.canonicalOrder([
            .tripType(.festival),
            .tripType(.beach),
            RecommendationProvenance(reasonCode: "activity.beachDays", reasonArguments: ["destination": "Miami"], sourceSignals: [.activity]),
        ])
        var draft = PackingItemDraft(
            canonicalItemID: "toiletries.sunscreen", displayName: "Sunscreen", category: .toiletries,
            quantity: 1, importance: .important, sourceSignals: [.tripType, .activity], reason: "Sun."
        )
        draft.provenance = facts

        let destination = try #require(try SharedLibrary.testDestinations().first { $0.city == "Miami" })
        let trip = TripRecord(
            destination: destination, startDate: .now, endDate: .now.addingTimeInterval(86400),
            durationDays: 2, durationNights: 1, tripType: .beach, activities: [], bagType: .checked, packingStyle: .balanced
        )
        modelContext.insert(trip)
        let record = PackingItemRecord(from: draft, trip: trip)
        modelContext.insert(record)
        try modelContext.save()
        #expect(record.recommendationTraceRaw != nil, "recommendationTraceRaw is the persisted encoding")
        #expect(record.draft.provenance == facts)
        #expect(RecommendationTrace.provenance(for: record.draft) == facts)

        var refreshed = draft
        refreshed.provenance = [.tripType(.beach)]
        record.apply(refreshed)
        #expect(record.draft.provenance == [.tripType(.beach)], "apply(_:) refreshes the same encoding")

        refreshed.provenance = []
        record.apply(refreshed)
        #expect(record.recommendationTraceRaw == nil)
        #expect(record.draft.provenance.isEmpty)
    }

    @Test func aDraftEncodedBeforeProvenanceExistedStillDecodes() throws {
        var draft = PackingItemDraft(
            canonicalItemID: "essentials.wallet", displayName: "Wallet", category: .essentials,
            quantity: 1, importance: .critical, sourceSignals: [.baseEssential], reason: "Core."
        )
        draft.provenance = [.tripType(.vacation)]
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        json.removeValue(forKey: "provenanceFacts")
        let legacy = try JSONDecoder().decode(PackingItemDraft.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.provenance.isEmpty, "a pending weather proposal saved before Task 4 keeps decoding")
    }

    // MARK: - Regeneration refresh

    @Test func aProvenanceChangeIsCausalButALegacyEmptyRecordIsNot() throws {
        var fresh = PackingItemDraft(
            canonicalItemID: "clothing.swimsuit", displayName: "Swimsuit", category: .clothing,
            quantity: 1, importance: .important, sourceSignals: [.tripType], reason: "Beach."
        )
        fresh.provenance = [.tripType(.beach)]

        var stale = fresh
        stale.provenance = [.tripType(.vacation)]
        #expect(stale.causallyDiffers(from: fresh), "stored provenance that disagrees with regeneration is refreshed")

        var legacy = fresh
        legacy.provenance = []
        #expect(!legacy.causallyDiffers(from: fresh), "a pre-Task-4 record without provenance is not a list change")
    }
}
