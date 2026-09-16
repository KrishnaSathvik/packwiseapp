import Foundation
import SwiftData
import Testing
@testable import PackWise

/// Product Experience V2, Task 11 — the family Packing List's All scope
/// aggregates identical personal records into one presentation row without
/// collapsing the records underneath. Aggregation is pure, deterministic,
/// and read-only: every mutation targets a real `PackingItemRecord` ID.
@MainActor
struct PackingListAggregationTests {
    // MARK: - Fixtures

    private static let you = Traveler.primarySelf()
    private static let alex = Traveler(name: "Alex", role: .partner, ageGroup: .adult)
    private static let adult2 = Traveler(role: .otherAdult, ageGroup: .adult)
    private static let child1 = Traveler(role: .child, ageGroup: .child, guardianTravelerID: you.id)
    private static let family = TripParty(travelMode: .family, travelers: [you, alex, adult2, child1])
    private static let order = PackingCategory.displayOrder(international: false, outdoor: false)

    private static func personal(
        _ canonical: String?, _ name: String, _ category: PackingCategory, for traveler: Traveler,
        quantity: Int = 1, packed: Int = 0, importance: ItemImportance = .normal, userAdded: Bool = false
    ) -> PackingListItem {
        PackingListItem(
            id: UUID(), canonicalItemID: canonical, displayName: name, category: category,
            quantity: quantity, packedQuantity: packed, importance: importance,
            ownershipType: .personal, travelerID: traveler.id, assignedTravelerID: traveler.id, isUserAdded: userAdded
        )
    }

    private static func shared(
        _ canonical: String?, _ name: String, _ category: PackingCategory,
        quantity: Int = 1, packed: Int = 0, carrier: Traveler? = nil
    ) -> PackingListItem {
        PackingListItem(
            id: UUID(), canonicalItemID: canonical, displayName: name, category: category,
            quantity: quantity, packedQuantity: packed, importance: .normal,
            ownershipType: .shared, travelerID: nil, assignedTravelerID: carrier?.id, isUserAdded: false
        )
    }

    private static func toothbrushes(packed: [Int] = [0, 0, 0, 0]) -> [PackingListItem] {
        zip(family.travelers, packed).map { personal("toiletries.toothbrush", "Toothbrush", .toiletries, for: $0, packed: $1) }
    }

    private static func tshirts() -> [PackingListItem] {
        zip(family.travelers, [5, 5, 5, 9]).map { personal("clothing.tshirt", "T-shirts", .clothing, for: $0, quantity: $1) }
    }

    private static func rows(
        _ items: [PackingListItem], party: TripParty = family, query: PackingListQuery = PackingListQuery()
    ) -> [PackingListPresentationRow] {
        PackingListAggregator.sections(items: items, party: party, order: order, query: query).flatMap(\.rows)
    }

    private static func groups(_ rows: [PackingListPresentationRow]) -> [PersonalItemGroup] {
        rows.compactMap { if case .personalGroup(let group) = $0 { group } else { nil } }
    }

    // MARK: - 21. Pure aggregation

    @Test func fourPersonalToothbrushesBecomeOneGroupOverFourRecords() throws {
        let items = Self.toothbrushes()
        let rows = Self.rows(items)
        #expect(rows.count == 1)
        let group = try #require(Self.groups(rows).first)
        #expect(group.canonicalItemID == "toiletries.toothbrush")
        #expect(group.category == .toiletries)
        #expect(group.displayName == "Toothbrush")
        #expect(Set(group.recordIDs) == Set(items.map(\.id)), "every record survives underneath")
        #expect(group.travelerCount == 4)
        #expect(group.completedTravelerCount == 0)
        #expect(group.totalQuantity == 4)
        #expect(!group.isComplete)
        #expect(group.travelerSummary == "4 personal")
        #expect(group.progressText == "0 / 4")
    }

    @Test func tshirtGroupKeepsEveryTravelersQuantity() throws {
        let group = try #require(Self.groups(Self.rows(Self.tshirts())).first)
        #expect(group.members.map(\.travelerLabel) == ["You", "Alex", "Adult 2", "Child 1"], "party order")
        #expect(group.members.map(\.quantity) == [5, 5, 5, 9])
        #expect(group.totalQuantity == 24)
        #expect(group.travelerSummary == "You ×5 · Alex ×5 · Adult 2 ×5 · Child 1 ×9")
        #expect(group.progressText == "0 / 4")
    }

    @Test func sharedUmbrellaStaysOneSharedRowApartFromPersonalRows() throws {
        let umbrella = Self.shared("essentials.umbrella_compact", "Compact umbrella", .essentials, quantity: 2, carrier: Self.alex)
        let personalUmbrellas = [Self.you, Self.alex].map { Self.personal("essentials.umbrella_compact", "Compact umbrella", .essentials, for: $0) }
        let rows = Self.rows(personalUmbrellas + [umbrella])
        #expect(rows.count == 2)
        let sharedRows = rows.compactMap { if case .shared(let entry) = $0 { entry } else { nil } }
        #expect(sharedRows.count == 1)
        #expect(sharedRows.first?.id == umbrella.id)
        #expect(sharedRows.first?.carrierLabel == "Alex")
        #expect(sharedRows.first?.secondaryText == "Shared · Alex carries")
        let group = try #require(Self.groups(rows).first)
        #expect(Set(group.recordIDs) == Set(personalUmbrellas.map(\.id)), "the shared row never joins the personal group")
    }

    @Test func sharedRowWithoutACarrierSaysOnlyShared() throws {
        let sunscreen = Self.shared("toiletries.sunscreen", "Sunscreen", .toiletries, quantity: 2)
        let rows = Self.rows([sunscreen])
        guard case .shared(let entry) = try #require(rows.first) else { Issue.record("expected a shared row"); return }
        #expect(entry.secondaryText == "Shared")
        #expect(entry.carrierLabel == nil)
    }

    @Test func sameCanonicalIDInDifferentCategoriesDoesNotMerge() throws {
        let items = [
            Self.personal("kids.snacks", "Snacks", .kids, for: Self.you),
            Self.personal("kids.snacks", "Snacks", .kids, for: Self.alex),
            Self.personal("kids.snacks", "Snacks", .miscellaneous, for: Self.adult2),
            Self.personal("kids.snacks", "Snacks", .miscellaneous, for: Self.child1),
        ]
        let sections = PackingListAggregator.sections(items: items, party: Self.family, order: Self.order, query: PackingListQuery())
        #expect(sections.map(\.category) == [.kids, .miscellaneous])
        #expect(sections.allSatisfy { $0.rows.count == 1 })
        #expect(Self.groups(sections.flatMap(\.rows)).map { Set($0.recordIDs) } == [Set(items[0...1].map(\.id)), Set(items[2...3].map(\.id))])
    }

    @Test func customItemsWithLookalikeNamesNeverMergeWithoutAStableIdentity() throws {
        let items = [
            Self.personal(nil, "Charger", .electronics, for: Self.you, userAdded: true),
            Self.personal(nil, "Charger", .electronics, for: Self.alex, userAdded: true),
            Self.personal(nil, "charger ", .electronics, for: Self.adult2, userAdded: true),
        ]
        let rows = Self.rows(items)
        #expect(rows.count == 3)
        #expect(Self.groups(rows).isEmpty)
        #expect(rows.allSatisfy { if case .individual = $0 { true } else { false } })
    }

    @Test func customItemsWithACanonicalIdentityDoAggregate() throws {
        let items = [
            Self.personal("electronics.power_bank", "Portable charger", .electronics, for: Self.you, userAdded: true),
            Self.personal("electronics.power_bank", "Portable charger", .electronics, for: Self.alex),
        ]
        let group = try #require(Self.groups(Self.rows(items)).first)
        #expect(group.travelerCount == 2)
    }

    @Test func aSinglePersonalRecordIsAnIndividualRowNotAGroupOfOne() throws {
        let rows = Self.rows([Self.personal("electronics.laptop", "Laptop", .electronics, for: Self.alex)])
        guard case .individual(let entry) = try #require(rows.first) else { Issue.record("expected an individual row"); return }
        #expect(entry.travelerLabel == "Alex")
        #expect(Self.groups(rows).isEmpty)
    }

    // MARK: - Labels (Step 3)

    @Test func travelerLabelsUseNamesAndStablePositionalFallbacks() throws {
        let group = try #require(Self.groups(Self.rows(Self.toothbrushes())).first)
        #expect(group.members.map(\.travelerLabel) == ["You", "Alex", "Adult 2", "Child 1"])
        #expect(group.members.map(\.travelerID) == Self.family.travelers.map(\.id), "identity is the traveler ID, never the label")

        let renamedAdult2 = Traveler(id: Self.adult2.id, name: "Sam", role: .otherAdult, ageGroup: .adult)
        let renamed = TripParty(travelMode: .family, travelers: [Self.you, Self.alex, renamedAdult2, Self.child1])
        let renamedGroup = try #require(Self.groups(Self.rows(Self.toothbrushes(), party: renamed)).first)
        #expect(renamedGroup.members.map(\.travelerLabel) == ["You", "Alex", "Sam", "Child 1"])
        #expect(renamedGroup.members.map(\.travelerID) == group.members.map(\.travelerID))
    }

    @Test func peopleScopeLabelsFollowTheSameRule() throws {
        let labels = PackingListAggregator.scopeLabels(for: Self.family)
        #expect(labels.map(\.title) == ["All", "You", "Alex", "Adult 2", "Child 1", "Shared"])
        #expect(labels.map(\.scope) == Self.family.listFilters())
    }

    // MARK: - 22. Search, status, scope

    @Test func searchMatchesBeforeAggregation() throws {
        let items = Self.toothbrushes() + Self.tshirts()
        let byName = Self.rows(items, query: PackingListQuery(search: "tooth"))
        #expect(byName.count == 1)
        #expect(Self.groups(byName).first?.canonicalItemID == "toiletries.toothbrush")
        #expect(Self.groups(byName).first?.travelerCount == 4, "the whole group, not a partial one")
    }

    @Test func travelerSearchReturnsTheRecordsThatIncludeThatTraveler() throws {
        let items = Self.toothbrushes() + [Self.personal("electronics.laptop", "Laptop", .electronics, for: Self.alex)]
        let rows = Self.rows(items, query: PackingListQuery(search: "Alex"))
        #expect(rows.map(\.displayName) == ["Toothbrush", "Laptop"], "category order, Toiletries before Electronics")
        // Only Alex's toothbrush matches, and one record is not a group: it
        // reads as Alex's own row, exactly as it would in Alex's scope.
        guard case .individual(let toothbrush) = rows[0] else { Issue.record("one matching record is an individual row"); return }
        #expect(toothbrush.travelerLabel == "Alex")
        #expect(toothbrush.item.canonicalItemID == "toiletries.toothbrush")
        guard case .individual(let laptop) = rows[1] else { Issue.record("laptop is Alex's own row"); return }
        #expect(laptop.travelerLabel == "Alex")
        #expect(Self.groups(rows).isEmpty)

        #expect(Self.rows(items, query: PackingListQuery(search: "Adult 2")).map(\.displayName) == ["Toothbrush"])
        #expect(Self.rows(items, query: PackingListQuery(search: "zzz")).isEmpty)
    }

    @Test func toPackShowsAPartiallyPackedGroupWithOnlyItsUnpackedRecords() throws {
        let items = Self.toothbrushes(packed: [1, 0, 1, 0])
        let rows = Self.rows(items, query: PackingListQuery(status: .toPack))
        let group = try #require(Self.groups(rows).first)
        #expect(group.members.map(\.travelerLabel) == ["Alex", "Child 1"])
        #expect(group.progressText == "0 / 2", "progress uses only the active scope")
        #expect(Self.rows(Self.toothbrushes(packed: [1, 1, 1, 1]), query: PackingListQuery(status: .toPack)).isEmpty)
    }

    @Test func packedShowsPartialAndFullGroupsDistinctly() throws {
        let partial = try #require(Self.groups(Self.rows(Self.toothbrushes(packed: [1, 0, 1, 0]), query: PackingListQuery(status: .packed))).first)
        #expect(partial.members.map(\.travelerLabel) == ["You", "Adult 2"])
        #expect(partial.progressText == "2 / 2")
        #expect(partial.isComplete)

        let unfiltered = try #require(Self.groups(Self.rows(Self.toothbrushes(packed: [1, 0, 1, 0]))).first)
        #expect(unfiltered.progressText == "2 / 4")
        #expect(!unfiltered.isComplete)
        #expect(unfiltered.completedTravelerCount == 2)

        let full = try #require(Self.groups(Self.rows(Self.toothbrushes(packed: [1, 1, 1, 1]))).first)
        #expect(full.isComplete)
        #expect(full.progressText == "4 / 4")
    }

    @Test func importantShowsAGroupWhenAnyRecordIsImportantWithoutChangingTheOthers() throws {
        var items = Self.toothbrushes()
        items[2].importance = .important
        items[3].importance = .critical
        let rows = Self.rows(items, query: PackingListQuery(status: .important))
        let group = try #require(Self.groups(rows).first)
        #expect(group.members.map(\.travelerLabel) == ["Adult 2", "Child 1"])
        #expect(group.importance == .critical, "the strongest member importance, read only")
        #expect(items.filter(\.isImportant).count == 2, "no record's importance changed")

        let unfiltered = try #require(Self.groups(Self.rows(items)).first)
        #expect(unfiltered.importance == .critical)
        #expect(unfiltered.members.map(\.importance) == [.normal, .normal, .important, .critical])

        var single = Self.toothbrushes()
        single[1].importance = .important
        let singleRows = Self.rows(single, query: PackingListQuery(status: .important))
        guard case .individual(let alex) = try #require(singleRows.first) else { Issue.record("one matching record is an individual row"); return }
        #expect(alex.travelerLabel == "Alex")
        #expect(Self.rows(Self.toothbrushes(), query: PackingListQuery(status: .important)).isEmpty)
    }

    @Test func hidePackedKeepsAGroupWhoseOtherTravelersAreStillUnpacked() throws {
        let items = Self.toothbrushes(packed: [1, 0, 0, 0])
        let group = try #require(Self.groups(Self.rows(items, query: PackingListQuery(hidePacked: true))).first)
        #expect(group.members.map(\.travelerLabel) == ["Alex", "Adult 2", "Child 1"])
        #expect(Self.rows(Self.toothbrushes(packed: [1, 1, 1, 1]), query: PackingListQuery(hidePacked: true)).isEmpty)
    }

    @Test func sharedScopeShowsOnlySharedRecords() throws {
        let sunscreen = Self.shared("toiletries.sunscreen", "Sunscreen", .toiletries, quantity: 2, packed: 2, carrier: Self.alex)
        let items = Self.toothbrushes() + [sunscreen, Self.personal("toiletries.sunscreen", "Sunscreen", .toiletries, for: Self.you)]
        let rows = Self.rows(items, query: PackingListQuery(scope: .shared))
        #expect(rows.count == 1)
        guard case .shared(let entry) = try #require(rows.first) else { Issue.record("expected the shared row"); return }
        #expect(entry.id == sunscreen.id)
        #expect(entry.item.quantity == 2)
        #expect(entry.item.isPacked)
        #expect(entry.carrierLabel == "Alex")
    }

    @Test func travelerScopeShowsThatTravelersRawRecordsWithoutAggregation() throws {
        let items = Self.toothbrushes() + Self.tshirts() + [Self.shared("toiletries.sunscreen", "Sunscreen", .toiletries)]
        let rows = Self.rows(items, query: PackingListQuery(scope: .traveler(Self.alex.id)))
        #expect(rows.count == 2)
        #expect(Self.groups(rows).isEmpty)
        #expect(rows.allSatisfy { row in
            if case .individual(let entry) = row { entry.item.travelerID == Self.alex.id } else { false }
        })
        #expect(rows.map(\.displayName) == ["T-shirts", "Toothbrush"])
    }

    @Test func soloListsNeverAggregateAndHaveNoPeopleScope() throws {
        let solo = TripParty.solo()
        let items = [Self.personal("toiletries.toothbrush", "Toothbrush", .toiletries, for: solo.primary)]
        let rows = Self.rows(items, party: solo)
        #expect(Self.groups(rows).isEmpty)
        #expect(PackingListAggregator.scopeLabels(for: solo).isEmpty)
    }

    @Test func statusCountsComeFromScopedUnderlyingRecords() throws {
        let items = Self.toothbrushes(packed: [1, 0, 0, 0]) + Self.tshirts()
        let all = PackingListAggregator.statusCounts(items: items, party: Self.family, query: PackingListQuery())
        #expect(all[.toPack] == 7)
        #expect(all[.packed] == 1)
        let alex = PackingListAggregator.statusCounts(items: items, party: Self.family, query: PackingListQuery(scope: .traveler(Self.alex.id)))
        #expect(alex[.toPack] == 2)
        #expect(alex[.packed] == 0)
    }

    @Test func categorySectionsSurviveAggregationInDisplayOrder() throws {
        let items = Self.tshirts() + Self.toothbrushes()
            + [Self.you, Self.alex].map { Self.personal("footwear.walking_shoes", "Walking shoes", .footwear, for: $0, packed: 1) }
        let sections = PackingListAggregator.sections(items: items, party: Self.family, order: Self.order, query: PackingListQuery())
        #expect(sections.map(\.category) == [.clothing, .footwear, .toiletries])
        #expect(sections.map(\.completedCount) == [0, 2, 0])
        #expect(sections.map(\.totalCount) == [4, 2, 4], "section counts are record-level, like the rows")
        #expect(sections[1].isComplete)
    }

    @Test func groupRowsHaveAConciseAccessibilityLabel() throws {
        let toothbrush = try #require(Self.groups(Self.rows(Self.toothbrushes(packed: [1, 1, 0, 0]))).first)
        #expect(toothbrush.accessibilityLabel == "Toothbrush. 4 travelers. 2 of 4 packed.")
        let tshirts = try #require(Self.groups(Self.rows(Self.tshirts())).first)
        #expect(tshirts.accessibilityLabel == "T-shirts. 4 travelers. 0 of 4 packed. You 5, Alex 5, Adult 2 5, Child 1 9.")
        let big = TripParty(travelMode: .group, travelers: [Self.you] + (1...6).map { _ in Traveler(role: .otherAdult, ageGroup: .adult) })
        let bigItems = big.travelers.enumerated().map { Self.personal("clothing.tshirt", "T-shirts", .clothing, for: $1, quantity: 2 + $0) }
        let bigGroup = try #require(Self.groups(Self.rows(bigItems, party: big)).first)
        #expect(bigGroup.accessibilityLabel == "T-shirts. 7 travelers. 0 of 7 packed.", "no per-traveler recital for large groups")
    }

    @Test func aggregationIsDeterministicAndCheapForHundredsOfRows() throws {
        let big = TripParty(travelMode: .group, travelers: [Self.you] + (1...7).map { _ in Traveler(role: .otherAdult, ageGroup: .adult) })
        var items: [PackingListItem] = []
        for index in 0..<60 {
            let category = PackingCategory.allCases[index % PackingCategory.allCases.count]
            for traveler in big.travelers {
                items.append(Self.personal("item.\(index)", "Item \(index)", category, for: traveler, packed: index % 3 == 0 ? 1 : 0))
            }
        }
        #expect(items.count == 480)
        let clock = ContinuousClock()
        var first: [PackingListSection] = []
        let elapsed = clock.measure {
            first = PackingListAggregator.sections(items: items, party: big, order: Self.order, query: PackingListQuery())
        }
        let second = PackingListAggregator.sections(items: items.shuffled(), party: big, order: Self.order, query: PackingListQuery())
        #expect(first == second, "input order never changes the output")
        #expect(first.flatMap(\.rows).count == 60)
        #expect(elapsed < .milliseconds(50), "\(elapsed)")
    }

    /// The physical-device fixture: You, Maya, a toddler, and a teen on a
    /// beach vacation, generated by the real engine. Every record survives;
    /// the All scope shows one row per item instead of one per traveler.
    @Test func theGeneratedFamilyListShowsOneRowPerItemWithEveryRecordUnderneath() throws {
        let party = TripPartyBuilder.make(
            mode: .family, selfChips: [],
            otherAdults: [AdultDraft(name: "Maya", chips: [.bringingPhone, .bringingLaptop])],
            children: [ChildDraft(name: "Ada", ageGroup: .toddler, needs: Set(ChildNeed.suggested(for: .toddler).prefix(2))), ChildDraft(ageGroup: .teen, chips: [.bringingPhone])]
        )
        let destination = try #require(try SharedLibrary.testDestinations().first { $0.city == "Chicago" })
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start)!
        let context = TripContext(
            destination: destination, startDate: start, endDate: end, durationDays: 7, durationNights: 6,
            tripTypes: [.vacation, .beach], activities: ["beachDays", "sightseeing"], datedActivities: [],
            bagTypes: [.carryOn, .checked], packingStyle: .prepared, transportation: .unknown, laundryAccess: .none,
            travelerCount: party.travelers.count, userNotes: "", contextChips: [], weather: nil,
            preferences: .deviceDefaults(), party: party,
            origin: TripOrigin(countryCode: "US", source: .userConfirmed)
        )
        let engine = PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
        let records = engine.generate(context: context).map { draft in
            PackingListItem(
                id: draft.id, canonicalItemID: draft.canonicalItemID, displayName: draft.displayName, category: draft.category,
                quantity: draft.quantity, packedQuantity: draft.packedQuantity, importance: draft.importance,
                ownershipType: draft.ownershipType, travelerID: draft.travelerID, assignedTravelerID: draft.assignedTravelerID,
                isUserAdded: draft.isUserAdded
            )
        }
        let sections = PackingListAggregator.sections(items: records, party: party, order: Self.order, query: PackingListQuery())
        let rows = sections.flatMap(\.rows)
        let groups = Self.groups(rows)
        print("[Task 11] family fixture: \(records.count) records → \(rows.count) rows (\(groups.count) groups, \(rows.count - groups.count) single rows)")
        #expect(rows.count < records.count / 2, "the All scope roughly halves what the user scans")
        #expect(Set(rows.flatMap(\.recordIDs)) == Set(records.map(\.id)), "every record is reachable from exactly the rows")
        #expect(rows.flatMap(\.recordIDs).count == records.count, "and from only one row")
        #expect(groups.contains { $0.canonicalItemID == "toiletries.toothbrush" && $0.travelerCount == 4 })
        #expect(!rows.contains { if case .shared(let entry) = $0 { entry.item.ownershipType != .shared } else { false } })
    }

    // MARK: - 23. Mutations target real records

    private static func familyStore() throws -> (TripRecord, ModelContext) {
        let context = ModelContext(try PackWisePersistence.container(inMemory: true))
        let destination = try #require(try SharedLibrary.testDestinations().first { $0.city == "Chicago" })
        let trip = TripRecord(
            destination: destination, startDate: .now, endDate: .now, durationDays: 5, durationNights: 4,
            tripType: .vacation, activities: [], bagType: .checked, packingStyle: .balanced,
            travelerCount: 4, travelMode: .family, origin: TripOrigin(countryCode: "US", source: .userConfirmed)
        )
        context.insert(trip)
        let repo = TripRepository(context: context)
        repo.attach(party: family, bagTypes: [.checked], on: trip)
        var drafts: [PackingItemDraft] = []
        for (traveler, quantity) in zip(family.travelers, [5, 5, 5, 9]) {
            drafts.append(PackingItemDraft(canonicalItemID: "clothing.tshirt", displayName: "T-shirts", category: .clothing, quantity: quantity, importance: .normal, sourceSignals: [.baseEssential], reason: "", ownershipType: .personal, travelerID: traveler.id, assignedTravelerID: traveler.id))
            drafts.append(PackingItemDraft(canonicalItemID: "toiletries.toothbrush", displayName: "Toothbrush", category: .toiletries, quantity: 1, importance: .normal, sourceSignals: [.baseEssential], reason: "", ownershipType: .personal, travelerID: traveler.id, assignedTravelerID: traveler.id))
        }
        repo.replaceItems(on: trip, with: drafts)
        try context.save()
        return (trip, context)
    }

    private static func liveRows(_ trip: TripRecord) -> [PackingListPresentationRow] {
        PackingListAggregator.sections(
            items: trip.items.map(PackingListItem.init(record:)), party: trip.party, order: order, query: PackingListQuery()
        ).flatMap(\.rows)
    }

    private static func record(_ trip: TripRecord, _ canonical: String, for traveler: Traveler) throws -> PackingItemRecord {
        try #require(trip.items.first { $0.canonicalItemID == canonical && $0.travelerID == traveler.id })
    }

    @Test func editingOneTravelersQuantityFromTheGroupChangesOnlyThatRecord() throws {
        let (trip, context) = try Self.familyStore()
        let group = try #require(Self.groups(Self.liveRows(trip)).first { $0.canonicalItemID == "clothing.tshirt" })
        let alexMember = try #require(group.members.first { $0.travelerID == Self.alex.id })
        let alexRecord = try #require(trip.items.first { $0.id == alexMember.id })
        alexRecord.quantity = 7
        alexRecord.isUserModified = true
        try context.save()

        let after = try #require(Self.groups(Self.liveRows(trip)).first { $0.canonicalItemID == "clothing.tshirt" })
        #expect(after.members.map(\.quantity) == [5, 7, 5, 9])
        #expect(after.recordIDs.count == 4)
        #expect(trip.items.filter { $0.canonicalItemID == "clothing.tshirt" && $0.isUserModified }.count == 1)
    }

    @Test func packingYourRowLeavesTheOtherTravelersUnpacked() throws {
        let (trip, context) = try Self.familyStore()
        let mine = try Self.record(trip, "toiletries.toothbrush", for: Self.you)
        mine.packedQuantity = mine.quantity
        try context.save()
        let group = try #require(Self.groups(Self.liveRows(trip)).first { $0.canonicalItemID == "toiletries.toothbrush" })
        #expect(group.members.map(\.isComplete) == [true, false, false, false])
        #expect(group.progressText == "1 / 4")
        #expect(trip.items.filter { $0.canonicalItemID == "toiletries.toothbrush" && $0.isPacked }.count == 1)
    }

    @Test func markingOneTravelerNotNeededKeepsTheOthersRecommendations() throws {
        let (trip, context) = try Self.familyStore()
        let alexRecord = try Self.record(trip, "toiletries.toothbrush", for: Self.alex)
        TripRepository(context: context).markNotNeeded(alexRecord, on: trip)
        try context.save()
        let group = try #require(Self.groups(Self.liveRows(trip)).first { $0.canonicalItemID == "toiletries.toothbrush" })
        #expect(group.members.map(\.travelerLabel) == ["You", "Adult 2", "Child 1"])
        #expect(trip.overrides.count == 1)
        #expect(trip.overrides.first?.travelerID == Self.alex.id)
        #expect(trip.items.filter { $0.canonicalItemID == "clothing.tshirt" }.count == 4, "unrelated rows untouched")
    }

    @Test func changingOneRecordsCategoryMovesItOutOfTheGroup() throws {
        let (trip, context) = try Self.familyStore()
        let childRecord = try Self.record(trip, "clothing.tshirt", for: Self.child1)
        childRecord.categoryRaw = PackingCategory.kids.rawValue
        try context.save()
        let sections = PackingListAggregator.sections(
            items: trip.items.map(PackingListItem.init(record:)), party: trip.party, order: Self.order, query: PackingListQuery()
        )
        #expect(sections.map(\.category) == [.clothing, .kids, .toiletries])
        let clothing = try #require(Self.groups(sections[0].rows).first)
        #expect(clothing.members.map(\.travelerLabel) == ["You", "Alex", "Adult 2"])
        guard case .individual(let moved) = try #require(sections[1].rows.first) else { Issue.record("Child 1's shirts are an individual row under Kids"); return }
        #expect(moved.id == childRecord.id)
        #expect(moved.item.quantity == 9, "quantity, owner, and identity travel with the record")
        #expect(moved.item.travelerID == Self.child1.id)
    }
}
