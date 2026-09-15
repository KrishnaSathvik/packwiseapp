import Foundation
import SwiftData
import Testing
@testable import PackWise

/// Phase 8, Task 3 (required amendment): the persisted-provenance refresh
/// gap on regeneration. `PackingItemRecord.apply(_:)` had zero real callers;
/// the actual regeneration path (`recommendationDiff` → `applyDiff`) never
/// refreshed an existing item's causal fields when quantity was unchanged
/// but cause changed. These tests reproduce the gap live, then prove the
/// fix while pinning every explicit-user-authority field untouched.
struct RegenerationProvenanceTests {
    private func makeEngine() throws -> PackingEngine {
        PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
    }

    private func destination(_ name: String) throws -> Destination {
        try SharedLibrary.testDestinations().first { $0.city == name }!
    }

    private func context(
        destination: Destination,
        days: Int = 5,
        activities: [String],
        party: TripParty
    ) -> TripContext {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        let end = Calendar.current.date(byAdding: .day, value: days - 1, to: start)!
        let math = TripDateMath.daysAndNights(from: start, to: end)
        var prefs = TravelerPreferences.deviceDefaults()
        prefs.homeCountryCode = "US"
        prefs.homeCountrySource = .userConfirmed
        return TripContext(
            destination: destination,
            startDate: start,
            endDate: end,
            durationDays: math.days,
            durationNights: math.nights,
            tripTypes: [.cityBreak],
            activities: activities,
            datedActivities: [],
            bagTypes: [.carryOn],
            packingStyle: .balanced,
            transportation: .unknown,
            laundryAccess: .none,
            travelerCount: 1,
            userNotes: "",
            contextChips: [],
            weather: nil,
            preferences: prefs,
            party: party
        )
    }

    @MainActor
    private func makeTrip(context ctx: TripContext) throws -> (repo: TripRepository, trip: TripRecord) {
        let container = try PackWisePersistence.container(inMemory: true)
        let modelContext = ModelContext(container)
        let trip = TripRecord(
            destination: ctx.destination,
            startDate: ctx.startDate,
            endDate: ctx.endDate,
            durationDays: ctx.durationDays,
            durationNights: ctx.durationNights,
            tripType: .other,
            activities: ctx.activities,
            bagType: .carryOn,  // the fixture context selects exactly [.carryOn]
            packingStyle: ctx.packingStyle
        )
        // The record's authoritative selection is the full set, not a scalar.
        trip.tripTypesRaw = PackWiseStableEncoding.tripTypesJSON(ctx.tripTypes)
        modelContext.insert(trip)
        let repo = TripRepository(context: modelContext)
        repo.attach(party: ctx.effectiveParty, bagTypes: [.carryOn], on: trip)
        return (repo, trip)
    }

    /// Amendment 3's required scenario: a trip generates with Hiking
    /// selected, `hydration.water_bottle` carries `activity.hiking`
    /// evidence (both Hiking's and Camping's activity contracts declare the
    /// `.hydration` need, per `ActivityContracts.swift` — the item survives
    /// under either activity, but the *cause* changes). The user removes
    /// Hiking and adds Camping; regenerating must refresh the causal fields
    /// to the new cause, not leave them pointing at Hiking — while, in the
    /// same regeneration, a packed item's `packedQuantity`, a manually-set
    /// quantity, a "Not Needed" override, and an explicitly-assigned
    /// `assignedTravelerID` on other items are byte-identical before/after.
    @Test @MainActor func regenerationRefreshesCausalFieldsButNeverExplicitUserState() throws {
        let engine = try makeEngine()
        let dest = try destination("Chicago")
        // A stable party identity across both regenerations — the same
        // traveler ids replaceParty/attach would preserve for a real trip,
        // so override traveler-scoping (isExplicitlyRemoved) matches
        // correctly on the second generation, exactly as it does in
        // production.
        let party = TripParty.solo()
        let hikingContext = context(destination: dest, activities: ["hiking"], party: party)
        let initial = engine.generate(context: hikingContext)
        let (repo, trip) = try makeTrip(context: hikingContext)
        repo.replaceItems(on: trip, with: initial)

        let bottle = try #require(trip.items.first { $0.canonicalItemID == "hydration.water_bottle" })
        #expect(bottle.reasonCode == "activity.hiking")

        // Pin four unrelated items into every explicit-user-state category
        // the non-touch list names — all base essentials, guaranteed
        // present regardless of activity.
        let packed = try #require(trip.items.first { $0.canonicalItemID == "clothing.tshirt" })
        packed.packedQuantity = packed.quantity

        let manual = try #require(trip.items.first { $0.canonicalItemID == "clothing.underwear" })
        manual.isUserModified = true
        manual.quantity = 11

        let notNeededCandidate = try #require(trip.items.first { $0.canonicalItemID == "toiletries.toothbrush" })
        repo.markNotNeeded(notNeededCandidate, on: trip)

        let carried = try #require(trip.items.first { $0.canonicalItemID == "essentials.wallet" })
        let explicitCarrier = UUID()
        carried.assignedTravelerID = explicitCarrier

        let pinnedPackedQuantity = packed.packedQuantity
        let pinnedManualQuantity = manual.quantity

        // Regenerate: Hiking removed, Camping added — hydration.water_bottle
        // must independently survive under Camping's own .hydration need,
        // not Hiking's.
        let campingContext = context(destination: dest, activities: ["camping"], party: party)
        let existingDrafts = trip.items.map(\.draft)
        let overrides = trip.overrides.map(\.draft)
        let diff = engine.recommendationDiff(context: campingContext, existing: existingDrafts, overrides: overrides)
        repo.applyDiff(
            diff,
            addIDs: Set(diff.add.map(\.id)),
            removeIDs: Set(diff.removeCandidates.map(\.id)),
            quantityIDs: Set(diff.quantityChanges.map(\.existing.id)),
            on: trip
        )

        let refreshedBottle = try #require(trip.items.first { $0.canonicalItemID == "hydration.water_bottle" })
        #expect(refreshedBottle.reasonCode == "activity.camping", "the stale Hiking cause must not survive")
        #expect(refreshedBottle.reasonCode != "activity.hiking")
        #expect(!refreshedBottle.sourceSignals.isEmpty)

        #expect(trip.items.first { $0.canonicalItemID == "clothing.tshirt" }?.packedQuantity == pinnedPackedQuantity)
        #expect(trip.items.first { $0.canonicalItemID == "clothing.underwear" }?.quantity == pinnedManualQuantity)
        #expect(trip.items.first { $0.canonicalItemID == "clothing.underwear" }?.isUserModified == true)
        #expect(!trip.items.contains { $0.canonicalItemID == "toiletries.toothbrush" }, "Not Needed must still hold")
        #expect(trip.overrides.contains { $0.canonicalItemID == "toiletries.toothbrush" && $0.action == "removed" })
        #expect(trip.items.first { $0.canonicalItemID == "essentials.wallet" }?.assignedTravelerID == explicitCarrier)
    }

    /// The staleness bug, reproduced live before the fix: quantity alone was
    /// the diff's only comparison, so an item whose cause changed but whose
    /// quantity did not was never flagged for the diff at all, and its
    /// persisted record was never touched. Proven directly at the
    /// `PackingEngine.recommendationDiff` level, independent of persistence.
    @Test func recommendationDiffFlagsACausalOnlyChangeEvenWhenQuantityIsUnchanged() throws {
        let engine = try makeEngine()
        let dest = try destination("Chicago")
        let party = TripParty.solo()
        let hikingContext = context(destination: dest, activities: ["hiking"], party: party)
        let existing = engine.generate(context: hikingContext)
        let bottle = try #require(existing.first { $0.canonicalItemID == "hydration.water_bottle" })
        #expect(bottle.reasonCode == "activity.hiking")
        #expect(bottle.quantity == 1)

        let campingContext = context(destination: dest, activities: ["camping"], party: party)
        let diff = engine.recommendationDiff(context: campingContext, existing: existing, overrides: [])
        let change = try #require(diff.quantityChanges.first { $0.existing.canonicalItemID == "hydration.water_bottle" })
        #expect(change.fresh.quantity == change.existing.quantity, "quantity itself must be unchanged — this is the causal-only case")
        #expect(change.fresh.reasonCode == "activity.camping")
        #expect(change.existing.reasonCode == "activity.hiking")
    }
}
