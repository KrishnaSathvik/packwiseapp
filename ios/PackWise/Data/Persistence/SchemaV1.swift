import Foundation
import SwiftData

/// Snapshot of the pre-party store. Do not add new fields here.
enum PackWiseSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            TripRecord.self,
            PackingItemRecord.self,
            WeatherSnapshotRecord.self,
            RecommendationOverrideRecord.self,
            PackingPreferenceRecord.self,
            PackingMemoryRecord.self,
            PostTripFeedbackRecord.self
        ]
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
        var travelerCount: Int
        var transportationRaw: String
        var laundryAccessRaw: String
        var createdAt: Date
        var updatedAt: Date

        @Relationship(deleteRule: .cascade, inverse: \PackingItemRecord.trip)
        var items: [PackingItemRecord]

        @Relationship(deleteRule: .cascade, inverse: \WeatherSnapshotRecord.trip)
        var weatherSnapshots: [WeatherSnapshotRecord]

        @Relationship(deleteRule: .cascade, inverse: \RecommendationOverrideRecord.trip)
        var overrides: [RecommendationOverrideRecord]

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
            durationDays = 1
            durationNights = 0
            tripTypeRaw = "other"
            activitiesRaw = ""
            bagTypeRaw = "notSure"
            packingStyleRaw = "balanced"
            statusRaw = "planning"
            userNotes = ""
            contextChipsRaw = ""
            travelerCount = 1
            transportationRaw = "unknown"
            laundryAccessRaw = "none"
            createdAt = Date.now
            updatedAt = Date.now
            items = []
            weatherSnapshots = []
            overrides = []
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
        var reasonCode: String
        var reasonArgumentsRaw: String
        var quantityReason: String
        var isUserAdded: Bool
        var isUserModified: Bool
        var createdAt: Date
        var updatedAt: Date
        var trip: TripRecord?

        init() {
            id = UUID()
            displayName = ""
            categoryRaw = "miscellaneous"
            quantity = 1
            packedQuantity = 0
            importanceRaw = "normal"
            sourceSignalsRaw = ""
            reason = ""
            reasonCode = ""
            reasonArgumentsRaw = ""
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
        var homeCountrySourceRaw: String
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
            homeCountrySourceRaw = "deviceSuggested"
            packingStyleRaw = "balanced"
            preferredBagRaw = "notSure"
            usesFahrenheit = true
            usesImperial = true
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
}
