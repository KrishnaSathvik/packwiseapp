import Foundation
import SwiftData

/// Best-effort stable-order JSON encoding for the V4 multi-value columns.
/// `StableRawValueSetCodec.encode` only fails if `JSONEncoder` itself fails
/// to encode `[String]`, which does not happen in practice; the fallback
/// exists so a persistence write is never allowed to throw over it.
enum PackWiseStableEncoding {
    static func tripTypesJSON(_ values: Set<TripType>) -> String {
        (try? StableRawValueSetCodec.encode(values, order: TripType.stableOrder)) ?? #"["other"]"#
    }

    static func bagTypesJSON(_ values: Set<BagType>) -> String {
        (try? StableRawValueSetCodec.encode(values, order: BagType.stableOrder)) ?? "[]"
    }

    /// Wraps a single legacy scalar raw value as the one-element JSON array
    /// `StableRawValueSetCodec.decode` expects, so V3 scalar migration
    /// reuses the same normalization/diagnostic logic as any other stable
    /// set boundary instead of re-implementing it.
    static func wrapLegacyScalar(_ rawValue: String) -> String {
        guard let data = try? JSONEncoder().encode([rawValue]) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
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
    /// V4 stable-order JSON array; see `TripType.stableOrder`. The
    /// authoritative multi-value trip-type storage — `tripTypeRaw` remains
    /// only as a migration-era compatibility column (design Section 6.1).
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
        self.tripTypesRaw = PackWiseStableEncoding.tripTypesJSON([tripType])
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

    /// The V4 multi-value trip-type selection, decoded from the stable JSON
    /// array. Falls back to `.other` if the stored JSON is somehow corrupt,
    /// matching `TripType.normalizedSet`'s own empty-result fallback.
    var tripTypes: Set<TripType> {
        (try? TripType.normalizedSet(fromStableJSON: tripTypesRaw))?.values ?? [.other]
    }

    /// The V4 physical bag selection, derived from the `bags` relationship —
    /// not stored as a parallel raw field, so it can never drift from the
    /// actual `BagRecord`s a trip owns (design Section 6.1).
    var bagTypes: Set<BagType> {
        Set(bags.compactMap { BagType(rawValue: $0.bagTypeRaw) }.filter { BagType.stableOrder.contains($0) })
    }

    /// Compatibility accessor for call sites not yet updated to consume
    /// `tripTypes` (Tasks 3/4 land the multi-type engine). A genuine
    /// multi-selection fails safe to `.other` — which contributes no typed
    /// packing needs — rather than silently picking one of the selected
    /// types as if it alone were authoritative.
    var tripType: TripType {
        let values = tripTypes
        guard values.count == 1, let only = values.first else { return .other }
        return only
    }

    /// Compatibility accessor; see `tripType`. A multi-bag selection fails
    /// safe to `.notSure` (no luggage constraint) rather than picking one
    /// bag as if it were the trip's only bag.
    var bagType: BagType {
        let values = bagTypes
        guard values.count == 1, let only = values.first else { return .notSure }
        return only
    }
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
    /// V4 persistence encoding of the Phase 8 `RecommendationTrace` (Task
    /// 13's concern to define/populate). Optional because migrated V3 rows
    /// have no trace yet; `sourceSignalsRaw`/`reason`/`reasonCode`/
    /// `reasonArgumentsRaw` remain the engine's current source/reason
    /// fields until Task 13 lands.
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
    /// V4 stable-order JSON array; see `BagType.stableOrder`. Replaces
    /// `preferredBagRaw` as the default-bag preference (design Section
    /// 6.2); the legacy scalar remains only as a migration/compat column.
    var preferredBagTypesRaw: String = "[]"
    /// True once `preferredBagTypesRaw` holds real V4 data — either backfilled
    /// from `preferredBagRaw` once, or written directly by `init`/`apply`.
    /// Unlike `TripRecord.tripTypesRaw` (never legitimately empty, so its
    /// own default doubles as an "unmigrated" signal), an empty
    /// `preferredBagTypesRaw` is a valid real V4 value (no bag preference),
    /// so this needs its own explicit marker: without it, the V3 → V4
    /// backfill would re-derive from the stale `preferredBagRaw` scalar on
    /// every launch forever and could clobber a genuine later multi-value
    /// write the same way it once did for `TripRecord.tripTypesRaw`/`bags`.
    var preferredBagTypesMigrated: Bool = false
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
        self.preferredBagTypesRaw = PackWiseStableEncoding.bagTypesJSON(preferences.preferredBagTypes)
        self.preferredBagTypesMigrated = true
        self.usesFahrenheit = preferences.usesFahrenheit
        self.usesImperial = preferences.usesImperial
        self.usuallyWorkOut = preferences.usuallyWorkOut
        self.usuallyBringLaptop = preferences.usuallyBringLaptop
        self.wearContacts = preferences.wearContacts
        self.alwaysBringMedication = preferences.alwaysBringMedication
        self.hasCompletedOnboarding = false
        self.hasConfirmedHomeCountry = false
    }

    /// V4 multi-value default-bag preference, decoded from the stable JSON
    /// array. See `TravelerPreferences.preferredBagTypes`.
    var preferredBagTypes: Set<BagType> {
        (try? BagType.normalizedSet(fromStableJSON: preferredBagTypesRaw))?.values ?? []
    }

    var preferences: TravelerPreferences {
        TravelerPreferences(
            homeCountryCode: homeCountryCode.isEmpty ? nil : homeCountryCode,
            homeCountrySource: HomeCountrySource(rawValue: homeCountrySourceRaw) ?? .deviceSuggested,
            packingStyle: PackingStyle(rawValue: packingStyleRaw) ?? .balanced,
            preferredBag: BagType(rawValue: preferredBagRaw) ?? .notSure,
            preferredBagTypes: preferredBagTypes,
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
        preferredBagTypesRaw = PackWiseStableEncoding.bagTypesJSON(preferences.preferredBagTypes)
        preferredBagTypesMigrated = true
        usesFahrenheit = preferences.usesFahrenheit
        usesImperial = preferences.usesImperial
        usuallyWorkOut = preferences.usuallyWorkOut
        usuallyBringLaptop = preferences.usuallyBringLaptop
        wearContacts = preferences.wearContacts
        alwaysBringMedication = preferences.alwaysBringMedication
    }
}

@Model
/// Superseded by `PackingMemoryEventRecord`: aggregate counters can't answer
/// the queries memory needs, and nothing ever wrote these. Kept in the schema
/// until a cleanup migration retires it.
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

/// One immutable packing-memory event (Engine V2, Step 6). Write-only for
/// now; the fingerprint is stored as flat raw fields so future memory
/// queries are simple predicates.
///
/// Deliberately not related to `TripRecord`: events survive trip deletion.
/// The retention decision is documented in `Domain/PackingMemory.swift` and
/// `docs/lifecycle-memory-and-me.md`.
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
    /// Legacy V3 scalar fields; migration source/compat only. No production
    /// code reads them — `tripTypesRaw`/`bagTypesRaw` are authoritative.
    var bagRaw: String
    var tripTypeRaw: String
    /// V4 stable-order JSON arrays; see `TripType`/`BagType.stableOrder`.
    var tripTypesRaw: String = "[]"
    var bagTypesRaw: String = "[]"
    var partySize: Int

    init(_ event: PackingMemoryEvent) {
        tripID = event.tripID
        travelerID = event.travelerID
        canonicalItemID = event.canonicalItemID
        kindRaw = event.kind.rawValue
        value = event.value
        timestamp = event.timestamp
        durationBucketRaw = event.context.durationBucket.rawValue
        laundryPlanRaw = event.context.laundryPlan.rawValue
        packingStyleRaw = event.context.packingStyle.rawValue
        tripTypesRaw = PackWiseStableEncoding.tripTypesJSON(event.context.tripTypes)
        bagTypesRaw = PackWiseStableEncoding.bagTypesJSON(event.context.bagTypes)
        // Compat scalars: the first stable value only, so older diagnostics
        // can still read the record. Never read back as authority.
        bagRaw = BagType.stableOrder.first(where: event.context.bagTypes.contains)?.rawValue ?? BagType.notSure.rawValue
        tripTypeRaw = TripType.stableOrder.first(where: event.context.tripTypes.contains)?.rawValue ?? TripType.other.rawValue
        partySize = event.context.partySize
    }

    var event: PackingMemoryEvent {
        PackingMemoryEvent(
            tripID: tripID,
            travelerID: travelerID,
            canonicalItemID: canonicalItemID,
            kind: PackingMemoryEventKind(rawValue: kindRaw) ?? .suggested,
            value: value,
            timestamp: timestamp,
            context: ContextFingerprint(
                durationBucket: DurationBucket(rawValue: durationBucketRaw) ?? .medium,
                laundryPlan: LaundryAccess(rawValue: laundryPlanRaw) ?? .none,
                packingStyle: PackingStyle(rawValue: packingStyleRaw) ?? .balanced,
                bagTypes: (try? BagType.normalizedSet(fromStableJSON: bagTypesRaw))?.values ?? [],
                tripTypes: (try? TripType.normalizedSet(fromStableJSON: tripTypesRaw))?.values ?? [.other],
                partySize: partySize
            )
        )
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

// Known limitation, pre-existing before Product Experience V2: unlike
// `PackWiseSchemaV1` (`SchemaV1.swift`, a genuinely frozen snapshot type),
// `PackWiseSchemaV2` and `PackWiseSchemaV3` below alias the same always-live
// types this file currently declares, rather than freezing their own
// historical shape. That has been safe so far because every V2→V3 change
// was purely additive (new defaulted/optional columns, one new entity) and
// `MigrationStage.lightweight` tolerates that. It does mean there is no
// independent, testable model of "an actual V2/V3-shaped store" to migrate
// against — only ever today's live types. A `.custom` stage (which needs
// its two schema versions to be genuinely distinct models, not just
// differently labeled) was tried for V3 → V4 and does not work under this
// aliasing scheme; see `PackWiseSchemaV4`'s doc comment for what was used
// instead. A real fix — frozen per-version snapshot types for V2/V3, the
// same pattern `SchemaV1.swift` already uses — is a separate task; flagging
// it here rather than re-attempting it under this one.
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

enum PackWiseSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] {
        PackWiseSchemaV2.models + [PackingMemoryEventRecord.self]
    }
}

/// V4 adds no new `@Model` entity and no structural attribute SwiftData
/// itself needs to migrate: every new V4 column (`tripTypesRaw`,
/// `recommendationTraceRaw`, `preferredBagTypesRaw`, the memory-event stable
/// arrays) is declared directly on the live types in this file with a
/// default value, exactly like every additive column V2 → V3 already added
/// this way. What genuinely needs "migrating" is the *data* — populating
/// those columns from the legacy scalars — not the schema shape, so V4
/// reuses `PackWiseSchemaV3.models` (see `PackWiseSchemaV4Migration` below
/// for the data step, run from `PackWisePersistence.container`).
enum PackWiseSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }
    static var models: [any PersistentModel.Type] {
        PackWiseSchemaV3.models
    }
}

/// V3 → V4 data migration (design Section 6.2): converts every legacy
/// scalar trip-type/bag-type/preferred-bag/memory-fingerprint value into its
/// V4 stable multi-value representation. The new V4 columns already exist
/// with their defaults (`PackWisePersistence.container` opens the store
/// before calling this), so this only has to backfill them from the legacy
/// scalars for pre-existing rows. Idempotent: every derived column is
/// recomputed from a legacy field this migration never modifies, so running
/// it again against already-migrated rows reproduces the same result.
///
/// Exposed as internal functions, not private, so tests can drive and
/// assert on migration diagnostics directly.
enum PackWiseSchemaV4Migration {
    /// Migrates every still-unmigrated V3-shaped record in `context` and
    /// saves the result. Returns every normalization diagnostic recorded
    /// along the way (design Section 6.2's "unknown value" rows). A
    /// per-record failure never throws — only genuine SwiftData fetch/save
    /// failures propagate — so one malformed row can't abort migrating the
    /// rest.
    ///
    /// Every record is filtered to "not yet migrated" in the fetch itself
    /// (see the `#Predicate` on each `FetchDescriptor` below), not after
    /// loading every row into memory: `PackingMemoryEventRecord` in
    /// particular is designed to accumulate indefinitely (see its doc
    /// comment), so this must not become an unconditional full-table scan
    /// that grows with total app usage forever — only genuinely unmigrated
    /// rows (normally zero, after the first post-upgrade launch) are ever
    /// faulted into memory.
    ///
    /// The filter matters for correctness, not just cost: this function
    /// runs on *every* container open, not once. Without it, it would keep
    /// re-deriving `tripTypesRaw`/`bags`/`preferredBagTypesRaw` from their
    /// legacy scalars forever, silently discarding any later genuine
    /// multi-value write made through `TripRepository.applyTripTypes`/
    /// `applyBagTypes` (whose compat scalars deliberately hold only the
    /// first stable value, never the full selection) the next time the app
    /// launched. A record is only ever migrated once; from then on its V4
    /// columns are the only authority.
    @discardableResult
    static func migrateV3Records(in context: ModelContext) throws -> [TripContextNormalizationDiagnostic] {
        var diagnostics: [TripContextNormalizationDiagnostic] = []

        // A trip/fingerprint has already been migrated to V4 the moment
        // `tripTypesRaw` holds a real value: every genuine V4 write
        // (`TripRecord.init`, `TripRepository.apply`/`applyTripTypes`, and
        // this migration itself) always writes at least one stable trip
        // type — a trip can never validly have zero — so `tripTypesRaw`
        // staying at its just-added default `"[]"` is only possible for a
        // row that predates this migration ever running.
        let unmigratedTrips = FetchDescriptor<TripRecord>(predicate: #Predicate { $0.tripTypesRaw == "[]" })
        for trip in try context.fetch(unmigratedTrips) {
            // Gates the whole trip — bag conversion included, not only the
            // trip-type array — since both legs are migrated together
            // below; one flag correctly protects both once either has run.
            diagnostics += migrate(trip, in: context)
        }

        // `preferredBagTypesRaw` has no such invariant (an empty selection
        // is a legitimate real V4 value — no bag preference), so it needs
        // its own explicit marker rather than reusing its own default.
        let unmigratedPreferences = FetchDescriptor<PackingPreferenceRecord>(
            predicate: #Predicate { $0.preferredBagTypesMigrated == false }
        )
        for preference in try context.fetch(unmigratedPreferences) {
            migrate(preference)
        }

        // Same reasoning as trips: a fingerprint's `tripTypesRaw` derives
        // from `TripRecord.tripTypes`, itself never empty, so it is an
        // equally reliable "still legacy-shaped" signal here.
        let unmigratedEvents = FetchDescriptor<PackingMemoryEventRecord>(predicate: #Predicate { $0.tripTypesRaw == "[]" })
        for event in try context.fetch(unmigratedEvents) {
            diagnostics += migrate(event)
        }

        try context.save()
        return diagnostics
    }

    /// Decodes a legacy scalar trip-type raw value the same way at every
    /// call site: an unknown value drops to `.other` with a diagnostic,
    /// mirroring `TripType.normalizedSet`'s own empty-result fallback.
    private static func decodeLegacyTripType(_ raw: String) -> NormalizedSet<TripType> {
        (try? TripType.normalizedSet(fromStableJSON: PackWiseStableEncoding.wrapLegacyScalar(raw)))
            ?? NormalizedSet(values: [.other], diagnostics: [.droppedUnknownRawValues([raw])])
    }

    /// Decodes a legacy scalar bag-type raw value the same way at every
    /// call site that only needs the normalized *set* (not `migrate(_
    /// trip:in:)`'s `BagRecord` bookkeeping, which has real side effects
    /// this decode alone can't express): `notSure`/`roadTripLuggage`/
    /// unknown all drop to no bag constraint.
    private static func decodeLegacyBagSet(_ raw: String) -> NormalizedSet<BagType> {
        (try? BagType.normalizedSet(fromStableJSON: PackWiseStableEncoding.wrapLegacyScalar(raw)))
            ?? NormalizedSet(values: [], diagnostics: [.droppedUnknownRawValues([raw])])
    }

    /// `tripTypeRaw = beach` → `tripTypesRaw = ["beach"]`; an unknown value
    /// becomes `["other"]` plus a diagnostic. `bagTypeRaw` becomes at most
    /// one physical `BagRecord`: `carryOn`/`checked` preserve an existing
    /// matching record's identity/owner or create one; `notSure`/
    /// `roadTripLuggage`/unknown leave no setup-created bag record (unknown
    /// also records a diagnostic). Migrating `roadTripLuggage` never adds
    /// `.roadTrip` to `tripTypes` — this only ever sees the bag scalar and
    /// must not infer a trip type from it. Only ever called for a trip
    /// `migrateV3Records` has already confirmed is still legacy-shaped.
    private static func migrate(_ trip: TripRecord, in context: ModelContext) -> [TripContextNormalizationDiagnostic] {
        let tripTypeResult = decodeLegacyTripType(trip.tripTypeRaw)
        var diagnostics = tripTypeResult.diagnostics
        trip.tripTypesRaw = PackWiseStableEncoding.tripTypesJSON(tripTypeResult.values)

        if let physicalBagType = BagType.stableOrder.first(where: { $0.rawValue == trip.bagTypeRaw }) {
            if !trip.bags.contains(where: { $0.bagTypeRaw == physicalBagType.rawValue }) {
                let bag = TripBag(name: physicalBagType.title, bagType: physicalBagType, ownershipType: .personal)
                let record = BagRecord(from: bag, trip: trip)
                context.insert(record)
                trip.bags.append(record)
            }
        } else {
            // notSure, roadTripLuggage, or an unknown raw value: no
            // setup-created bag record. A V3 setup bag was created directly
            // from this same scalar (`TripRepository.replaceParty`), so any
            // matching stray record here carried no real bag information.
            for bag in trip.bags where bag.bagTypeRaw == trip.bagTypeRaw {
                context.delete(bag)
            }
            trip.bags.removeAll { $0.bagTypeRaw == trip.bagTypeRaw }
            if BagType(rawValue: trip.bagTypeRaw) == nil {
                diagnostics.append(.droppedUnknownRawValues([trip.bagTypeRaw]))
            }
        }

        return diagnostics
    }

    /// Legacy physical defaults become singleton `preferredBagTypes`;
    /// `notSure`, `roadTripLuggage`, and unknown values become empty. Only
    /// ever called for a preference row that isn't `preferredBagTypesMigrated`
    /// yet.
    private static func migrate(_ preference: PackingPreferenceRecord) {
        let result = decodeLegacyBagSet(preference.preferredBagRaw)
        preference.preferredBagTypesRaw = PackWiseStableEncoding.bagTypesJSON(result.values)
        preference.preferredBagTypesMigrated = true
    }

    /// The same one-to-one scalar → stable-array conversion applies to
    /// immutable memory-event fingerprints (design Section 6.2). Only ever
    /// called for an event `migrateV3Records` has already confirmed is
    /// still legacy-shaped.
    private static func migrate(_ event: PackingMemoryEventRecord) -> [TripContextNormalizationDiagnostic] {
        let tripTypeResult = decodeLegacyTripType(event.tripTypeRaw)
        event.tripTypesRaw = PackWiseStableEncoding.tripTypesJSON(tripTypeResult.values)

        let bagResult = decodeLegacyBagSet(event.bagRaw)
        event.bagTypesRaw = PackWiseStableEncoding.bagTypesJSON(bagResult.values)

        return tripTypeResult.diagnostics + bagResult.diagnostics
    }
}

enum PackWiseMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PackWiseSchemaV1.self, PackWiseSchemaV2.self, PackWiseSchemaV3.self, PackWiseSchemaV4.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: PackWiseSchemaV1.self,
        toVersion: PackWiseSchemaV2.self
    )

    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: PackWiseSchemaV2.self,
        toVersion: PackWiseSchemaV3.self
    )

    /// Lightweight, not custom: `PackWiseSchemaV4.models` is exactly
    /// `PackWiseSchemaV3.models` — the same live types, unchanged as a
    /// schema graph — so there is no structural difference for a
    /// `MigrationStage.custom` stage to act on. (A `.custom` stage requires
    /// its `fromVersion`/`toVersion` model graphs to be genuinely distinct;
    /// with identical graphs, SwiftData/CoreData raises "the current model
    /// reference and the next model reference cannot be equal.") The actual
    /// V4 *data* migration — populating the new stable-array columns from
    /// their legacy scalars — is not a schema-shape change at all, so it
    /// runs as an ordinary, idempotent post-open step from
    /// `PackWisePersistence.container` instead. See `PackWiseSchemaV4Migration`.
    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: PackWiseSchemaV3.self,
        toVersion: PackWiseSchemaV4.self
    )
}

enum PackWisePersistence {
    /// A persistent-store open or migration error is surfaced to the
    /// caller, never silently recovered by deleting data (design Section
    /// 6.3): PackWise must never delete `packwise.store`, its WAL, or SHM
    /// merely because migration failed.
    static func container(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: PackWiseSchemaV4.self)
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
        let container = try ModelContainer(for: schema, migrationPlan: PackWiseMigrationPlan.self, configurations: [config])
        // The V3 → V4 *data* backfill (design Section 6.2) runs here rather
        // than as a migration-stage callback — see `migrateV3toV4` above.
        // It is safe to call on every open: each record is only ever
        // actually migrated once (see `migrateV3Records`'s own doc
        // comment for the per-record "already migrated" guards), so this
        // converges a store to the V4 shape once and then does
        // near-zero-cost work on every subsequent launch.
        let diagnostics = try PackWiseSchemaV4Migration.migrateV3Records(in: ModelContext(container))
        #if DEBUG
        if !diagnostics.isEmpty {
            print("[PackWise] V4 migration normalized \(diagnostics.count) legacy value(s): \(diagnostics)")
        }
        #endif
        return container
    }
}
