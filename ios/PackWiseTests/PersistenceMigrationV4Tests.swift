import Foundation
import SwiftData
import Testing
@testable import PackWise

/// Product Experience V2, Task 2 — SwiftData V3 → V4 migration
/// (`docs/plans/2026-09-04-product-experience-v2-design.md` Section 6).
///
/// These tests use real file-backed `ModelContainer`s, not in-memory ones,
/// for every migration scenario: the property under test is migration
/// correctness across a genuine store relaunch, which an in-memory store
/// that never actually serializes can't exercise. The non-destructive
/// container-failure test likewise asserts on real bytes on disk, not
/// merely "no crash."
struct PersistenceMigrationV4Tests {
    // MARK: - Fixtures

    private func makeStoreDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistenceMigrationV4Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeV3Container(url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: PackWiseSchemaV3.self)
        let config = ModelConfiguration("packwise", schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Mirrors `PackWisePersistence.container`: opens (and, for a V3 store,
    /// structurally migrates) the container, then runs the V4 data backfill
    /// the same way the real app does — see that function's doc comment for
    /// why the backfill is a separate, idempotent post-open step rather
    /// than a migration-stage callback.
    private func openV4Container(url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: PackWiseSchemaV4.self)
        let config = ModelConfiguration("packwise", schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: PackWiseMigrationPlan.self, configurations: [config])
        try PackWiseSchemaV4Migration.migrateV3Records(in: ModelContext(container))
        return container
    }

    private func chicago() throws -> Destination {
        try #require(try SharedLibrary.testDestinations().first { $0.city == "Chicago" })
    }

    // MARK: - Step 1: the core authority-preserving migration

    /// Seeds a genuine V3 file-backed store — through the real
    /// `TripRepository` code path, exactly like a shipped app would — with a
    /// family trip carrying every kind of protected user state, then proves
    /// it survives both the V3 → V4 migration and a second relaunch.
    @Test @MainActor func beachCarryOnFamilyTripMigratesAuthorityAndSurvivesTwoRelaunches() throws {
        let storeURL = try makeStoreDirectory().appendingPathComponent("packwise.store")
        let destination = try chicago()
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 10))!
        let end = Calendar.current.date(byAdding: .day, value: 5, to: start)!

        var tripID = UUID()
        var primaryID = UUID()
        var otherAdultID = UUID()
        var existingBagID = UUID()
        var personalItemID = UUID()
        var sharedItemID = UUID()
        var customItemID = UUID()

        // --- Seed a genuine V3 store. ---
        do {
            let container = try makeV3Container(url: storeURL)
            let context = ModelContext(container)
            let repo = TripRepository(context: context)

            let trip = TripRecord(
                destination: destination,
                startDate: start,
                endDate: end,
                durationDays: 6,
                durationNights: 5,
                tripType: .beach,
                activities: ["swimming"],
                bagType: .carryOn,
                packingStyle: .balanced
            )
            context.insert(trip)
            tripID = trip.id

            let party = TripPartyBuilder.make(mode: .family)
            primaryID = party.primary.id
            otherAdultID = try #require(party.travelers.first { $0.role == .otherAdult }).id
            repo.replaceParty(party, bagType: .carryOn, on: trip)
            existingBagID = try #require(trip.bags.first).id
            // `TripRecord.init` (the live type V3 also aliases) already
            // populates `tripTypesRaw` as a side effect — that's Task 2's
            // own V4 write behavior, not what a genuine pre-V4 row on disk
            // would ever have. Resetting it to its untouched default is
            // what actually makes this fixture V3-shaped and exercises the
            // real backfill below, instead of the value already being
            // correct by construction.
            trip.tripTypesRaw = "[]"

            repo.replaceItems(on: trip, with: [
                PackingItemDraft(
                    canonicalItemID: "clothing.tshirt", displayName: "T-shirts", category: .clothing,
                    quantity: 4, importance: .normal, sourceSignals: [.baseEssential], reason: "",
                    ownershipType: .personal, travelerID: party.primary.id
                ),
                PackingItemDraft(
                    canonicalItemID: "travel_comfort.umbrella", displayName: "Umbrella", category: .travelComfort,
                    quantity: 1, importance: .normal, sourceSignals: [.baseEssential], reason: "",
                    ownershipType: .shared, assignedTravelerID: otherAdultID
                ),
                PackingItemDraft(
                    canonicalItemID: "clothing.rain_jacket", displayName: "Rain jacket", category: .clothing,
                    quantity: 1, importance: .normal, sourceSignals: [.weather], reason: ""
                )
            ])

            personalItemID = try #require(trip.items.first { $0.canonicalItemID == "clothing.tshirt" }).id
            sharedItemID = try #require(trip.items.first { $0.canonicalItemID == "travel_comfort.umbrella" }).id

            // Manual quantity + packed quantity (authority).
            let tshirt = try #require(trip.items.first { $0.id == personalItemID })
            tshirt.quantity = 3
            tshirt.isUserModified = true
            tshirt.packedQuantity = 2

            // Category edit (authority).
            let umbrella = try #require(trip.items.first { $0.id == sharedItemID })
            umbrella.categoryRaw = PackingCategory.miscellaneous.rawValue

            // Not Needed override.
            let jacket = try #require(trip.items.first { $0.canonicalItemID == "clothing.rain_jacket" })
            repo.markNotNeeded(jacket, on: trip)

            // Custom item.
            repo.addItem(
                PackingItemDraft(
                    canonicalItemID: nil, displayName: "Travel journal", category: .miscellaneous,
                    quantity: 1, importance: .optional, sourceSignals: [.userPreference], reason: "",
                    isUserAdded: true
                ),
                to: trip
            )
            customItemID = try #require(trip.items.first { $0.displayName == "Travel journal" }).id

            try context.save()
        }

        func assertMigratedState(url: URL) throws {
            let container = try openV4Container(url: url)
            let context = ModelContext(container)

            let trip = try #require(
                try context.fetch(FetchDescriptor<TripRecord>(predicate: #Predicate { $0.id == tripID })).first
            )

            #expect(trip.tripTypes == [.beach])
            #expect(trip.tripType == .beach, "the singleton compat accessor must agree with the migrated set")
            #expect(trip.bagTypes == [.carryOn])
            #expect(trip.bagType == .carryOn)
            #expect(trip.bags.count == 1)
            #expect(trip.bags.first?.id == existingBagID, "migration must preserve the existing bag record's identity")
            #expect(trip.travelers.count == 2)
            #expect(trip.travelers.contains { $0.id == otherAdultID })

            let tshirt = try #require(trip.items.first { $0.id == personalItemID })
            #expect(tshirt.quantity == 3, "manual quantity must survive migration")
            #expect(tshirt.packedQuantity == 2, "packed quantity must survive migration")
            #expect(tshirt.isUserModified)
            #expect(tshirt.ownershipType == .personal)
            #expect(tshirt.travelerID == primaryID, "owner assignment must survive migration")

            let umbrella = try #require(trip.items.first { $0.id == sharedItemID })
            #expect(umbrella.category == .miscellaneous, "the category edit must survive migration")
            #expect(umbrella.ownershipType == .shared)
            #expect(umbrella.assignedTravelerID == otherAdultID, "carrier assignment must survive migration")

            #expect(trip.items.contains { $0.id == customItemID && $0.isUserAdded }, "the custom item must survive migration")
            #expect(!trip.items.contains { $0.canonicalItemID == "clothing.rain_jacket" }, "the Not Needed item must stay removed")
            #expect(
                trip.overrides.contains { $0.canonicalItemID == "clothing.rain_jacket" && $0.action == "removed" },
                "the Not Needed override itself must survive migration"
            )
        }

        // --- First relaunch: the actual V3 → V4 migration. ---
        try assertMigratedState(url: storeURL)

        // --- Second relaunch: the store is already V4; must remain stable. ---
        try assertMigratedState(url: storeURL)
    }

    // MARK: - Solo coverage

    @Test @MainActor func soloTripMigratesTripTypeAndBagTypeAcrossRelaunch() throws {
        let storeURL = try makeStoreDirectory().appendingPathComponent("packwise.store")
        let destination = try chicago()
        let start = Date.now
        var tripID = UUID()

        do {
            let container = try makeV3Container(url: storeURL)
            let context = ModelContext(container)
            let repo = TripRepository(context: context)
            let trip = TripRecord(
                destination: destination, startDate: start, endDate: start.addingTimeInterval(3 * 86400),
                durationDays: 4, durationNights: 3, tripType: .business, activities: ["work"],
                bagType: .checked, packingStyle: .prepared
            )
            context.insert(trip)
            tripID = trip.id
            repo.replaceParty(.solo(), bagType: .checked, on: trip)
            trip.tripTypesRaw = "[]" // simulate a genuine pre-V4 row; see the family-trip test's comment
            try context.save()
        }

        for _ in 0..<2 {
            let container = try openV4Container(url: storeURL)
            let context = ModelContext(container)
            let trip = try #require(
                try context.fetch(FetchDescriptor<TripRecord>(predicate: #Predicate { $0.id == tripID })).first
            )
            #expect(trip.tripTypes == [.business])
            #expect(trip.bagTypes == [.checked])
            #expect(trip.bags.count == 1)
        }
    }

    // MARK: - Step 2: legacy/unknown-value edge cases

    /// One V3 store carrying every non-happy-path row from design Section
    /// 6.2's migration table: `notSure`/`roadTripLuggage`/unknown bag
    /// values, an unknown trip type, and the matching preference and memory
    /// event fingerprint conversions.
    @Test @MainActor func legacyEdgeCasesMigrateWithoutInferringRoadTripOrArbitraryPrimary() throws {
        let storeURL = try makeStoreDirectory().appendingPathComponent("packwise.store")
        let destination = try chicago()
        let start = Date.now
        let end = start.addingTimeInterval(3 * 86400)

        var notSureTripID = UUID()
        var roadTripLuggageTripID = UUID()
        var unknownTripTypeTripID = UUID()
        var unknownBagTypeTripID = UUID()

        do {
            let container = try makeV3Container(url: storeURL)
            let context = ModelContext(container)
            let repo = TripRepository(context: context)

            // `TripRecord.init` (the live type V3 also aliases) already
            // populates `tripTypesRaw` as a side effect — that's Task 2's
            // own V4 write behavior, not what a genuine pre-V4 row on disk
            // would ever have. Resetting it to its untouched default here
            // is what actually makes this fixture "V3-shaped": the same
            // technique already used below for the memory-event fixtures.
            func makeTrip(tripType: TripType, bagType: BagType) -> TripRecord {
                let trip = TripRecord(
                    destination: destination, startDate: start, endDate: end,
                    durationDays: 4, durationNights: 3,
                    tripType: tripType, activities: [], bagType: bagType, packingStyle: .balanced
                )
                context.insert(trip)
                repo.replaceParty(.solo(), bagType: bagType, on: trip)
                trip.tripTypesRaw = "[]"
                return trip
            }

            let notSureTrip = makeTrip(tripType: .vacation, bagType: .notSure)
            notSureTripID = notSureTrip.id

            let roadTripLuggageTrip = makeTrip(tripType: .vacation, bagType: .roadTripLuggage)
            roadTripLuggageTripID = roadTripLuggageTrip.id

            let unknownTripTypeTrip = makeTrip(tripType: .vacation, bagType: .carryOn)
            unknownTripTypeTrip.tripTypeRaw = "campingWeekend" // a pre-V2 label no longer in the enum
            unknownTripTypeTripID = unknownTripTypeTrip.id

            let unknownBagTypeTrip = makeTrip(tripType: .vacation, bagType: .carryOn)
            unknownBagTypeTrip.bagTypeRaw = "duffelBag"
            for bag in unknownBagTypeTrip.bags { bag.bagTypeRaw = "duffelBag" }
            unknownBagTypeTripID = unknownBagTypeTrip.id

            // `PackingPreferenceRecord.init` also already marks itself
            // migrated (`preferredBagTypesMigrated = true`) as Task 2's own
            // V4 write behavior; reset that plus the derived array to their
            // untouched defaults so each fixture is genuinely V3-shaped.
            func makeLegacyPreferences(preferredBagRaw: String) {
                let record = PackingPreferenceRecord(from: .deviceDefaults())
                record.preferredBagRaw = preferredBagRaw
                record.preferredBagTypesRaw = "[]"
                record.preferredBagTypesMigrated = false
                context.insert(record)
            }

            makeLegacyPreferences(preferredBagRaw: BagType.checked.rawValue)
            makeLegacyPreferences(preferredBagRaw: BagType.notSure.rawValue)
            makeLegacyPreferences(preferredBagRaw: BagType.roadTripLuggage.rawValue)
            makeLegacyPreferences(preferredBagRaw: "tote")

            // Two genuine-looking pre-migration memory events: the array
            // columns reset to "[]" (their default) to represent a row that
            // predates this migration, exactly as a real V3 row would be.
            let knownEvent = PackingMemoryEventRecord(PackingMemoryEvent(
                tripID: notSureTripID, travelerID: nil, canonicalItemID: "clothing.tshirt",
                kind: .suggested, value: 3, timestamp: .now,
                context: ContextFingerprint(
                    durationBucket: .short, laundryPlan: .none, packingStyle: .balanced,
                    bagTypes: [.carryOn], tripTypes: [.beach], partySize: 1
                )
            ))
            knownEvent.tripTypesRaw = "[]"
            knownEvent.bagTypesRaw = "[]"
            context.insert(knownEvent)

            let unknownEvent = PackingMemoryEventRecord(PackingMemoryEvent(
                tripID: unknownTripTypeTripID, travelerID: nil, canonicalItemID: "clothing.socks",
                kind: .suggested, value: 2, timestamp: .now,
                context: ContextFingerprint(
                    durationBucket: .short, laundryPlan: .none, packingStyle: .balanced,
                    bagTypes: [], tripTypes: [.other], partySize: 1
                )
            ))
            unknownEvent.tripTypeRaw = "campingWeekend"
            unknownEvent.bagRaw = "duffelBag"
            unknownEvent.tripTypesRaw = "[]"
            unknownEvent.bagTypesRaw = "[]"
            context.insert(unknownEvent)

            try context.save()
        }

        let container = try openV4Container(url: storeURL)
        let context = ModelContext(container)

        let notSureTrip = try #require(
            try context.fetch(FetchDescriptor<TripRecord>(predicate: #Predicate { $0.id == notSureTripID })).first
        )
        #expect(notSureTrip.bagTypes.isEmpty)
        #expect(notSureTrip.bags.isEmpty, "a notSure bag record carries no real bag information and is not preserved")
        #expect(notSureTrip.tripTypes == [.vacation])

        let roadTripLuggageTrip = try #require(
            try context.fetch(FetchDescriptor<TripRecord>(predicate: #Predicate { $0.id == roadTripLuggageTripID })).first
        )
        #expect(roadTripLuggageTrip.bagTypes.isEmpty)
        #expect(roadTripLuggageTrip.bags.isEmpty)
        #expect(!roadTripLuggageTrip.tripTypes.contains(.roadTrip), "a roadTripLuggage bag label must never infer the Road Trip trip type")
        #expect(roadTripLuggageTrip.tripTypes == [.vacation])

        let unknownTripTypeTrip = try #require(
            try context.fetch(FetchDescriptor<TripRecord>(predicate: #Predicate { $0.id == unknownTripTypeTripID })).first
        )
        #expect(unknownTripTypeTrip.tripTypes == [.other])
        #expect(unknownTripTypeTrip.bagTypes == [.carryOn], "the bag scalar migrates independently of the trip-type scalar")

        let unknownBagTypeTrip = try #require(
            try context.fetch(FetchDescriptor<TripRecord>(predicate: #Predicate { $0.id == unknownBagTypeTripID })).first
        )
        #expect(unknownBagTypeTrip.bagTypes.isEmpty)
        #expect(unknownBagTypeTrip.bags.isEmpty)

        let allPreferences = try context.fetch(FetchDescriptor<PackingPreferenceRecord>())
        let physical = try #require(allPreferences.first { $0.preferredBagRaw == BagType.checked.rawValue })
        #expect(physical.preferredBagTypes == [.checked], "a physical legacy default becomes a singleton set")
        let notSurePrefs = try #require(allPreferences.first { $0.preferredBagRaw == BagType.notSure.rawValue })
        #expect(notSurePrefs.preferredBagTypes.isEmpty)
        let roadTripLuggagePrefs = try #require(allPreferences.first { $0.preferredBagRaw == BagType.roadTripLuggage.rawValue })
        #expect(roadTripLuggagePrefs.preferredBagTypes.isEmpty)
        let unknownPrefs = try #require(allPreferences.first { $0.preferredBagRaw == "tote" })
        #expect(unknownPrefs.preferredBagTypes.isEmpty)

        let events = try context.fetch(FetchDescriptor<PackingMemoryEventRecord>()).map(\.event)
        let migratedKnownEvent = try #require(events.first { $0.canonicalItemID == "clothing.tshirt" })
        #expect(migratedKnownEvent.context.tripTypes == [.beach])
        #expect(migratedKnownEvent.context.bagTypes == [.carryOn])

        let migratedUnknownEvent = try #require(events.first { $0.canonicalItemID == "clothing.socks" })
        #expect(migratedUnknownEvent.context.tripTypes == [.other], "an unknown fingerprint trip type falls back to .other")
        #expect(migratedUnknownEvent.context.bagTypes.isEmpty, "an unknown fingerprint bag value drops to no bag constraint")
    }

    // MARK: - Step 5: non-destructive failure

    /// A store that fails to open — corrupt bytes standing in for any
    /// unreadable/incompatible store — must surface its error rather than
    /// being silently deleted and recreated. Asserted against the actual
    /// bytes on disk, not merely "the app didn't crash."
    @Test func containerOpenFailureNeverDeletesStoreBytes() throws {
        let dir = try makeStoreDirectory()
        let storeURL = dir.appendingPathComponent("packwise.store")
        let walURL = URL(fileURLWithPath: storeURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: storeURL.path + "-shm")

        let storeBytes = Data("not a real SwiftData store".utf8)
        let walBytes = Data("wal-sentinel".utf8)
        let shmBytes = Data("shm-sentinel".utf8)
        try storeBytes.write(to: storeURL)
        try walBytes.write(to: walURL)
        try shmBytes.write(to: shmURL)

        let schema = Schema(versionedSchema: PackWiseSchemaV4.self)
        let config = ModelConfiguration("packwise", schema: schema, url: storeURL, cloudKitDatabase: .none)

        #expect(throws: (any Error).self, "an incompatible/corrupt store must surface its open error, not be silently repaired") {
            _ = try ModelContainer(for: schema, migrationPlan: PackWiseMigrationPlan.self, configurations: [config])
        }

        #expect(try Data(contentsOf: storeURL) == storeBytes, "packwise.store must never be deleted or rewritten merely because it failed to open")
        #expect(try Data(contentsOf: walURL) == walBytes, "the WAL must never be deleted merely because the store failed to open")
        #expect(try Data(contentsOf: shmURL) == shmBytes, "the SHM must never be deleted merely because the store failed to open")
    }

    // MARK: - Fail-safe compatibility accessors

    /// `TripRecord.tripType`/`bagType` are read by every existing engine
    /// call site that hasn't yet moved to the multi-value sets (Tasks 3/5).
    /// A genuine multi-value selection must never resolve to one of the
    /// selected values as if it were primary.
    @Test @MainActor func tripTypeAndBagTypeCompatAccessorsFailSafeForMultiValueSelections() throws {
        let container = try PackWisePersistence.container(inMemory: true)
        let context = ModelContext(container)
        let destination = try chicago()
        let trip = TripRecord(
            destination: destination, startDate: .now, endDate: .now.addingTimeInterval(2 * 86400),
            durationDays: 2, durationNights: 1, tripType: .beach, activities: [], bagType: .carryOn,
            packingStyle: .balanced
        )
        context.insert(trip)

        // Not yet reachable through any shipped write path (Task 8's UI),
        // but the compatibility accessors must already fail safe once a
        // multi-value selection reaches a `TripRecord` some other way.
        // `TripRecord.init` never creates a `BagRecord` on its own (only
        // `TripRepository.replaceParty` does), so both physical bags are
        // added explicitly here.
        trip.tripTypesRaw = PackWiseStableEncoding.tripTypesJSON([.beach, .cityBreak])
        trip.bags.append(BagRecord(from: TripBag(name: "Carry-on", bagType: .carryOn, ownershipType: .personal), trip: trip))
        trip.bags.append(BagRecord(from: TripBag(name: "Checked bag", bagType: .checked, ownershipType: .personal), trip: trip))

        #expect(trip.tripTypes == [.beach, .cityBreak])
        #expect(trip.tripType == .other, "a multi-value selection must never resolve to one selected type as if it were primary")
        #expect(trip.bagTypes == [.carryOn, .checked])
        #expect(trip.bagType == .notSure, "a multi-bag selection must never resolve to one selected bag as if it were the only one")
    }

    // MARK: - Set-valued repository write boundary

    @Test @MainActor func applyTripTypesWritesStableArrayAndRejectsEmptySelection() throws {
        let container = try PackWisePersistence.container(inMemory: true)
        let context = ModelContext(container)
        let repo = TripRepository(context: context)
        let destination = try chicago()
        let trip = TripRecord(
            destination: destination, startDate: .now, endDate: .now.addingTimeInterval(2 * 86400),
            durationDays: 2, durationNights: 1, tripType: .vacation, activities: [], bagType: .notSure,
            packingStyle: .balanced
        )
        context.insert(trip)

        try repo.applyTripTypes([.beach, .cityBreak, .vacation], on: trip)
        #expect(trip.tripTypes == [.beach, .cityBreak, .vacation])
        #expect(trip.tripTypeRaw == TripType.vacation.rawValue, "the compat scalar is the first stable-order value, for older diagnostics only")

        #expect(throws: TripTypeSelectionError.emptySelection) {
            try repo.applyTripTypes([], on: trip)
        }
        #expect(trip.tripTypes == [.beach, .cityBreak, .vacation], "a rejected write must not partially apply")
    }

    @Test @MainActor func applyBagTypesRejectsMultiValueSelectionAndPreservesExistingBagIdentity() throws {
        let container = try PackWisePersistence.container(inMemory: true)
        let context = ModelContext(container)
        let repo = TripRepository(context: context)
        let destination = try chicago()
        let trip = TripRecord(
            destination: destination, startDate: .now, endDate: .now.addingTimeInterval(2 * 86400),
            durationDays: 2, durationNights: 1, tripType: .vacation, activities: [], bagType: .carryOn,
            packingStyle: .balanced
        )
        context.insert(trip)
        repo.replaceParty(.solo(), bagType: .carryOn, on: trip)
        let existingBagID = try #require(trip.bags.first).id

        try repo.applyBagTypes([.carryOn], on: trip)
        #expect(trip.bags.count == 1)
        #expect(trip.bags.first?.id == existingBagID, "re-applying the same bag must preserve its identity, not recreate it")

        #expect(throws: TripRepository.BagAssignmentError.multipleBagsNotYetSupported) {
            try repo.applyBagTypes([.carryOn, .checked], on: trip)
        }
        #expect(trip.bags.map(\.id) == [existingBagID], "a rejected multi-bag write must not partially apply")

        try repo.applyBagTypes([], on: trip)
        #expect(trip.bags.isEmpty)
    }

    /// Regression: `TripRecord.bagTypes` derives from the `bags`
    /// relationship, and the only code that ever populated `bags` for an
    /// existing trip was `replaceParty` — which used to create a bag only
    /// when `trip.bags.isEmpty`, so it silently no-op'd on every *edit* of
    /// an already-set-up trip's bag selection (exactly what
    /// `TripRepository.apply`, and so `TripSetupView.saveTrip()`'s edit
    /// path, calls). `bagTypeRaw` got updated harmlessly; `bagTypes` — the
    /// value every reader actually consumes — kept returning the trip's
    /// original bag forever.
    @Test @MainActor func editingBagSelectionReconcilesBagsInsteadOfLeavingTheOriginalBagStale() throws {
        let container = try PackWisePersistence.container(inMemory: true)
        let context = ModelContext(container)
        let repo = TripRepository(context: context)
        let destination = try chicago()
        let trip = TripRecord(
            destination: destination, startDate: .now, endDate: .now.addingTimeInterval(2 * 86400),
            durationDays: 2, durationNights: 1, tripType: .vacation, activities: [], bagType: .carryOn,
            packingStyle: .balanced
        )
        context.insert(trip)
        repo.replaceParty(.solo(), bagType: .carryOn, on: trip)
        let originalBagID = try #require(trip.bags.first).id
        #expect(trip.bagTypes == [.carryOn])

        // The edit: same call `TripRepository.apply` makes, with a
        // genuinely different bag type than the trip already has.
        repo.replaceParty(.solo(), bagType: .checked, on: trip)

        #expect(
            trip.bagTypes == [.checked],
            "editing the bag selection must update the bags relationship — bagTypes' source of truth — not just the unread bagTypeRaw scalar"
        )
        #expect(trip.bags.count == 1)
        #expect(trip.bags.first?.id != originalBagID, "the stale Carry-on record must not survive alongside or instead of the new selection")

        // Re-applying the same (now current) bag type must be a no-op that
        // preserves identity, not a needless recreate.
        let checkedBagID = try #require(trip.bags.first).id
        repo.replaceParty(.solo(), bagType: .checked, on: trip)
        #expect(trip.bags.first?.id == checkedBagID, "re-applying the same bag type must preserve the existing record's identity")
    }

    /// Regression: `replaceParty`'s reconciliation must filter per-record,
    /// not ask "does any bag match" — an all-or-nothing check skips the
    /// whole branch (leaving a stray non-matching record behind) whenever
    /// a match happens to already be present among several bag records.
    /// No shipped path currently produces more than one `BagRecord`, but
    /// the reconciliation must still converge to exactly one matching
    /// record regardless of starting state.
    @Test @MainActor func replacePartyRemovesStrayBagRecordsEvenWhenAMatchingOneAlreadyExists() throws {
        let container = try PackWisePersistence.container(inMemory: true)
        let context = ModelContext(container)
        let repo = TripRepository(context: context)
        let destination = try chicago()
        let trip = TripRecord(
            destination: destination, startDate: .now, endDate: .now.addingTimeInterval(2 * 86400),
            durationDays: 2, durationNights: 1, tripType: .vacation, activities: [], bagType: .carryOn,
            packingStyle: .balanced
        )
        context.insert(trip)

        // Seed two bag records directly: one already matching the target
        // selection, one a stray that must be cleaned up.
        let matchingBag = BagRecord(from: TripBag(name: "Carry-on", bagType: .carryOn, ownershipType: .personal), trip: trip)
        let strayBag = BagRecord(from: TripBag(name: "Checked bag", bagType: .checked, ownershipType: .personal), trip: trip)
        context.insert(matchingBag)
        context.insert(strayBag)
        trip.bags = [matchingBag, strayBag]
        let matchingBagID = matchingBag.id

        repo.replaceParty(.solo(), bagType: .carryOn, on: trip)

        #expect(trip.bags.count == 1, "the stray Checked record must be removed even though a matching Carry-on record was already present")
        #expect(trip.bags.first?.id == matchingBagID, "the already-matching record's identity must be preserved, not recreated")
        #expect(trip.bagTypes == [.carryOn])
    }

    // MARK: - Regression: the V3 → V4 backfill must never re-run against
    // already-migrated data and clobber a later multi-value write.
    //
    // `PackWiseSchemaV4Migration.migrateV3Records` runs on every container
    // open (not once). Before the `needsTripMigration`/
    // `preferredBagTypesMigrated` guards existed, it unconditionally
    // re-derived `tripTypesRaw`/`bags`/`preferredBagTypesRaw` from their
    // legacy scalars every time — and `TripRepository.applyTripTypes`/
    // `applyBagTypes` deliberately keep those legacy scalars at only a
    // single stable/first value for old-diagnostic compatibility. Reopening
    // the container after a multi-value write silently collapsed it back to
    // that single legacy value (trip types) or resurrected a bag the user
    // had explicitly removed (bags), because the backfill treated the
    // stale scalar as authoritative forever. These tests close and reopen
    // a real file-backed store — not the same session — to prove that
    // failure mode is actually fixed, not just untriggered.

    @Test @MainActor func multiValueTripTypeAndEmptyBagWritesSurviveContainerRelaunchWithoutClobbering() throws {
        let storeURL = try makeStoreDirectory().appendingPathComponent("packwise.store")
        let destination = try chicago()
        var tripID = UUID()

        do {
            let container = try openV4Container(url: storeURL)
            let context = ModelContext(container)
            let repo = TripRepository(context: context)
            let trip = TripRecord(
                destination: destination, startDate: .now, endDate: .now.addingTimeInterval(3 * 86400),
                durationDays: 4, durationNights: 3, tripType: .vacation, activities: [], bagType: .carryOn,
                packingStyle: .balanced
            )
            context.insert(trip)
            tripID = trip.id
            repo.replaceParty(.solo(), bagType: .carryOn, on: trip)

            try repo.applyTripTypes([.beach, .cityBreak, .vacation], on: trip)
            try repo.applyBagTypes([], on: trip) // user explicitly removes every bag
            try context.save()
        }

        func assertSurvived(url: URL) throws {
            let container = try openV4Container(url: url)
            let context = ModelContext(container)
            let trip = try #require(
                try context.fetch(FetchDescriptor<TripRecord>(predicate: #Predicate { $0.id == tripID })).first
            )
            #expect(
                trip.tripTypes == [.beach, .cityBreak, .vacation],
                "a multi-value trip-type write must survive relaunch, not collapse to the compat scalar's single stable value"
            )
            #expect(trip.bags.isEmpty, "an explicit empty bag selection must survive relaunch, not resurrect the removed bag")
            #expect(trip.bagTypes.isEmpty)
        }

        try assertSurvived(url: storeURL)
        // A second relaunch must remain stable too — this is exactly the
        // "runs on every open" code path that used to keep re-clobbering.
        try assertSurvived(url: storeURL)
    }

    @Test @MainActor func multiValuePreferredBagTypesWriteSurvivesContainerRelaunchWithoutClobbering() throws {
        let storeURL = try makeStoreDirectory().appendingPathComponent("packwise.store")

        do {
            let container = try openV4Container(url: storeURL)
            let context = ModelContext(container)
            let record = PackingPreferenceRecord(from: .deviceDefaults())
            context.insert(record)
            var preferences = record.preferences
            preferences.preferredBag = .checked
            preferences.preferredBagTypes = [.checked, .carryOn]
            record.apply(preferences)
            try context.save()
        }

        let container = try openV4Container(url: storeURL)
        let context = ModelContext(container)
        let record = try #require(try context.fetch(FetchDescriptor<PackingPreferenceRecord>()).first)
        #expect(
            record.preferredBagTypes == [.checked, .carryOn],
            "a multi-value preferred-bag write must survive relaunch, not collapse to the compat scalar's single value"
        )
    }
}
