import Foundation

// Product Experience V2, Task 3 — typed trip-type need contracts.
//
//     Set<TripType> → TripTypeContract → PackingNeedContribution
//
// A trip type contributes closed, typed needs with provenance; it never owns
// an item checklist. `shared/rules/trip-types.json` is the approved design 8.1
// matrix as data, decoded strictly here and validated against the same
// vocabularies by scripts/validate_shared.py. This layer produces facts only:
// Task 4 composes them into the existing candidate/coverage/quantity/constraint
// pipeline. Nothing here reads the temporary singular `TripContext.tripType`,
// and nothing here reads or writes a trip's selected activities.

/// The closed trip-type need vocabulary, in stable order (design 8.1). Swift is
/// the authority; `trip-types.json`'s `needs` must match it exactly.
enum PackingNeed: String, Codable, CaseIterable, Hashable, Sendable {
    case leisureGeneralTravel
    case urbanWalking
    case cityDayUse
    case beachSwim
    case sunExposure
    case workContext
    case formalPresentation
    case outdoorDayUse
    case roadTravelComfort
    case formalEvent
    case snowSport
    case coldActivityExposure
    case festivalAttendance
    case hostVisit
}

/// One need's bounded meaning and its central canonical candidates. Candidate
/// identity stays the existing recommendation key, so several needs may name
/// the same canonical ID without producing duplicate rows.
struct PackingNeedDefinition: Equatable, Sendable {
    var need: PackingNeed
    var meaning: String
    var candidateItemIDs: [String]
}

/// One trip type's approved contract.
struct TripTypeContract: Equatable, Sendable {
    var tripType: TripType
    var needs: [PackingNeed]
    /// Unselected and non-causal: may order setup suggestions, never enters a
    /// trip's activities.
    var suggestedActivityIDs: [String]
    /// The machine-checkable part of `nonImplications`.
    var excludedNeeds: [PackingNeed]
    var excludedActivityIDs: [String]
    /// The approved prose, verbatim.
    var nonImplications: String
}

/// One typed need contributed by one source.
struct PackingNeedContribution: Hashable, Sendable {
    let need: PackingNeed
    let provenance: RecommendationProvenance
    /// `nil` for trip-wide needs; trip types are always trip-wide.
    let travelerID: UUID?
}

/// A need after identical contributions are merged: one need, every distinct
/// provenance fact behind it, in stable source order.
struct NormalizedPackingNeed: Hashable, Sendable {
    let need: PackingNeed
    let provenance: [RecommendationProvenance]
}

enum TripTypeContractError: Error, Equatable {
    case retiredKey(tripType: String, key: String)
    case unknownTripType(String)
    case duplicateTripType(String)
    case tripTypesDoNotMatchStableOrder
    case needsDoNotMatchVocabulary
    case unknownNeed(tripType: String, raw: String)
    case canonicalItemIDInNeeds(tripType: String, raw: String)
    case duplicateNeed(tripType: String, need: PackingNeed)
    case unknownSuggestedActivity(tripType: String, raw: String)
    case duplicateSuggestedActivity(tripType: String, raw: String)
    case unknownExcludedActivity(tripType: String, raw: String)
    case contradictoryExclusion(tripType: String, value: String)
    case otherHasDeterministicContent
}

/// The decoded, validated contract table.
struct TripTypeContractTable: Sendable {
    private(set) var contracts: [TripType: TripTypeContract]
    let needDefinitions: [PackingNeed: PackingNeedDefinition]

    func contract(for tripType: TripType) -> TripTypeContract {
        // Validation guarantees every known type is present.
        contracts[tripType] ?? TripTypeContract(
            tripType: tripType, needs: [], suggestedActivityIDs: [],
            excludedNeeds: [], excludedActivityIDs: [], nonImplications: ""
        )
    }

    /// Canonical candidates for a set of needs: need order, then candidate
    /// order, each ID once.
    func candidateItemIDs(for needs: [PackingNeed]) -> [String] {
        var seen: Set<String> = []
        return needs
            .flatMap { needDefinitions[$0]?.candidateItemIDs ?? [] }
            .filter { seen.insert($0).inserted }
    }

    #if DEBUG
    /// Test seam: edit one contract to exercise resolver behavior the approved
    /// matrix does not yet contain (for example, a need shared by two types).
    mutating func replaceContract(for tripType: TripType, _ edit: (inout TripTypeContract) -> Void) {
        var contract = contract(for: tripType)
        edit(&contract)
        contracts[tripType] = contract
    }
    #endif
}

extension TripTypeContractTable {
    private struct File: Decodable {
        struct Need: Decodable {
            var id: String
            var meaning: String
            var candidates: [String]
        }
        var needs: [Need]
        var tripTypes: [[String: RawValue]]
    }

    /// Loosely typed row values so retired keys and bad shapes can be named.
    private enum RawValue: Decodable {
        case string(String)
        case strings([String])

        init(from decoder: Decoder) throws {
            if let value = try? String(from: decoder) {
                self = .string(value)
            } else {
                self = .strings(try [String](from: decoder))
            }
        }

        var strings: [String] {
            if case .strings(let values) = self { return values }
            return []
        }

        var string: String {
            if case .string(let value) = self { return value }
            return ""
        }
    }

    /// Strictly decodes `trip-types.json`. `activityIDs` is the known activity
    /// vocabulary (`activity-rules.json` keys).
    init(data: Data, activityIDs: Set<String>) throws {
        let file = try JSONDecoder().decode(File.self, from: data)

        guard file.needs.map(\.id) == PackingNeed.allCases.map(\.rawValue) else {
            throw TripTypeContractError.needsDoNotMatchVocabulary
        }
        var definitions: [PackingNeed: PackingNeedDefinition] = [:]
        for row in file.needs {
            let need = PackingNeed(rawValue: row.id)!
            definitions[need] = PackingNeedDefinition(need: need, meaning: row.meaning, candidateItemIDs: row.candidates)
        }

        var contracts: [TripType: TripTypeContract] = [:]
        var order: [TripType] = []
        for row in file.tripTypes {
            let raw = row["id"]?.string ?? ""
            for key in ["add", "prefer_activities"] where row[key] != nil {
                throw TripTypeContractError.retiredKey(tripType: raw, key: key)
            }
            guard let tripType = TripType(rawValue: raw) else { throw TripTypeContractError.unknownTripType(raw) }
            guard contracts[tripType] == nil else { throw TripTypeContractError.duplicateTripType(raw) }

            func needs(_ key: String) throws -> [PackingNeed] {
                var result: [PackingNeed] = []
                for value in row[key]?.strings ?? [] {
                    guard let need = PackingNeed(rawValue: value) else {
                        throw value.contains(".")
                            ? TripTypeContractError.canonicalItemIDInNeeds(tripType: raw, raw: value)
                            : TripTypeContractError.unknownNeed(tripType: raw, raw: value)
                    }
                    guard !result.contains(need) else { throw TripTypeContractError.duplicateNeed(tripType: raw, need: need) }
                    result.append(need)
                }
                return result
            }
            let suggested = row["suggestedActivities"]?.strings ?? []
            for (index, activity) in suggested.enumerated() {
                guard activityIDs.contains(activity) else {
                    throw TripTypeContractError.unknownSuggestedActivity(tripType: raw, raw: activity)
                }
                guard !suggested[..<index].contains(activity) else {
                    throw TripTypeContractError.duplicateSuggestedActivity(tripType: raw, raw: activity)
                }
            }
            let excludedActivities = row["excludedActivities"]?.strings ?? []
            for activity in excludedActivities where !activityIDs.contains(activity) {
                throw TripTypeContractError.unknownExcludedActivity(tripType: raw, raw: activity)
            }

            let contract = TripTypeContract(
                tripType: tripType,
                needs: try needs("needs"),
                suggestedActivityIDs: suggested,
                excludedNeeds: try needs("excludedNeeds"),
                excludedActivityIDs: excludedActivities,
                nonImplications: row["nonImplications"]?.string ?? ""
            )
            if let overlap = contract.needs.first(where: contract.excludedNeeds.contains) {
                throw TripTypeContractError.contradictoryExclusion(tripType: raw, value: overlap.rawValue)
            }
            if let overlap = contract.suggestedActivityIDs.first(where: contract.excludedActivityIDs.contains) {
                throw TripTypeContractError.contradictoryExclusion(tripType: raw, value: overlap)
            }
            if tripType == .other, !contract.needs.isEmpty || !contract.suggestedActivityIDs.isEmpty {
                throw TripTypeContractError.otherHasDeterministicContent
            }
            contracts[tripType] = contract
            order.append(tripType)
        }
        guard order == TripType.stableOrder else { throw TripTypeContractError.tripTypesDoNotMatchStableOrder }

        self.contracts = contracts
        self.needDefinitions = definitions
    }
}

/// Resolves a trip-type selection into typed needs. Deterministic and
/// insertion-order independent: every output follows `TripType.stableOrder`
/// and `PackingNeed` order, never `Set` iteration order.
struct TripTypeContractResolver: Sendable {
    let contracts: TripTypeContractTable

    init(contracts: TripTypeContractTable) {
        self.contracts = contracts
    }

    /// One contribution per (selected type, need), in stable type order then
    /// contract need order. No type is primary; `other` contributes nothing.
    func contributions(for tripTypes: Set<TripType>) -> [PackingNeedContribution] {
        TripType.stableOrder.filter(tripTypes.contains).flatMap { tripType in
            contracts.contract(for: tripType).needs.map { need in
                PackingNeedContribution(need: need, provenance: .tripType(tripType), travelerID: nil)
            }
        }
    }

    /// Reads the full selection, never the temporary singular accessor.
    func contributions(for context: TripContext) -> [PackingNeedContribution] {
        contributions(for: context.tripTypes)
    }

    /// Identical needs merged into one, keeping every distinct provenance fact.
    func normalizedNeeds(for tripTypes: Set<TripType>) -> [NormalizedPackingNeed] {
        let all = contributions(for: tripTypes)
        return PackingNeed.allCases.compactMap { need in
            var provenance: [RecommendationProvenance] = []
            for contribution in all where contribution.need == need && !provenance.contains(contribution.provenance) {
                provenance.append(contribution.provenance)
            }
            return provenance.isEmpty ? nil : NormalizedPackingNeed(need: need, provenance: provenance)
        }
    }

    /// The stable union of the selected types' suggestions: display/order data
    /// only. It is never a selection and never causal.
    func suggestedActivityIDs(for tripTypes: Set<TripType>) -> [String] {
        var seen: Set<String> = []
        return TripType.stableOrder
            .filter(tripTypes.contains)
            .flatMap { contracts.contract(for: $0).suggestedActivityIDs }
            .filter { seen.insert($0).inserted }
    }
}

extension RecommendationProvenance {
    /// The structured fact that a trip type contributed a need.
    static func tripType(_ tripType: TripType) -> RecommendationProvenance {
        RecommendationProvenance(
            reasonCode: "trip_type.generic",
            reasonArguments: ["tripType": tripType.rawValue],
            sourceSignals: [.tripType],
            tripType: tripType
        )
    }
}

extension TripType {
    /// The trip-type phrase for a reason template argument: every contributing
    /// type in stable order, never one promoted to primary. "beach",
    /// "vacation and beach", "vacation, city break, and beach".
    static func reasonPhrase(_ tripTypes: Set<TripType>) -> String {
        let titles = TripType.stableOrder.filter(tripTypes.contains).map { $0.title.lowercased() }
        switch titles.count {
        case 0: return ""
        case 1: return titles[0]
        case 2: return "\(titles[0]) and \(titles[1])"
        default: return titles.dropLast().joined(separator: ", ") + ", and " + titles.last!
        }
    }
}
