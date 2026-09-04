import Foundation
import SwiftData
import Testing
@testable import PackWise

/// `PackingItemRecord` persistence round-trip tests — Phase 8, Task 2.
struct PersistenceTests {
    @MainActor
    private func makeTrip() throws -> (context: ModelContext, trip: TripRecord) {
        let container = try PackWisePersistence.container(inMemory: true)
        let context = ModelContext(container)
        let destination = try SharedLibrary.testDestinations().first { $0.city == "Chicago" }!
        let trip = TripRecord(
            destination: destination,
            startDate: .now,
            endDate: Calendar.current.date(byAdding: .day, value: 4, to: .now)!,
            durationDays: 5,
            durationNights: 4,
            tripType: .cityBreak,
            activities: ["sightseeing"],
            bagType: .carryOn,
            packingStyle: .balanced
        )
        context.insert(trip)
        return (context, trip)
    }

    /// The three new Phase 8 fields (`quantityReasonArguments`,
    /// `satisfiedCapabilities`, `bagStyleConstraintFact`) plus the
    /// previously-unpersisted `quantityEvidence` all round-trip through
    /// `PackingItemRecord` the same way `reasonCode`/`reasonArguments`
    /// already do.
    @Test @MainActor func newTraceFieldsRoundTripThroughPersistence() throws {
        let (_, trip) = try makeTrip()
        var draft = PackingItemDraft(
            canonicalItemID: "footwear.hiking_shoes",
            displayName: "Hiking shoes",
            category: .footwear,
            quantity: 1,
            importance: .normal,
            sourceSignals: [.activity],
            reason: "Hiking is on your plans."
        )
        draft.quantityReasonArguments = ["quantity": "1", "days": "5"]
        draft.satisfiedCapabilities = ["footwear.everyday_walking"]
        draft.bagStyleConstraintFact = BagStyleConstraintFact(survivedByEssentialTagProtection: true, wouldTrimUnderKey: "bag.personal_item")

        let record = PackingItemRecord(from: draft, trip: trip)
        #expect(record.draft.quantityReasonArguments == draft.quantityReasonArguments)
        #expect(record.draft.satisfiedCapabilities == draft.satisfiedCapabilities)
        #expect(record.draft.bagStyleConstraintFact == draft.bagStyleConstraintFact)
    }

    /// `bagStyleConstraintFact` round-trips as nil when the ruling never
    /// left its no-op guard — the common case, must not decode to a
    /// spurious non-nil fact.
    @Test @MainActor func nilBagStyleConstraintFactRoundTripsAsNil() throws {
        let (_, trip) = try makeTrip()
        let draft = PackingItemDraft(
            canonicalItemID: "toiletries.toothbrush",
            displayName: "Toothbrush",
            category: .toiletries,
            quantity: 1,
            importance: .critical,
            sourceSignals: [.baseEssential],
            reason: "Base essential."
        )
        let record = PackingItemRecord(from: draft, trip: trip)
        #expect(record.draft.bagStyleConstraintFact == nil)
        #expect(record.draft.quantityReasonArguments.isEmpty)
        #expect(record.draft.satisfiedCapabilities.isEmpty)
    }

    /// `quantityEvidence` — a previously-unpersisted field, closed alongside
    /// the three new ones in the same task — round-trips through its
    /// JSON-encoded raw storage.
    @Test @MainActor func quantityEvidenceRoundTripsThroughPersistence() throws {
        let (_, trip) = try makeTrip()
        var draft = PackingItemDraft(
            canonicalItemID: "clothing.tshirt",
            displayName: "T-Shirts",
            category: .clothing,
            quantity: 4,
            importance: .normal,
            sourceSignals: [.baseEssential],
            reason: "Everyday wear."
        )
        draft.quantityEvidence = ClothingQuantityEvidence(
            policyID: "test.policy",
            basis: "dailyWear",
            requiredUses: 4,
            wearsPerItem: 1,
            washIntervalDays: nil,
            laundryPlan: .none,
            laundryReduced: false,
            styleBuffer: 0,
            bagCap: nil,
            bagCapApplied: false,
            appearanceOffsetUses: 0,
            ageMultiplier: nil,
            quantity: 4
        )
        let record = PackingItemRecord(from: draft, trip: trip)
        #expect(record.draft.quantityEvidence == draft.quantityEvidence)
    }
}
