import Foundation

/// Everything trip setup collects, as sets where the product is multi-select
/// (Product Experience V2, Task 8). Selection rules live here, not in views,
/// so they are testable without UI:
///
/// - trip types: at least one before the flow can advance;
/// - activities: only a user tap changes them — trip types change which
///   suggestions show, never what is selected;
/// - bags: any of the four physical bags, independently; none is "not sure".
struct TripDraft {
    var destination: Destination?
    /// Where this trip is taken from (Task 9.2). Seeded from Me for a fresh
    /// trip, restored from the trip on edit; there is no setup control yet.
    var origin: TripOrigin = .unknown
    var startDate = Calendar.current.startOfDay(for: Date.now)
    var endDate = Calendar.current.date(byAdding: .day, value: 4, to: Calendar.current.startOfDay(for: Date.now)) ?? Date.now
    var tripTypes: Set<TripType> = []
    var activities: [String] = []
    var bagTypes: Set<BagType> = []
    var packingStyle: PackingStyle = .balanced
    var laundry: LaundryAccess = .none
    /// The primary traveler's About you choices (including device signals)
    /// plus trip-level chips.
    var chips: Set<ContextChip> = []
    var notes: String = ""
    var travelMode: TravelMode = .solo
    /// Adults other than You, in party order. A couple uses the first.
    var otherAdults: [AdultDraft] = []
    var childProfiles: [ChildDraft] = []
    var existingParty: TripParty?

    var duration: (days: Int, nights: Int) {
        TripDateMath.daysAndNights(from: startDate, to: endDate)
    }

    /// The chips stored on the trip itself. Traveler device signals belong
    /// to one companion's details and are never trip context.
    var tripChips: Set<ContextChip> {
        chips.subtracting(ContextChip.travelerDeviceSignals)
    }

    var party: TripParty {
        TripPartyBuilder.make(
            mode: travelMode,
            // You's device signals live on your traveler record only.
            selfChips: chips.subtracting(ContextChip.tripLevel),
            otherAdults: otherAdults,
            children: travelMode == .family ? childProfiles : [],
            existing: existingParty
        )
    }

    var hasTripType: Bool { !tripTypes.isEmpty }

    // MARK: - Selection

    /// Toggles a trip type. Never adds or removes an activity.
    mutating func toggleTripType(_ type: TripType) {
        if tripTypes.contains(type) { tripTypes.remove(type) } else { tripTypes.insert(type) }
    }

    mutating func toggleActivity(_ id: String) {
        if activities.contains(id) {
            activities.removeAll { $0 == id }
        } else {
            activities.append(id)
        }
    }

    /// Only the four V2 physical bags are selectable.
    mutating func toggleBag(_ bag: BagType) {
        guard BagType.stableOrder.contains(bag) else { return }
        if bagTypes.contains(bag) { bagTypes.remove(bag) } else { bagTypes.insert(bag) }
    }

    /// The activities to show: the stable union of every selected trip type's
    /// suggestions, then any selection outside it, so a chosen activity never
    /// disappears from the field it lives in. Display and order only.
    func visibleActivities(contracts: TripTypeContractTable) -> [String] {
        var ids = TripTypeContractResolver(contracts: contracts).suggestedActivityIDs(for: tripTypes)
        ids.append(contentsOf: activities.filter { !ids.contains($0) })
        return ids
    }

    // MARK: - Travelers

    /// Single-select party mode. Switching keeps every traveler draft, so
    /// switching back restores names and choices; only the minimums a mode
    /// needs are added.
    mutating func setTravelMode(_ mode: TravelMode) {
        travelMode = mode
        switch mode {
        case .solo:
            break
        case .couple:
            if otherAdults.isEmpty { otherAdults = [AdultDraft()] }
        case .family:
            if childProfiles.isEmpty { childProfiles = [ChildDraft(ageGroup: .child)] }
        case .group:
            while otherAdults.count < 2 { otherAdults.append(AdultDraft()) }
        }
    }

    /// Adults besides You that this mode includes.
    var otherAdultCount: Int {
        switch travelMode {
        case .solo: 0
        case .couple: min(1, otherAdults.count)
        case .family, .group: otherAdults.count
        }
    }

    static func otherAdultRange(for mode: TravelMode) -> ClosedRange<Int> {
        switch mode {
        case .solo: 0...0
        case .couple: 1...1
        case .family: 0...5
        case .group: 1...7
        }
    }

    static let childRange: ClosedRange<Int> = 0...6

    mutating func setOtherAdultCount(_ count: Int) {
        let target = min(max(count, Self.otherAdultRange(for: travelMode).lowerBound), Self.otherAdultRange(for: travelMode).upperBound)
        if target < otherAdults.count {
            otherAdults = Array(otherAdults.prefix(target))
        }
        while otherAdults.count < target { otherAdults.append(AdultDraft()) }
    }

    mutating func setChildCount(_ count: Int) {
        let target = min(max(count, Self.childRange.lowerBound), Self.childRange.upperBound)
        if target < childProfiles.count {
            childProfiles = Array(childProfiles.prefix(target))
        }
        while childProfiles.count < target { childProfiles.append(ChildDraft(ageGroup: .child)) }
    }

    // MARK: - Construction

    static func fresh(preferences: TravelerPreferences) -> TripDraft {
        var draft = TripDraft()
        draft.packingStyle = preferences.packingStyle
        draft.bagTypes = preferences.preferredBagTypes
        // Me's home country seeds this trip's origin (Task 9.2). From here on
        // the trip owns it; editing Me later reaches the next new trip only.
        draft.origin = TripOrigin(seededFrom: preferences)
        // Me's habits prefill You only (Tasks 8.2–9.1). Deselecting one here
        // changes this trip, never the preference; companions start with no
        // choices regardless.
        draft.chips.formUnion(MeDefaultChoices.chips(for: preferences))
        return draft
    }

    static func from(trip: TripRecord) -> TripDraft {
        let party = trip.party
        var draft = TripDraft()
        draft.destination = trip.destination
        draft.origin = trip.origin ?? .unknown
        draft.startDate = trip.startDate
        draft.endDate = trip.endDate
        draft.tripTypes = trip.tripTypes
        draft.activities = trip.activities
        draft.bagTypes = trip.bagTypes
        draft.packingStyle = trip.packingStyle
        draft.laundry = trip.laundryAccess
        draft.chips = Set(trip.contextChips).subtracting(ContextChip.travelerDeviceSignals)
            .union(party.primary.chips.intersection(ContextChip.travelerDeviceSignals))
        draft.notes = trip.userNotes
        draft.travelMode = party.travelMode
        draft.otherAdults = party.travelers
            .filter { $0.role == .partner || $0.role == .otherAdult }
            .map { AdultDraft(id: $0.id, name: $0.name, chips: $0.chips, notes: $0.notes) }
        draft.childProfiles = party.travelers
            .filter { $0.role == .child }
            .map { ChildDraft(id: $0.id, name: $0.name, ageGroup: $0.ageGroup, needs: $0.needs, chips: $0.chips) }
        draft.existingParty = party
        return draft
    }
}

/// The nine logical setup steps (design Section 11), in order.
enum SetupStep: Int, CaseIterable, Hashable {
    case destination, dates, travelers, tripTypes, activities, bags, styleAndLaundry, preferences, review

    var number: Int { rawValue + 1 }
    static var count: Int { allCases.count }

    var next: SetupStep? { SetupStep(rawValue: rawValue + 1) }

    var title: String {
        switch self {
        case .destination: "Where are you going?"
        case .dates: "When are you going?"
        case .travelers: "Who's traveling?"
        case .tripTypes: "What kind of trip is it?"
        case .activities: "What will you be doing?"
        case .bags: "What bags are you bringing?"
        case .styleAndLaundry: "How do you like to pack?"
        case .preferences: "Anything PackWise should know?"
        case .review: "Review your trip"
        }
    }

    var subtitle: String {
        switch self {
        case .destination: "Search for a city, region, or country."
        case .dates: "Pick the days you'll be away."
        case .travelers: "Add everyone you're packing for."
        case .tripTypes: "Choose all that apply."
        case .activities: "Suggestions follow your trip types. Choose any that apply."
        case .bags: "Choose all that apply."
        case .styleAndLaundry: "Your packing style and laundry for this trip."
        case .preferences: "Optional, but it makes the list fit better."
        case .review: "One look before PackWise builds your list."
        }
    }
}
