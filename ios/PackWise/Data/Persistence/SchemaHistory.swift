import Foundation
import SwiftData

// Frozen per-version store snapshots (Product Experience V2, persistence
// schema-history fix).
//
// V2, V3, and V4 used to alias the always-live `@Model` types in Models.swift.
// Aliased versions share one checksum, and any migration stage between two
// equal checksums makes CoreData abort the process ("Duplicate version
// checksums detected") — so every install whose store was not already in the
// exact current shape crashed at launch. Each historical shape now has its own
// frozen snapshot, matching the real stores in `PackWiseTests/StoreFixtures/`.
// The live types in Models.swift are only ever the newest version.


/// Frozen snapshot of the 2.0.0 store shape — party/bag/weather-proposal model (18d754d … a975eab).
/// Captured from `a975eab`; real store checksum `L3DEX+RPGd0t9Hz1KO36ttgCV1h/9tGzwVxbgoDRUFU=`.
/// Generated from that commit's `@Model` declarations: stored properties,
/// attributes, relationships, and declared defaults only. Do not edit —
/// `StoreHistoryTests` pins these entity hashes to real captured stores.
enum PackWiseSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [TripRecord.self, PackingItemRecord.self, WeatherSnapshotRecord.self, RecommendationOverrideRecord.self, PackingPreferenceRecord.self, PackingMemoryRecord.self, PostTripFeedbackRecord.self, TravelerRecord.self, BagRecord.self, WeatherChangeProposalRecord.self]
    }

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

        init() {
            id = UUID()
            destinationDisplayName = ""
            destinationCity = ""
            destinationRegion = ""
            destinationCountry = ""
            destinationCountryCode = ""
            destinationLatitude = 0
            destinationLongitude = 0
            destinationTimeZone = ""
            startDate = Date.now
            endDate = Date.now
            durationDays = 0
            durationNights = 0
            tripTypeRaw = ""
            activitiesRaw = ""
            bagTypeRaw = ""
            packingStyleRaw = ""
            statusRaw = ""
            userNotes = ""
            contextChipsRaw = ""
            createdAt = Date.now
            updatedAt = Date.now
            items = []
            weatherSnapshots = []
            overrides = []
            travelers = []
            bags = []
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

        init() {
            id = UUID()
            displayName = ""
            categoryRaw = ""
            quantity = 0
            packedQuantity = 0
            importanceRaw = ""
            sourceSignalsRaw = ""
            reason = ""
            quantityReason = ""
            isUserAdded = false
            isUserModified = false
            createdAt = Date.now
            updatedAt = Date.now
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

        init() {
            fetchedAt = Date.now
            forecastStart = Date.now
            forecastEnd = Date.now
            summary = ""
            payloadJSON = Data()
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

        init() {
            canonicalItemID = ""
            action = ""
            createdAt = Date.now
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

        init() {
            homeCountryCode = ""
            packingStyleRaw = ""
            preferredBagRaw = ""
            usesFahrenheit = false
            usesImperial = false
            usuallyWorkOut = false
            usuallyBringLaptop = false
            wearContacts = false
            alwaysBringMedication = false
            hasCompletedOnboarding = false
            hasConfirmedHomeCountry = false
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

        init() {
            canonicalItemID = ""
            suggestedCount = 0
            removedCount = 0
            packedCount = 0
            usedCount = 0
        }
    }

    @Model
    final class PostTripFeedbackRecord {
        var tripID: UUID
        var createdAt: Date
        var notes: String

        init() {
            tripID = UUID()
            createdAt = Date.now
            notes = ""
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

        init() {
            id = UUID()
            name = ""
            roleRaw = ""
            ageGroupRaw = ""
            chipsRaw = ""
            notes = ""
            createdAt = Date.now
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

        init() {
            id = UUID()
            name = ""
            bagTypeRaw = ""
            createdAt = Date.now
        }
    }

    @Model
    final class WeatherChangeProposalRecord {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var statusRaw: String
        var payloadJSON: Data
        var trip: TripRecord?

        init() {
            id = UUID()
            createdAt = Date.now
            statusRaw = ""
            payloadJSON = Data()
        }
    }
}

/// Frozen snapshot of the 3.0.0 store shape — adds the immutable packing-memory event log (d4ed374 … 791cf88).
/// Captured from `d4ed374`; real store checksum `x1im2J1dIEeJJLT8UTjeIllRkmZyAGkrUoUtjncr3FQ=`.
/// Generated from that commit's `@Model` declarations: stored properties,
/// attributes, relationships, and declared defaults only. Do not edit —
/// `StoreHistoryTests` pins these entity hashes to real captured stores.
enum PackWiseSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [TripRecord.self, PackingItemRecord.self, WeatherSnapshotRecord.self, RecommendationOverrideRecord.self, PackingPreferenceRecord.self, PackingMemoryRecord.self, PostTripFeedbackRecord.self, TravelerRecord.self, BagRecord.self, WeatherChangeProposalRecord.self, PackingMemoryEventRecord.self]
    }

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

        init() {
            id = UUID()
            destinationDisplayName = ""
            destinationCity = ""
            destinationRegion = ""
            destinationCountry = ""
            destinationCountryCode = ""
            destinationLatitude = 0
            destinationLongitude = 0
            destinationTimeZone = ""
            startDate = Date.now
            endDate = Date.now
            durationDays = 0
            durationNights = 0
            tripTypeRaw = ""
            activitiesRaw = ""
            bagTypeRaw = ""
            packingStyleRaw = ""
            statusRaw = ""
            userNotes = ""
            contextChipsRaw = ""
            createdAt = Date.now
            updatedAt = Date.now
            items = []
            weatherSnapshots = []
            overrides = []
            travelers = []
            bags = []
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

        init() {
            id = UUID()
            displayName = ""
            categoryRaw = ""
            quantity = 0
            packedQuantity = 0
            importanceRaw = ""
            sourceSignalsRaw = ""
            reason = ""
            quantityReason = ""
            isUserAdded = false
            isUserModified = false
            createdAt = Date.now
            updatedAt = Date.now
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

        init() {
            fetchedAt = Date.now
            forecastStart = Date.now
            forecastEnd = Date.now
            summary = ""
            payloadJSON = Data()
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

        init() {
            canonicalItemID = ""
            action = ""
            createdAt = Date.now
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

        init() {
            homeCountryCode = ""
            packingStyleRaw = ""
            preferredBagRaw = ""
            usesFahrenheit = false
            usesImperial = false
            usuallyWorkOut = false
            usuallyBringLaptop = false
            wearContacts = false
            alwaysBringMedication = false
            hasCompletedOnboarding = false
            hasConfirmedHomeCountry = false
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

        init() {
            canonicalItemID = ""
            suggestedCount = 0
            removedCount = 0
            packedCount = 0
            usedCount = 0
        }
    }

    @Model
    final class PostTripFeedbackRecord {
        var tripID: UUID
        var createdAt: Date
        var notes: String

        init() {
            tripID = UUID()
            createdAt = Date.now
            notes = ""
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

        init() {
            id = UUID()
            name = ""
            roleRaw = ""
            ageGroupRaw = ""
            chipsRaw = ""
            notes = ""
            createdAt = Date.now
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

        init() {
            id = UUID()
            name = ""
            bagTypeRaw = ""
            createdAt = Date.now
        }
    }

    @Model
    final class WeatherChangeProposalRecord {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var statusRaw: String
        var payloadJSON: Data
        var trip: TripRecord?

        init() {
            id = UUID()
            createdAt = Date.now
            statusRaw = ""
            payloadJSON = Data()
        }
    }

    @Model
    final class PackingMemoryEventRecord {
        var tripID: UUID
        var travelerID: UUID?
        var canonicalItemID: String
        var kindRaw: String
        var value: Int?
        var timestamp: Date
        var durationBucketRaw: String
        var laundryPlanRaw: String
        var packingStyleRaw: String
        var bagRaw: String
        var tripTypeRaw: String
        var partySize: Int

        init() {
            tripID = UUID()
            canonicalItemID = ""
            kindRaw = ""
            timestamp = Date.now
            durationBucketRaw = ""
            laundryPlanRaw = ""
            packingStyleRaw = ""
            bagRaw = ""
            tripTypeRaw = ""
            partySize = 0
        }
    }
}

/// Frozen snapshot of the 4.0.0 store shape — first V4 multi-value columns, before `preferredBagTypesMigrated` (7a219ee).
/// Captured from `7a219ee`; real store checksum `Spmg1piT42GjARuuYTGcR0dp2b9vVKuuJd97OGdbauA=`.
/// Generated from that commit's `@Model` declarations: stored properties,
/// attributes, relationships, and declared defaults only. Do not edit —
/// `StoreHistoryTests` pins these entity hashes to real captured stores.
enum PackWiseSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [TripRecord.self, PackingItemRecord.self, WeatherSnapshotRecord.self, RecommendationOverrideRecord.self, PackingPreferenceRecord.self, PackingMemoryRecord.self, PostTripFeedbackRecord.self, TravelerRecord.self, BagRecord.self, WeatherChangeProposalRecord.self, PackingMemoryEventRecord.self]
    }

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
        var tripTypesRaw: String = "[]"
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

        init() {
            id = UUID()
            destinationDisplayName = ""
            destinationCity = ""
            destinationRegion = ""
            destinationCountry = ""
            destinationCountryCode = ""
            destinationLatitude = 0
            destinationLongitude = 0
            destinationTimeZone = ""
            startDate = Date.now
            endDate = Date.now
            durationDays = 0
            durationNights = 0
            tripTypeRaw = ""
            activitiesRaw = ""
            bagTypeRaw = ""
            packingStyleRaw = ""
            statusRaw = ""
            userNotes = ""
            contextChipsRaw = ""
            createdAt = Date.now
            updatedAt = Date.now
            items = []
            weatherSnapshots = []
            overrides = []
            travelers = []
            bags = []
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
        var recommendationTraceRaw: String?
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

        init() {
            id = UUID()
            displayName = ""
            categoryRaw = ""
            quantity = 0
            packedQuantity = 0
            importanceRaw = ""
            sourceSignalsRaw = ""
            reason = ""
            quantityReason = ""
            isUserAdded = false
            isUserModified = false
            createdAt = Date.now
            updatedAt = Date.now
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

        init() {
            fetchedAt = Date.now
            forecastStart = Date.now
            forecastEnd = Date.now
            summary = ""
            payloadJSON = Data()
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

        init() {
            canonicalItemID = ""
            action = ""
            createdAt = Date.now
        }
    }

    @Model
    final class PackingPreferenceRecord {
        var homeCountryCode: String
        var homeCountrySourceRaw: String = "deviceSuggested"
        var packingStyleRaw: String
        var preferredBagRaw: String
        var preferredBagTypesRaw: String = "[]"
        var usesFahrenheit: Bool
        var usesImperial: Bool
        var usuallyWorkOut: Bool
        var usuallyBringLaptop: Bool
        var wearContacts: Bool
        var alwaysBringMedication: Bool
        var hasCompletedOnboarding: Bool
        var hasConfirmedHomeCountry: Bool

        init() {
            homeCountryCode = ""
            packingStyleRaw = ""
            preferredBagRaw = ""
            usesFahrenheit = false
            usesImperial = false
            usuallyWorkOut = false
            usuallyBringLaptop = false
            wearContacts = false
            alwaysBringMedication = false
            hasCompletedOnboarding = false
            hasConfirmedHomeCountry = false
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

        init() {
            canonicalItemID = ""
            suggestedCount = 0
            removedCount = 0
            packedCount = 0
            usedCount = 0
        }
    }

    @Model
    final class PostTripFeedbackRecord {
        var tripID: UUID
        var createdAt: Date
        var notes: String

        init() {
            tripID = UUID()
            createdAt = Date.now
            notes = ""
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

        init() {
            id = UUID()
            name = ""
            roleRaw = ""
            ageGroupRaw = ""
            chipsRaw = ""
            notes = ""
            createdAt = Date.now
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

        init() {
            id = UUID()
            name = ""
            bagTypeRaw = ""
            createdAt = Date.now
        }
    }

    @Model
    final class WeatherChangeProposalRecord {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var statusRaw: String
        var payloadJSON: Data
        var trip: TripRecord?

        init() {
            id = UUID()
            createdAt = Date.now
            statusRaw = ""
            payloadJSON = Data()
        }
    }

    @Model
    final class PackingMemoryEventRecord {
        var tripID: UUID
        var travelerID: UUID?
        var canonicalItemID: String
        var kindRaw: String
        var value: Int?
        var timestamp: Date
        var durationBucketRaw: String
        var laundryPlanRaw: String
        var packingStyleRaw: String
        var bagRaw: String
        var tripTypeRaw: String
        var tripTypesRaw: String = "[]"
        var bagTypesRaw: String = "[]"
        var partySize: Int

        init() {
            tripID = UUID()
            canonicalItemID = ""
            kindRaw = ""
            timestamp = Date.now
            durationBucketRaw = ""
            laundryPlanRaw = ""
            packingStyleRaw = ""
            bagRaw = ""
            tripTypeRaw = ""
            partySize = 0
        }
    }
}
