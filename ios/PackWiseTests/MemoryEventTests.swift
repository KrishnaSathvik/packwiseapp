import Foundation
import SwiftData
import Testing
@testable import PackWise

/// Memory event log tests — Engine V2 plan, Step 6.
///
/// The log is write-only: nothing reads it yet, which is exactly where bugs
/// hide indefinitely. This walks a full trip lifecycle and asserts the ledger
/// it produces, so a mediation point that silently stops recording fails here
/// rather than a year from now.
struct MemoryEventTests {
    @Test @MainActor func fullLifecycleProducesExpectedLedger() throws {
        let container = try PackWisePersistence.container(inMemory: true)
        let model = ModelContext(container)
        let repo = TripRepository(context: model)
        let destination = try SharedLibrary.testDestinations().first { $0.city == "Chicago" }!
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        let trip = TripRecord(
            destination: destination,
            startDate: start,
            endDate: Calendar.current.date(byAdding: .day, value: 4, to: start)!,
            durationDays: 5,
            durationNights: 4,
            tripType: .cityBreak,
            activities: ["sightseeing"],
            bagType: .carryOn,
            packingStyle: .light,
            status: .packing,
            laundryAccess: .planned
        )
        model.insert(trip)

        // Generation: two engine suggestions.
        repo.replaceItems(on: trip, with: [
            PackingItemDraft(
                canonicalItemID: "clothing.tshirt", displayName: "T-shirts", category: .clothing,
                quantity: 4, importance: .normal, sourceSignals: [.baseEssential], reason: ""
            ),
            PackingItemDraft(
                canonicalItemID: "clothing.rain_jacket", displayName: "Rain jacket", category: .clothing,
                quantity: 1, importance: .normal, sourceSignals: [.weather], reason: ""
            )
        ])
        // User adds something of their own.
        repo.addItem(
            PackingItemDraft(
                canonicalItemID: nil, displayName: "Portable fan", category: .travelComfort,
                quantity: 1, importance: .optional, sourceSignals: [.userPreference], reason: "", isUserAdded: true
            ),
            to: trip
        )
        // Declines the jacket, edits and packs the shirts.
        let jacket = trip.items.first { $0.canonicalItemID == "clothing.rain_jacket" }!
        repo.markNotNeeded(jacket, on: trip)
        let tshirt = trip.items.first { $0.canonicalItemID == "clothing.tshirt" }!
        tshirt.quantity = 3
        tshirt.isUserModified = true
        tshirt.packedQuantity = 3
        repo.complete(trip)

        let events = try model.fetch(FetchDescriptor<PackingMemoryEventRecord>())
            .map(\.event)
            .sorted { ($0.timestamp, $0.canonicalItemID) < ($1.timestamp, $1.canonicalItemID) }

        func ofKind(_ kind: PackingMemoryEventKind) -> [PackingMemoryEvent] {
            events.filter { $0.kind == kind }
        }
        #expect(ofKind(.suggested).map(\.canonicalItemID).sorted() == ["clothing.rain_jacket", "clothing.tshirt"])
        #expect(ofKind(.suggested).first { $0.canonicalItemID == "clothing.tshirt" }?.value == 4)
        #expect(ofKind(.userAdded).map(\.canonicalItemID) == ["custom:Portable fan"])
        #expect(ofKind(.notNeeded).map(\.canonicalItemID) == ["clothing.rain_jacket"])
        #expect(ofKind(.quantityChanged).allSatisfy { $0.canonicalItemID == "clothing.tshirt" && $0.value == 3 })
        #expect(ofKind(.quantityChanged).count == 1)
        #expect(ofKind(.packed).map(\.canonicalItemID) == ["clothing.tshirt"], "the unpacked fan must not record a packed event")
        #expect(ofKind(.packed).first?.value == 3)

        // Every event carries the structured fingerprint, not a hash.
        for event in events {
            #expect(event.tripID == trip.id)
            #expect(event.context == ContextFingerprint(
                durationBucket: .medium,
                laundryPlan: .planned,
                packingStyle: .light,
                bag: .carryOn,
                tripType: .cityBreak,
                partySize: 1
            ))
        }

        // Completing twice must not double the snapshot.
        repo.complete(trip)
        #expect(try model.fetch(FetchDescriptor<PackingMemoryEventRecord>()).count == events.count)

        // Retention decision: deleting the trip keeps its packing history.
        repo.delete(trip)
        try model.save()
        let survivors = try model.fetch(FetchDescriptor<PackingMemoryEventRecord>())
        #expect(survivors.count == events.count, "memory events must survive trip deletion")
    }

    /// Regeneration keeps existing items without re-recording them; only a
    /// genuinely new suggestion earns a new event.
    @Test @MainActor func regenerationRecordsOnlyNewSuggestions() throws {
        let container = try PackWisePersistence.container(inMemory: true)
        let model = ModelContext(container)
        let repo = TripRepository(context: model)
        let destination = try SharedLibrary.testDestinations().first { $0.city == "Chicago" }!
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        let trip = TripRecord(
            destination: destination,
            startDate: start,
            endDate: Calendar.current.date(byAdding: .day, value: 2, to: start)!,
            durationDays: 3,
            durationNights: 2,
            tripType: .cityBreak,
            activities: [],
            bagType: .carryOn,
            packingStyle: .balanced,
            status: .packing
        )
        model.insert(trip)

        let tshirt = PackingItemDraft(
            canonicalItemID: "clothing.tshirt", displayName: "T-shirts", category: .clothing,
            quantity: 3, importance: .normal, sourceSignals: [.baseEssential], reason: ""
        )
        repo.replaceItems(on: trip, with: [tshirt])
        repo.replaceItems(on: trip, with: [
            tshirt,
            PackingItemDraft(
                canonicalItemID: "clothing.socks", displayName: "Socks", category: .clothing,
                quantity: 4, importance: .normal, sourceSignals: [.baseEssential], reason: ""
            )
        ])
        let suggested = try model.fetch(FetchDescriptor<PackingMemoryEventRecord>())
            .map(\.event)
            .filter { $0.kind == .suggested }
        #expect(suggested.map(\.canonicalItemID).sorted() == ["clothing.socks", "clothing.tshirt"])
    }
}
