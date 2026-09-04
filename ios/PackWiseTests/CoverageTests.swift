import Foundation
import Testing
@testable import PackWise

/// Coverage resolver tests — Engine V2 plan, Step 3 (footwear + outerwear).
struct CoverageTests {
    private func candidate(
        _ canonicalItemID: String,
        sourceSignals: [RecommendationSignal] = [.tripType]
    ) -> PackingItemDraft {
        PackingItemDraft(
            canonicalItemID: canonicalItemID,
            displayName: canonicalItemID,
            category: canonicalItemID.hasPrefix("footwear.") ? .footwear : .clothing,
            quantity: 1,
            importance: .normal,
            sourceSignals: sourceSignals,
            reason: "Test"
        )
    }

    private func makeEngine() throws -> PackingEngine {
        PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
    }

    private func destination(_ name: String) throws -> Destination {
        try SharedLibrary.testDestinations().first { $0.city == name }!
    }

    /// A synthetic forecast: every day identical, span matching the trip.
    private func weather(
        days: Int,
        start: Date,
        highF: Double,
        lowF: Double,
        rain: Double = 0,
        uv: Double = 4,
        wind: Double = 8,
        snow: Bool = false,
        swingDay: Bool = false
    ) -> TripWeatherContext {
        let fixture = WeatherFixture(
            id: "synthetic",
            summary: "Synthetic",
            days: [WeatherFixtureDay(
                offset: 0,
                symbol: "cloud",
                highF: highF,
                lowF: swingDay ? highF - 25 : lowF,
                rainProbability: rain,
                uvIndex: uv,
                windMph: wind,
                snowExpected: snow,
                summary: "Synthetic"
            )]
        )
        let end = Calendar.current.date(byAdding: .day, value: days - 1, to: start)!
        return MockWeatherService.context(from: fixture, start: start, end: end, fixtureID: "synthetic")
    }

    private func context(
        destination: Destination,
        days: Int = 5,
        type: TripType = .cityBreak,
        activities: [String] = ["sightseeing", "walking"],
        bag: BagType = .carryOn,
        style: PackingStyle = .balanced,
        weather: TripWeatherContext? = nil,
        party: TripParty? = nil
    ) -> TripContext {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 14))!
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
            datedActivities: [],
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

    @Test func snapshotProjectionPreservesExistingCoverageNeeds() throws {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        let rainAndWind = weather(days: 5, start: start, highF: 55, lowF: 45, rain: 0.6, wind: 26)
        var raw = context(
            destination: try destination("Chicago"),
            type: .business,
            activities: ["running", "walking"],
            weather: rainAndWind
        )
        raw.contextChips = [.needFormalOutfit]
        let rules = try SharedLibrary.rules()
        let snapshot = TripContextCompiler.compile(raw, rules: rules)
        let projected = CoverageContext(snapshot: snapshot, thresholds: rules.weather.thresholds)

        #expect(CoverageResolver.needs(context: projected) == [
            .everydayWalking, .running, .formal, .rainShell, .windShell, .warmthLight, .warmthHeavy
        ])
    }

    @Test func suppressionPairsEachCapabilityWithItsCoverer() {
        let (kept, suppressions) = CoverageResolver.resolve(
            items: [candidate("footwear.running_shoes"), candidate("footwear.walking_shoes")],
            needs: [.running, .everydayWalking]
        )

        #expect(kept.compactMap(\.canonicalItemID) == ["footwear.running_shoes"])
        #expect(suppressions == [CoverageSuppression(
            travelerID: nil,
            canonicalItemID: "footwear.walking_shoes",
            covered: [CapabilityCoverage(
                capability: .everydayWalking,
                coveringItemID: "footwear.running_shoes"
            )],
            refutedCapabilities: []
        )])
    }

    @Test func refutedSuppressionHasCapabilitiesButNoCoverer() {
        let (_, suppressions) = CoverageResolver.resolve(
            items: [candidate("clothing.rain_jacket", sourceSignals: [.weather])],
            needs: [.everydayWalking]
        )

        #expect(suppressions == [CoverageSuppression(
            travelerID: nil,
            canonicalItemID: "clothing.rain_jacket",
            covered: [],
            refutedCapabilities: [.rainShell, .windShell]
        )])
    }

    @Test func evidenceIsStableWhenCandidateInputIsReversed() {
        let candidates = [candidate("footwear.running_shoes"), candidate("footwear.walking_shoes")]
        let forward = CoverageResolver.resolve(items: candidates, needs: [.running, .everydayWalking])
        let reverse = CoverageResolver.resolve(items: Array(candidates.reversed()), needs: [.running, .everydayWalking])

        #expect(forward.kept.compactMap(\.canonicalItemID) == reverse.kept.compactMap(\.canonicalItemID))
        #expect(forward.suppressions == reverse.suppressions)
    }

    @Test func partiallyUsefulCandidateStaysAndDoesNotReplaceExistingCoverer() {
        let (kept, suppressions) = CoverageResolver.resolve(
            items: [
                candidate("footwear.hiking_shoes"),
                candidate("footwear.running_shoes"),
                candidate("footwear.walking_shoes")
            ],
            needs: [.hiking, .running, .everydayWalking]
        )

        #expect(kept.compactMap(\.canonicalItemID) == ["footwear.running_shoes", "footwear.hiking_shoes"])
        #expect(suppressions.first?.covered == [CapabilityCoverage(
            capability: .everydayWalking,
            coveringItemID: "footwear.running_shoes"
        )])
    }

    /// The budget the vocabulary must not silently drift past: three families
    /// use twelve capabilities. Growing this number is a design decision — make
    /// it deliberately, then update this test in the same commit.
    @Test func capabilityVocabularyStaysClosed() {
        #expect(PackingCapability.allCases.count == 12)
        for id in CoverageResolver.priority {
            #expect(CoverageResolver.itemCapabilities[id]?.isEmpty == false, "\(id) is prioritized but has no capabilities")
        }
        #expect(Set(CoverageResolver.priority) == Set(CoverageResolver.itemCapabilities.keys))
    }

    /// Warm rain is umbrella weather: the wearable shell dies, the umbrella
    /// survives, and the suppression names the refuted need.
    @Test func hotRainDropsShellKeepsUmbrella() throws {
        let dest = try destination("Miami")
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 6))!
        let hotRain = weather(days: 5, start: start, highF: 91, lowF: 78, rain: 0.45, uv: 10)
        let generation = try makeEngine().generateDetailed(
            context: context(destination: dest, type: .beach, activities: ["swimming", "beachDays"], bag: .personalItem, style: .light, weather: hotRain)
        )
        let ids = Set(generation.items.compactMap(\.canonicalItemID))
        #expect(!ids.contains("clothing.rain_jacket"))
        #expect(ids.contains("essentials.umbrella_compact"))
        let suppression = generation.coverageSuppressions.first { $0.canonicalItemID == "clothing.rain_jacket" }
        #expect(suppression?.coveredBy.isEmpty == true, "the shell should die for lack of need, not by being covered")
    }

    @Test func coldRainKeepsShell() throws {
        let dest = try destination("Seattle")
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5))!
        let coldRain = weather(days: 5, start: start, highF: 57, lowF: 48, rain: 0.6, uv: 2)
        let items = try makeEngine().generate(context: context(destination: dest, weather: coldRain))
        #expect(items.contains { $0.canonicalItemID == "clothing.rain_jacket" })
    }

    /// A rain shell already blocks wind; a windbreaker on top is duplicate
    /// outerwear and the record must say what covered it.
    @Test func rainShellCoversWind() throws {
        let dest = try destination("Seattle")
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5))!
        let rainAndWind = weather(days: 5, start: start, highF: 55, lowF: 45, rain: 0.6, wind: 26)
        let generation = try makeEngine().generateDetailed(context: context(destination: dest, weather: rainAndWind))
        let ids = Set(generation.items.compactMap(\.canonicalItemID))
        #expect(ids.contains("clothing.rain_jacket"))
        #expect(!ids.contains("clothing.windbreaker"))
        let suppression = generation.coverageSuppressions.first { $0.canonicalItemID == "clothing.windbreaker" }
        #expect(suppression?.coveredBy == ["clothing.rain_jacket"])
    }

    /// A large temperature swing suggests a warm layer, not two of them.
    @Test func temperatureSwingKeepsOneLightLayer() throws {
        let dest = try destination("Denver")
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        let swingy = weather(days: 5, start: start, highF: 85, lowF: 60, swingDay: true)
        let items = try makeEngine().generate(context: context(destination: dest, weather: swingy))
        let layers = items.filter { ["clothing.light_sweater", "clothing.light_jacket"].contains($0.canonicalItemID ?? "") }
        #expect(layers.count == 1, "expected one light layer, got \(layers.compactMap(\.canonicalItemID))")
    }

    /// A winter coat is not a substitute for the layer underneath it: snow
    /// trips keep the coat, the sweater, and the boots.
    @Test func winterLayeringSurvivesCoverage() throws {
        let dest = try destination("Denver")
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 12))!
        let snowy = weather(days: 5, start: start, highF: 30, lowF: 14, rain: 0.1, wind: 18, snow: true)
        let ids = Set(try makeEngine().generate(
            context: context(destination: dest, type: .outdoor, activities: ["sightseeing"], bag: .checked, weather: snowy)
        ).compactMap(\.canonicalItemID))
        #expect(ids.contains("clothing.winter_coat"))
        #expect(ids.contains("clothing.light_sweater"))
        #expect(ids.contains("footwear.boots"))
    }

    @Test func skiGlovesCoverColdHandsWithoutAnIDPairRule() throws {
        let dest = try destination("Denver")
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 12))!
        let snowy = weather(days: 5, start: start, highF: 30, lowF: 14, rain: 0.1, wind: 18, snow: true)
        let skiTrip = context(
            destination: dest,
            type: .skiSnow,
            activities: ["sightseeing"],
            bag: .checked,
            style: .prepared,
            weather: snowy
        )
        let generation = try makeEngine().generateDetailed(context: skiTrip)
        let ids = Set(generation.items.compactMap(\.canonicalItemID))
        #expect(ids.contains("activities.ski_gloves"))
        #expect(!ids.contains("clothing.gloves"))
        let suppression = try #require(generation.coverageSuppressions.first {
            $0.canonicalItemID == "clothing.gloves"
        })
        #expect(suppression.covered == [
            CapabilityCoverage(capability: .coldHands, coveringItemID: "activities.ski_gloves")
        ])
    }

    @Test func coldNonSkiTripNeedsColdHandsButNotSnowSportHands() throws {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 12))!
        let cold = weather(days: 5, start: start, highF: 28, lowF: 12)
        let raw = context(destination: try destination("Denver"), weather: cold)
        let rules = try SharedLibrary.rules()
        let projected = CoverageContext(
            snapshot: TripContextCompiler.compile(raw, rules: rules),
            thresholds: rules.weather.thresholds
        )
        let needs = CoverageResolver.needs(context: projected)
        let resolution = CoverageResolver.resolve(
            items: [candidate("clothing.gloves", sourceSignals: [.weather])],
            needs: needs
        )

        #expect(needs.contains(.coldHands))
        #expect(!needs.contains(.snowSportHands))
        #expect(resolution.kept.compactMap(\.canonicalItemID) == ["clothing.gloves"])
        #expect(resolution.suppressions.isEmpty)
    }

    @Test func skiIntentResolvesHandOverlapWithoutForecastWeather() throws {
        let skiTrip = context(
            destination: try destination("Denver"),
            type: .skiSnow,
            activities: ["sightseeing"],
            bag: .checked,
            style: .prepared
        )
        let generation = try makeEngine().generateDetailed(context: skiTrip)
        let ids = Set(generation.items.compactMap(\.canonicalItemID))
        let suppression = generation.coverageSuppressions.first { $0.canonicalItemID == "clothing.gloves" }

        #expect(ids.contains("activities.ski_gloves"))
        #expect(!ids.contains("clothing.gloves"))
        #expect(suppression?.covered == [
            CapabilityCoverage(capability: .coldHands, coveringItemID: "activities.ski_gloves")
        ])
    }

    /// Running and hiking each keep their own shoe; the walking pair is the
    /// one that goes, and the suppression names its coverer.
    @Test func runningAndHikingKeepBothSuppressWalking() throws {
        let generation = try makeEngine().generateDetailed(
            context: context(destination: try destination("Chicago"), type: .outdoor, activities: ["running", "hiking", "sightseeing"])
        )
        let ids = Set(generation.items.compactMap(\.canonicalItemID))
        #expect(ids.contains("footwear.running_shoes"))
        #expect(ids.contains("footwear.hiking_shoes"))
        #expect(!ids.contains("footwear.walking_shoes"))
        let suppression = generation.coverageSuppressions.first { $0.canonicalItemID == "footwear.walking_shoes" }
        #expect(suppression?.coveredBy == ["footwear.running_shoes"])
        #expect(suppression?.capabilities == [PackingCapability.everydayWalking.rawValue])
    }

    /// A user-added item is never suppressed, but it claims coverage: the
    /// suggested walking shoes become redundant next to the user's runners.
    @Test func userAddedItemClaimsCoverageWithoutBeingSuppressed() throws {
        let userRunners = PackingItemDraft(
            canonicalItemID: "footwear.running_shoes",
            displayName: "Running shoes",
            category: .footwear,
            quantity: 1,
            importance: .normal,
            sourceSignals: [.userPreference],
            reason: "Added by you",
            isUserAdded: true
        )
        let generation = try makeEngine().generateDetailed(
            context: context(destination: try destination("Chicago")),
            existing: [userRunners]
        )
        let ids = generation.items.compactMap(\.canonicalItemID)
        #expect(ids.contains("footwear.running_shoes"))
        #expect(!ids.contains("footwear.walking_shoes"))
    }

    @Test func requiredOverlapMatrixProducesMinimalFocusedSetsDeterministically() throws {
        struct CoverageCase {
            var name: String
            var context: TripContext
            var kept: Set<String>
            var suppressed: Set<String>
        }

        let dest = try destination("Denver")
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        let rainWind = weather(days: 5, start: start, highF: 55, lowF: 45, rain: 0.6, wind: 26)
        let winter = weather(days: 5, start: start, highF: 30, lowF: 14, snow: true)
        let cases = [
            CoverageCase(
                name: "running + walking",
                context: context(destination: dest, activities: ["running", "walking"]),
                kept: ["footwear.running_shoes"],
                suppressed: ["footwear.walking_shoes"]
            ),
            CoverageCase(
                name: "hiking + walking",
                context: context(destination: dest, type: .outdoor, activities: ["hiking", "walking"]),
                kept: ["footwear.hiking_shoes"],
                suppressed: ["footwear.walking_shoes"]
            ),
            CoverageCase(
                name: "running + hiking + walking",
                context: context(destination: dest, type: .outdoor, activities: ["running", "hiking", "walking"]),
                kept: ["footwear.running_shoes", "footwear.hiking_shoes"],
                suppressed: ["footwear.walking_shoes"]
            ),
            CoverageCase(
                name: "formal business",
                context: context(destination: dest, type: .business, activities: ["work"]),
                kept: ["footwear.dress_shoes", "footwear.walking_shoes"],
                suppressed: []
            ),
            CoverageCase(
                name: "rain + wind",
                context: context(destination: dest, weather: rainWind),
                kept: ["clothing.rain_jacket", "clothing.light_sweater"],
                suppressed: ["clothing.windbreaker"]
            ),
            CoverageCase(
                name: "winter layering",
                context: context(destination: dest, type: .outdoor, weather: winter),
                kept: ["clothing.winter_coat", "clothing.light_sweater", "footwear.boots"],
                suppressed: []
            ),
            CoverageCase(
                name: "ski hands",
                context: context(destination: dest, type: .skiSnow, weather: winter),
                kept: ["activities.ski_gloves"],
                suppressed: ["clothing.gloves"]
            )
        ]
        let engine = try makeEngine()

        for testCase in cases {
            let first = engine.generateDetailed(context: testCase.context)
            let second = engine.generateDetailed(context: testCase.context)
            let focus = testCase.kept.union(testCase.suppressed)
            let firstIDs = Set(first.items.compactMap(\.canonicalItemID))
            let firstSuppressed = Set(first.coverageSuppressions.map(\.canonicalItemID))

            #expect(firstIDs.intersection(focus) == testCase.kept, "\(testCase.name): kept set")
            #expect(firstSuppressed.intersection(focus) == testCase.suppressed, "\(testCase.name): suppressed set")
            #expect(first.items.compactMap(\.canonicalItemID).sorted() == second.items.compactMap(\.canonicalItemID).sorted(), "\(testCase.name): item determinism")
            #expect(sortedSuppressions(first.coverageSuppressions) == sortedSuppressions(second.coverageSuppressions), "\(testCase.name): evidence determinism")
        }
    }

    @Test func explicitMultifunctionItemsRemainAuthoritativeAndClaimCoverage() throws {
        let primary = Traveler(id: UUID(), role: .self, ageGroup: .adult)
        let party = TripParty(travelMode: .solo, travelers: [primary])
        let runners = PackingItemDraft(
            canonicalItemID: "footwear.running_shoes",
            displayName: "My broken-in runners",
            category: .footwear,
            quantity: 2,
            packedQuantity: 1,
            importance: .important,
            sourceSignals: [.userPreference],
            reason: "Added by you",
            isUserAdded: true,
            ownershipType: .personal,
            travelerID: primary.id,
            assignedTravelerID: primary.id
        )
        let runnerGeneration = try makeEngine().generateDetailed(
            context: context(destination: try destination("Chicago"), party: party),
            existing: [runners]
        )
        let keptRunners = try #require(runnerGeneration.items.first { $0.id == runners.id })
        #expect(keptRunners.quantity == 2)
        #expect(keptRunners.packedQuantity == 1)
        #expect(keptRunners.travelerID == primary.id)
        #expect(keptRunners.assignedTravelerID == primary.id)
        #expect(keptRunners.isUserAdded)
        #expect(!runnerGeneration.items.contains { $0.canonicalItemID == "footwear.walking_shoes" })

        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        let rainWind = weather(days: 5, start: start, highF: 55, lowF: 45, rain: 0.6, wind: 26)
        let shell = PackingItemDraft(
            canonicalItemID: "clothing.rain_jacket",
            displayName: "My shell",
            category: .clothing,
            quantity: 2,
            packedQuantity: 1,
            importance: .important,
            sourceSignals: [.userPreference],
            reason: "Edited by you",
            isUserModified: true,
            ownershipType: .personal,
            travelerID: primary.id,
            assignedTravelerID: primary.id
        )
        let shellGeneration = try makeEngine().generateDetailed(
            context: context(destination: try destination("Seattle"), weather: rainWind, party: party),
            existing: [shell]
        )
        let keptShell = try #require(shellGeneration.items.first { $0.id == shell.id })
        #expect(keptShell.quantity == 2)
        #expect(keptShell.packedQuantity == 1)
        #expect(keptShell.travelerID == primary.id)
        #expect(keptShell.assignedTravelerID == primary.id)
        #expect(keptShell.isUserModified)
        #expect(!shellGeneration.items.contains { $0.canonicalItemID == "clothing.windbreaker" })
    }

    @Test func coverageIsOwnerScopedAndUnassignedPartyItemsInferNothing() throws {
        let primary = Traveler(id: UUID(), role: .self, ageGroup: .adult)
        let partner = Traveler(id: UUID(), role: .partner, ageGroup: .adult)
        let party = TripParty(travelMode: .couple, travelers: [primary, partner])
        func runners(owner: UUID?) -> PackingItemDraft {
            PackingItemDraft(
                canonicalItemID: "footwear.running_shoes",
                displayName: "Running shoes",
                category: .footwear,
                quantity: 1,
                importance: .normal,
                sourceSignals: [.userPreference],
                reason: "Added by you",
                isUserAdded: true,
                ownershipType: .personal,
                travelerID: owner,
                assignedTravelerID: owner
            )
        }
        let trip = context(destination: try destination("Chicago"), party: party)
        let explicit = try makeEngine().generateDetailed(context: trip, existing: [runners(owner: primary.id)])
        #expect(!explicit.items.contains { $0.travelerID == primary.id && $0.canonicalItemID == "footwear.walking_shoes" })
        #expect(explicit.items.contains { $0.travelerID == partner.id && $0.canonicalItemID == "footwear.walking_shoes" })

        let unassignedRunner = runners(owner: nil)
        let ambiguous = try makeEngine().generateDetailed(context: trip, existing: [unassignedRunner])
        #expect(ambiguous.items.contains { $0.travelerID == primary.id && $0.canonicalItemID == "footwear.walking_shoes" })
        #expect(ambiguous.items.contains { $0.travelerID == partner.id && $0.canonicalItemID == "footwear.walking_shoes" })
        let retained = try #require(ambiguous.items.first { $0.id == unassignedRunner.id })
        #expect(retained.travelerID == nil)
        #expect(retained.assignedTravelerID == nil)
    }

    private func sortedSuppressions(_ values: [CoverageSuppression]) -> [CoverageSuppression] {
        values.sorted {
            let lhs = "\($0.travelerID?.uuidString ?? ""):\($0.canonicalItemID)"
            let rhs = "\($1.travelerID?.uuidString ?? ""):\($1.canonicalItemID)"
            return lhs < rhs
        }
    }
}
