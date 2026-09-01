import Foundation
import SwiftData

@MainActor
final class TripRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func upcoming() throws -> [TripRecord] {
        let now = Date.now
        var descriptor = FetchDescriptor<TripRecord>(
            predicate: #Predicate { $0.endDate >= now && $0.statusRaw != "archived" && $0.statusRaw != "completed" },
            sortBy: [SortDescriptor(\.startDate)]
        )
        descriptor.fetchLimit = 50
        return try context.fetch(descriptor)
    }

    func past() throws -> [TripRecord] {
        var descriptor = FetchDescriptor<TripRecord>(
            predicate: #Predicate { $0.statusRaw == "completed" || $0.statusRaw == "archived" },
            sortBy: [SortDescriptor(\.endDate, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        return try context.fetch(descriptor)
    }

    func trip(id: UUID) throws -> TripRecord? {
        var descriptor = FetchDescriptor<TripRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func insert(_ trip: TripRecord) {
        context.insert(trip)
    }

    func delete(_ trip: TripRecord) {
        context.delete(trip)
    }

    func save() throws {
        try context.save()
    }

    func replaceItems(on trip: TripRecord, with drafts: [PackingItemDraft]) {
        let previous = Set(trip.items.compactMap(\.canonicalItemID))
        for item in trip.items {
            context.delete(item)
        }
        trip.items = drafts.map { PackingItemRecord(from: $0, trip: trip) }
        trip.updatedAt = .now
        // First appearance of an engine suggestion is a memory event;
        // regenerations that keep an item don't re-record it.
        for draft in drafts where !draft.isUserAdded {
            guard let canonical = draft.canonicalItemID, !previous.contains(canonical) else { continue }
            recordMemoryEvent(.suggested, canonicalItemID: canonical, travelerID: draft.travelerID, value: draft.quantity, on: trip)
        }
    }

    func attach(party: TripParty, bagType: BagType, on trip: TripRecord) {
        replaceParty(party, bagType: bagType, on: trip)
    }

    func replaceParty(_ party: TripParty, bagType: BagType, on trip: TripRecord) {
        trip.travelModeRaw = party.travelMode.rawValue
        trip.travelerCount = max(1, party.travelers.count)
        let existingByID = Dictionary(uniqueKeysWithValues: trip.travelers.map { ($0.id, $0) })
        var next: [TravelerRecord] = []
        for traveler in party.travelers {
            if let record = existingByID[traveler.id] {
                record.apply(traveler)
                next.append(record)
            } else {
                next.append(TravelerRecord(from: traveler, trip: trip))
            }
        }
        for record in trip.travelers where !party.containsTraveler(record.id) {
            context.delete(record)
        }
        trip.travelers = next
        if trip.bags.isEmpty {
            let ownership: PackingOwnership = party.usesSimpleList ? .personal : .shared
            let bag = TripBag(
                name: bagType.title,
                bagType: bagType,
                ownerTravelerID: party.usesSimpleList ? party.primary.id : nil,
                ownershipType: ownership
            )
            trip.bags = [BagRecord(from: bag, trip: trip)]
        }
    }

    func addItem(_ draft: PackingItemDraft, to trip: TripRecord, syncWeatherChange: Bool = true) {
        trip.items.append(PackingItemRecord(from: draft, trip: trip))
        trip.updatedAt = .now
        recordMemoryEvent(
            draft.isUserAdded ? .userAdded : .suggested,
            canonicalItemID: draft.canonicalItemID ?? "custom:\(draft.displayName)",
            travelerID: draft.travelerID,
            value: draft.quantity,
            on: trip
        )
        if syncWeatherChange {
            syncPendingWeatherChange(on: trip)
        }
    }

    func markNotNeeded(_ item: PackingItemRecord, on trip: TripRecord) {
        if let canonical = item.canonicalItemID {
            trip.overrides.append(
                RecommendationOverrideRecord(
                    canonicalItemID: canonical,
                    action: "removed",
                    trip: trip,
                    travelerID: item.travelerID,
                    ownershipType: item.ownershipType
                )
            )
        }
        if let canonical = item.canonicalItemID {
            recordMemoryEvent(.notNeeded, canonicalItemID: canonical, travelerID: item.travelerID, value: nil, on: trip)
        }
        context.delete(item)
        trip.items.removeAll { $0.id == item.id }
        trip.updatedAt = .now
        syncPendingWeatherChange(on: trip)
    }

    func deleteItem(_ item: PackingItemRecord, on trip: TripRecord) {
        context.delete(item)
        trip.items.removeAll { $0.id == item.id }
        trip.updatedAt = .now
        syncPendingWeatherChange(on: trip)
    }

    /// Completion snapshots the trip's final state into memory: what was
    /// actually packed, and where the user overrode a suggested quantity.
    /// Pack/unpack churn during the trip is noise; the final state is what
    /// memory can learn from.
    func complete(_ trip: TripRecord) {
        guard trip.statusRaw != TripStatus.completed.rawValue else {
            trip.updatedAt = .now
            return
        }
        trip.statusRaw = TripStatus.completed.rawValue
        trip.updatedAt = .now
        for item in trip.items {
            let canonical = item.canonicalItemID ?? "custom:\(item.displayName)"
            if item.isUserModified && !item.isUserAdded {
                recordMemoryEvent(.quantityChanged, canonicalItemID: canonical, travelerID: item.travelerID, value: item.quantity, on: trip)
            }
            if item.packedQuantity > 0 {
                recordMemoryEvent(.packed, canonicalItemID: canonical, travelerID: item.travelerID, value: item.packedQuantity, on: trip)
            }
        }
    }

    /// Events carry the trip's UUID but no relationship: they survive trip
    /// deletion by design (see `Domain/PackingMemory.swift`).
    private func recordMemoryEvent(
        _ kind: PackingMemoryEventKind,
        canonicalItemID: String,
        travelerID: UUID?,
        value: Int?,
        on trip: TripRecord
    ) {
        let event = PackingMemoryEvent(
            tripID: trip.id,
            travelerID: travelerID,
            canonicalItemID: canonicalItemID,
            kind: kind,
            value: value,
            timestamp: .now,
            context: ContextFingerprint(
                durationBucket: .from(days: trip.durationDays),
                laundryPlan: trip.laundryAccess,
                packingStyle: trip.packingStyle,
                bag: trip.bagType,
                tripType: trip.tripType,
                partySize: max(1, trip.travelerCount)
            )
        )
        context.insert(PackingMemoryEventRecord(event))
    }

    func apply(
        destination: Destination,
        startDate: Date,
        endDate: Date,
        durationDays: Int,
        durationNights: Int,
        tripType: TripType,
        activities: [String],
        bagType: BagType,
        packingStyle: PackingStyle,
        laundryAccess: LaundryAccess,
        userNotes: String,
        contextChips: [ContextChip],
        party: TripParty,
        on trip: TripRecord
    ) {
        trip.destinationDisplayName = destination.displayName
        trip.destinationCity = destination.city
        trip.destinationRegion = destination.region
        trip.destinationCountry = destination.country
        trip.destinationCountryCode = destination.countryCode
        trip.destinationLatitude = destination.latitude
        trip.destinationLongitude = destination.longitude
        trip.destinationTimeZone = destination.timeZone
        trip.destinationMapKitID = destination.mapKitIdentifier
        trip.destinationFixtureID = destination.fixtureID
        trip.startDate = startDate
        trip.endDate = endDate
        trip.durationDays = durationDays
        trip.durationNights = durationNights
        trip.tripTypeRaw = tripType.rawValue
        trip.activitiesRaw = activities.joined(separator: ",")
        trip.bagTypeRaw = bagType.rawValue
        trip.packingStyleRaw = packingStyle.rawValue
        trip.laundryAccessRaw = laundryAccess.rawValue
        trip.userNotes = userNotes
        trip.contextChipsRaw = contextChips.map(\.rawValue).joined(separator: ",")
        trip.updatedAt = .now
        replaceParty(party, bagType: bagType, on: trip)
        syncPendingWeatherChange(on: trip)
    }

    func applyDiff(
        _ diff: RecommendationDiff,
        addIDs: Set<UUID>,
        removeIDs: Set<UUID>,
        quantityIDs: Set<UUID>,
        on trip: TripRecord
    ) {
        for draft in diff.add where addIDs.contains(draft.id) {
            if trip.items.contains(where: { $0.draft.recommendationKey == draft.recommendationKey }) {
                continue
            }
            addItem(draft, to: trip, syncWeatherChange: false)
        }
        for change in diff.quantityChanges where quantityIDs.contains(change.item.id) {
            if let record = trip.items.first(where: { $0.id == change.item.id }) {
                record.quantity = change.suggestedQuantity
                if record.packedQuantity > record.quantity {
                    record.packedQuantity = record.quantity
                }
                record.updatedAt = .now
            }
        }
        for candidate in diff.removeCandidates where removeIDs.contains(candidate.id) {
            if let record = trip.items.first(where: { $0.id == candidate.id }) {
                markNotNeeded(record, on: trip)
            }
        }
        trip.updatedAt = .now
    }

    func storeWeather(_ weather: TripWeatherContext, on trip: TripRecord) {
        for snapshot in trip.weatherSnapshots {
            context.delete(snapshot)
        }
        trip.weatherSnapshots = [WeatherSnapshotRecord(context: weather, trip: trip)]
        trip.updatedAt = .now
    }

    func pendingWeatherChange(on trip: TripRecord) -> WeatherChangeProposal? {
        let signature = WeatherChangeProposalLifecycle.tripContextSignature(
            trip.context(preferences: .deviceDefaults(), weather: nil)
        )
        let existing = trip.items.map(\.draft)
        let overrides = trip.overrides.map(\.draft)
        return trip.weatherChangeProposals
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap(\.proposal)
            .first { $0.status == .pending }
            .flatMap { proposal in
                WeatherChangeProposalLifecycle.actionable(
                    proposal,
                    tripContextSignature: signature,
                    existing: existing,
                    overrides: overrides
                )
            }
    }

    func replacePendingWeatherChange(_ proposal: WeatherChangeProposal, on trip: TripRecord) {
        let pendingRecords = trip.weatherChangeProposals.filter { $0.status == .pending }
        if let existingRecord = pendingRecords.first,
           let existing = existingRecord.proposal,
           WeatherChangeProposalLifecycle.hasSamePackingConsequence(existing, proposal) {
            var kept = existing
            kept.oldSnapshotID = proposal.oldSnapshotID
            kept.newSnapshotID = proposal.newSnapshotID
            kept.signalChanges = proposal.signalChanges
            kept.headline = proposal.headline
            kept.tripContextSignature = proposal.tripContextSignature
            existingRecord.apply(kept)
            trip.updatedAt = .now
            return
        }
        for record in pendingRecords {
            guard var current = record.proposal else {
                context.delete(record)
                continue
            }
            current.status = .superseded
            record.apply(current)
        }
        trip.weatherChangeProposals.append(WeatherChangeProposalRecord(proposal: proposal, trip: trip))
        trip.updatedAt = .now
    }

    func updateWeatherChange(_ proposal: WeatherChangeProposal, on trip: TripRecord) {
        if let record = trip.weatherChangeProposals.first(where: { $0.id == proposal.id }) {
            record.apply(proposal)
        } else {
            trip.weatherChangeProposals.append(WeatherChangeProposalRecord(proposal: proposal, trip: trip))
        }
        trip.updatedAt = .now
    }

    func dismissWeatherChange(_ proposal: WeatherChangeProposal, on trip: TripRecord) {
        var updated = proposal
        updated.status = .dismissed
        updateWeatherChange(updated, on: trip)
    }

    func applyWeatherChange(_ proposal: WeatherChangeProposal, on trip: TripRecord) {
        var updated = proposal
        updated.status = .applied
        updateWeatherChange(updated, on: trip)
    }

    func syncPendingWeatherChange(on trip: TripRecord) {
        let signature = WeatherChangeProposalLifecycle.tripContextSignature(
            trip.context(preferences: .deviceDefaults(), weather: nil)
        )
        let existing = trip.items.map(\.draft)
        let overrides = trip.overrides.map(\.draft)
        for record in trip.weatherChangeProposals where record.status == .pending {
            guard let proposal = record.proposal else { continue }
            switch WeatherChangeProposalLifecycle.evaluate(
                proposal,
                tripContextSignature: signature,
                existing: existing,
                overrides: overrides
            ) {
            case .pending(let current):
                record.apply(current)
            case .invalidated:
                var updated = proposal
                updated.status = .invalidated
                record.apply(updated)
            }
        }
    }
}

@MainActor
final class PreferenceRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func current() throws -> PackingPreferenceRecord {
        var descriptor = FetchDescriptor<PackingPreferenceRecord>()
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let created = PackingPreferenceRecord(from: .deviceDefaults())
        context.insert(created)
        try context.save()
        return created
    }

    func save() throws {
        try context.save()
    }
}
