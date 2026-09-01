import Foundation
import SwiftData

@Model
final class TripRecord {
    @Attribute(.unique) var id: UUID
    var destinationDisplayName: String
    var destinationCity: String
    var destinationRegion: String
    var destinationCountry: String
    var destinationCountryCode: String
    var destinationLatitude: Double
    var destinationLongitude: Double
    var destinationTimeZone: String
    var destinationMapKitID: String?
    var destinationFixtureID: String?
    var startDate: Date
    var endDate: Date
    var durationDays: Int
    var durationNights: Int
    var tripTypeRaw: String
    var activitiesRaw: String
    var bagTypeRaw: String
    var packingStyleRaw: String
    var statusRaw: String
    var userNotes: String
    var contextChipsRaw: String
    var travelerCount: Int = 1
    var travelModeRaw: String = "solo"
    var transportationRaw: String = "unknown"
    var laundryAccessRaw: String = "none"
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \PackingItemRecord.trip)
    var items: [PackingItemRecord]

    @Relationship(deleteRule: .cascade, inverse: \WeatherSnapshotRecord.trip)
    var weatherSnapshots: [WeatherSnapshotRecord]

    @Relationship(deleteRule: .cascade, inverse: \RecommendationOverrideRecord.trip)
    var overrides: [RecommendationOverrideRecord]

    @Relationship(deleteRule: .cascade, inverse: \WeatherChangeProposalRecord.trip)
    var weatherChangeProposals: [WeatherChangeProposalRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \TravelerRecord.trip)
    var travelers: [TravelerRecord]

    @Relationship(deleteRule: .cascade, inverse: \BagRecord.trip)
    var bags: [BagRecord]

    init(
        id: UUID = UUID(),
        destination: Destination,
        startDate: Date,
        endDate: Date,
        durationDays: Int,
        durationNights: Int,
        tripType: TripType,
        activities: [String],
        bagType: BagType,
        packingStyle: PackingStyle,
        status: TripStatus = .planning,
        userNotes: String = "",
        contextChips: [ContextChip] = [],
        travelerCount: Int = 1,
        travelMode: TravelMode = .solo,
        transportation: Transportation = .unknown,
        laundryAccess: LaundryAccess = .none,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.destinationDisplayName = destination.displayName
        self.destinationCity = destination.city
        self.destinationRegion = destination.region
        self.destinationCountry = destination.country
        self.destinationCountryCode = destination.countryCode
        self.destinationLatitude = destination.latitude
        self.destinationLongitude = destination.longitude
        self.destinationTimeZone = destination.timeZone
        self.destinationMapKitID = destination.mapKitIdentifier
        self.destinationFixtureID = destination.fixtureID
        self.startDate = startDate
        self.endDate = endDate
        self.durationDays = durationDays
        self.durationNights = durationNights
        self.tripTypeRaw = tripType.rawValue
        self.activitiesRaw = activities.joined(separator: ",")
        self.bagTypeRaw = bagType.rawValue
        self.packingStyleRaw = packingStyle.rawValue
        self.statusRaw = status.rawValue
        self.userNotes = userNotes
        self.contextChipsRaw = contextChips.map(\.rawValue).joined(separator: ",")
        self.travelerCount = travelerCount
        self.travelModeRaw = travelMode.rawValue
        self.transportationRaw = transportation.rawValue
        self.laundryAccessRaw = laundryAccess.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.items = []
        self.weatherSnapshots = []
        self.overrides = []
        self.weatherChangeProposals = []
        self.travelers = []
        self.bags = []
    }

    var destination: Destination {
        Destination(
            displayName: destinationDisplayName,
            city: destinationCity,
            region: destinationRegion,
            country: destinationCountry,
            countryCode: destinationCountryCode,
            latitude: destinationLatitude,
            longitude: destinationLongitude,
            timeZone: destinationTimeZone,
            mapKitIdentifier: destinationMapKitID,
            fixtureID: destinationFixtureID
        )
    }

    var tripType: TripType { TripType(rawValue: tripTypeRaw) ?? .other }
    var bagType: BagType { BagType(rawValue: bagTypeRaw) ?? .notSure }
    var packingStyle: PackingStyle { PackingStyle(rawValue: packingStyleRaw) ?? .balanced }
    var status: TripStatus { TripStatus(rawValue: statusRaw) ?? .planning }
    var activities: [String] {
        ActivityVocabulary.normalize(
            activitiesRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
        )
    }
    var contextChips: [ContextChip] {
        contextChipsRaw.split(separator: ",").compactMap { ContextChip(rawValue: String($0)) }
    }

    var packedCount: Int { items.filter(\.isPacked).count }
    var remainingCount: Int { max(0, items.count - packedCount) }
    var travelMode: TravelMode { TravelMode(rawValue: travelModeRaw) ?? .solo }

    var party: TripParty {
        if travelers.isEmpty {
            return .solo(chips: Set(contextChips).subtracting(ContextChip.tripLevel))
        }
        let mapped = travelers
            .sorted { $0.createdAt < $1.createdAt }
            .map(\.domain)
        return TripParty(travelMode: travelMode, travelers: mapped)
    }

    /// The stored three-way value wins; the legacy `laundryAvailable` chip maps
    /// to `.possible`, not `.planned` — "I'll have laundry" states availability,
    /// not intent, and `.planned` requires deliberate user intent.
    var laundryAccess: LaundryAccess {
        let stored = LaundryAccess(rawValue: laundryAccessRaw) ?? .none
        if stored != .none { return stored }
        return contextChips.contains(.laundryAvailable) ? .possible : .none
    }

    func context(preferences: TravelerPreferences, weather: TripWeatherContext?) -> TripContext {
        let resolvedParty = party
        return TripContext(
            destination: destination,
            startDate: startDate,
            endDate: endDate,
            durationDays: durationDays,
            durationNights: durationNights,
            tripType: tripType,
            activities: activities,
            datedActivities: activities.map { DatedActivity(activityID: $0, date: nil) },
            bagType: bagType,
            packingStyle: packingStyle,
            transportation: Transportation(rawValue: transportationRaw) ?? .unknown,
            laundryAccess: laundryAccess,
            travelerCount: max(1, resolvedParty.travelers.count),
            userNotes: userNotes,
            contextChips: Set(contextChips),
            weather: weather,
            preferences: preferences,
            party: resolvedParty
        )
    }
}

@Model
final class PackingItemRecord {
    @Attribute(.unique) var id: UUID
    var canonicalItemID: String?
    var displayName: String
    var categoryRaw: String
    var quantity: Int
    var packedQuantity: Int
    var importanceRaw: String
    var sourceSignalsRaw: String
    var reason: String
    var reasonCode: String = ""
    var reasonArgumentsRaw: String = ""
    var quantityReason: String
    var isUserAdded: Bool
    var isUserModified: Bool
    var ownershipTypeRaw: String = "personal"
    var travelerID: UUID?
    var assignedTravelerID: UUID?
    var bagID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var trip: TripRecord?

    init(from draft: PackingItemDraft, trip: TripRecord) {
        self.id = draft.id
        self.canonicalItemID = draft.canonicalItemID
        self.displayName = draft.displayName
        self.categoryRaw = draft.category.rawValue
        self.quantity = draft.quantity
        self.packedQuantity = draft.packedQuantity
        self.importanceRaw = draft.importance.rawValue
        self.sourceSignalsRaw = draft.sourceSignals.map(\.rawValue).joined(separator: ",")
        self.reason = draft.reason
        self.reasonCode = draft.reasonCode
        self.reasonArgumentsRaw = draft.reasonArguments.map { "\($0.key)=\($0.value)" }.joined(separator: "|")
        self.quantityReason = draft.quantityReason
        self.isUserAdded = draft.isUserAdded
        self.isUserModified = draft.isUserModified
        self.ownershipTypeRaw = draft.ownershipType.rawValue
        self.travelerID = draft.travelerID
        self.assignedTravelerID = draft.assignedTravelerID
        self.bagID = draft.bagID
        self.createdAt = .now
        self.updatedAt = .now
        self.trip = trip
    }

    var category: PackingCategory { PackingCategory(rawValue: categoryRaw) ?? .miscellaneous }
    var importance: ItemImportance { ItemImportance(rawValue: importanceRaw) ?? .normal }
    var ownershipType: PackingOwnership { PackingOwnership(rawValue: ownershipTypeRaw) ?? .personal }
    var isPacked: Bool { packedQuantity >= max(1, quantity) }
    var sourceSignals: [RecommendationSignal] {
        sourceSignalsRaw.split(separator: ",").compactMap { RecommendationSignal(rawValue: String($0)) }
    }

    var draft: PackingItemDraft {
        PackingItemDraft(
            id: id,
            canonicalItemID: canonicalItemID,
            displayName: displayName,
            category: category,
            quantity: quantity,
            packedQuantity: packedQuantity,
            importance: importance,
            sourceSignals: sourceSignals,
            reason: reason,
            reasonCode: reasonCode,
            reasonArguments: Dictionary(uniqueKeysWithValues: reasonArgumentsRaw.split(separator: "|").compactMap { pair in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return (parts[0], parts[1])
            }),
            quantityReason: quantityReason,
            isUserAdded: isUserAdded,
            isUserModified: isUserModified,
            ownershipType: ownershipType,
            travelerID: travelerID,
            assignedTravelerID: assignedTravelerID,
            bagID: bagID
        )
    }

    func apply(_ draft: PackingItemDraft) {
        quantity = draft.quantity
        packedQuantity = draft.packedQuantity
        reason = draft.reason
        quantityReason = draft.quantityReason
        isUserModified = draft.isUserModified
        ownershipTypeRaw = draft.ownershipType.rawValue
        travelerID = draft.travelerID
        assignedTravelerID = draft.assignedTravelerID
        bagID = draft.bagID
        updatedAt = .now
    }
}

@Model
final class TravelerRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var roleRaw: String
    var ageGroupRaw: String
    var packingResponsibilityRaw: String = "self"
    var guardianTravelerID: UUID?
    var chipsRaw: String
    var needsRaw: String = ""
    var notes: String
    var createdAt: Date
    var trip: TripRecord?

    init(from traveler: Traveler, trip: TripRecord) {
        self.id = traveler.id
        self.name = traveler.name
        self.roleRaw = traveler.role.rawValue
        self.ageGroupRaw = traveler.ageGroup.rawValue
        self.packingResponsibilityRaw = traveler.packingResponsibility.rawValue
        self.guardianTravelerID = traveler.guardianTravelerID
        self.chipsRaw = traveler.chips.map(\.rawValue).joined(separator: ",")
        self.needsRaw = traveler.needs.map(\.rawValue).joined(separator: ",")
        self.notes = traveler.notes
        self.createdAt = .now
        self.trip = trip
    }

    func apply(_ traveler: Traveler) {
        name = traveler.name
        roleRaw = traveler.role.rawValue
        ageGroupRaw = traveler.ageGroup.rawValue
        packingResponsibilityRaw = traveler.packingResponsibility.rawValue
        guardianTravelerID = traveler.guardianTravelerID
        chipsRaw = traveler.chips.map(\.rawValue).joined(separator: ",")
        needsRaw = traveler.needs.map(\.rawValue).joined(separator: ",")
        notes = traveler.notes
    }

    var domain: Traveler {
        Traveler(
            id: id,
            name: name,
            role: TravelerRole(rawValue: roleRaw) ?? .self,
            ageGroup: AgeGroup(rawValue: ageGroupRaw) ?? .adult,
            packingResponsibility: PackingResponsibility(rawValue: packingResponsibilityRaw) ?? .self,
            guardianTravelerID: guardianTravelerID,
            chips: Set(chipsRaw.split(separator: ",").compactMap { ContextChip(rawValue: String($0)) }),
            needs: Set(needsRaw.split(separator: ",").compactMap { ChildNeed(rawValue: String($0)) }),
            notes: notes
        )
    }
}

@Model
final class BagRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var bagTypeRaw: String
    var ownerTravelerID: UUID?
    var ownershipTypeRaw: String = "personal"
    var createdAt: Date
    var trip: TripRecord?

    init(from bag: TripBag, trip: TripRecord) {
        self.id = bag.id
        self.name = bag.name
        self.bagTypeRaw = bag.bagType.rawValue
        self.ownerTravelerID = bag.ownerTravelerID
        self.ownershipTypeRaw = bag.ownershipType.rawValue
        self.createdAt = .now
        self.trip = trip
    }

    var domain: TripBag {
        TripBag(
            id: id,
            name: name,
            bagType: BagType(rawValue: bagTypeRaw) ?? .notSure,
            ownerTravelerID: ownerTravelerID,
            ownershipType: PackingOwnership(rawValue: ownershipTypeRaw) ?? .personal
        )
    }
}

@Model
final class WeatherSnapshotRecord {
    var fetchedAt: Date
    var forecastStart: Date
    var forecastEnd: Date
    var summary: String
    var payloadJSON: Data
    var trip: TripRecord?

    init(context: TripWeatherContext, trip: TripRecord) {
        self.fetchedAt = context.fetchedAt
        self.forecastStart = context.coverageStart ?? context.dailyForecast.first?.date ?? trip.startDate
        self.forecastEnd = context.coverageEnd ?? context.dailyForecast.last?.date ?? trip.endDate
        self.summary = context.weatherSummary
        self.payloadJSON = (try? JSONEncoder().encode(context)) ?? Data()
        self.trip = trip
    }

    var weatherContext: TripWeatherContext? {
        try? JSONDecoder().decode(TripWeatherContext.self, from: payloadJSON)
    }

    var providerFetchedAt: Date? { weatherContext?.providerFetchedAt }
    var providerExpiresAt: Date? { weatherContext?.providerExpiresAt }
    var coverageStart: Date? { weatherContext?.coverageStart }
    var coverageEnd: Date? { weatherContext?.coverageEnd }
    var source: WeatherSource { weatherContext?.source ?? .none }
    var tripWeatherState: TripWeatherState { weatherContext?.state() ?? .unavailable }
}

@Model
final class WeatherChangeProposalRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var statusRaw: String
    var payloadJSON: Data
    var trip: TripRecord?

    init(proposal: WeatherChangeProposal, trip: TripRecord) {
        self.id = proposal.id
        self.createdAt = proposal.createdAt
        self.statusRaw = proposal.status.rawValue
        self.payloadJSON = (try? JSONEncoder().encode(proposal)) ?? Data()
        self.trip = trip
    }

    var status: WeatherChangeProposalStatus {
        WeatherChangeProposalStatus(rawValue: statusRaw) ?? .pending
    }

    var proposal: WeatherChangeProposal? {
        try? JSONDecoder().decode(WeatherChangeProposal.self, from: payloadJSON)
    }

    func apply(_ proposal: WeatherChangeProposal) {
        id = proposal.id
        createdAt = proposal.createdAt
        statusRaw = proposal.status.rawValue
        payloadJSON = (try? JSONEncoder().encode(proposal)) ?? payloadJSON
    }
}

@Model
final class RecommendationOverrideRecord {
    var canonicalItemID: String
    var action: String
    var travelerID: UUID?
    var ownershipTypeRaw: String?
    var createdAt: Date
    var trip: TripRecord?

    init(canonicalItemID: String, action: String, trip: TripRecord, travelerID: UUID? = nil, ownershipType: PackingOwnership? = nil) {
        self.canonicalItemID = canonicalItemID
        self.action = action
        self.travelerID = travelerID
        self.ownershipTypeRaw = ownershipType?.rawValue
        self.createdAt = .now
        self.trip = trip
    }

    var draft: RecommendationOverrideDraft {
        RecommendationOverrideDraft(
            canonicalItemID: canonicalItemID,
            action: action,
            travelerID: travelerID,
            ownershipType: ownershipTypeRaw.flatMap(PackingOwnership.init(rawValue:))
        )
    }
}

@Model
final class PackingPreferenceRecord {
    var homeCountryCode: String
    var homeCountrySourceRaw: String = "deviceSuggested"
    var packingStyleRaw: String
    var preferredBagRaw: String
    var usesFahrenheit: Bool
    var usesImperial: Bool
    var usuallyWorkOut: Bool
    var usuallyBringLaptop: Bool
    var wearContacts: Bool
    var alwaysBringMedication: Bool
    var hasCompletedOnboarding: Bool
    var hasConfirmedHomeCountry: Bool

    init(from preferences: TravelerPreferences) {
        self.homeCountryCode = preferences.homeCountryCode ?? ""
        self.homeCountrySourceRaw = preferences.homeCountrySource.rawValue
        self.packingStyleRaw = preferences.packingStyle.rawValue
        self.preferredBagRaw = preferences.preferredBag.rawValue
        self.usesFahrenheit = preferences.usesFahrenheit
        self.usesImperial = preferences.usesImperial
        self.usuallyWorkOut = preferences.usuallyWorkOut
        self.usuallyBringLaptop = preferences.usuallyBringLaptop
        self.wearContacts = preferences.wearContacts
        self.alwaysBringMedication = preferences.alwaysBringMedication
        self.hasCompletedOnboarding = false
        self.hasConfirmedHomeCountry = false
    }

    var preferences: TravelerPreferences {
        TravelerPreferences(
            homeCountryCode: homeCountryCode.isEmpty ? nil : homeCountryCode,
            homeCountrySource: HomeCountrySource(rawValue: homeCountrySourceRaw) ?? .deviceSuggested,
            packingStyle: PackingStyle(rawValue: packingStyleRaw) ?? .balanced,
            preferredBag: BagType(rawValue: preferredBagRaw) ?? .notSure,
            usesFahrenheit: usesFahrenheit,
            usesImperial: usesImperial,
            usuallyWorkOut: usuallyWorkOut,
            usuallyBringLaptop: usuallyBringLaptop,
            wearContacts: wearContacts,
            alwaysBringMedication: alwaysBringMedication
        )
    }

    func apply(_ preferences: TravelerPreferences) {
        homeCountryCode = preferences.homeCountryCode ?? ""
        homeCountrySourceRaw = preferences.homeCountrySource.rawValue
        packingStyleRaw = preferences.packingStyle.rawValue
        preferredBagRaw = preferences.preferredBag.rawValue
        usesFahrenheit = preferences.usesFahrenheit
        usesImperial = preferences.usesImperial
        usuallyWorkOut = preferences.usuallyWorkOut
        usuallyBringLaptop = preferences.usuallyBringLaptop
        wearContacts = preferences.wearContacts
        alwaysBringMedication = preferences.alwaysBringMedication
    }
}

@Model
final class PackingMemoryRecord {
    var canonicalItemID: String
    var travelerID: UUID?
    var suggestedCount: Int
    var removedCount: Int
    var packedCount: Int
    var usedCount: Int

    init(canonicalItemID: String, travelerID: UUID? = nil) {
        self.canonicalItemID = canonicalItemID
        self.travelerID = travelerID
        self.suggestedCount = 0
        self.removedCount = 0
        self.packedCount = 0
        self.usedCount = 0
    }
}

@Model
final class PostTripFeedbackRecord {
    var tripID: UUID
    var createdAt: Date
    var notes: String

    init(tripID: UUID, notes: String = "") {
        self.tripID = tripID
        self.createdAt = .now
        self.notes = notes
    }
}

enum PackWiseSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [
            TripRecord.self,
            PackingItemRecord.self,
            WeatherSnapshotRecord.self,
            RecommendationOverrideRecord.self,
            PackingPreferenceRecord.self,
            PackingMemoryRecord.self,
            PostTripFeedbackRecord.self,
            TravelerRecord.self,
            BagRecord.self,
            WeatherChangeProposalRecord.self
        ]
    }
}

enum PackWiseMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PackWiseSchemaV1.self, PackWiseSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: PackWiseSchemaV1.self,
        toVersion: PackWiseSchemaV2.self
    )
}

enum PackWisePersistence {
    static func container(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: PackWiseSchemaV2.self)
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            config = ModelConfiguration(
                "packwise",
                schema: schema,
                url: support.appendingPathComponent("packwise.store"),
                cloudKitDatabase: .none
            )
        }
        do {
            return try ModelContainer(for: schema, migrationPlan: PackWiseMigrationPlan.self, configurations: [config])
        } catch {
            resetUnknownStore(config)
            return try ModelContainer(for: schema, migrationPlan: PackWiseMigrationPlan.self, configurations: [config])
        }
    }

    private static func resetUnknownStore(_ config: ModelConfiguration) {
        let url = config.url
        for file in [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")] {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
