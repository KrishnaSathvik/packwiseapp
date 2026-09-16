import Foundation
import SwiftData
import Testing
@testable import PackWise

/// Product Experience V2, Task 12 — one dedicated category selector shared by
/// Add Item and Item Detail, and the authority of a category the user chose.
@MainActor
struct CategorySelectorTests {
    // MARK: - Selector model

    @Test func selectorOffersEverySupportedCategoryOnceInCanonicalOrder() {
        let options = CategorySelection.options
        #expect(options == PackingCategory.displayOrder(international: false, outdoor: false), "the one ordering authority, no selector table")
        #expect(Set(options).count == PackingCategory.allCases.count)
        #expect(options.count == PackingCategory.allCases.count)
    }

    @Test func selectorMarksTheCurrentCategoryAndOnlyIt() {
        let selection = CategorySelection(current: .toiletries)
        #expect(selection.isSelected(.toiletries))
        #expect(PackingCategory.allCases.filter(selection.isSelected) == [.toiletries])
        #expect(selection.accessibilityValue(for: .toiletries) == "Selected")
        #expect(selection.accessibilityValue(for: .clothing) == nil)
    }

    @Test func choosingACategoryUpdatesTheAddDraftAndNothingElse() throws {
        var draft = AddItemDraft(name: "Sun hat", quantity: 2, category: .clothing, owner: .shared, important: true)
        draft.category = .toiletries
        #expect(draft.category == .toiletries)
        #expect(draft.name == "Sun hat")
        #expect(draft.quantity == 2)
        #expect(draft.owner == .shared)
        #expect(draft.important)
    }

    @Test func leavingTheSelectorWithoutChoosingKeepsThePriorCategory() {
        var draft = AddItemDraft(category: .clothing)
        let selection = CategorySelection(current: draft.category)
        // Backing out never calls choose.
        #expect(selection.current == .clothing)
        draft.category = selection.current
        #expect(draft.category == .clothing)
    }

    // MARK: - Fixtures

    private static let family: TripParty = {
        let you = Traveler.primarySelf()
        return TripParty(travelMode: .family, travelers: [
            you, Traveler(name: "Maya", role: .partner, ageGroup: .adult),
            Traveler(role: .child, ageGroup: .child, guardianTravelerID: you.id)
        ])
    }()
    private static let engine = PackingEngine(catalog: try! SharedLibrary.catalog(), rules: try! SharedLibrary.rules())

    private static func familyTrip(at url: URL? = nil) throws -> (TripRecord, ModelContext, ModelContainer) {
        let container: ModelContainer
        if let url { container = try PackWisePersistence.container(storeURL: url) } else { container = try PackWisePersistence.container(inMemory: true) }
        let context = ModelContext(container)
        let destination = try #require(try SharedLibrary.testDestinations().first { $0.city == "Chicago" })
        let start = Calendar.current.startOfDay(for: .now)
        let trip = TripRecord(
            destination: destination, startDate: start, endDate: Calendar.current.date(byAdding: .day, value: 4, to: start)!,
            durationDays: 5, durationNights: 4, tripType: .vacation, activities: ["sightseeing"], bagType: .checked,
            packingStyle: .balanced, status: .packing, travelerCount: 3, travelMode: .family,
            origin: TripOrigin(countryCode: "US", source: .userConfirmed)
        )
        context.insert(trip)
        let repo = TripRepository(context: context)
        try repo.applyTripTypes([.vacation], on: trip)
        repo.attach(party: family, bagTypes: [.checked], on: trip)
        repo.replaceItems(on: trip, with: engine.generate(context: trip.context(preferences: .deviceDefaults(), weather: nil)))
        try context.save()
        return (trip, context, container)
    }

    /// The edit-and-regenerate path `TripSetupView.saveTrip` takes for an
    /// existing trip, accepting every proposal.
    private static func regenerate(_ trip: TripRecord, in context: ModelContext, tripTypes: Set<TripType> = [.vacation, .beach]) throws {
        let repo = TripRepository(context: context)
        try repo.applyTripTypes(tripTypes, on: trip)
        let diff = engine.recommendationDiff(
            context: trip.context(preferences: .deviceDefaults(), weather: nil),
            existing: trip.items.map(\.draft),
            overrides: trip.overrides.map(\.draft)
        )
        repo.applyDiff(
            diff,
            addIDs: Set(diff.add.map(\.id)),
            removeIDs: Set(diff.removeCandidates.map(\.id)),
            quantityIDs: Set(diff.quantityChanges.map(\.existing.id)),
            on: trip
        )
        try context.save()
    }

    private static func record(_ trip: TripRecord, _ canonical: String, for traveler: Traveler) throws -> PackingItemRecord {
        try #require(trip.items.first { $0.canonicalItemID == canonical && $0.travelerID == traveler.id })
    }

    // MARK: - Authority

    @Test func aUserChosenCategorySurvivesRegeneration() throws {
        let (trip, context, _) = try Self.familyTrip()
        let maya = Self.family.travelers[1]
        let shirts = try Self.record(trip, "clothing.tshirt", for: maya)
        let before = shirts.quantity
        ItemCategoryEdit.apply(.miscellaneous, to: shirts)
        try context.save()

        try Self.regenerate(trip, in: context)
        let after = try Self.record(trip, "clothing.tshirt", for: maya)
        #expect(after.id == shirts.id, "the same record, not a re-added one")
        #expect(after.category == .miscellaneous, "the engine's clothing category never silently returns")
        #expect(after.quantity == before)
        #expect(trip.items.filter { $0.canonicalItemID == "clothing.tshirt" }.count == 3, "no duplicate shirt row for Maya")
        #expect(trip.items.filter { $0.canonicalItemID == "clothing.tshirt" && $0.category == .clothing }.count == 2)
    }

    @Test func manualQuantityAndCategoryBothSurviveRegeneration() throws {
        let (trip, context, _) = try Self.familyTrip()
        let shirts = try Self.record(trip, "clothing.tshirt", for: Self.family.primary)
        shirts.quantity = 11
        shirts.isUserModified = true
        ItemCategoryEdit.apply(.travelComfort, to: shirts)
        try context.save()
        try Self.regenerate(trip, in: context)
        #expect(shirts.quantity == 11)
        #expect(shirts.category == .travelComfort)
    }

    @Test func packedStateSurvivesACategoryChangeAndRegeneration() throws {
        let (trip, context, _) = try Self.familyTrip()
        let brush = try Self.record(trip, "toiletries.toothbrush", for: Self.family.primary)
        brush.packedQuantity = brush.quantity
        ItemCategoryEdit.apply(.health, to: brush)
        try context.save()
        #expect(brush.isPacked)
        try Self.regenerate(trip, in: context)
        #expect(brush.isPacked)
        #expect(brush.category == .health)
    }

    @Test func ownerAndCarrierAreUntouchedByACategoryChange() throws {
        let (trip, context, _) = try Self.familyTrip()
        let child = Self.family.travelers[2]
        let shirts = try Self.record(trip, "clothing.tshirt", for: child)
        let owner = shirts.travelerID, carrier = shirts.assignedTravelerID, ownership = shirts.ownershipType
        let shared = try #require(trip.items.first { $0.ownershipType == .shared })
        let sharedCarrier = shared.assignedTravelerID
        ItemCategoryEdit.apply(.kids, to: shirts)
        ItemCategoryEdit.apply(.miscellaneous, to: shared)
        try context.save()
        try Self.regenerate(trip, in: context)
        #expect(shirts.travelerID == owner)
        #expect(shirts.assignedTravelerID == carrier)
        #expect(shirts.ownershipType == ownership)
        #expect(shared.ownershipType == .shared)
        #expect(shared.travelerID == nil)
        #expect(shared.assignedTravelerID == sharedCarrier)
        #expect(shared.category == .miscellaneous)
    }

    @Test func aCustomItemsCategorySurvivesARelaunch() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CategorySelectorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("packwise.store")
        let tripID: UUID
        let customID: UUID
        do {
            let (trip, context, _) = try Self.familyTrip(at: url)
            tripID = trip.id
            let draft = PackingItemDraft(
                canonicalItemID: nil, displayName: "Kite", category: .activities, quantity: 1, importance: .normal,
                sourceSignals: [.userPreference], reason: "Added by you", isUserAdded: true,
                ownershipType: .personal, travelerID: Self.family.primary.id
            )
            customID = draft.id
            TripRepository(context: context).addItem(draft, to: trip)
            let kite = try #require(trip.items.first { $0.id == customID })
            ItemCategoryEdit.apply(.kids, to: kite)
            try context.save()
        }
        let container = try PackWisePersistence.container(storeURL: url)
        let context = ModelContext(container)
        let trip = try #require(try context.fetch(FetchDescriptor<TripRecord>()).first { $0.id == tripID })
        let kite = try #require(trip.items.first { $0.id == customID })
        #expect(kite.category == .kids)
        #expect(kite.isUserAdded)
        try Self.regenerate(trip, in: context)
        #expect(kite.category == .kids, "regeneration leaves custom rows alone")
    }

    @Test func editingOneTravelersCategoryMovesOnlyThatRecordOutOfItsGroup() throws {
        let (trip, context, _) = try Self.familyTrip()
        let maya = Self.family.travelers[1]
        let shirts = try Self.record(trip, "clothing.tshirt", for: maya)
        ItemCategoryEdit.apply(.miscellaneous, to: shirts)
        try context.save()
        let sections = PackingListAggregator.sections(
            items: trip.items.map(PackingListItem.init(record:)), party: trip.party,
            order: PackingCategory.displayOrder(international: false, outdoor: false), query: PackingListQuery()
        )
        let clothing = try #require(sections.first { $0.category == .clothing })
        let group = try #require(clothing.rows.compactMap { if case .personalGroup(let g) = $0, g.canonicalItemID == "clothing.tshirt" { g } else { nil } }.first)
        #expect(group.members.map(\.travelerLabel) == ["You", "Child 1"])
        let misc = try #require(sections.first { $0.category == .miscellaneous })
        #expect(misc.rows.contains { $0.recordIDs == [shirts.id] })
        #expect(shirts.updatedAt >= shirts.createdAt)
    }
}
