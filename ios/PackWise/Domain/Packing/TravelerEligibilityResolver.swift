import Foundation

// Product Experience V2, Task 6 — the one traveler eligibility authority.
//
//     candidate × traveler → EligibilityDecision   (before quantity and sharing)
//
// Eligibility answers only whether a generated recommendation is appropriate
// for a traveler, given age, that traveler's own explicit needs, and signals
// attributed to that traveler. Age answers "can this traveler use it?", never
// "does this traveler own it?" — device ownership needs evidence (Task 7.1). It never decides how many, whether an item is
// shared, who carries it, or what covers it. It never infers attribution: a
// signal belongs to the traveler it was set on, and trip-wide context (a Work
// activity, a Business trip type) names no one. Explicit user rows — added or
// edited — are never evaluated; eligibility controls generated
// recommendations, not user intent.

/// Closed eligibility families, one per catalog item (`party.json`
/// `eligibility`). `scripts/validate_shared.py` requires every item to be
/// classified.
enum EligibilityFamily: Hashable, Sendable {
    /// Any traveler.
    case universal
    /// Adults and teens by age.
    case adultOrTeen
    /// Exactly these age groups (ordinary clothing excludes infants, whose
    /// clothing is `kids.extra_outfits`/`kids.sleep_sack`).
    case ageSpecific(Set<AgeGroup>)
    /// Only when the traveler's own explicit child need is selected. Age,
    /// a Family trip, or another traveler's preference never substitutes.
    case explicitChildNeed(ChildNeed)
    /// Phone, phone charger, and car charger only (Tasks 7.2–8.1). The primary
    /// traveler carries an implicit phone-ownership signal: PackWise is
    /// running on their phone. That proves a phone — and what charges it —
    /// and nothing else. Every other traveler, at any age, needs an explicit
    /// traveler-scoped phone signal: `bringingPhone`, set in traveler details
    /// (Task 8).
    case phoneOwnership
    /// Every other personal device (Tasks 7.1–8.1): ownership needs evidence,
    /// never age, and is never proven by owning a phone. The signal must be
    /// attributed to the traveler — their own chip or preference, or on a
    /// solo list only the trip's own context. An item with no named signal
    /// reaches no one automatically, the primary traveler included; the
    /// Task 7.2 interim carryover is gone.
    case deviceSignalRequired(ContextChip?)
    /// Medication and contacts: only from the traveler's own signal, never
    /// presumed at any age.
    case travelerSignalRequired(ContextChip)
    /// Personal travel documents (design 9.3).
    case travelerDocument(DocumentHolders)

    enum DocumentHolders: String, Hashable, Sendable {
        /// Passport, visa/entry documents, boarding pass, health card.
        case all
        /// Photo ID.
        case adultOrTeen
    }
}

struct EligibilityRules: Sendable {
    var families: [String: EligibilityFamily]
}

/// Why a traveler is or isn't eligible. Machine vocabulary for the audit
/// ledger; never customer prose.
enum EligibilityReason: String, Hashable, Sendable {
    case universal
    case ageAppropriate = "age_appropriate"
    case explicitChildNeed = "explicit_child_need"
    /// The primary traveler's implicit phone-ownership signal (see
    /// `EligibilityFamily.phoneOwnership`).
    case implicitPrimaryPhone = "implicit_primary_phone"
    /// A solo list's trip context, attributed to its only traveler.
    case soleTravelerContext = "sole_traveler_context"
    case travelerSignal = "traveler_signal"
    case travelerDocument = "traveler_document"
    case adultOrTeenOnly = "adult_or_teen_only"
    case notForAgeGroup = "not_for_age_group"
    case missingMetadata = "missing_eligibility_metadata"
}

enum EligibilitySignal: Hashable, Sendable {
    case childNeed(ChildNeed)
    case phone
    case device(ContextChip?)
    case traveler(ContextChip)

    var code: String {
        switch self {
        case .childNeed(let need): "child_need.\(need.rawValue)"
        case .phone: "device_signal.phone"
        case .device(nil): "device_signal_required"
        case .device(let chip?): "device_signal.\(chip.rawValue)"
        case .traveler(let chip): "traveler_signal.\(chip.rawValue)"
        }
    }
}

enum EligibilityDecision: Hashable, Sendable {
    case eligible(EligibilityReason)
    case requiresExplicitSignal(EligibilitySignal)
    case ineligible(EligibilityReason)

    var isEligible: Bool {
        if case .eligible = self { true } else { false }
    }
}

enum TravelerEligibilityResolver {
    /// - Parameters:
    ///   - explicitNeeds: the traveler's own selected child needs.
    ///   - signals: context chips attributed to this traveler only (the
    ///     primary's own chips and preferences, or a companion's own chips).
    ///   - isSoleTraveler: the list has one traveler, so trip-wide work
    ///     context (a Business trip, a Work activity) is unambiguously theirs
    ///     and counts as their laptop signal. Never true on a party list,
    ///     where that context names no one, and never a signal for any other
    ///     device.
    static func evaluate(
        canonicalItemID: String,
        traveler: Traveler,
        explicitNeeds: Set<ChildNeed>,
        signals: Set<ContextChip>,
        isSoleTraveler: Bool = false,
        catalog: PackingCatalog,
        rules: EligibilityRules
    ) -> EligibilityDecision {
        let age = traveler.ageGroup
        let adultOrTeen = age == .adult || age == .teen
        guard let family = rules.families[canonicalItemID] else {
            // Conservative: adult behavior never depends on metadata, and an
            // unclassified item never attaches to anyone younger.
            return age.isAdult ? .eligible(.universal) : .ineligible(.missingMetadata)
        }
        switch family {
        case .universal:
            return .eligible(.universal)
        case .adultOrTeen:
            return adultOrTeen ? .eligible(.ageAppropriate) : .ineligible(.adultOrTeenOnly)
        case .ageSpecific(let groups):
            return groups.contains(age) ? .eligible(.ageAppropriate) : .ineligible(.notForAgeGroup)
        case .explicitChildNeed(let need):
            return explicitNeeds.contains(need) ? .eligible(.explicitChildNeed) : .requiresExplicitSignal(.childNeed(need))
        case .deviceSignalRequired(let signal?):
            if signals.contains(signal) { return .eligible(.travelerSignal) }
            // D2: a solo trip's Business/Work context is its traveler's work
            // device — the laptop family only. Headphones, a power bank, or a
            // camera are never implied by a trip, solo or not (Task 8.1).
            if isSoleTraveler && signal == .bringingLaptop { return .eligible(.soleTravelerContext) }
            return .requiresExplicitSignal(.device(signal))
        case .phoneOwnership:
            if traveler.role == .self { return .eligible(.implicitPrimaryPhone) }
            return signals.contains(.bringingPhone) ? .eligible(.travelerSignal) : .requiresExplicitSignal(.phone)
        case .deviceSignalRequired(nil):
            return .requiresExplicitSignal(.device(nil))
        case .travelerSignalRequired(let signal):
            return signals.contains(signal) ? .eligible(.travelerSignal) : .requiresExplicitSignal(.traveler(signal))
        case .travelerDocument(.all):
            return .eligible(.travelerDocument)
        case .travelerDocument(.adultOrTeen):
            return adultOrTeen ? .eligible(.travelerDocument) : .ineligible(.adultOrTeenOnly)
        }
    }
}

/// One recorded eligibility outcome group for the audit ledger: every
/// candidate a traveler did not receive for the same result and reason.
struct EligibilityLedgerEntry: Hashable, Sendable {
    enum Result: String, Hashable, Sendable {
        case requiresExplicitSignal
        case ineligible
    }

    var travelerID: UUID?
    var result: Result
    /// `EligibilityReason` raw value or `EligibilitySignal.code`.
    var reason: String
    /// Canonical IDs, sorted.
    var items: [String]

    static func entries(from drops: [(travelerID: UUID?, canonicalItemID: String, decision: EligibilityDecision)]) -> [EligibilityLedgerEntry] {
        var grouped: [String: EligibilityLedgerEntry] = [:]
        for drop in drops {
            let result: Result
            let reason: String
            switch drop.decision {
            case .eligible: continue
            case .requiresExplicitSignal(let signal): (result, reason) = (.requiresExplicitSignal, signal.code)
            case .ineligible(let why): (result, reason) = (.ineligible, why.rawValue)
            }
            let key = "\(drop.travelerID?.uuidString ?? "none")|\(result.rawValue)|\(reason)"
            var entry = grouped[key] ?? EligibilityLedgerEntry(travelerID: drop.travelerID, result: result, reason: reason, items: [])
            if !entry.items.contains(drop.canonicalItemID) { entry.items.append(drop.canonicalItemID) }
            grouped[key] = entry
        }
        return grouped.values
            .map { var entry = $0; entry.items.sort(); return entry }
            .sorted {
                if ($0.travelerID?.uuidString ?? "") != ($1.travelerID?.uuidString ?? "") {
                    return ($0.travelerID?.uuidString ?? "") < ($1.travelerID?.uuidString ?? "")
                }
                if $0.result != $1.result { return $0.result.rawValue < $1.result.rawValue }
                return $0.reason < $1.reason
            }
    }
}

extension EligibilityRules: Decodable {
    private struct Row: Decodable {
        var family: String
        var ageGroups: [String]?
        var need: String?
        var signal: String?
        var travelers: String?
    }

    struct InvalidMetadata: Error, CustomStringConvertible {
        var description: String
    }

    init(from decoder: Decoder) throws {
        let rows = try [String: Row](from: decoder)
        var families: [String: EligibilityFamily] = [:]
        for (id, row) in rows {
            func fail(_ message: String) -> InvalidMetadata { InvalidMetadata(description: "\(id): \(message)") }
            switch row.family {
            case "universal":
                families[id] = .universal
            case "adultOrTeen":
                families[id] = .adultOrTeen
            case "phoneOwnership":
                families[id] = .phoneOwnership
            case "ageSpecific":
                let groups = try (row.ageGroups ?? []).map { raw -> AgeGroup in
                    guard let group = AgeGroup(rawValue: raw) else { throw fail("unknown age group \(raw)") }
                    return group
                }
                guard !groups.isEmpty else { throw fail("ageSpecific needs ageGroups") }
                families[id] = .ageSpecific(Set(groups))
            case "explicitChildNeed":
                guard let need = row.need.flatMap(ChildNeed.init(rawValue:)) else { throw fail("unknown need \(row.need ?? "nil")") }
                families[id] = .explicitChildNeed(need)
            case "deviceSignalRequired":
                if let raw = row.signal {
                    guard let chip = ContextChip(rawValue: raw) else { throw fail("unknown signal \(raw)") }
                    families[id] = .deviceSignalRequired(chip)
                } else {
                    families[id] = .deviceSignalRequired(nil)
                }
            case "travelerSignalRequired":
                guard let chip = row.signal.flatMap(ContextChip.init(rawValue:)) else { throw fail("unknown signal \(row.signal ?? "nil")") }
                families[id] = .travelerSignalRequired(chip)
            case "travelerDocument":
                guard let holders = row.travelers.flatMap(EligibilityFamily.DocumentHolders.init(rawValue:)) else {
                    throw fail("unknown document holders \(row.travelers ?? "nil")")
                }
                families[id] = .travelerDocument(holders)
            default:
                throw fail("unknown family \(row.family)")
            }
        }
        self.families = families
    }
}
