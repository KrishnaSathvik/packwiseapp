import Foundation
import Testing
@testable import PackWise

/// Product Experience V2, Task 3 — typed trip-type need contracts.
///
/// `TripType` set → `TripTypeContract` → `PackingNeedContribution`. These tests
/// pin the approved design 8.1 matrix as executable policy and prove the
/// resolver is deterministic, primary-free, and non-causal for suggestions.
/// They deliberately assert needs and provenance, never final packing items:
/// composition into the list is Task 4.
struct TripTypeCompositionTests {
    private func table() throws -> TripTypeContractTable {
        try SharedLibrary.rules().tripTypeContracts
    }

    private func resolver() throws -> TripTypeContractResolver {
        TripTypeContractResolver(contracts: try table())
    }

    // MARK: - The approved matrix (design 8.1), row by row

    private struct Row {
        var needs: [PackingNeed]
        var suggested: [String]
        var excludedNeeds: [PackingNeed]
        var excludedActivities: [String]
    }

    private static let approved: [TripType: Row] = [
        .vacation: Row(needs: [.leisureGeneralTravel], suggested: ["sightseeing", "walking", "niceDinner", "shopping"],
                       excludedNeeds: [.beachSwim, .sunExposure, .workContext, .formalPresentation, .formalEvent],
                       excludedActivities: ["swimming", "beachDays", "work", "nightlife"]),
        .cityBreak: Row(needs: [.urbanWalking, .cityDayUse],
                        suggested: ["sightseeing", "walking", "museums", "niceDinner", "shopping", "nightlife"],
                        excludedNeeds: [.workContext, .formalPresentation], excludedActivities: ["work"]),
        .beach: Row(needs: [.beachSwim, .sunExposure], suggested: ["swimming", "beachDays", "snorkeling", "boatTrip"],
                    excludedNeeds: [.leisureGeneralTravel], excludedActivities: ["nightlife"]),
        .business: Row(needs: [.workContext, .formalPresentation], suggested: ["work", "niceDinner", "walking"],
                       excludedNeeds: [.leisureGeneralTravel], excludedActivities: ["nightlife"]),
        .outdoor: Row(needs: [.outdoorDayUse], suggested: ["hiking", "wildlife", "walking", "running"],
                      excludedNeeds: [], excludedActivities: ["camping"]),
        .roadTrip: Row(needs: [.roadTravelComfort], suggested: ["sightseeing", "walking"],
                       excludedNeeds: [.outdoorDayUse], excludedActivities: ["camping"]),
        .weddingEvent: Row(needs: [.formalEvent], suggested: ["niceDinner"],
                           excludedNeeds: [.workContext, .leisureGeneralTravel], excludedActivities: ["work", "nightlife"]),
        .skiSnow: Row(needs: [.snowSport, .coldActivityExposure], suggested: [],
                      excludedNeeds: [.outdoorDayUse], excludedActivities: ["camping"]),
        .festival: Row(needs: [.festivalAttendance], suggested: [],
                       excludedNeeds: [], excludedActivities: ["nightlife", "camping"]),
        .visitingFamily: Row(needs: [.hostVisit], suggested: ["sightseeing", "walking"],
                             excludedNeeds: [.leisureGeneralTravel], excludedActivities: []),
        .other: Row(needs: [], suggested: [], excludedNeeds: [], excludedActivities: []),
    ]

    @Test func everyKnownTripTypeMatchesTheApprovedMatrixExactly() throws {
        let table = try table()
        #expect(Set(Self.approved.keys) == Set(TripType.allCases))
        for tripType in TripType.stableOrder {
            let row = try #require(Self.approved[tripType])
            let contract = table.contract(for: tripType)
            #expect(contract.needs == row.needs, "\(tripType) needs")
            #expect(contract.suggestedActivityIDs == row.suggested, "\(tripType) suggested activities")
            #expect(contract.excludedNeeds == row.excludedNeeds, "\(tripType) excluded needs")
            #expect(contract.excludedActivityIDs == row.excludedActivities, "\(tripType) excluded activities")
            #expect(!contract.nonImplications.isEmpty, "\(tripType) keeps its prose non-implications")
        }
    }

    @Test func thePackingNeedVocabularyIsClosedAndProductSized() {
        #expect(PackingNeed.allCases == [
            .leisureGeneralTravel, .urbanWalking, .cityDayUse, .beachSwim, .sunExposure, .workContext,
            .formalPresentation, .outdoorDayUse, .roadTravelComfort, .formalEvent, .snowSport,
            .coldActivityExposure, .festivalAttendance, .hostVisit,
        ])
    }

    // MARK: - Single types

    @Test func eachSingleTripTypeContributesExactlyItsNeedsWithItsOwnProvenance() throws {
        let resolver = try resolver()
        for tripType in TripType.stableOrder {
            let contributions = resolver.contributions(for: [tripType])
            #expect(contributions.map(\.need) == Self.approved[tripType]?.needs, "\(tripType)")
            for contribution in contributions {
                #expect(contribution.provenance.tripType == tripType)
                #expect(contribution.provenance.reasonCode == "trip_type.generic")
                #expect(contribution.provenance.reasonArguments == ["tripType": tripType.rawValue])
                #expect(contribution.provenance.sourceSignals == [.tripType])
                #expect(contribution.travelerID == nil, "trip-type needs are trip-wide")
            }
        }
    }

    @Test func otherContributesNoDeterministicNeedsAndNoSuggestions() throws {
        let resolver = try resolver()
        #expect(resolver.contributions(for: [.other]).isEmpty)
        #expect(resolver.normalizedNeeds(for: [.other]).isEmpty)
        #expect(resolver.suggestedActivityIDs(for: [.other]).isEmpty)
        // Adding Other to a real selection changes nothing either.
        #expect(resolver.contributions(for: [.beach, .other]) == resolver.contributions(for: [.beach]))
    }

    // MARK: - Required combinations

    private struct Expected {
        var types: Set<TripType>
        var needs: [PackingNeed]
        var provenance: Set<TripType>
    }

    private static let combinations: [Expected] = [
        Expected(types: [.vacation, .beach], needs: [.leisureGeneralTravel, .beachSwim, .sunExposure],
                 provenance: [.vacation, .beach]),
        Expected(types: [.vacation, .cityBreak], needs: [.leisureGeneralTravel, .urbanWalking, .cityDayUse],
                 provenance: [.vacation, .cityBreak]),
        Expected(types: [.vacation, .beach, .cityBreak],
                 needs: [.leisureGeneralTravel, .urbanWalking, .cityDayUse, .beachSwim, .sunExposure],
                 provenance: [.vacation, .beach, .cityBreak]),
        Expected(types: [.business, .cityBreak], needs: [.urbanWalking, .cityDayUse, .workContext, .formalPresentation],
                 provenance: [.business, .cityBreak]),
        Expected(types: [.business, .vacation], needs: [.leisureGeneralTravel, .workContext, .formalPresentation],
                 provenance: [.business, .vacation]),
        Expected(types: [.roadTrip, .outdoor], needs: [.outdoorDayUse, .roadTravelComfort],
                 provenance: [.roadTrip, .outdoor]),
        Expected(types: [.outdoor, .skiSnow], needs: [.outdoorDayUse, .snowSport, .coldActivityExposure],
                 provenance: [.outdoor, .skiSnow]),
        Expected(types: [.vacation, .weddingEvent], needs: [.leisureGeneralTravel, .formalEvent],
                 provenance: [.vacation, .weddingEvent]),
        Expected(types: [.festival, .cityBreak], needs: [.urbanWalking, .cityDayUse, .festivalAttendance],
                 provenance: [.festival, .cityBreak]),
        Expected(types: [.visitingFamily, .vacation], needs: [.leisureGeneralTravel, .hostVisit],
                 provenance: [.visitingFamily, .vacation]),
    ]

    @Test func everyRequiredCombinationUnionsNeedsAndKeepsEveryProvenanceSource() throws {
        let resolver = try resolver()
        for combination in Self.combinations {
            let label = TripType.stableOrder.filter(combination.types.contains).map(\.rawValue).joined(separator: " + ")
            let normalized = resolver.normalizedNeeds(for: combination.types)
            #expect(normalized.map(\.need) == combination.needs, "\(label) needs")
            #expect(
                Set(normalized.flatMap { $0.provenance.compactMap(\.tripType) }) == combination.provenance,
                "\(label) provenance"
            )
            // Union of each member's approved suggestions, first-seen in stable type order.
            var expectedSuggestions: [String] = []
            for tripType in TripType.stableOrder where combination.types.contains(tripType) {
                for id in Self.approved[tripType]?.suggested ?? [] where !expectedSuggestions.contains(id) {
                    expectedSuggestions.append(id)
                }
            }
            #expect(resolver.suggestedActivityIDs(for: combination.types) == expectedSuggestions, "\(label) suggestions")
        }
    }

    @Test func noCombinationLetsATypeContributeWhatItExplicitlyDoesNotImply() throws {
        let resolver = try resolver()
        let table = try table()
        let sets = Self.combinations.map(\.types) + TripType.allCases.map { Set([$0]) }
        for types in sets {
            for contribution in resolver.contributions(for: types) {
                let owner = try #require(contribution.provenance.tripType)
                #expect(!table.contract(for: owner).excludedNeeds.contains(contribution.need), "\(owner) contributed excluded \(contribution.need)")
            }
        }
        for tripType in TripType.allCases {
            let contract = table.contract(for: tripType)
            #expect(Set(contract.suggestedActivityIDs).isDisjoint(with: contract.excludedActivityIDs), "\(tripType)")
        }
    }

    @Test func resolutionIsIndependentOfInsertionOrder() throws {
        let resolver = try resolver()
        let members: [TripType] = [.beach, .cityBreak, .vacation, .festival]
        let reference = Set(members)
        let expected = (resolver.contributions(for: reference), resolver.normalizedNeeds(for: reference), resolver.suggestedActivityIDs(for: reference))
        for permutation in members.allPermutations() {
            var set = Set<TripType>(minimumCapacity: 1)
            for tripType in permutation { set.insert(tripType) }
            #expect(resolver.contributions(for: set) == expected.0)
            #expect(resolver.normalizedNeeds(for: set) == expected.1)
            #expect(resolver.suggestedActivityIDs(for: set) == expected.2)
        }
    }

    @Test func aNeedSharedByTwoTypesNormalizesOnceWithBothProvenanceFacts() throws {
        // The approved matrix has no shared need today; the resolver must still
        // merge one if a later approved row adds it.
        var table = try table()
        table.replaceContract(for: .festival) { $0.needs = [.festivalAttendance, .sunExposure] }
        let resolver = TripTypeContractResolver(contracts: table)

        let normalized = resolver.normalizedNeeds(for: [.festival, .beach])
        #expect(normalized.map(\.need) == [.beachSwim, .sunExposure, .festivalAttendance])
        let sun = try #require(normalized.first { $0.need == .sunExposure })
        #expect(sun.provenance.compactMap(\.tripType) == [.beach, .festival], "one need, both sources, stable order")
        #expect(resolver.contributions(for: [.festival, .beach]).filter { $0.need == .sunExposure }.count == 2)
    }

    // MARK: - Consumes the full set, never a primary

    @Test func theContextResolverReadsEveryTripTypeNotTheTemporarySingularAccessor() throws {
        let resolver = try resolver()
        let context = try Self.context(tripTypes: [.business, .cityBreak], activities: [])
        #expect(context.tripType == .other, "precondition: the temporary accessor fails safe for a multi-selection")
        #expect(resolver.contributions(for: context) == resolver.contributions(for: [.business, .cityBreak]))
        #expect(Set(resolver.contributions(for: context).compactMap(\.provenance.tripType)) == [.business, .cityBreak])
    }

    // MARK: - Suggestion is not selection

    @Test func suggestionsNeverWriteTheSelectedActivities() throws {
        let resolver = try resolver()
        var context = try Self.context(tripTypes: [.cityBreak], activities: [])
        _ = resolver.suggestedActivityIDs(for: context.tripTypes)
        _ = resolver.contributions(for: context)
        #expect(context.activities.isEmpty, "suggesting Walking/Museums/Nice Dinner selects nothing")

        context.activities = ["hiking"]
        context.tripTypes = [.vacation, .beach]
        #expect(context.activities == ["hiking"], "changing trip types never adds or removes a selected activity")
    }

    @Test func aSuggestedActivityIsNotCausalUntilSelected() throws {
        let engine = PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
        let unselected = engine.generate(context: try Self.context(tripTypes: [.cityBreak], activities: []))
        #expect(!unselected.contains { $0.reasonCode.hasPrefix("activity.") }, "no suggested activity drives an item")

        let selected = engine.generate(context: try Self.context(tripTypes: [.cityBreak], activities: ["walking"]))
        #expect(selected.contains { $0.reasonCode == "activity.walking" }, "an explicit selection does")
    }

    // MARK: - Task 3 → Task 4 bridge: output cannot move

    /// Until Task 4 composes needs through the engine, the engine reads each
    /// singleton type's candidates derived from its contract. That derived
    /// list must be exactly today's per-type item list.
    @Test func derivedCandidatesForEachSingleTypeEqualTodaysItemLists() throws {
        let legacy: [TripType: Set<String>] = [
            .vacation: ["electronics.headphones", "travel_comfort.book"],
            .cityBreak: ["essentials.sunglasses", "activities.daypack"],
            .beach: ["clothing.swimsuit", "clothing.coverup", "footwear.sandals", "toiletries.sunscreen",
                     "activities.beach_towel", "clothing.hat_sun", "clothing.shorts"],
            .business: ["clothing.dress_shirt", "clothing.blazer", "footwear.dress_shoes", "electronics.laptop",
                        "electronics.laptop_charger"],
            .outdoor: ["activities.daypack", "hydration.water_bottle", "toiletries.insect_repellent",
                       "health.blister_pads", "health.first_aid"],
            .roadTrip: ["miscellaneous.car_charger", "miscellaneous.car_snacks", "essentials.snacks"],
            .weddingEvent: ["clothing.formal_outfit", "footwear.dress_shoes", "miscellaneous.wedding_card"],
            .skiSnow: ["clothing.winter_coat", "clothing.gloves", "clothing.beanie", "clothing.thermal_top",
                       "footwear.boots", "activities.ski_goggles", "activities.ski_gloves"],
            .festival: ["activities.festival_earplugs", "electronics.power_bank", "toiletries.sunscreen",
                        "essentials.hand_sanitizer"],
            .visitingFamily: ["miscellaneous.gift"],
            .other: [],
        ]
        let rules = try SharedLibrary.rules()
        for tripType in TripType.allCases {
            let derived = try #require(rules.tripTypes[tripType.rawValue], "\(tripType)").add
            #expect(Set(derived) == legacy[tripType], "\(tripType)")
            #expect(derived.count == Set(derived).count, "\(tripType) derived list has no duplicates")
        }
    }

    // MARK: - Strict decoding

    private static func decode(_ mutate: (inout [String: Any]) -> Void) throws -> TripTypeContractTable {
        let url = try #require(Bundle.main.url(forResource: "trip-types", withExtension: "json"))
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        mutate(&json)
        let data = try JSONSerialization.data(withJSONObject: json)
        let activities = Set(try SharedLibrary.rules().activities.keys)
        return try TripTypeContractTable(data: data, activityIDs: activities)
    }

    private static func editRow(_ json: inout [String: Any], _ id: String, _ edit: (inout [String: Any]) -> Void) {
        var rows = json["tripTypes"] as! [[String: Any]]
        let index = rows.firstIndex { $0["id"] as? String == id }!
        edit(&rows[index])
        json["tripTypes"] = rows
    }

    @Test func theDecoderRejectsEveryInvalidContractShape() throws {
        _ = try Self.decode { _ in }

        #expect(throws: TripTypeContractError.unknownNeed(tripType: "vacation", raw: "spaFacials")) {
            _ = try Self.decode { Self.editRow(&$0, "vacation") { $0["needs"] = ["spaFacials"] } }
        }
        #expect(throws: TripTypeContractError.canonicalItemIDInNeeds(tripType: "vacation", raw: "electronics.headphones")) {
            _ = try Self.decode { Self.editRow(&$0, "vacation") { $0["needs"] = ["electronics.headphones"] } }
        }
        #expect(throws: TripTypeContractError.duplicateNeed(tripType: "beach", need: .beachSwim)) {
            _ = try Self.decode { Self.editRow(&$0, "beach") { $0["needs"] = ["beachSwim", "beachSwim"] } }
        }
        #expect(throws: TripTypeContractError.unknownSuggestedActivity(tripType: "beach", raw: "cosplay")) {
            _ = try Self.decode { Self.editRow(&$0, "beach") { $0["suggestedActivities"] = ["cosplay"] } }
        }
        #expect(throws: TripTypeContractError.otherHasDeterministicContent) {
            _ = try Self.decode { Self.editRow(&$0, "other") { $0["needs"] = ["hostVisit"] } }
        }
        #expect(throws: TripTypeContractError.duplicateTripType("beach")) {
            _ = try Self.decode { json in
                var rows = json["tripTypes"] as! [[String: Any]]
                rows.append(rows.first { $0["id"] as? String == "beach" }!)
                json["tripTypes"] = rows
            }
        }
        #expect(throws: TripTypeContractError.tripTypesDoNotMatchStableOrder) {
            _ = try Self.decode { json in
                json["tripTypes"] = (json["tripTypes"] as! [[String: Any]]).filter { $0["id"] as? String != "festival" }
            }
        }
        #expect(throws: TripTypeContractError.retiredKey(tripType: "vacation", key: "add")) {
            _ = try Self.decode { Self.editRow(&$0, "vacation") { $0["add"] = ["electronics.headphones"] } }
        }
    }

    // MARK: - Helpers

    private static func context(tripTypes: Set<TripType>, activities: [String]) throws -> TripContext {
        let destination = try #require(try SharedLibrary.testDestinations().first { $0.city == "Chicago" })
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5))!
        let end = Calendar.current.date(byAdding: .day, value: 3, to: start)!
        var preferences = TravelerPreferences.deviceDefaults()
        preferences.homeCountryCode = "US"
        preferences.homeCountrySource = .userConfirmed
        return TripContext(
            destination: destination,
            startDate: start,
            endDate: end,
            durationDays: 4,
            durationNights: 3,
            tripTypes: tripTypes,
            activities: activities,
            datedActivities: [],
            bagTypes: [.carryOn],
            packingStyle: .balanced,
            transportation: .unknown,
            laundryAccess: .none,
            travelerCount: 1,
            userNotes: "",
            contextChips: [],
            weather: nil,
            preferences: preferences
        )
    }
}

private extension Array {
    func allPermutations() -> [[Element]] {
        guard count > 1 else { return [self] }
        return indices.flatMap { index -> [[Element]] in
            var rest = self
            let element = rest.remove(at: index)
            return rest.allPermutations().map { [element] + $0 }
        }
    }
}
