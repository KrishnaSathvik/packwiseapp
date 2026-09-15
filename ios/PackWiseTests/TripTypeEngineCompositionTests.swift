import Foundation
import SwiftData
import Testing
@testable import PackWise

/// Product Experience V2, Task 4 — every selected trip type composes through
/// the one engine pipeline: needs once, candidates once, coverage once,
/// quantities once, constraints once, one list, no primary type.
struct TripTypeEngineCompositionTests {
    private static let engine: PackingEngine = {
        PackingEngine(catalog: try! SharedLibrary.catalog(), rules: try! SharedLibrary.rules())
    }()
    private static let contracts: TripTypeContractTable = { try! SharedLibrary.rules().tripTypeContracts }()

    private static func context(
        city: String = "Chicago",
        tripTypes: Set<TripType>,
        activities: [String] = [],
        bags: Set<BagType> = [.checked],
        style: PackingStyle = .balanced,
        weatherFixture: String? = nil,
        start: DateComponents = DateComponents(year: 2026, month: 10, day: 5),
        days: Int = 5
    ) throws -> TripContext {
        let destination = try #require(try SharedLibrary.testDestinations().first { $0.city == city })
        let startDate = Calendar.current.date(from: start)!
        let endDate = Calendar.current.date(byAdding: .day, value: days - 1, to: startDate)!
        var weather: TripWeatherContext?
        if let weatherFixture {
            let fixture = try #require(try SharedLibrary.weatherFixtures()[weatherFixture])
            weather = MockWeatherService.context(from: fixture, start: startDate, end: endDate, fixtureID: fixture.id)
        }
        var preferences = TravelerPreferences.deviceDefaults()
        preferences.homeCountryCode = "US"
        preferences.homeCountrySource = .userConfirmed
        let math = TripDateMath.daysAndNights(from: startDate, to: endDate)
        return TripContext(
            destination: destination, startDate: startDate, endDate: endDate,
            durationDays: math.days, durationNights: math.nights,
            tripTypes: tripTypes, activities: activities, datedActivities: [], bagTypes: bags,
            packingStyle: style, transportation: .unknown, laundryAccess: .none, travelerCount: 1,
            userNotes: "", contextChips: [], weather: weather, preferences: preferences
        )
    }

    private static func quantity(_ items: [PackingItemDraft], _ id: String) -> Int? {
        items.first { $0.canonicalItemID == id }?.quantity
    }

    /// The design 8.1 combinations (Business + Vacation included).
    private static let combinations: [Set<TripType>] = [
        [.vacation, .beach],
        [.vacation, .cityBreak],
        [.vacation, .beach, .cityBreak],
        [.business, .cityBreak],
        [.business, .vacation],
        [.roadTrip, .outdoor],
        [.outdoor, .skiSnow],
        [.vacation, .weddingEvent],
        [.festival, .cityBreak],
        [.visitingFamily, .vacation],
    ]

    // MARK: - Every selected type contributes, once

    @Test func everyCombinationComposesAllSelectedTypesWithoutDuplicatesOrAPrimary() throws {
        for types in Self.combinations {
            let label = TripType.stableOrder.filter(types.contains).map(\.rawValue).joined(separator: "+")
            let context = try Self.context(tripTypes: types)
            let generation = Self.engine.generateDetailed(context: context)
            let items = generation.items

            let keys = items.map(\.recommendationKey)
            #expect(keys.count == Set(keys).count, "\(label): duplicate recommendation keys")

            let suppressed = Set(generation.coverageSuppressions.map(\.canonicalItemID))
            let trimmed = Set(generation.constraintDecisions.flatMap(\.items))
            for tripType in TripType.stableOrder where types.contains(tripType) {
                let contract = Self.contracts.contract(for: tripType)
                for id in Self.contracts.candidateItemIDs(for: contract.needs) {
                    guard let item = items.first(where: { $0.canonicalItemID == id }) else {
                        #expect(suppressed.contains(id) || trimmed.contains(id),
                                "\(label): \(tripType) candidate \(id) vanished without a coverage or constraint decision")
                        continue
                    }
                    #expect(item.provenance.contains(.tripType(tripType)), "\(label): \(id) lost \(tripType) provenance")
                }
            }
            for item in items {
                for fact in item.provenance {
                    if let source = fact.tripType {
                        #expect(types.contains(source), "\(label): \(item.canonicalItemID ?? "") names unselected \(source)")
                    }
                }
            }
        }
    }

    @Test func aSharedItemCarriesEveryContributingTripTypeAndOneReasonNamingThemAll() throws {
        // Sunscreen is a Beach (sunExposure) and Festival (festivalAttendance) candidate.
        let items = Self.engine.generate(context: try Self.context(tripTypes: [.festival, .beach]))
        let sunscreen = try #require(items.first { $0.canonicalItemID == "toiletries.sunscreen" })
        #expect(items.filter { $0.canonicalItemID == "toiletries.sunscreen" }.count == 1)
        #expect(sunscreen.provenance.filter { $0.tripType != nil } == [.tripType(.beach), .tripType(.festival)])
        #expect(sunscreen.reasonCode == "trip_type.generic")
        #expect(sunscreen.reasonArguments["tripType"] == "beach and festival", "copy names every source; no primary")
    }

    @Test func aSingleTypeReasonIsUnchanged() throws {
        let items = Self.engine.generate(context: try Self.context(tripTypes: [.beach]))
        let swimsuit = try #require(items.first { $0.canonicalItemID == "clothing.swimsuit" })
        #expect(swimsuit.reasonArguments == ["tripType": "beach"])
        #expect(swimsuit.reason == "Suggested for a beach trip.")
    }

    @Test func threeTripTypesRenderAsOneList() {
        #expect(TripType.reasonPhrase([.vacation]) == "vacation")
        #expect(TripType.reasonPhrase([.beach, .vacation]) == "vacation and beach")
        #expect(TripType.reasonPhrase([.beach, .cityBreak, .vacation]) == "vacation, city break, and beach")
    }

    // MARK: - Quantities and essentials are computed once

    @Test func addingTripTypesNeverMultipliesBaselineClothingOrEssentials() throws {
        let baseline = ["clothing.tshirt", "clothing.underwear", "clothing.socks", "clothing.pants", "clothing.sleepwear"]
        let vacation = Self.engine.generate(context: try Self.context(tripTypes: [.vacation]))
        let vacationBeach = Self.engine.generate(context: try Self.context(tripTypes: [.vacation, .beach]))
        let all = Self.engine.generate(context: try Self.context(tripTypes: [.vacation, .beach, .cityBreak]))

        for id in baseline {
            #expect(Self.quantity(vacation, id) != nil, "\(id) is a baseline item")
            #expect(Self.quantity(vacationBeach, id) == Self.quantity(vacation, id), "\(id) Vacation + Beach")
            #expect(Self.quantity(all, id) == Self.quantity(vacation, id), "\(id) Vacation + Beach + City Break")
        }
        for id in try SharedLibrary.rules().baseEssentials {
            #expect(Self.quantity(all, id) == Self.quantity(vacation, id), "essential \(id) is not multiplied")
        }
    }

    // MARK: - Determinism

    @Test func outputTraceAndSignatureAreIndependentOfInsertionOrder() throws {
        let members: [TripType] = [.beach, .cityBreak, .vacation]
        var reference: String?
        var referenceSignature: String?
        for permutation in [members, [.vacation, .beach, .cityBreak], [.cityBreak, .vacation, .beach]] {
            var set = Set<TripType>()
            for tripType in permutation { set.insert(tripType) }
            let context = try Self.context(tripTypes: set)
            // Identity without the per-context solo traveler UUID.
            let items = Self.engine.generate(context: context)
                .map { "\($0.ownershipType.rawValue):\($0.canonicalItemID ?? "")|\($0.quantity)|\($0.reason)|\($0.provenance)" }
                .sorted()
                .joined(separator: "\n")
            let signature = WeatherChangeProposalLifecycle.tripContextSignature(context)
            if reference == nil { reference = items; referenceSignature = signature }
            #expect(items == reference, "\(permutation)")
            #expect(signature == referenceSignature, "\(permutation)")
        }
    }

    // MARK: - Specific product expectations

    @Test func businessAndCityBreakKeepFormalAndUrbanNeedsTogether() throws {
        let generation = Self.engine.generateDetailed(context: try Self.context(tripTypes: [.business, .cityBreak]))
        let ids = Set(generation.items.compactMap(\.canonicalItemID))
        #expect(ids.contains("footwear.dress_shoes"), "formal capability still needs dress shoes")
        #expect(ids.contains("electronics.laptop"))
        #expect(ids.contains("activities.daypack"))
        #expect(!generation.items.contains { $0.provenance.contains(.tripType(.vacation)) }, "no leisure inference")
        let needs = CoverageResolver.needs(context: CoverageContext(
            snapshot: TripContextCompiler.compile(try Self.context(tripTypes: [.business, .cityBreak]), rules: try SharedLibrary.rules()),
            thresholds: try SharedLibrary.rules().weather.thresholds
        ))
        #expect(needs.contains(.formal) && needs.contains(.everydayWalking))
    }

    @Test func roadTripNeverChangesLuggageCapacity() throws {
        for bags: Set<BagType> in [[.carryOn], [.personalItem], [.checked]] {
            let outdoor = Self.engine.generateDetailed(context: try Self.context(tripTypes: [.outdoor], bags: bags, style: .light))
            let both = Self.engine.generateDetailed(context: try Self.context(tripTypes: [.outdoor, .roadTrip], bags: bags, style: .light))
            let roadOnly = Set(Self.contracts.candidateItemIDs(for: [.roadTravelComfort]))

            // Compared without the per-context solo traveler UUID.
            func trims(_ decisions: [ConstraintDecision]) -> [String] {
                decisions.flatMap { decision in
                    decision.items.filter { !roadOnly.contains($0) }.map { "\(decision.constraint):\($0)" }
                }.sorted()
            }
            #expect(trims(both.constraintDecisions) == trims(outdoor.constraintDecisions),
                    "\(bags): the same trims apply with or without Road Trip")
            for item in outdoor.items {
                let match = both.items.first { $0.canonicalItemID == item.canonicalItemID }
                #expect(match?.quantity == item.quantity, "\(item.canonicalItemID ?? ""): Road Trip leaves quantity alone")
                #expect(match?.bagStyleConstraintFact == item.bagStyleConstraintFact)
            }
        }
    }

    @Test func outdoorAndSkiSnowReuseTheOneCoveragePass() throws {
        let generation = Self.engine.generateDetailed(
            context: try Self.context(city: "Aspen", tripTypes: [.outdoor, .skiSnow], style: .prepared,
                                      weatherFixture: "DenverColdOutdoor", start: DateComponents(year: 2027, month: 1, day: 11))
        )
        let keys = generation.items.map(\.recommendationKey)
        #expect(keys.count == Set(keys).count)
        let ids = Set(generation.items.compactMap(\.canonicalItemID))
        #expect(ids.contains("activities.ski_gloves") || generation.coverageSuppressions.contains { $0.canonicalItemID == "activities.ski_gloves" })
        for suppression in generation.coverageSuppressions {
            #expect(!ids.contains(suppression.canonicalItemID), "a suppressed item is not also kept")
        }
    }

    // MARK: - Suggested activities stay non-causal

    @Test func cityBreakSuggestionsContributeNothingUntilSelected() throws {
        let rules = try SharedLibrary.rules()
        let suggested = TripTypeContractResolver(contracts: rules.tripTypeContracts).suggestedActivityIDs(for: [.cityBreak])
        #expect(suggested.contains("walking") && suggested.contains("museums") && suggested.contains("niceDinner"))

        let unselected = Self.engine.generate(context: try Self.context(tripTypes: [.cityBreak], activities: []))
        for item in unselected {
            #expect(!item.provenance.contains { $0.sourceSignals == [.activity] }, "\(item.canonicalItemID ?? ""): no activity fact without a selection")
            #expect(!item.reasonCode.hasPrefix("activity."))
        }

        let selected = Self.engine.generate(context: try Self.context(tripTypes: [.cityBreak], activities: ["sightseeing"]))
        let daypack = try #require(selected.first { $0.canonicalItemID == "activities.daypack" })
        #expect(daypack.provenance.contains(.tripType(.cityBreak)))
        #expect(daypack.provenance.contains { $0.reasonCode == "activity.sightseeing" }, "an explicit selection adds its own fact")
    }

    // MARK: - Explicit user authority survives trip-type changes

    @Test func notNeededStaysSuppressedWhenANewTripTypeContributesTheSameItem() throws {
        let overrides = [RecommendationOverrideDraft(canonicalItemID: "toiletries.sunscreen", action: "removed")]
        let vacation = Self.engine.generate(context: try Self.context(tripTypes: [.vacation]), overrides: overrides)
        let withBeach = Self.engine.generate(context: try Self.context(tripTypes: [.vacation, .beach]), existing: vacation, overrides: overrides)
        #expect(!withBeach.contains { $0.canonicalItemID == "toiletries.sunscreen" })
        #expect(withBeach.contains { $0.canonicalItemID == "clothing.swimsuit" }, "Beach still contributes everything else")
    }

    @Test func manualQuantityCustomItemsAndPackedStateSurviveTripTypeChanges() throws {
        var existing = Self.engine.generate(context: try Self.context(tripTypes: [.vacation]))
        let shirtIndex = try #require(existing.firstIndex { $0.canonicalItemID == "clothing.tshirt" })
        existing[shirtIndex].quantity = 9
        existing[shirtIndex].isUserModified = true
        let walletIndex = try #require(existing.firstIndex { $0.canonicalItemID == "essentials.wallet" })
        existing[walletIndex].packedQuantity = existing[walletIndex].quantity
        let custom = PackingItemDraft(canonicalItemID: "custom.lucky_scarf", displayName: "Lucky scarf", category: .clothing,
                                      quantity: 1, importance: .normal, sourceSignals: [], reason: "", isUserAdded: true)
        existing.append(custom)

        let context = try Self.context(tripTypes: [.vacation, .cityBreak])
        let regenerated = Self.engine.generate(context: context, existing: existing)
        #expect(Self.quantity(regenerated, "clothing.tshirt") == 9, "manual quantity wins")
        #expect(regenerated.contains { $0.id == custom.id }, "custom item survives")
        let wallet = try #require(regenerated.first { $0.canonicalItemID == "essentials.wallet" })
        #expect(wallet.isPacked, "packed state survives")

        let diff = Self.engine.recommendationDiff(context: context, existing: existing, overrides: [])
        #expect(!diff.removeCandidates.contains { $0.id == custom.id || $0.canonicalItemID == "clothing.tshirt" })
        #expect(diff.add.contains { $0.canonicalItemID == "essentials.sunglasses" }, "City Break adds through the diff, not a wholesale replace")
    }

    // MARK: - Weather boundary

    @Test func tripTypesNeverManufactureWeather() throws {
        func weatherItems(_ types: Set<TripType>) throws -> Set<String> {
            Set(Self.engine.generate(context: try Self.context(tripTypes: types))
                .filter { $0.provenance.contains { $0.sourceSignals == [.weather] } }
                .compactMap(\.canonicalItemID))
        }
        let neutral = try weatherItems([.other])
        for types: Set<TripType> in [[.outdoor], [.skiSnow], [.beach], [.outdoor, .skiSnow, .beach]] {
            #expect(try weatherItems(types) == neutral, "\(types) must not add or remove weather-driven items")
        }
    }

    @Test func outdoorAndPreciseRainComposeBothFacts() throws {
        let items = Self.engine.generate(context: try Self.context(
            city: "Seattle", tripTypes: [.outdoor], activities: ["hiking"], weatherFixture: "SeattleWetCity"
        ))
        #expect(items.contains { $0.provenance.contains { $0.sourceSignals == [.weather] } }, "rain contributes")
        #expect(items.contains { $0.provenance.contains(.tripType(.outdoor)) }, "outdoor contributes")
    }

    // MARK: - Task 4.1: normalized needs are the one trip-type authority

    private static func coverageNeeds(_ types: Set<TripType>, rules: PackingRulesFile) throws -> Set<PackingCapability> {
        CoverageResolver.needs(context: CoverageContext(
            snapshot: TripContextCompiler.compile(try context(tripTypes: types), rules: rules),
            thresholds: rules.weather.thresholds
        ))
    }

    /// Pins the capabilities each single type reached through the retired
    /// direct `tripTypes` checks (beach → beach, business/wedding → formal,
    /// ski/snow → both hand capabilities, nothing else) now that they arrive
    /// through the contract's needs.
    @Test func contractNeedsReproduceTheRetiredTripTypeCoverageMapping() throws {
        let rules = try SharedLibrary.rules()
        let baseline = try Self.coverageNeeds([.other], rules: rules)
        let expected: [TripType: Set<PackingCapability>] = [
            .beach: [.beach], .business: [.formal], .weddingEvent: [.formal],
            .skiSnow: [.coldHands, .snowSportHands]
        ]
        for type in TripType.stableOrder {
            #expect(try Self.coverageNeeds([type], rules: rules).subtracting(baseline) == (expected[type] ?? []), "\(type)")
        }
    }

    /// Coverage reads the resolver's needs, so editing a contract moves
    /// coverage with it — there is no second trip-type mapping to drift.
    @Test func coverageFollowsTheContractNotTheTripType() throws {
        var rules = try SharedLibrary.rules()
        #expect(!(try Self.coverageNeeds([.vacation], rules: rules)).contains(.formal))
        #expect(try Self.coverageNeeds([.business], rules: rules).contains(.formal))

        rules.tripTypeContracts.replaceContract(for: .vacation) { $0.needs = [.leisureGeneralTravel, .formalPresentation] }
        rules.tripTypeContracts.replaceContract(for: .business) { $0.needs = [.workContext] }
        rules.tripTypeContracts.replaceContract(for: .skiSnow) { $0.needs = [.coldActivityExposure] }
        #expect(try Self.coverageNeeds([.vacation], rules: rules).contains(.formal))
        #expect(!(try Self.coverageNeeds([.business], rules: rules)).contains(.formal))
        #expect(try Self.coverageNeeds([.skiSnow], rules: rules).isDisjoint(with: [.snowSportHands]))
    }

    @Test func snapshotCarriesTheResolverNeedsOnce() throws {
        let rules = try SharedLibrary.rules()
        let types: Set<TripType> = [.festival, .beach, .cityBreak]
        let snapshot = TripContextCompiler.compile(try Self.context(tripTypes: types), rules: rules)
        #expect(snapshot.packingNeeds == TripTypeContractResolver(contracts: rules.tripTypeContracts).normalizedNeeds(for: types))
    }

    /// Structural guard: coverage names no trip type. A `TripType` mapping
    /// reappearing in the coverage resolver is exactly the parallel
    /// semantics Task 4.1 removed.
    @Test func coverageResolverSourceNamesNoTripType() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PackWise/Domain/Packing/CoverageResolver.swift"), encoding: .utf8)
        #expect(!source.contains("TripType"))
        #expect(!source.contains("tripTypes"))
    }

    // MARK: - Legacy road-trip luggage

    @Test @MainActor func legacyRoadTripLuggageNeverCreatesRoadTripBehavior() throws {
        let container = try PackWisePersistence.container(inMemory: true)
        let modelContext = ModelContext(container)
        let destination = try #require(try SharedLibrary.testDestinations().first { $0.city == "Denver" })
        let trip = TripRecord(destination: destination, startDate: .now, endDate: .now.addingTimeInterval(3 * 86400),
                              durationDays: 4, durationNights: 3, tripType: .outdoor, activities: [],
                              bagType: .roadTripLuggage, packingStyle: .balanced)
        modelContext.insert(trip)
        let context = trip.context(preferences: .deviceDefaults(), weather: nil)
        #expect(context.tripTypes == [.outdoor])
        #expect(context.bagTypes.isEmpty)
        let ids = Set(Self.engine.generate(context: context).compactMap(\.canonicalItemID))
        #expect(ids.isDisjoint(with: Self.contracts.candidateItemIDs(for: [.roadTravelComfort])),
                "Road Trip behavior comes only from tripTypes.contains(.roadTrip)")
    }
}
