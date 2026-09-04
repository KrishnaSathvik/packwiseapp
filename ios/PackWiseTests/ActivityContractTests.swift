import Foundation
import Testing
@testable import PackWise

/// Phase 5 — every surfaced activity has an explicit contract.
struct ActivityContractTests {
    private func rules() throws -> PackingRulesFile { try SharedLibrary.rules() }

    // MARK: - Fixtures

    private func makeEngine() throws -> PackingEngine {
        PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
    }

    private func destination(_ name: String) throws -> Destination {
        try #require(try SharedLibrary.testDestinations().first { $0.city == name })
    }

    private static func frozenDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func weather(fixture name: String, start: Date, days: Int) throws -> TripWeatherContext {
        let fixture = try #require(try SharedLibrary.weatherFixtures()[name])
        let end = Calendar.current.date(byAdding: .day, value: days - 1, to: start)!
        return MockWeatherService.context(from: fixture, start: start, end: end, fixtureID: fixture.id)
    }

    private func trip(
        destination: Destination,
        start: Date,
        days: Int,
        type: TripType,
        activities: [String],
        bag: BagType,
        style: PackingStyle,
        weather: TripWeatherContext? = nil,
        party: TripParty? = nil
    ) -> TripContext {
        let end = Calendar.current.date(byAdding: .day, value: days - 1, to: start)!
        let math = TripDateMath.daysAndNights(from: start, to: end)
        var prefs = TravelerPreferences.deviceDefaults()
        prefs.homeCountryCode = "US"
        prefs.homeCountrySource = .userConfirmed
        return TripContext(
            destination: destination,
            startDate: start,
            endDate: end,
            durationDays: math.days,
            durationNights: math.nights,
            tripType: type,
            activities: activities,
            datedActivities: activities.map { DatedActivity(activityID: $0, date: nil) },
            bagType: bag,
            packingStyle: style,
            transportation: .unknown,
            laundryAccess: .none,
            travelerCount: party?.travelers.count ?? 1,
            userNotes: "",
            contextChips: [],
            weather: weather,
            preferences: prefs,
            party: party ?? .solo()
        )
    }

    /// Golden fixture 28's trip: Yellowstone, no forecast, August, four days,
    /// `outdoor`, road-trip luggage, balanced. Mild by construction — no
    /// weather signals and no seasonal warmth fallback.
    private func campingContext(
        activities: [String],
        type: TripType = .outdoor,
        bag: BagType = .roadTripLuggage,
        style: PackingStyle = .balanced,
        party: TripParty? = nil
    ) throws -> TripContext {
        trip(
            destination: try destination("Yellowstone"),
            start: Self.frozenDate(2027, 8, 15),
            days: 4,
            type: type,
            activities: activities,
            bag: bag,
            style: style,
            party: party
        )
    }

    /// An ordinary August road trip to Seattle with no forecast. Nothing else
    /// on this trip supplies Camping's candidates: `roadTrip` adds no water or
    /// repellent the way `outdoor` does, and Seattle sits above the seasonal
    /// sun path's 45° cutoff so no sunscreen arrives seasonally. That makes
    /// Camping's whole contribution observable in one delta. It is a trip any
    /// user can build, not a fixture tuned to flatter the contract.
    private func roadTripCampingContext(activities: [String]) throws -> TripContext {
        trip(
            destination: try destination("Seattle"),
            start: Self.frozenDate(2027, 8, 15),
            days: 4,
            type: .roadTrip,
            activities: activities,
            bag: .roadTripLuggage,
            style: .balanced
        )
    }

    /// A camping trip with a real cold forecast, so the gated
    /// `overnightWarmth` need has an existing cold signal to resolve against.
    private func coldCampingContext(activities: [String] = ["camping"]) throws -> TripContext {
        let start = Self.frozenDate(2026, 11, 9)
        return trip(
            destination: try destination("Denver"),
            start: start,
            days: 5,
            type: .outdoor,
            activities: activities,
            bag: .checked,
            style: .prepared,
            weather: try weather(fixture: "DenverColdOutdoor", start: start, days: 5)
        )
    }

    private func rainyCampingContext(activities: [String] = ["camping"]) throws -> TripContext {
        let start = Self.frozenDate(2026, 10, 5)
        return trip(
            destination: try destination("Seattle"),
            start: start,
            days: 5,
            type: .outdoor,
            activities: activities,
            bag: .checked,
            style: .balanced,
            weather: try weather(fixture: "SeattleWetCity", start: start, days: 5)
        )
    }

    private func family(of count: Int) -> TripParty {
        var travelers = [Traveler(role: .self, ageGroup: .adult)]
        for _ in 1..<count {
            travelers.append(Traveler(role: .otherAdult, ageGroup: .adult))
        }
        return TripParty(travelMode: .family, travelers: travelers)
    }

    private func ids(_ items: [PackingItemDraft]) -> Set<String> {
        Set(items.compactMap(\.canonicalItemID))
    }

    /// Closed like `PackingCapability`. Growing this is a design decision.
    @Test func activityNeedVocabularyIsClosedAtEight() {
        #expect(ActivityNeed.allCases.count == 8)
    }

    /// The contract table must cover exactly the surfaced vocabulary — no
    /// activity chip without a contract, no contract without a chip.
    @Test func everySurfacedActivityHasAContract() throws {
        let vocabulary = Set(try rules().activities.keys)
        #expect(Set(ActivityContracts.all.keys) == vocabulary)
        #expect(vocabulary.contains("camping"))
        let suggested = Set(TripType.allCases.flatMap(\.suggestedActivityIDs))
        #expect(suggested.isSubset(of: vocabulary))
    }

    @Test func campingAndHikingDeclareTheirNeeds() {
        #expect(ActivityContracts.needs(for: ["hiking"]) == [
            .trailFootwear, .dayCarry, .hydration, .blisterCare
        ])
        #expect(ActivityContracts.needs(for: ["camping"]) == [
            .hydration, .portableLight,
            .insectProtection, .sunProtection, .overnightWarmth
        ])
    }

    /// Camping is not a trail signal. Car camping, campgrounds, festivals and
    /// cabins do not universally put anyone on a trail, so Camping alone may
    /// neither add hiking shoes nor claim the hiking capability that would
    /// suppress ordinary walking shoes. Hiking remains the sole claimant.
    @Test func onlyHikingClaimsTrailFootwear() {
        #expect(!ActivityContracts.needs(for: ["camping"]).contains(.trailFootwear))
        #expect(ActivityContracts.capabilities(for: ActivityContracts.needs(for: ["camping"])).isEmpty)
        #expect(ActivityContracts.capabilities(for: ActivityContracts.needs(for: ["hiking"])) == [.hiking])
        #expect(!ActivityContracts.candidates(for: ActivityContracts.needs(for: ["camping"]))
            .contains("footwear.hiking_shoes"))
        // The general mapping itself is unchanged and stays available to any
        // contract that legitimately declares the need.
        #expect(ActivityContracts.needCandidates[.trailFootwear] == ["footwear.hiking_shoes"])
        #expect(ActivityContracts.needCapabilities[.trailFootwear] == .hiking)
    }

    /// Composition is a set union, so the shared needs appear once.
    @Test func hikingAndCampingComposeIntoOneNeedSet() {
        let composed = ActivityContracts.needs(for: ["hiking", "camping"])
        #expect(composed == ActivityContracts.needs(for: ["camping", "hiking"]))
        #expect(composed.count == 8)
        #expect(composed.contains(.hydration))   // declared by both, present once
        // Trail footwear enters the composed set through Hiking alone, so
        // dropping Hiking drops it.
        #expect(composed.contains(.trailFootwear))
        #expect(!ActivityContracts.needs(for: ["camping"]).contains(.trailFootwear))
    }

    /// Hiking's typed needs must resolve to exactly the IDs its JSON row
    /// holds today — the equivalence that lets Task 3 empty that row.
    @Test func hikingNeedsResolveToItsHistoricalItemSet() {
        #expect(ActivityContracts.candidates(for: ActivityContracts.needs(for: ["hiking"])) == [
            "activities.daypack",
            "footwear.hiking_shoes",
            "health.blister_pads",
            "hydration.water_bottle"
        ])
    }

    /// Camping is a packing signal, not a campsite planner.
    @Test func campingNeverProducesCampsiteLogistics() {
        let forbidden: Set<String> = [
            "activities.tent", "activities.sleeping_bag", "activities.sleeping_pad",
            "activities.camp_stove", "activities.camp_fuel", "activities.cookware",
            "activities.food_storage", "activities.camp_chair"
        ]
        let candidates = Set(ActivityContracts.candidates(for: ActivityContracts.needs(for: ["camping"])))
        #expect(candidates.isDisjoint(with: forbidden))
    }

    /// An id with no contract stays inert — never mapped onto a known one.
    @Test func unknownActivityHasNoContractAndNoNeeds() {
        #expect(ActivityContracts.contract(for: "cosplayConvention") == nil)
        #expect(ActivityContracts.needs(for: ["cosplayConvention"]).isEmpty)
        #expect(ActivityContracts.candidates(for: ActivityContracts.needs(for: ["cosplayConvention"])).isEmpty)
    }

    // MARK: - Task 2: need resolution

    /// On a road-trip camping trip nothing else supplies Camping's
    /// candidates, so all four appear as new rows and none of them is
    /// campsite logistics.
    @Test func campingAloneAddsItsFourCandidatesAndNoCampsiteLogistics() throws {
        let engine = try makeEngine()
        let base = ids(engine.generate(context: try roadTripCampingContext(activities: ["sightseeing"])))
        let camping = ids(engine.generate(context: try roadTripCampingContext(activities: ["sightseeing", "camping"])))

        #expect(camping.subtracting(base) == [
            "hydration.water_bottle",
            "miscellaneous.flashlight",
            "toiletries.insect_repellent",
            "toiletries.sunscreen"
        ])
        // Camping declares no footwear need: nothing is added and, critically,
        // nothing is taken away. Walking shoes survive a camping trip.
        #expect(base.subtracting(camping).isEmpty)
        #expect(camping.contains("footwear.walking_shoes"))
        #expect(!camping.contains("footwear.hiking_shoes"))

        let forbidden: Set<String> = [
            "activities.tent", "activities.sleeping_bag", "activities.sleeping_pad",
            "activities.camp_stove", "activities.camp_fuel", "activities.cookware",
            "activities.food_storage", "activities.camp_chair"
        ]
        #expect(camping.isDisjoint(with: forbidden))
    }

    /// The same contract on an `outdoor` trip type adds only the flashlight,
    /// because the trip type already supplies water and repellent and the
    /// seasonal-sun path already supplies sunscreen. One shared candidate
    /// yields one row — the collector's de-duplication, not a weaker
    /// contract.
    @Test func campingDeDuplicatesAgainstTheOutdoorTripTypeAndSeasonalSun() throws {
        let engine = try makeEngine()
        let baseItems = engine.generate(context: try campingContext(activities: ["sightseeing"]))
        let campingItems = engine.generate(context: try campingContext(activities: ["sightseeing", "camping"]))
        let base = ids(baseItems)
        let camping = ids(campingItems)

        #expect(camping.subtracting(base) == ["miscellaneous.flashlight"])
        #expect(base.subtracting(camping).isEmpty)
        for id in ["hydration.water_bottle", "toiletries.insect_repellent", "toiletries.sunscreen"] {
            #expect(campingItems.filter { $0.canonicalItemID == id }.count == 1)
        }
        #expect(camping.contains("footwear.walking_shoes"))
    }

    @Test func campingNeverManufacturesRainOrWarmth() throws {
        let engine = try makeEngine()
        let mild = ids(engine.generate(context: try campingContext(activities: ["camping"])))
        #expect(!mild.contains("clothing.rain_jacket"))
        #expect(!mild.contains("essentials.umbrella_compact"))
        #expect(!mild.contains("clothing.winter_coat"))
        #expect(!mild.contains("clothing.light_sweater"))
        #expect(!mild.contains("clothing.thermal_top"))   // overnightWarmth is gated
    }

    /// The gated need resolves only when the projection already carries a
    /// cold signal — and never invents one. Three trips pin the whole rule.
    @Test func overnightWarmthResolvesOnlyWithAnExistingColdSignal() throws {
        let engine = try makeEngine()

        // Mild: a cold signal does not exist, so the need resolves to nothing.
        let mild = ids(engine.generate(context: try campingContext(activities: ["camping"])))
        #expect(!mild.contains("clothing.thermal_top"))

        // Cold but not freezing: the cold signal exists, so the need resolves.
        // `clothing.thermal_top` is only in the `freezingCold` signalAdds row,
        // so weather does not emit it here — the item is on the list because
        // Camping asked for it against cold that was already forecast, and
        // Camping therefore owns the reason.
        let cold = engine.generateDetailed(context: try coldCampingContext())
        #expect(ids(cold.items).contains("clothing.thermal_top"))
        let campingRow = try #require(cold.items.first { $0.canonicalItemID == "clothing.thermal_top" })
        #expect(campingRow.reasonCode == "activity.camping")
        #expect(campingRow.sourceSignals.contains(.activity))

        // Freezing: weather emits the same item itself, and its higher-tier
        // reason outranks the activity's. Camping never displaces a weather
        // explanation for a weather-driven row.
        let start = Self.frozenDate(2026, 1, 12)
        let freezing = engine.generateDetailed(context: trip(
            destination: try destination("Minneapolis"),
            start: start,
            days: 5,
            type: .outdoor,
            activities: ["camping"],
            bag: .checked,
            style: .prepared,
            weather: try weather(fixture: "MinneapolisDeepWinter", start: start, days: 5)
        ))
        let freezingRow = try #require(freezing.items.first { $0.canonicalItemID == "clothing.thermal_top" })
        #expect(freezingRow.reasonCode.hasPrefix("weather."))
    }

    @Test func campingPlusRainProducesExactlyOneShellAndNoCampingRainItem() throws {
        let engine = try makeEngine()
        let items = engine.generate(context: try rainyCampingContext())
        #expect(items.filter { $0.canonicalItemID == "clothing.rain_jacket" }.count == 1)
        #expect(!items.contains { $0.canonicalItemID == "activities.rain_cover" })
    }

    /// Both orders produce one row; only the reason may differ.
    @Test func sharedNeedsAttributeToTheFirstDeclaringActivity() throws {
        let engine = try makeEngine()
        func bottleReason(_ activities: [String]) throws -> String {
            let items = engine.generate(context: try campingContext(activities: activities))
            let bottles = items.filter { $0.canonicalItemID == "hydration.water_bottle" }
            #expect(bottles.count == 1)
            return try #require(bottles.first).reasonCode
        }
        #expect(try bottleReason(["hiking", "camping"]) == "activity.hiking")
        #expect(try bottleReason(["camping", "hiking"]) == "activity.camping")
    }

    /// Phase 5 makes no party-sharing decision. `miscellaneous.flashlight` is
    /// not in `party.sharedByDefault`, so it stays a personal-carry item: one
    /// per traveler, owned personally. Whether a family should instead share
    /// one is finding F-5, routed to Phase 7 — this test records the baseline
    /// that decision will be made against, and must not be "corrected" here.
    @Test func aPartyCampingTripKeepsFlashlightsPersonalPerTraveler() throws {
        let engine = try makeEngine()
        let party = family(of: 4)
        let items = engine.generate(context: try campingContext(activities: ["camping"], party: party))
        let lights = items.filter { $0.canonicalItemID == "miscellaneous.flashlight" }
        #expect(lights.count == party.travelers.count)
        #expect(lights.allSatisfy { $0.ownershipType == .personal })
        #expect(Set(lights.compactMap(\.travelerID)) == Set(party.travelers.map(\.id)))
        // The mechanism that would change this is untouched this phase.
        #expect(!Set(try rules().party.sharedByDefault).contains("miscellaneous.flashlight"))
        #expect(try rules().party.sharingPolicies["miscellaneous.flashlight"] == nil)
    }

    /// Camping must not blow past an existing bag constraint — the optional
    /// flashlight is trimmed by the constraint that already exists.
    @Test func campingRespectsLightPackingConstraints() throws {
        let engine = try makeEngine()
        let generation = engine.generateDetailed(
            context: try campingContext(activities: ["camping"], bag: .carryOn, style: .light)
        )
        let generated = ids(generation.items)
        #expect(!generated.contains("miscellaneous.flashlight"))
        #expect(generated.contains("hydration.water_bottle"))
        #expect(generation.constraintDecisions.contains {
            $0.constraint == "bag.space_constrained" && $0.items.contains("miscellaneous.flashlight")
        })
    }

    /// A user-added multifunction item that already satisfies a Camping need
    /// must survive and prevent a duplicate.
    @Test func aUserAddedBottleSatisfiesCampingHydrationWithoutDuplication() throws {
        let engine = try makeEngine()
        let existing = [PackingItemDraft(
            canonicalItemID: "hydration.water_bottle",
            displayName: "My filter bottle",
            category: .essentials,
            quantity: 1,
            importance: .normal,
            sourceSignals: [.activity],
            reason: "Mine",
            isUserAdded: true
        )]
        let items = engine.generate(context: try campingContext(activities: ["camping"]), existing: existing)
        let bottles = items.filter { $0.canonicalItemID == "hydration.water_bottle" }
        #expect(bottles.count == 1)
        #expect(bottles.first?.isUserAdded == true)
        #expect(bottles.first?.displayName == "My filter bottle")
    }

    // MARK: - Task 3: composition through capability coverage

    /// Camping is not a trail signal. A camping-and-walking trip keeps the
    /// ordinary walking shoes it would have had without Camping, and
    /// suppresses nothing — the failure mode this guards is Camping quietly
    /// claiming `PackingCapability.hiking` and deleting a normal traveler's
    /// shoes.
    @Test func campingAloneLeavesWalkingFootwearAlone() throws {
        let engine = try makeEngine()
        let context = try campingContext(activities: ["camping", "walking"])
        let generation = engine.generateDetailed(context: context)
        let generated = ids(generation.items)
        #expect(generated.contains("footwear.walking_shoes"))
        #expect(!generated.contains("footwear.hiking_shoes"))
        #expect(!generation.coverageSuppressions.contains { $0.canonicalItemID == "footwear.walking_shoes" })

        let snapshot = TripContextCompiler.compile(context, rules: try rules())
        let coverage = CoverageContext(snapshot: snapshot, thresholds: try rules().weather.thresholds)
        #expect(!CoverageResolver.needs(context: coverage).contains(.hiking))
    }

    /// The hiking capability is derived from `ActivityNeed.trailFootwear`, not
    /// from the literal id `"hiking"`. Hiking declares that need, so the
    /// Phase 4 suppression and its evidence are byte-identical to baseline.
    @Test func trailFootwearCoverageIsDerivedFromTheNeedNotTheActivityString() throws {
        let engine = try makeEngine()
        let generation = engine.generateDetailed(context: try campingContext(activities: ["hiking", "walking"]))
        let generated = ids(generation.items)
        #expect(generated.contains("footwear.hiking_shoes"))
        #expect(!generated.contains("footwear.walking_shoes"))

        let suppression = try #require(generation.coverageSuppressions.first {
            $0.canonicalItemID == "footwear.walking_shoes"
        })
        #expect(suppression.covered == [
            CapabilityCoverage(capability: .everydayWalking, coveringItemID: "footwear.hiking_shoes")
        ])

        // The derivation, stated directly: the capability follows the need
        // set, and the need set is what the contract table says it is.
        #expect(ActivityContracts.capabilities(for: ActivityContracts.needs(for: ["hiking", "walking"]))
            == [.hiking])
        #expect(ActivityContracts.capabilities(for: ActivityContracts.needs(for: ["camping", "walking"]))
            .isEmpty)
    }

    @Test func hikingPlusCampingIsOneComposedTripNotTwoChecklists() throws {
        let engine = try makeEngine()
        let items = engine.generateDetailed(context: try campingContext(activities: ["hiking", "camping"])).items
        func count(_ id: String) -> Int { items.filter { $0.canonicalItemID == id }.count }
        // `hydration` is declared by both contracts and yields exactly one row.
        #expect(count("hydration.water_bottle") == 1)
        // Exactly one `.hiking`-covered footwear item, sourced by Hiking alone
        // — Camping neither adds a second pair nor is required for this one.
        #expect(count("footwear.hiking_shoes") == 1)
        #expect(count("activities.daypack") == 1)
        #expect(count("health.blister_pads") == 1)
        #expect(items.first { $0.canonicalItemID == "hydration.water_bottle" }?.quantity == 1)

        // Composition is preserved but no longer double-sourced: the footwear
        // result is identical with and without Camping on the same trip.
        let hikingOnly = engine.generateDetailed(context: try campingContext(activities: ["hiking"])).items
        func footwear(_ rows: [PackingItemDraft]) -> Set<String> {
            Set(rows.compactMap(\.canonicalItemID).filter { $0.hasPrefix("footwear.") })
        }
        #expect(footwear(items) == footwear(hikingOnly))
    }

    /// Hiking's behavior must be unchanged by moving its item list out of
    /// `activity-rules.json` and into its typed contract.
    @Test func hikingOnlyBehaviorIsUnchangedByTheContractMigration() throws {
        let engine = try makeEngine()
        let items = engine.generate(context: try campingContext(activities: ["hiking"]))
        #expect(ids(items).isSuperset(of: [
            "activities.daypack", "footwear.hiking_shoes",
            "health.blister_pads", "hydration.water_bottle"
        ]))
        for item in items where item.canonicalItemID == "activities.daypack" {
            #expect(item.reasonCode == "activity.hiking")
        }
    }

    // MARK: - Task 4: `other` and the unknown-activity contract

    /// `Other` means "no additional trip-type-specific needs; activities,
    /// preferences, and context carry the meaning." That is a declared empty
    /// rule, not a failed lookup — and it must stay the only one.
    @Test func otherIsADeclaredIdentityTripType() throws {
        let tripTypes = try rules().tripTypes
        let other = try #require(tripTypes["other"])
        #expect(other.add.isEmpty)
        #expect(other.preferActivities?.isEmpty ?? true)

        let emptyRules = tripTypes.filter { $0.value.add.isEmpty }.keys.sorted()
        #expect(emptyRules == ["other"], "a trip type silently lost its rule: \(emptyRules)")
        #expect(Set(tripTypes.keys) == Set(TripType.allCases.map(\.rawValue)))
    }

    /// An `Other` trip still produces a complete, coherent list, and every row
    /// is explained by base essentials, activities, weather, or party — never
    /// by an invented `other` recommendation.
    @Test func otherTripsAreCarriedEntirelyByActivitiesAndContext() throws {
        let engine = try makeEngine()
        let other = try campingContext(activities: ["sightseeing", "walking"], type: .other)
        let items = engine.generateDetailed(context: other).items
        #expect(items.count > 10)
        #expect(!items.contains { $0.reasonCode == "trip_type.generic" })
        for item in items {
            #expect(item.sourceSignals.contains { $0 != .tripType })
        }
    }

    @Test func anUnknownActivityChangesNothingAtAll() throws {
        let engine = try makeEngine()
        func rows(_ activities: [String]) throws -> [String] {
            engine.generate(context: try campingContext(activities: activities))
                .compactMap(\.canonicalItemID).sorted()
        }
        #expect(try rows(["sightseeing", "walking"]) == rows(["sightseeing", "walking", "cosplayConvention"]))

        let generation = engine.generateDetailed(
            context: try campingContext(activities: ["sightseeing", "walking", "cosplayConvention"])
        )
        #expect(generation.contextDiagnostics.contains {
            $0.field == "activities" && $0.outcome.isUnsupportedButSafe
        })
    }

    // MARK: - Task 5: observable effect for every deterministic activity

    /// Every activity the ledger calls deterministic must be responsible for
    /// something, proved as a delta against the same trip without it —
    /// presence in a full list proves nothing.
    private func addedBy(_ activity: String) throws -> Set<String> {
        let engine = try makeEngine()
        let without = ids(engine.generate(context: try campingContext(activities: ["sightseeing"])))
        let with = ids(engine.generate(context: try campingContext(activities: ["sightseeing", activity])))
        return with.subtracting(without)
    }

    /// Requirement 3: executable coverage for every deterministic activity.
    @Test func everyDeterministicActivityHasAnObservableEffect() throws {
        let expected: [String: Set<String>] = [
            "nightlife": ["clothing.nice_outfit"],
            "shopping": ["essentials.reusable_bag"],
            "museums": ["clothing.light_sweater"],
            "wildlife": ["activities.binoculars", "electronics.camera"],
            "snorkeling": ["activities.snorkel", "footwear.water_shoes"],
            "boatTrip": ["activities.dry_bag", "health.motion_sickness"],
            "yoga": ["activities.yoga_mat_travel"],
            "photography": ["electronics.camera", "electronics.memory_card"]
            // running/walking/hiking/camping/swimming/beachDays/work/
            // niceDinner/sightseeing are pinned by their own named tests and
            // golden fixtures.
        ]
        for (activity, mustAppear) in expected.sorted(by: { $0.key < $1.key }) {
            #expect(mustAppear.isSubset(of: try addedBy(activity)),
                    "\(activity) produced no observable effect")
        }
    }

    // One named test per previously-untested activity, so every ledger
    // `testIDs` entry resolves to a real function in this file.

    @Test func nightlifeAddsANiceOutfit() throws {
        #expect(try addedBy("nightlife").contains("clothing.nice_outfit"))
    }

    @Test func shoppingAddsAReusableBag() throws {
        #expect(try addedBy("shopping").contains("essentials.reusable_bag"))
    }

    @Test func museumsAddsALightSweater() throws {
        #expect(try addedBy("museums").contains("clothing.light_sweater"))
    }

    @Test func wildlifeAddsBinocularsAndACamera() throws {
        #expect(try addedBy("wildlife").isSuperset(of: ["activities.binoculars", "electronics.camera"]))
    }

    @Test func snorkelingAddsSnorkelGearAndWaterShoes() throws {
        #expect(try addedBy("snorkeling").isSuperset(of: ["activities.snorkel", "footwear.water_shoes"]))
    }

    @Test func boatTripAddsADryBagAndMotionSickness() throws {
        #expect(try addedBy("boatTrip").isSuperset(of: ["activities.dry_bag", "health.motion_sickness"]))
    }

    @Test func yogaAddsAMatAndWorkoutClothes() throws {
        #expect(try addedBy("yoga").contains("activities.yoga_mat_travel"))
    }

    @Test func photographyAddsACameraAndMemoryCard() throws {
        #expect(try addedBy("photography").isSuperset(of: ["electronics.camera", "electronics.memory_card"]))
    }
}
