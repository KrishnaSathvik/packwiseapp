import CoreData
import Foundation
import SwiftData
import Testing
@testable import PackWise

/// Real-store upgrade safety.
///
/// `StoreFixtures/` holds `packwise.store` files captured from actual old
/// builds of `com.packwiseapp.app` (launched on a simulator, WAL checkpointed),
/// not stores built from today's types. They are the ground truth for which
/// persisted shapes exist in the wild:
///
/// | fixture                          | label | built by                        |
/// | -------------------------------- | ----- | ------------------------------- |
/// | `v2-a975eab`                     | 2.0.0 | 18d754d … a975eab (same shape)  |
/// | `v3-791cf88`                     | 3.0.0 | d4ed374 … 791cf88 (pre-Task-2)  |
/// | `v4.0-7a219ee`                   | 4.0.0 | 7a219ee (first Task 2 commit)   |
/// | `v4.1-d7663a5`                   | 4.0.0 | c5c35bb … d7663a5 (main today)  |
/// | `unsupported-hardening-b302634`  | 3.0.0 | product-hardening-phase1 tip, never on main |
///
/// SwiftData picks a store's source schema by entity version hashes, not by
/// the label, and a migration plan whose schemas share a checksum aborts the
/// process with "Duplicate version checksums detected" the moment any stage
/// runs. So every plan schema must hash distinctly, and every real historical
/// store must hash identically to exactly one of them.
@Suite(.serialized)
struct StoreHistoryTests {
    private static let fixturesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("StoreFixtures")

    /// Supported historical fixture → the plan schema that must describe it.
    private static let supported: [(fixture: String, version: Schema.Version)] = [
        ("v2-a975eab", Schema.Version(2, 0, 0)),
        ("v3-791cf88", Schema.Version(3, 0, 0)),
        ("v4.0-7a219ee", Schema.Version(4, 0, 0)),
        ("v4.1-d7663a5", Schema.Version(4, 1, 0)),
    ]

    private static func storeHashes(fixture: String) throws -> [String: Data] {
        let url = fixturesDirectory.appendingPathComponent(fixture).appendingPathComponent("packwise.store")
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        return try #require(metadata[NSStoreModelVersionHashesKey] as? [String: Data], "\(fixture) has no model hashes")
    }

    private static func hashes(of schema: any VersionedSchema.Type) throws -> [String: Data] {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: schema.models))
        return model.entityVersionHashesByName
    }

    /// Version identifiers of every plan schema whose entity hashes equal `store`.
    private static func matchingPlanVersions(_ store: [String: Data]) throws -> [Schema.Version] {
        var versions: [Schema.Version] = []
        for schema in PackWiseMigrationPlan.schemas {
            let schemaHashes = try hashes(of: schema)
            if schemaHashes == store { versions.append(schema.versionIdentifier) }
        }
        return versions
    }

    /// Copies a fixture into a fresh directory so no test ever mutates the checked-in bytes.
    private static func copyFixture(_ fixture: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreHistoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("packwise.store")
        try FileManager.default.copyItem(
            at: fixturesDirectory.appendingPathComponent(fixture).appendingPathComponent("packwise.store"),
            to: destination
        )
        return destination
    }

    // MARK: - Plan integrity (never crashes, even when red)

    @Test func everyPlanSchemaHasADistinctChecksum() throws {
        let schemas = PackWiseMigrationPlan.schemas
        var seen: [(version: Schema.Version, hashes: [String: Data])] = []
        for schema in schemas {
            let schemaHashes = try Self.hashes(of: schema)
            for earlier in seen where earlier.hashes == schemaHashes {
                Issue.record("\(earlier.version) and \(schema.versionIdentifier) hash identically; any migration stage between them aborts the app")
            }
            seen.append((schema.versionIdentifier, schemaHashes))
        }
    }

    @Test func everyCapturedHistoricalStoreMatchesExactlyItsPlanSchema() throws {
        for (fixture, version) in Self.supported {
            let matches = try Self.matchingPlanVersions(Self.storeHashes(fixture: fixture))
            #expect(matches == [version], "\(fixture) must match exactly schema \(version); matched \(matches)")
        }
    }

    @Test func theNewestPlanSchemaIsTheOneTheAppOpens() throws {
        let newest = try #require(PackWiseMigrationPlan.schemas.last)
        let newestHashes = try Self.hashes(of: newest)
        let currentHashes = try Self.hashes(of: PackWiseCurrentSchema.self)
        #expect(newestHashes == currentHashes)
        #expect(PackWiseCurrentSchema.versionIdentifier == Schema.Version(4, 1, 0))
    }

    // MARK: - Real upgrades

    @Test @MainActor func everyCapturedHistoricalStoreUpgradesToTheCurrentModelWithoutLoss() throws {
        for (fixture, _) in Self.supported {
            // Guard first: opening a store no plan schema describes aborts the
            // whole test process instead of failing one expectation.
            let matches = try Self.matchingPlanVersions(Self.storeHashes(fixture: fixture))
            try #require(!matches.isEmpty, "\(fixture) is not described by the plan; refusing to open it")

            let url = try Self.copyFixture(fixture)
            for launch in 1...2 {
                let container = try PackWisePersistence.container(storeURL: url)
                let context = ModelContext(container)
                let preferences = try context.fetch(FetchDescriptor<PackingPreferenceRecord>())
                #expect(preferences.count == 1, "\(fixture) launch \(launch): the captured preference row survives")
                #expect(preferences.first?.preferredBagTypesMigrated == true, "\(fixture) launch \(launch): V4 backfill ran")
                #expect(try context.fetchCount(FetchDescriptor<TripRecord>()) == 0)
            }
            let upgraded = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
            let currentHashes = try Self.hashes(of: PackWiseCurrentSchema.self)
            #expect(
                upgraded[NSStoreModelVersionHashesKey] as? [String: Data] == currentHashes,
                "\(fixture) is persisted in the current shape after upgrade"
            )
        }
    }

    @Test func anUnrecognizedStoreShapeThrowsInsteadOfAbortingAndKeepsItsBytes() throws {
        let url = try Self.copyFixture("unsupported-hardening-b302634")
        let before = try Data(contentsOf: url)

        #expect(throws: PackWisePersistenceError.self) {
            _ = try PackWisePersistence.container(storeURL: url)
        }
        #expect(try Data(contentsOf: url) == before, "a refused store is never modified or deleted")
    }

    // MARK: - Rich data through the full chain

    /// Writes a genuine old-shape store through a frozen snapshot schema. The
    /// snapshot hashes are pinned to real captured stores above, so this is
    /// the same shape an old build would have written.
    private static func makeFrozenStore(
        _ schema: any VersionedSchema.Type,
        seed: (ModelContext) throws -> Void
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreHistoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("packwise.store")
        let frozen = Schema(versionedSchema: schema)
        let container = try ModelContainer(
            for: frozen,
            configurations: [ModelConfiguration("packwise", schema: frozen, url: url, cloudKitDatabase: .none)]
        )
        let context = ModelContext(container)
        try seed(context)
        try context.save()
        return url
    }

    @Test @MainActor func aV3StoreWithRealTripDataUpgradesWithEveryDecisionIntact() throws {
        let tripID = UUID(), selfID = UUID(), childID = UUID(), bagID = UUID(), manualID = UUID(), customID = UUID()
        let url = try Self.makeFrozenStore(PackWiseSchemaV3.self) { context in
            let trip = PackWiseSchemaV3.TripRecord()
            trip.id = tripID
            trip.destinationDisplayName = "Miami"
            trip.tripTypeRaw = "beach"
            trip.bagTypeRaw = "carryOn"
            trip.activitiesRaw = "swimming,beachDays"
            trip.travelModeRaw = "family"
            context.insert(trip)

            let me = PackWiseSchemaV3.TravelerRecord()
            me.id = selfID; me.roleRaw = "self"; me.ageGroupRaw = "adult"; me.trip = trip
            let child = PackWiseSchemaV3.TravelerRecord()
            child.id = childID; child.roleRaw = "child"; child.ageGroupRaw = "toddler"
            child.guardianTravelerID = selfID; child.needsRaw = "diapers"; child.trip = trip
            let bag = PackWiseSchemaV3.BagRecord()
            bag.id = bagID; bag.name = "My carry-on"; bag.bagTypeRaw = "carryOn"; bag.ownerTravelerID = selfID; bag.trip = trip
            [me, child].forEach(context.insert)
            context.insert(bag)

            let manual = PackWiseSchemaV3.PackingItemRecord()
            manual.id = manualID; manual.canonicalItemID = "clothing.tshirt"; manual.displayName = "T-shirt"
            manual.categoryRaw = "clothing"; manual.quantity = 5; manual.packedQuantity = 2
            manual.isUserModified = true; manual.travelerID = selfID; manual.bagID = bagID; manual.trip = trip
            let custom = PackWiseSchemaV3.PackingItemRecord()
            custom.id = customID; custom.displayName = "Grandma's gift"; custom.isUserAdded = true
            custom.ownershipTypeRaw = "shared"; custom.assignedTravelerID = selfID; custom.trip = trip
            [manual, custom].forEach(context.insert)

            let override = PackWiseSchemaV3.RecommendationOverrideRecord()
            override.canonicalItemID = "clothing.rain_jacket"; override.action = "removed"; override.trip = trip
            context.insert(override)

            let preferences = PackWiseSchemaV3.PackingPreferenceRecord()
            preferences.preferredBagRaw = "checked"; preferences.hasCompletedOnboarding = true
            context.insert(preferences)

            let event = PackWiseSchemaV3.PackingMemoryEventRecord()
            event.tripID = tripID; event.canonicalItemID = "clothing.tshirt"; event.kindRaw = "removed"
            event.bagRaw = "carryOn"; event.tripTypeRaw = "beach"; event.partySize = 2
            context.insert(event)
        }

        for launch in 1...2 {
            let context = ModelContext(try PackWisePersistence.container(storeURL: url))
            let trip = try #require(try context.fetch(FetchDescriptor<TripRecord>()).first, "launch \(launch)")
            #expect(trip.id == tripID)
            #expect(trip.tripTypes == [.beach], "launch \(launch): legacy scalar backfilled")
            #expect(trip.bagTypes == [.carryOn])
            #expect(trip.bags.map(\.id) == [bagID], "the existing bag record keeps its identity")
            #expect(trip.bags.first?.ownerTravelerID == selfID, "and its owner")
            #expect(Set(trip.travelers.map(\.id)) == [selfID, childID])
            #expect(trip.travelers.first { $0.id == childID }?.guardianTravelerID == selfID)

            let manual = try #require(trip.items.first { $0.id == manualID })
            #expect(manual.quantity == 5 && manual.packedQuantity == 2 && manual.isUserModified)
            #expect(manual.travelerID == selfID && manual.bagID == bagID)
            #expect(manual.recommendationTraceRaw == nil)
            let custom = try #require(trip.items.first { $0.id == customID })
            #expect(custom.isUserAdded && custom.ownershipTypeRaw == "shared" && custom.assignedTravelerID == selfID)
            #expect(trip.overrides.map(\.action) == ["removed"], "Not Needed survives")

            let preferences = try #require(try context.fetch(FetchDescriptor<PackingPreferenceRecord>()).first)
            #expect(preferences.preferredBagTypes == [.checked] && preferences.hasCompletedOnboarding)

            let event = try #require(try context.fetch(FetchDescriptor<PackingMemoryEventRecord>()).first)
            #expect(event.tripTypesRaw == #"["beach"]"# && event.bagTypesRaw == #"["carryOn"]"#)
        }
    }

    @Test @MainActor func aV2StoreUpgradesAndRoadTripLuggageNeverBecomesRoadTrip() throws {
        let tripID = UUID(), itemID = UUID()
        let url = try Self.makeFrozenStore(PackWiseSchemaV2.self) { context in
            let trip = PackWiseSchemaV2.TripRecord()
            trip.id = tripID; trip.tripTypeRaw = "vacation"; trip.bagTypeRaw = "roadTripLuggage"
            context.insert(trip)
            let item = PackWiseSchemaV2.PackingItemRecord()
            item.id = itemID; item.canonicalItemID = "essentials.wallet"; item.displayName = "Wallet"
            item.quantity = 1; item.packedQuantity = 1; item.trip = trip
            context.insert(item)
            let preferences = PackWiseSchemaV2.PackingPreferenceRecord()
            preferences.preferredBagRaw = "notSure"
            context.insert(preferences)
        }

        let context = ModelContext(try PackWisePersistence.container(storeURL: url))
        let trip = try #require(try context.fetch(FetchDescriptor<TripRecord>()).first)
        #expect(trip.id == tripID)
        #expect(trip.tripTypes == [.vacation], "roadTripLuggage must not add Road Trip")
        #expect(trip.bagTypes.isEmpty && trip.bags.isEmpty)
        #expect(trip.items.first?.id == itemID && trip.items.first?.packedQuantity == 1)
        #expect(try context.fetchCount(FetchDescriptor<PackingMemoryEventRecord>()) == 0, "V3 added the entity empty")
        #expect(try #require(try context.fetch(FetchDescriptor<PackingPreferenceRecord>()).first).preferredBagTypes.isEmpty)
    }

    @Test @MainActor func aV4_0StoreKeepsMultiValueTripTypesButRederivesItsPreferenceOnce() throws {
        let url = try Self.makeFrozenStore(PackWiseSchemaV4.self) { context in
            let trip = PackWiseSchemaV4.TripRecord()
            trip.tripTypeRaw = "vacation"
            trip.tripTypesRaw = #"["vacation","beach"]"#
            context.insert(trip)
            // 4.0.0 had no `preferredBagTypesMigrated` column, so an upgraded
            // row is indistinguishable from an unmigrated one and the backfill
            // re-derives it from the scalar once — the known cost of the one
            // intermediate commit that wrote this shape.
            let preferences = PackWiseSchemaV4.PackingPreferenceRecord()
            preferences.preferredBagRaw = "carryOn"
            preferences.preferredBagTypesRaw = #"["carryOn","checked"]"#
            context.insert(preferences)
        }

        let context = ModelContext(try PackWisePersistence.container(storeURL: url))
        let trip = try #require(try context.fetch(FetchDescriptor<TripRecord>()).first)
        #expect(trip.tripTypes == [.vacation, .beach], "an already-migrated multi-value trip is never clobbered")
        let preferences = try #require(try context.fetch(FetchDescriptor<PackingPreferenceRecord>()).first)
        #expect(preferences.preferredBagTypes == [.carryOn])
        #expect(preferences.preferredBagTypesMigrated)
    }
}
