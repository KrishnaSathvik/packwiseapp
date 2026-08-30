import Foundation
import SwiftData
import Testing
@testable import PackWise

struct M1LoopTests {
    @Test func destinationTimezoneNeverFallsBackToDevice() {
        let tokyo = DestinationNormalizer.destination(
            city: "Tokyo",
            region: "Tokyo",
            country: "Japan",
            countryCode: "JP",
            latitude: 35.6762,
            longitude: 139.6503,
            mapKitTimeZone: "Asia/Tokyo",
            placemarkTimeZone: nil,
            mapKitIdentifier: nil
        )
        #expect(tokyo.timeZone == "Asia/Tokyo")
        #expect(tokyo.countryCode == "JP")
        #expect(tokyo.latitude == 35.6762)

        let unknown = DestinationNormalizer.destination(
            city: "Somewhere",
            region: "",
            country: "",
            countryCode: "",
            latitude: 10,
            longitude: 20,
            mapKitTimeZone: nil,
            placemarkTimeZone: nil,
            mapKitIdentifier: nil
        )
        #expect(unknown.timeZone.isEmpty)
        #expect(unknown.timeZone != TimeZone.current.identifier || TimeZone.current.identifier.isEmpty)
    }

    @Test @MainActor func notNeededStoresOverrideAndDeleteDoesNot() throws {
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
        let repo = TripRepository(context: context)
        repo.addItem(
            PackingItemDraft(
                canonicalItemID: "clothing.rain_jacket",
                displayName: "Rain jacket",
                category: .clothing,
                quantity: 1,
                importance: .important,
                sourceSignals: [.weather],
                reason: "Rain is expected."
            ),
            to: trip
        )
        repo.addItem(
            PackingItemDraft(
                canonicalItemID: nil,
                displayName: "Portable fan",
                category: .travelComfort,
                quantity: 1,
                importance: .optional,
                sourceSignals: [.userPreference],
                reason: "Added by you",
                isUserAdded: true
            ),
            to: trip
        )
        try context.save()

        let jacket = try #require(trip.items.first { $0.canonicalItemID == "clothing.rain_jacket" })
        repo.markNotNeeded(jacket, on: trip)
        #expect(trip.overrides.contains { $0.canonicalItemID == "clothing.rain_jacket" && $0.action == "removed" })
        #expect(!trip.items.contains { $0.canonicalItemID == "clothing.rain_jacket" })

        let fan = try #require(trip.items.first { $0.displayName == "Portable fan" })
        repo.deleteItem(fan, on: trip)
        #expect(!trip.items.contains { $0.displayName == "Portable fan" })
        #expect(trip.overrides.allSatisfy { $0.canonicalItemID == "clothing.rain_jacket" })
    }

    @Test @MainActor func completeTripMovesStatusToCompleted() throws {
        let container = try PackWisePersistence.container(inMemory: true)
        let context = ModelContext(container)
        let destination = try SharedLibrary.testDestinations().first { $0.city == "Chicago" }!
        let trip = TripRecord(
            destination: destination,
            startDate: .now,
            endDate: Calendar.current.date(byAdding: .day, value: 2, to: .now)!,
            durationDays: 3,
            durationNights: 2,
            tripType: .cityBreak,
            activities: ["walking"],
            bagType: .carryOn,
            packingStyle: .balanced,
            status: .packing
        )
        context.insert(trip)
        TripRepository(context: context).complete(trip)
        #expect(trip.status == .completed)
    }

    @Test @MainActor func applyDiffAddsWithoutTouchingPackedCustomItem() throws {
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
        let repo = TripRepository(context: context)
        let shirt = PackingItemDraft(
            canonicalItemID: "clothing.tshirt",
            displayName: "T-shirts",
            category: .clothing,
            quantity: 4,
            packedQuantity: 4,
            importance: .normal,
            sourceSignals: [.baseEssential],
            reason: "A core item."
        )
        repo.addItem(shirt, to: trip)
        let add = PackingItemDraft(
            canonicalItemID: "footwear.hiking_shoes",
            displayName: "Hiking shoes",
            category: .footwear,
            quantity: 1,
            importance: .important,
            sourceSignals: [.activity],
            reason: "Hiking is on your plans."
        )
        let diff = RecommendationDiff(add: [add], removeCandidates: [], quantityChanges: [])
        repo.applyDiff(diff, addIDs: [add.id], removeIDs: [], quantityIDs: [], on: trip)
        #expect(trip.items.contains { $0.canonicalItemID == "footwear.hiking_shoes" })
        #expect(trip.items.contains { $0.canonicalItemID == "clothing.tshirt" && $0.packedQuantity == 4 })
    }

    @Test func mergedActivityIDsNormalizeOnRead() throws {
        // A trip saved before fineDining was merged still holds the old value.
        // Left alone it would lose its packing rule and be rejected by the
        // intelligence API's closed vocabulary.
        #expect(ActivityVocabulary.normalize("fineDining") == "niceDinner")
        #expect(ActivityVocabulary.normalize("hiking") == "hiking")
        #expect(
            ActivityVocabulary.normalize(["walking", "fineDining", "niceDinner"])
                == ["walking", "niceDinner"]
        )
    }
}
