import Foundation
import Testing
@testable import PackWise

/// Product Experience V2, Task 5 — every selected bag contributes to one
/// normalized luggage capacity; the engine never builds a plan per bag.
struct MultiBagEngineTests {
    private static let engine: PackingEngine = {
        PackingEngine(catalog: try! SharedLibrary.catalog(), rules: try! SharedLibrary.rules())
    }()

    /// A 14-day Miami beach trip with running and swimming: optional beach
    /// items a constrained bag can trim, and every representative clothing
    /// need (tops, underwear, socks, pants, sleepwear, workout, swimwear).
    private static func context(
        bags: Set<BagType>,
        style: PackingStyle = .balanced,
        tripTypes: Set<TripType> = [.beach],
        days: Int = 14,
        party: TripParty = .solo()
    ) throws -> TripContext {
        let destination = try #require(try SharedLibrary.testDestinations().first { $0.city == "Miami" })
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 6))!
        let end = Calendar.current.date(byAdding: .day, value: days - 1, to: start)!
        var preferences = TravelerPreferences.deviceDefaults()
        preferences.homeCountryCode = "US"
        preferences.homeCountrySource = .userConfirmed
        let math = TripDateMath.daysAndNights(from: start, to: end)
        return TripContext(
            destination: destination, startDate: start, endDate: end,
            durationDays: math.days, durationNights: math.nights,
            tripTypes: tripTypes, activities: ["running", "swimming", "beachDays"], datedActivities: [], bagTypes: bags,
            packingStyle: style, transportation: .unknown, laundryAccess: .none, travelerCount: party.travelers.count,
            userNotes: "", contextChips: [], weather: nil, preferences: preferences, party: party
        )
    }

    private static let bottle = "travel_comfort.empty_security_bottle"

    /// Item identity and quantity without per-context traveler UUIDs.
    private static func quantities(_ generation: EngineGeneration) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: generation.items.map { ("\($0.ownershipType.rawValue):\($0.canonicalItemID ?? $0.displayName)", $0.quantity) })
    }

    private static func trims(_ generation: EngineGeneration) -> [String] {
        generation.constraintDecisions.flatMap { decision in decision.items.map { "\(decision.constraint):\($0)" } }.sorted()
    }

    private static func generate(_ bags: Set<BagType>, style: PackingStyle = .balanced) throws -> EngineGeneration {
        engine.generateDetailed(context: try context(bags: bags, style: style))
    }

    // MARK: - Required scenarios

    @Test func emptyBagsApplyNoTrimAndAssumeNoBag() throws {
        for style in PackingStyle.allCases {
            let empty = try Self.generate([], style: style)
            #expect(empty.constraintDecisions.isEmpty, "\(style): no luggage trimming")
            #expect(empty.items.allSatisfy { $0.bagStyleConstraintFact == nil }, "\(style): no constraint evidence at all")
            #expect(!empty.items.contains { $0.canonicalItemID == Self.bottle }, "\(style): no assumed carry-on")
            #expect(Self.quantities(empty) == Self.quantities(try Self.generate([.checked], style: style)),
                    "\(style): not sure yet sizes like unconstrained capacity, never like a carry-on")
            #expect(Self.quantities(empty) != Self.quantities(try Self.generate([.carryOn], style: style)), "\(style): no assumed carry-on caps")
        }
    }

    @Test func personalItemOnlyIsTheStrongestRestriction() throws {
        let personal = try Self.generate([.personalItem])
        #expect(!personal.constraintDecisions.isEmpty, "optional bulky items trim under very constrained capacity")
        #expect(personal.constraintDecisions.allSatisfy { $0.constraint == "bag.personal_item" })
        let tight = Self.quantities(personal)
        for other: Set<BagType> in [[.carryOn], [.backpack], [.carryOn, .backpack], [.checked], []] {
            let roomier = Self.quantities(try Self.generate(other))
            for (key, value) in tight {
                #expect(value <= (roomier[key] ?? value), "\(key): personal item \(value) > \(other) \(roomier[key] ?? -1)")
            }
        }
    }

    @Test func carryOnOnlyPreservesCarryOnSemantics() throws {
        #expect(Self.trims(try Self.generate([.carryOn], style: .light)).allSatisfy { $0.hasPrefix("bag.space_constrained:") })
        #expect(!(try Self.generate([.carryOn], style: .light)).constraintDecisions.isEmpty, "Light trims optionals")
        #expect(try Self.generate([.carryOn], style: .balanced).constraintDecisions.isEmpty, "Balanced keeps optionals")
        let tshirts = try #require(try Self.generate([.carryOn]).items.first { $0.canonicalItemID == "clothing.tshirt" })
        #expect(tshirts.quantityEvidence?.bagCapApplied == true, "carry-on clothing cap binds on a long trip")
        #expect(try Self.generate([.carryOn]).items.contains { $0.canonicalItemID == Self.bottle })
    }

    /// Approved Task 5 semantics: the bottle follows the cabin-accessible-bag
    /// signal, not capacity, so a checked bag never removes it.
    @Test func securityBottleFollowsTheCabinBagSignalNotCapacity() throws {
        for (bags, expected) in [([BagType.carryOn], true), ([.carryOn, .checked], true), ([.personalItem, .checked], true), ([.checked], false)] {
            let items = try Self.generate(Set(bags)).items
            #expect(items.contains { $0.canonicalItemID == Self.bottle } == expected, "\(bags)")
        }
    }

    @Test func carryOnPlusCheckedNeverBehavesLikeCarryOnOnly() throws {
        for style in PackingStyle.allCases {
            let both = try Self.generate([.carryOn, .checked], style: style)
            let checked = try Self.generate([.checked], style: style)
            #expect(both.constraintDecisions.isEmpty, "\(style): no trim because a carry-on is also present")
            #expect(both.items.allSatisfy { $0.bagStyleConstraintFact == nil }, "\(style): no carry-on constraint evidence")
            #expect(both.items.allSatisfy { $0.quantityEvidence?.bagCap == nil }, "\(style): no carry-on clothing caps")
            var expected = Self.quantities(checked)
            expected["personal:\(Self.bottle)"] = 1
            #expect(Self.quantities(both) == expected, "\(style): checked capacity, plus the cabin-bag security bottle")
        }
    }

    @Test func backpackPlusCheckedIsCheckedCapacity() throws {
        for style in PackingStyle.allCases {
            let both = try Self.generate([.backpack, .checked], style: style)
            #expect(both.constraintDecisions.isEmpty)
            #expect(Self.quantities(both) == Self.quantities(try Self.generate([.checked], style: style)),
                    "\(style): the backpack never reduces overall capacity")
        }
    }

    @Test func personalItemCarryOnAndCheckedIsCheckedCapacity() throws {
        for style in PackingStyle.allCases {
            let all = try Self.generate([.personalItem, .carryOn, .checked], style: style)
            #expect(all.constraintDecisions.isEmpty, "\(style)")
            #expect(Self.quantities(all) == Self.quantities(try Self.generate([.carryOn, .checked], style: style)), "\(style)")
        }
    }

    @Test func personalItemPlusCarryOnIsCarryOnCapacity() throws {
        for style in PackingStyle.allCases {
            let both = try Self.generate([.personalItem, .carryOn], style: style)
            #expect(Self.quantities(both) == Self.quantities(try Self.generate([.carryOn], style: style)), "\(style)")
            #expect(Self.trims(both) == Self.trims(try Self.generate([.carryOn], style: style)), "\(style): never personal-item trimming")
        }
    }

    /// Moderate has no looser approved policy of its own, so it keeps the
    /// existing constrained-bag levers: Light trims, clothing caps bind.
    @Test func backpackPlusCarryOnIsModerateCapacity() throws {
        #expect(try Self.context(bags: [.carryOn, .backpack]).luggage.capacity == .moderate)
        for style in PackingStyle.allCases {
            let both = try Self.generate([.carryOn, .backpack], style: style)
            #expect(Self.quantities(both) == Self.quantities(try Self.generate([.carryOn], style: style)), "\(style)")
            #expect(Self.trims(both) == Self.trims(try Self.generate([.carryOn], style: style)), "\(style)")
        }
    }

    // MARK: - Capacity vs packing style

    @Test func checkedPlusLightStillPacksLightThroughStyleOnly() throws {
        let light = try Self.generate([.checked], style: .light)
        let balanced = try Self.generate([.checked], style: .balanced)
        #expect(light.constraintDecisions.isEmpty, "plenty of capacity: no capacity trimming")
        let lightTops = try #require(Self.quantities(light)["personal:clothing.tshirt"])
        let balancedTops = try #require(Self.quantities(balanced)["personal:clothing.tshirt"])
        #expect(lightTops < balancedTops, "Light still reduces through its existing style policy")
        #expect(light.items.allSatisfy { $0.quantityEvidence?.bagCap == nil })
    }

    @Test func personalItemPlusPreparedResolvesInCapacitysFavor() throws {
        let prepared = try Self.generate([.personalItem], style: .prepared)
        #expect(!prepared.constraintDecisions.isEmpty)
        #expect(prepared.constraintDecisions.allSatisfy { $0.constraint == "style.prepared_vs_personal_item" })
        let keptIDs = Set(prepared.items.compactMap(\.canonicalItemID))
        #expect(keptIDs.isDisjoint(with: prepared.constraintDecisions.flatMap(\.items)), "trimmed optionals stay out despite Prepared")
    }

    // MARK: - Determinism

    @Test func bagInsertionOrderNeverChangesOutputTraceOrSignature() throws {
        let memberSets: [[BagType]] = [
            [.carryOn, .checked],
            [.personalItem, .carryOn, .backpack],
            [.personalItem, .carryOn, .checked, .backpack]
        ]
        for members in memberSets {
            var reference: String?
            var referenceSignature: String?
            let permutations = [members, members.reversed(), Array(members.dropFirst()) + [members[0]]]
            for permutation in permutations {
                var bags = Set<BagType>(minimumCapacity: 16)
                for bag in permutation { bags.insert(bag) }
                let context = try Self.context(bags: bags, style: .light)
                let generation = Self.engine.generateDetailed(context: context)
                let rendered = (generation.items.map {
                    "\($0.ownershipType.rawValue):\($0.canonicalItemID ?? "")|\($0.quantity)|\($0.reason)|\($0.provenance)|\(String(describing: $0.bagStyleConstraintFact))|\(String(describing: $0.quantityEvidence))"
                } + generation.constraintDecisions.map { "\($0.constraint)|\($0.summary)|\($0.items)" }).joined(separator: "\n")
                let signature = WeatherChangeProposalLifecycle.tripContextSignature(context)
                if reference == nil { reference = rendered; referenceSignature = signature }
                #expect(rendered == reference, "\(permutation)")
                #expect(signature == referenceSignature, "\(permutation)")
            }
        }
    }

    @Test func signatureNamesBagsInStableOrderAndDistinguishesSets() throws {
        let a = WeatherChangeProposalLifecycle.tripContextSignature(try Self.context(bags: [.checked, .carryOn]))
        let b = WeatherChangeProposalLifecycle.tripContextSignature(try Self.context(bags: [.carryOn]))
        #expect(a.contains("|carryOn+checked|"), "stable BagType order, whatever the insertion order")
        #expect(a != b, "adding a checked bag is a context change")
    }

    // MARK: - Road Trip guard

    @Test func roadTripNeverChangesLuggageAndCheckedNeverImpliesRoadTrip() throws {
        let rules = try SharedLibrary.rules()
        let roadCandidates = Set(rules.tripTypeContracts.candidateItemIDs(for: [.roadTravelComfort]))
        for bags: Set<BagType> in [[], [.personalItem], [.carryOn], [.checked], [.carryOn, .backpack], [.carryOn, .checked]] {
            let withRoad = TripContextCompiler.compile(try Self.context(bags: bags, tripTypes: [.beach, .roadTrip]), rules: rules)
            let without = TripContextCompiler.compile(try Self.context(bags: bags), rules: rules)
            #expect(withRoad.luggage == without.luggage, "\(bags): Road Trip contributes road-travel needs only")
            #expect(withRoad.luggage == .resolve(bags), "\(bags): no assumed checked bag, backpack, or carry-on")
        }
        let checked = Self.engine.generateDetailed(context: try Self.context(bags: [.checked]))
        #expect(!checked.items.contains { $0.provenance.contains(.tripType(.roadTrip)) })
        #expect(TripContextCompiler.compile(try Self.context(bags: [.checked]), rules: rules).packingNeeds.allSatisfy { $0.need != .roadTravelComfort })
        #expect(!checked.items.contains { item in
            item.canonicalItemID.map(roadCandidates.contains) == true && item.provenance.contains { $0.tripType != nil }
        }, "a checked bag never manufactures Road Trip needs")
    }

    // MARK: - Explicit user authority across bag edits

    @Test func notNeededSurvivesAddingOrRemovingACheckedBag() throws {
        let overrides = [RecommendationOverrideDraft(canonicalItemID: "clothing.coverup", action: "removed")]
        let carryOn = Self.engine.generate(context: try Self.context(bags: [.carryOn]), overrides: overrides)
        let added = Self.engine.generate(context: try Self.context(bags: [.carryOn, .checked]), existing: carryOn, overrides: overrides)
        let removed = Self.engine.generate(context: try Self.context(bags: [.carryOn]), existing: added, overrides: overrides)
        for list in [carryOn, added, removed] {
            #expect(!list.contains { $0.canonicalItemID == "clothing.coverup" }, "Not Needed stays Not Needed")
        }
    }

    @Test func manualQuantityCustomPackedAndCarrierSurviveBagEdits() throws {
        let partner = Traveler(name: "Sam", role: .partner, ageGroup: .adult)
        let party = TripParty(travelMode: .couple, travelers: [Traveler.primarySelf(), partner])
        var existing = Self.engine.generate(context: try Self.context(bags: [.carryOn], party: party))

        let shirt = try #require(existing.firstIndex { $0.canonicalItemID == "clothing.tshirt" && $0.travelerID == party.primary.id })
        existing[shirt].quantity = 3
        existing[shirt].isUserModified = true
        let wallet = try #require(existing.firstIndex { $0.canonicalItemID == "essentials.wallet" && $0.travelerID == party.primary.id })
        existing[wallet].packedQuantity = existing[wallet].quantity
        let shared = try #require(existing.firstIndex { $0.ownershipType == .shared })
        existing[shared].assignedTravelerID = partner.id
        let sharedID = existing[shared].id
        let custom = PackingItemDraft(canonicalItemID: nil, displayName: "Travel journal", category: .travelComfort,
                                      quantity: 1, importance: .optional, sourceSignals: [.userPreference], reason: "Added by you",
                                      isUserAdded: true, ownershipType: .personal, travelerID: partner.id)
        existing.append(custom)

        for bags: Set<BagType> in [[.carryOn, .checked], [.personalItem], []] {
            let context = try Self.context(bags: bags, party: party)
            let regenerated = Self.engine.generate(context: context, existing: existing)
            let row = try #require(regenerated.first { $0.canonicalItemID == "clothing.tshirt" && $0.travelerID == party.primary.id })
            #expect(row.quantity == 3 && row.isUserModified, "\(bags): manual quantity survives")
            #expect(regenerated.contains { $0.id == custom.id && $0.travelerID == partner.id }, "\(bags): custom item and its owner survive")
            #expect(regenerated.first { $0.canonicalItemID == "essentials.wallet" && $0.travelerID == party.primary.id }?.isPacked == true,
                    "\(bags): packed state survives")
            #expect(regenerated.first { $0.id == sharedID }?.assignedTravelerID == partner.id, "\(bags): explicit carrier unchanged")

            let diff = Self.engine.recommendationDiff(context: context, existing: existing, overrides: [])
            #expect(!diff.removeCandidates.contains { $0.id == custom.id || $0.isUserModified }, "\(bags): authority never offered for removal")
            #expect(diff.add.count + diff.removeCandidates.count + diff.quantityChanges.count < existing.count,
                    "\(bags): a bag edit is a diff, not a wholesale replacement")
        }
    }
}
