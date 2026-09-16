import Foundation
import SwiftData
import Testing
@testable import PackWise

struct M1LoopTests {
    @Test func ordinaryCustomActivitiesNeverUseTheSparkleFallback() {
        #expect(PackWiseActivityStyle.symbol(for: "camping") == "tent")
        #expect(PackWiseActivityStyle.symbol(for: "roadTrip") == "car")
    }

    @Test func tripCardsOnlyShowProgressWhenItCarriesInformation() {
        #expect(TripPackingPresentationState.resolve(packed: 0, total: 0, isFinished: false) == .empty)
        #expect(TripPackingPresentationState.resolve(packed: 0, total: 12, isFinished: false) == .ready)
        #expect(TripPackingPresentationState.resolve(packed: 3, total: 12, isFinished: false) == .inProgress)
        #expect(TripPackingPresentationState.resolve(packed: 12, total: 12, isFinished: false) == .allPacked)
        #expect(TripPackingPresentationState.resolve(packed: 9, total: 12, isFinished: true) == .completed)
    }

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

    #if DEBUG
    /// Checkpoint V (run with Task 8.1): every reference state the whole-product
    /// contact sheet needs is a capturable Debug preview screen, so no major
    /// surface silently drops out of the review.
    @Test func checkpointVReferenceStatesAreAllCapturable() {
        let required = [
            "onboarding", "onboardingTrip", "onboardingPersonal", "tripsHome",
            "setupDestination", "setupDates", "setupTravelers", "setupTravelersFamilyDetails", "setupTravelersGroup",
            "setupTripTypes", "setupActivities", "setupBags", "setupStyleLaundry", "setupPreferences", "setupReview",
            "tripDetail", "packingList", "packingListFamily", "addItem", "addItemCategory", "itemDetailSheet",
        ]
        for id in required {
            #expect(DebugPreviewScreen(rawValue: id) != nil, "missing reference state \(id)")
        }
    }
    #endif

    #if DEBUG
    /// Task 9: every destination and onboarding state the contact sheet
    /// reviews is capturable.
    @Test func task9ReferenceStatesAreAllCapturable() {
        let required = [
            "onboarding", "onboardingTrip", "onboardingPersonal",
            "setupDestinationEmpty", "setupDestinationRecents", "setupDestinationSearching", "setupDestinationResults",
            "setupDestinationChicago", "setupDestinationKhammam", "setupDestinationLong", "setupDestinationOffline",
            "setupReview", "setupReviewMap", "setupReviewOffline", "tripsHome", "tripDetail", "tripDetailOffline",
            "setupDestinationNoMatch", "setupDestinationUnavailable", "setupDestinationUnavailableKept",
        ]
        for id in required {
            #expect(DebugPreviewScreen(rawValue: id) != nil, "missing Task 9 state \(id)")
        }
    }
    #endif

    // MARK: - Task 10: every non-empty category on Trip Detail

    private static func entries(_ categories: [PackingCategory], packedEvery: Int = 0) -> [(category: PackingCategory, isPacked: Bool)] {
        var result: [(category: PackingCategory, isPacked: Bool)] = []
        for category in categories {
            for index in 0..<3 {
                result.append((category, packedEvery > 0 && index % packedEvery == 0))
            }
        }
        return result
    }

    @Test func tripDetailShowsEveryNonEmptyCategoryInDisplayOrder() {
        let order = PackingCategory.displayOrder(international: false, outdoor: false)
        #expect(order.count == 11)
        let summaries = TripDetailCategoryOverview.summaries(
            of: Self.entries(order.reversed(), packedEvery: 3),
            order: order
        )
        #expect(summaries.map(\.category) == order, "all eleven, in the canonical order, not insertion order")
        #expect(summaries.allSatisfy { $0.total == 3 && $0.packed == 1 })
    }

    @Test func tripDetailHidesEmptyCategoriesWithoutPlaceholders() {
        let order = PackingCategory.displayOrder(international: true, outdoor: false)
        let summaries = TripDetailCategoryOverview.summaries(
            of: Self.entries([.clothing, .documents, .miscellaneous]),
            order: order
        )
        #expect(summaries.map(\.category) == [.documents, .clothing, .miscellaneous])
        #expect(TripDetailCategoryOverview.summaries(of: [], order: order).isEmpty)
    }

    @Test func categoryOrderDerivesOutdoorFromTheTripTypeSet() {
        #expect(PackingCategory.displayOrder(international: false, tripTypes: [.beach, .outdoor])
            == PackingCategory.displayOrder(international: false, outdoor: true),
            "a multi-type trip that includes Outdoor orders as outdoor")
        #expect(PackingCategory.displayOrder(international: true, tripTypes: [.beach])
            == PackingCategory.displayOrder(international: true, outdoor: false))
        #expect(PackingCategory.displayOrder(international: false, tripTypes: [])
            == PackingCategory.allCases)
    }

    #if DEBUG
    /// Task 10: the all-categories Trip Detail is capturable, top and scrolled.
    @Test func task10ReferenceStatesAreAllCapturable() {
        for id in ["tripDetailAllCategories", "tripDetailAllCategoriesMiddle", "tripDetailAllCategoriesScrolled", "packingListScrolled"] {
            #expect(DebugPreviewScreen(rawValue: id) != nil, "missing Task 10 state \(id)")
        }
        #expect(DebugPreviewScreen.tripDetailAllCategoriesScrolled.initialScrollAnchor == .bottom)
        #expect(DebugPreviewScreen.tripDetailAllCategoriesMiddle.initialScrollAnchor == .center)
        #expect(DebugPreviewScreen.tripDetailAllCategories.initialScrollAnchor == nil)
    }
    #endif

    #if DEBUG
    /// Task 11: every Packing List state the contact sheet reviews is capturable.
    @Test func task11ReferenceStatesAreAllCapturable() {
        let required = [
            "packingList", "packingListCouple", "packingListFamily",
            "packingListFamilyYou", "packingListFamilyAdult1", "packingListFamilyChild1", "packingListFamilyShared",
            "packingListFamilyMiddle", "packingListFamilyBottom",
            "packingListFamilyToPack", "packingListFamilyPacked", "packingListFamilyImportant", "packingListFamilyHidePacked",
            "packingListFamilySearchItem", "packingListFamilySearchTraveler", "packingListFamilySearchNone",
            "packingListFamilyGroupTshirts", "packingListFamilyGroupToothbrush",
        ]
        for id in required {
            #expect(DebugPreviewScreen(rawValue: id) != nil, "missing Task 11 state \(id)")
        }
    }
    #endif

    #if DEBUG
    /// Task 12: every category-selector state the contact sheet reviews is capturable.
    @Test func task12ReferenceStatesAreAllCapturable() {
        for id in ["addItem", "addItemCategory", "addItemCategoryChosen", "addItemChosen", "itemDetailSheet", "itemDetailCategory", "itemDetailMoved", "packingListFamilyMoved"] {
            #expect(DebugPreviewScreen(rawValue: id) != nil, "missing Task 12 state \(id)")
        }
    }
    #endif

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
