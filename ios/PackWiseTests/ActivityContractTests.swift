import Foundation
import Testing
@testable import PackWise

/// Phase 5 — every surfaced activity has an explicit contract.
struct ActivityContractTests {
    private func rules() throws -> PackingRulesFile { try SharedLibrary.rules() }

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
}
