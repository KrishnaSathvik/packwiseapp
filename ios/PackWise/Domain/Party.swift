import Foundation

enum TravelMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case solo
    case couple
    case family
    case group

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solo: "Just me"
        case .couple: "Me + partner"
        case .family: "Family"
        case .group: "Group"
        }
    }

    var usesSimpleList: Bool { self == .solo }
}

enum TravelerRole: String, Codable, CaseIterable, Sendable {
    case `self`
    case partner
    case child
    case otherAdult

    var defaultName: String {
        switch self {
        case .self: "You"
        case .partner: "Partner"
        case .child: "Child"
        case .otherAdult: "Adult"
        }
    }
}

enum AgeGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case adult
    case teen
    case child
    case toddler
    case infant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .adult: "Adult"
        case .teen: "Teen"
        case .child: "Child"
        case .toddler: "Toddler"
        case .infant: "Infant"
        }
    }

    var isYoungChild: Bool {
        switch self {
        case .infant, .toddler, .child: true
        case .teen, .adult: false
        }
    }

    var skipsAdultPersonalEssentials: Bool {
        self == .infant || self == .toddler
    }

    var allowsGuardian: Bool { self != .adult }
    var isAdult: Bool { self == .adult }
}

enum PackingOwnership: String, Codable, Sendable {
    case personal
    case shared
}

enum PackingResponsibility: String, Codable, Sendable {
    case `self`
    case anotherTraveler
    case shared
    case guardian
}

enum SharingPolicy: String, Codable, Sendable {
    case singlePerParty
    case scaleByParty
    case scaleByDevices
    case scaleByDurationAndParty
    case personalOnly
}

enum ChildNeed: String, Codable, CaseIterable, Identifiable, Sendable {
    case diapers
    case formula
    case pacifier
    case stroller
    case carrier
    case carSeat
    case medication
    case comfortItem

    var id: String { rawValue }

    var title: String {
        switch self {
        case .diapers: "Diapers"
        case .formula: "Formula / bottles"
        case .pacifier: "Pacifier"
        case .stroller: "Stroller"
        case .carrier: "Baby carrier"
        case .carSeat: "Car seat"
        case .medication: "Child medication"
        case .comfortItem: "Comfort item"
        }
    }

    static func suggested(for ageGroup: AgeGroup) -> [ChildNeed] {
        switch ageGroup {
        case .infant: [.diapers, .formula, .pacifier, .stroller, .carrier, .carSeat, .medication]
        case .toddler: [.diapers, .stroller, .carSeat, .medication, .comfortItem]
        case .child: [.medication, .comfortItem, .carSeat]
        case .teen, .adult: []
        }
    }
}

struct Traveler: Hashable, Identifiable, Codable, Sendable {
    var id: UUID
    var name: String
    var role: TravelerRole
    var ageGroup: AgeGroup
    var packingResponsibility: PackingResponsibility
    var guardianTravelerID: UUID?
    var chips: Set<ContextChip>
    var needs: Set<ChildNeed>
    var notes: String

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? role.defaultName : trimmed
    }

    /// Who should carry this traveler's personal items. Owner stays `id`.
    var carrierID: UUID? {
        switch packingResponsibility {
        case .self: id
        case .guardian, .anotherTraveler: guardianTravelerID ?? id
        case .shared: nil
        }
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        role: TravelerRole,
        ageGroup: AgeGroup,
        packingResponsibility: PackingResponsibility? = nil,
        guardianTravelerID: UUID? = nil,
        chips: Set<ContextChip> = [],
        needs: Set<ChildNeed> = [],
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.ageGroup = ageGroup
        self.packingResponsibility = packingResponsibility ?? (role == .child ? .guardian : .self)
        self.guardianTravelerID = guardianTravelerID
        self.chips = chips
        self.needs = needs
        self.notes = notes
    }

    static func primarySelf(name: String = "You", chips: Set<ContextChip> = []) -> Traveler {
        Traveler(name: name, role: .self, ageGroup: .adult, chips: chips)
    }
}

struct TripBag: Hashable, Identifiable, Codable, Sendable {
    var id: UUID
    var name: String
    var bagType: BagType
    var ownerTravelerID: UUID?
    var ownershipType: PackingOwnership

    init(
        id: UUID = UUID(),
        name: String,
        bagType: BagType,
        ownerTravelerID: UUID? = nil,
        ownershipType: PackingOwnership
    ) {
        self.id = id
        self.name = name
        self.bagType = bagType
        self.ownerTravelerID = ownerTravelerID
        self.ownershipType = ownershipType
    }
}

struct TripParty: Hashable, Codable, Sendable {
    var travelMode: TravelMode
    var travelers: [Traveler]

    static func solo(chips: Set<ContextChip> = []) -> TripParty {
        TripParty(travelMode: .solo, travelers: [.primarySelf(chips: chips)])
    }

    var usesSimpleList: Bool {
        travelMode == .solo || travelers.count <= 1
    }

    var primary: Traveler {
        travelers.first { $0.role == .self } ?? travelers.first ?? .primarySelf()
    }

    var adults: [Traveler] {
        travelers.filter { $0.ageGroup == .adult || $0.ageGroup == .teen }
    }

    var children: [Traveler] {
        travelers.filter(\.ageGroup.isYoungChild)
    }

    var summary: String {
        switch travelMode {
        case .solo:
            return "Just you"
        case .couple:
            return "You + \(travelers.first { $0.role == .partner }?.displayName ?? "Partner")"
        case .family:
            let adultCount = travelers.filter { $0.role != .child }.count
            let childCount = travelers.filter { $0.role == .child }.count
            return "Family · \(adultCount) adult\(adultCount == 1 ? "" : "s"), \(childCount) child\(childCount == 1 ? "" : "ren")"
        case .group:
            return "Group · \(travelers.count) traveler\(travelers.count == 1 ? "" : "s")"
        }
    }

    /// Presentation label for a traveler (Product Experience V2, Task 8): the
    /// optional name when set, otherwise a stable positional label — You,
    /// Adult 1, Adult 2, Child 1, Child 2 — derived from party order. Never
    /// written back over the name, and never an engine input.
    func label(for traveler: Traveler) -> String {
        let trimmed = traveler.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if traveler.role == .self { return trimmed.isEmpty || trimmed == "You" ? "You" : trimmed }
        return trimmed.isEmpty ? positionLabel(for: traveler) : trimmed
    }

    /// The structural position label — You, Adult 1, Child 1 — ignoring the
    /// name. Traveler editors use it as the card heading so a typed name is
    /// never shown twice (Task 8.1).
    func positionLabel(for traveler: Traveler) -> String {
        if traveler.role == .self { return "You" }
        if traveler.role == .child {
            let children = travelers.filter { $0.role == .child }
            return "Child \((children.firstIndex { $0.id == traveler.id } ?? 0) + 1)"
        }
        let adults = travelers.filter { $0.role == .partner || $0.role == .otherAdult }
        return "Adult \((adults.firstIndex { $0.id == traveler.id } ?? 0) + 1)"
    }

    /// The label for the shared group, beside `label(for:)`.
    static let sharedLabel = "Shared"

    /// One unambiguous count: the current user is always "You", so the rest
    /// are *other* adults — "You + 3 adults", "You + 1 adult, 2 children".
    var travelerCountSummary: String {
        let adults = travelers.filter { $0.role == .partner || $0.role == .otherAdult }.count
        let children = travelers.filter { $0.role == .child }.count
        var parts: [String] = []
        if adults > 0 { parts.append("\(adults) adult\(adults == 1 ? "" : "s")") }
        if children > 0 { parts.append("\(children) \(children == 1 ? "child" : "children")") }
        return parts.isEmpty ? "Just you" : "You + " + parts.joined(separator: ", ")
    }

    /// The People scopes: All, one per traveler in party order, Shared
    /// (Task 11.1). One traveler is one scope — children are never folded
    /// into a generic bucket, because two children differ in age, needs,
    /// quantities, and packed state. A large party scrolls the chips.
    func listFilters() -> [PartyListFilter] {
        [.all] + travelers.map { .traveler($0.id) } + [.shared]
    }

    func containsTraveler(_ id: UUID) -> Bool {
        travelers.contains { $0.id == id }
    }
}

enum PartyInvariantViolation: Equatable, Sendable {
    case personalItemMissingOwner
    case sharedItemHasOwner
    case assignedTravelerNotInParty
    case guardianNotAllowed
    case guardianNotInParty
    case guardianNotAdult
    case bagOwnerNotInParty
}

enum PartyInvariants {
    static func violations(
        party: TripParty,
        items: [PackingItemDraft] = [],
        bags: [TripBag] = []
    ) -> [PartyInvariantViolation] {
        var found: [PartyInvariantViolation] = []
        let ids = Set(party.travelers.map(\.id))
        let adults = Set(party.travelers.filter(\.ageGroup.isAdult).map(\.id))

        for traveler in party.travelers {
            if let guardian = traveler.guardianTravelerID {
                if !traveler.ageGroup.allowsGuardian {
                    found.append(.guardianNotAllowed)
                } else if !ids.contains(guardian) {
                    found.append(.guardianNotInParty)
                } else if !adults.contains(guardian) {
                    found.append(.guardianNotAdult)
                }
            }
        }

        for item in items {
            switch item.ownershipType {
            case .personal:
                if item.travelerID == nil { found.append(.personalItemMissingOwner) }
            case .shared:
                if item.travelerID != nil { found.append(.sharedItemHasOwner) }
            }
            if let assigned = item.assignedTravelerID, !ids.contains(assigned) {
                found.append(.assignedTravelerNotInParty)
            }
        }

        for bag in bags {
            if let owner = bag.ownerTravelerID, !ids.contains(owner) {
                found.append(.bagOwnerNotInParty)
            }
        }

        return found
    }

    static func normalize(_ item: PackingItemDraft, in party: TripParty) -> PackingItemDraft {
        var copy = item
        let ids = Set(party.travelers.map(\.id))
        switch copy.ownershipType {
        case .personal:
            if copy.travelerID == nil || copy.travelerID.map(ids.contains) == false {
                copy.travelerID = party.primary.id
            }
        case .shared:
            copy.travelerID = nil
        }
        if let assigned = copy.assignedTravelerID, !ids.contains(assigned) {
            copy.assignedTravelerID = nil
        }
        return copy
    }
}

enum PartyListFilter: Hashable, Identifiable, Sendable {
    case all
    case traveler(UUID)
    case shared

    var id: String {
        switch self {
        case .all: "all"
        case .traveler(let id): "traveler-\(id.uuidString)"
        case .shared: "shared"
        }
    }
}

struct ChildDraft: Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var ageGroup: AgeGroup
    var needs: Set<ChildNeed>
    /// Device choices. Only a teen is offered them; the builder drops them
    /// for any younger age group.
    var chips: Set<ContextChip>

    init(id: UUID = UUID(), name: String = "", ageGroup: AgeGroup = .child, needs: Set<ChildNeed> = [], chips: Set<ContextChip> = []) {
        self.id = id
        self.name = name
        self.ageGroup = ageGroup
        self.needs = needs
        self.chips = chips
    }

    /// Whether traveler details offer device choices for this age.
    static func offersDevices(_ ageGroup: AgeGroup) -> Bool { ageGroup == .teen }
}

/// Setup's editable details for one adult other than You (Task 8): the
/// partner on a couple trip, or an other adult on a family or group trip.
struct AdultDraft: Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    /// Differences (medication, contacts, …) and device choices, attributed
    /// to this adult only.
    var chips: Set<ContextChip>
    var notes: String

    init(id: UUID = UUID(), name: String = "", chips: Set<ContextChip> = [], notes: String = "") {
        self.id = id
        self.name = name
        self.chips = chips
        self.notes = notes
    }
}

enum TripPartyBuilder {
    /// Builds a party from setup's per-traveler drafts (Task 8). Draft IDs are
    /// traveler IDs, so editing a trip keeps every surviving traveler's
    /// identity (and the rows that belong to them). You is implicit; `otherAdults`
    /// are everyone else who is an adult. A couple uses the first as partner;
    /// a group always has at least one.
    static func make(
        mode: TravelMode,
        selfChips: Set<ContextChip>,
        otherAdults: [AdultDraft],
        children: [ChildDraft],
        existing: TripParty? = nil
    ) -> TripParty {
        let primary = reusedSelf(from: existing, chips: selfChips)
        let partnerIDs = Set(existing?.travelers.filter { $0.role == .partner }.map(\.id) ?? [])
        func adult(_ draft: AdultDraft, role: TravelerRole) -> Traveler {
            Traveler(id: draft.id, name: draft.name, role: role, ageGroup: .adult, chips: draft.chips, notes: draft.notes)
        }
        switch mode {
        case .solo:
            return TripParty(travelMode: .solo, travelers: [primary])
        case .couple:
            return TripParty(travelMode: .couple, travelers: [primary, adult(otherAdults.first ?? AdultDraft(), role: .partner)])
        case .family:
            var travelers = [primary] + otherAdults.map { adult($0, role: partnerIDs.contains($0.id) ? .partner : .otherAdult) }
            for child in children {
                travelers.append(Traveler(
                    id: child.id,
                    name: child.name,
                    role: .child,
                    ageGroup: child.ageGroup,
                    packingResponsibility: .guardian,
                    guardianTravelerID: primary.id,
                    chips: ChildDraft.offersDevices(child.ageGroup) ? child.chips.intersection(ContextChip.travelerDevices) : [],
                    needs: child.needs
                ))
            }
            return TripParty(travelMode: .family, travelers: travelers)
        case .group:
            let adults = otherAdults.isEmpty ? [AdultDraft()] : otherAdults
            return TripParty(travelMode: .group, travelers: [primary] + adults.map { adult($0, role: .otherAdult) })
        }
    }

    static func make(
        mode: TravelMode,
        selfChips: Set<ContextChip> = [],
        partnerName: String = "",
        partnerChips: Set<ContextChip> = [],
        partnerNotes: String = "",
        adultCount: Int = 2,
        childProfiles: [ChildDraft] = [],
        existing: TripParty? = nil
    ) -> TripParty {
        let primary = reusedSelf(from: existing, chips: selfChips)
        switch mode {
        case .solo:
            return TripParty(travelMode: .solo, travelers: [primary])
        case .couple:
            let partner = reusedPartner(
                from: existing,
                name: partnerName,
                chips: partnerChips,
                notes: partnerNotes
            )
            return TripParty(travelMode: .couple, travelers: [primary, partner])
        case .family:
            var travelers: [Traveler] = [primary]
            let extraAdults = existing?.travelers.filter { $0.role == .otherAdult || ($0.role == .partner && mode == .family) } ?? []
            let neededExtras = max(0, adultCount - 1)
            for index in 0..<neededExtras {
                if extraAdults.indices.contains(index) {
                    let prior = extraAdults[index]
                    travelers.append(
                        Traveler(
                            id: prior.id,
                            name: prior.name,
                            role: prior.role == .partner ? .partner : .otherAdult,
                            ageGroup: .adult,
                            chips: prior.chips,
                            notes: prior.notes
                        )
                    )
                } else {
                    travelers.append(Traveler(role: .otherAdult, ageGroup: .adult))
                }
            }
            for child in childProfiles {
                travelers.append(
                    Traveler(
                        id: child.id,
                        name: child.name,
                        role: .child,
                        ageGroup: child.ageGroup,
                        packingResponsibility: .guardian,
                        guardianTravelerID: primary.id,
                        needs: child.needs
                    )
                )
            }
            return TripParty(travelMode: .family, travelers: travelers)
        case .group:
            var travelers: [Traveler] = [primary]
            let extras = existing?.travelers.filter { $0.role != .self && $0.role != .child } ?? []
            for index in 1..<max(2, adultCount) {
                let extraIndex = index - 1
                if extras.indices.contains(extraIndex) {
                    let prior = extras[extraIndex]
                    travelers.append(
                        Traveler(
                            id: prior.id,
                            name: prior.name,
                            role: .otherAdult,
                            ageGroup: .adult,
                            chips: prior.chips,
                            notes: prior.notes
                        )
                    )
                } else {
                    travelers.append(Traveler(role: .otherAdult, ageGroup: .adult))
                }
            }
            return TripParty(travelMode: .group, travelers: travelers)
        }
    }

    private static func reusedSelf(from existing: TripParty?, chips: Set<ContextChip>) -> Traveler {
        if let prior = existing?.primary {
            return Traveler(
                id: prior.id,
                name: prior.name,
                role: .self,
                ageGroup: .adult,
                chips: chips,
                notes: prior.notes
            )
        }
        return .primarySelf(chips: chips)
    }

    private static func reusedPartner(
        from existing: TripParty?,
        name: String,
        chips: Set<ContextChip>,
        notes: String
    ) -> Traveler {
        if let prior = existing?.travelers.first(where: { $0.role == .partner }) {
            return Traveler(
                id: prior.id,
                name: name,
                role: .partner,
                ageGroup: .adult,
                chips: chips,
                notes: notes
            )
        }
        return Traveler(name: name, role: .partner, ageGroup: .adult, chips: chips, notes: notes)
    }
}
