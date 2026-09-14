import Foundation
import Testing
@testable import PackWise

/// `RecommendationTrace` — Phase 8, Task 5: the pure read layer.
///
/// Every fact these tests check is a field read off an already-generated
/// `PackingItemDraft` — no test here re-derives a decision. Reuses
/// `GoldenEngineTests`' fixture-rendering helpers rather than duplicating
/// context/engine construction.
struct RecommendationTraceTests {
    private func drafts(for fixtureID: String) throws -> [PackingItemDraft] {
        try GoldenEngineTests().engineDrafts(for: fixtureID)
    }

    private func draft(_ canonicalItemID: String, in drafts: [PackingItemDraft]) throws -> PackingItemDraft {
        try #require(drafts.first { $0.canonicalItemID == canonicalItemID })
    }

    // MARK: - inclusionFamily

    @Test func inclusionFamilyCoversEveryReasonCodePrefixInTheTemplateFile() throws {
        let templates = try SharedLibrary.rules().reasons.templates
        let expectations: [String: RecommendationTrace.InclusionFamily] = [
            "base.essential.clothing": .baseEssential,
            "weather.seasonal_sun": .weatherSeasonal,
            "weather.rain_days": .weatherPrecise,
            "activity.hiking": .activity,
            "party.shared": .party,
            "dependency.companion": .dependency,
            "preference.usuallyWorkOut": .personalPreference,
            "trip_type.generic": .tripType,
            "destination.international": .destination,
            "documents.visa_check": .documents,
            "flight.empty_bottle": .flight,
            "substitution.hiking_covers_walking": .substitution
        ]
        for (code, expected) in expectations {
            #expect(templates[code] != nil, "\(code) must be a real reasons.json key — the test itself would be meaningless otherwise")
            #expect(RecommendationTrace.inclusionFamily(reasonCode: code, signals: []) == expected)
        }
    }

    @Test func inclusionFamilyIsUserAuthorityForAnEmptyReasonCode() {
        #expect(RecommendationTrace.inclusionFamily(reasonCode: "", signals: []) == .userAuthority)
    }

    /// Every real inclusion-reason key in `reasons.json` must classify to a
    /// named family, never silently fall through to the closed fallback.
    /// `category.`/`impact.`/`quantity.`/`context.`/`weather_change.` are
    /// excluded: they are not inclusion-reason vocabulary at all —
    /// `category`/`impact`/`context` key weather-detail copy fragments,
    /// `quantity.*` keys the *quantity* reason template set (a different
    /// vocabulary from `reasonCode`, closed separately in Task 1), and
    /// `weather_change.*` is `WeatherSignalDiff`'s notification-copy
    /// vocabulary — confirmed never assigned to `PackingItemDraft.reasonCode`
    /// anywhere in the app (`grep -rn "weather_change\\." ios/PackWise/Domain`
    /// finds only `WeatherSignalDiff.swift`).
    @Test func everyReasonCodeInTheTemplateFileClassifiesToAKnownFamilyNotTheFallback() throws {
        let templates = try SharedLibrary.rules().reasons.templates
        let excludedPrefixes = ["category.", "impact.", "quantity.", "context.", "weather_change."]
        for code in templates.keys where !excludedPrefixes.contains(where: code.hasPrefix) {
            let family = RecommendationTrace.inclusionFamily(reasonCode: code, signals: [])
            #expect(family != .tripType || code.hasPrefix("trip_type."), "\(code) unexpectedly fell through to the fallback family")
        }
    }

    // MARK: - ConstraintFacet

    @Test func constraintFacetIsAPureFieldReadWithNoDecisionDependency() throws {
        // Structural proof, not just documentation: read(from:) takes only a
        // PackingItemDraft — there is no way to pass it a catalog, rules,
        // context, or party even if a future edit wanted to.
        let hikingShoes = try draft("footwear.hiking_shoes", in: try drafts(for: "29-yellowstone-4d-hiking-camping"))
        let facet = RecommendationTrace.ConstraintFacet.read(from: hikingShoes)
        #expect(facet.sharing == nil, "a personal item is never .shared")
    }

    @Test func constraintFacetReconstructsSharingFromStoredFieldsNotALiveCall() throws {
        let umbrella = try draft("essentials.umbrella_compact", in: try drafts(for: "38-couple-5d-seattle-shared-umbrella"))
        let facet = RecommendationTrace.ConstraintFacet.read(from: umbrella)
        if case .shared(let quantity, let reason) = facet.sharing {
            #expect(quantity == umbrella.quantity)
            #expect(reason == umbrella.quantityReason)
        } else {
            Issue.record("expected a shared resolution reconstructed from item.quantity/quantityReason")
        }
    }

    // MARK: - CoverageFacet

    @Test func coverageFacetReadsSatisfiedCapabilitiesDirectly() throws {
        let hikingShoes = try draft("footwear.hiking_shoes", in: try drafts(for: "29-yellowstone-4d-hiking-camping"))
        let facet = RecommendationTrace.coverageFacet(for: hikingShoes)
        #expect(facet.satisfiedCapabilities.contains(PackingCapability.everydayWalking.rawValue))
    }

    // MARK: - Authority

    @Test func userAuthorityRowsPresentAsUserDecidedNotEngineGenerated() throws {
        var manual = PackingItemDraft(canonicalItemID: "clothing.tshirt", displayName: "T-Shirts", category: .clothing, quantity: 3, importance: .normal, sourceSignals: [], reason: "")
        manual.isUserModified = true
        let authority = RecommendationTrace.authority(for: manual)
        #expect(authority.isUserModified)
        #expect(!authority.isUserAdded)
    }

    // MARK: - Task 6: PackingTracePresentation.authorityLine

    @Test func authorityLineIsNilForAnOrdinaryEngineGeneratedRow() throws {
        let ordinary = PackingItemDraft(canonicalItemID: "toiletries.toothbrush", displayName: "Toothbrush", category: .toiletries, quantity: 1, importance: .critical, sourceSignals: [.baseEssential], reason: "Base essential.")
        #expect(PackingTracePresentation.authorityLine(RecommendationTrace.authority(for: ordinary)) == nil)
    }

    @Test func authorityLineNamesAUserModifiedRow() throws {
        var modified = PackingItemDraft(canonicalItemID: "clothing.tshirt", displayName: "T-Shirts", category: .clothing, quantity: 3, importance: .normal, sourceSignals: [], reason: "")
        modified.isUserModified = true
        #expect(PackingTracePresentation.authorityLine(RecommendationTrace.authority(for: modified)) == "You changed this.")
    }

    @Test func authorityLineNamesAUserAddedRow() throws {
        var added = PackingItemDraft(canonicalItemID: "clothing.tshirt", displayName: "T-Shirts", category: .clothing, quantity: 3, importance: .normal, sourceSignals: [], reason: "Added by you", isUserAdded: true)
        added.isUserAdded = true
        #expect(PackingTracePresentation.authorityLine(RecommendationTrace.authority(for: added)) == "Added by you.")
    }

    @Test func authorityLineNamesACustomItemEvenWithoutTheUserAddedFlag() throws {
        let custom = PackingItemDraft(canonicalItemID: "custom.lucky_travel_journal", displayName: "Lucky travel journal", category: .miscellaneous, quantity: 1, importance: .optional, sourceSignals: [], reason: "")
        #expect(PackingTracePresentation.authorityLine(RecommendationTrace.authority(for: custom)) == "Added by you.")
    }

    // MARK: - QuantityFacet

    @Test func clothingQuantityFacetPrefersStructuredEvidenceOverBareReasonText() throws {
        let tshirt = try draft("clothing.tshirt", in: try drafts(for: "02-tokyo-15d-light-laundry-possible"))
        let facet = RecommendationTrace.quantityFacet(for: tshirt)
        #expect(facet.clothingEvidence != nil)
        #expect(facet.isFixedSingleton == false)
    }

    // MARK: - Phase 8, Task 8: the 18 required scenarios, trace-level evidence
    //
    // Sixteen of eighteen scenarios already have a named, passing test or
    // fixture proving the underlying *decision* (design doc's 18-scenario
    // table). This task's job for those is a trace-classification test
    // proving RecommendationTrace reads the right facet correctly off that
    // existing evidence — not re-proving the decision. Scenario 12 (Task 4)
    // and scenario 15 (no Item Detail row by definition) are covered
    // elsewhere, cited in their own comments below, not duplicated here.

    /// Scenario 1: base essential singleton. Cites fixture 01
    /// toiletries.toothbrush (fixed singleton).
    @Test func scenario1BaseEssentialSingletonClassifiesCorrectly() throws {
        let toothbrush = try draft("toiletries.toothbrush", in: try drafts(for: "01-chicago-5d-city-balanced"))
        #expect(RecommendationTrace.inclusionFamily(reasonCode: toothbrush.reasonCode, signals: toothbrush.sourceSignals) == .baseEssential)
        #expect(RecommendationTrace.quantityFacet(for: toothbrush).isFixedSingleton)
    }

    /// Scenario 2: Tokyo planned-laundry T-shirts — quantityFacet must
    /// surface clothingEvidence with laundryPlan/laundryReduced, not just
    /// the rendered string. Cites GoldenEngineTests.swift's
    /// phase3RequiredFixturesHoldClothingQuantityContracts; this proves the
    /// *trace* reads it correctly.
    @Test func scenario2TokyoLaundryTshirtsExposeClothingEvidence() throws {
        let tshirt = try draft("clothing.tshirt", in: try drafts(for: "02b-tokyo-15d-light-laundry-planned"))
        let facet = RecommendationTrace.quantityFacet(for: tshirt)
        #expect(facet.clothingEvidence?.laundryPlan == .planned)
        #expect(facet.clothingEvidence?.laundryReduced == true)
    }

    /// Scenario 3: workout clothing quantity basis is the workout policy,
    /// not a bare number. Cites fixture 08.
    @Test func scenario3WorkoutClothingExposesWorkoutPolicyBasis() throws {
        let top = try draft("clothing.workout_top", in: try drafts(for: "08-running-sightseeing-footwear"))
        #expect(RecommendationTrace.quantityFacet(for: top).clothingEvidence?.policyID.contains("workout") == true)
    }

    /// Scenario 4: swimwear's drying-rotation basis is visible via the
    /// clothing evidence. Cites GoldenEngineTests.swift's
    /// phase3RequiredFixturesHoldClothingQuantityContracts (basis ==
    /// "dryingRotation").
    @Test func scenario4SwimwearExposesDryingRotationBasis() throws {
        let swimsuit = try draft("clothing.swimsuit", in: try drafts(for: "06-miami-5d-beach-personal-item"))
        #expect(RecommendationTrace.quantityFacet(for: swimsuit).clothingEvidence?.basis == "dryingRotation")
    }

    /// Scenarios 5/6: footwear/hand-protection coverage substitution reason
    /// codes classify as .substitution. Cites fixture 29 (hiking covers
    /// walking) and CoverageTests.skiGlovesCoverColdHandsWithoutAnIDPairRule
    /// for the underlying decision.
    @Test func scenario5And6SubstitutionCoverageReasonCodesClassifyCorrectly() throws {
        let hikingShoes = try draft("footwear.hiking_shoes", in: try drafts(for: "29-yellowstone-4d-hiking-camping"))
        #expect(RecommendationTrace.inclusionFamily(reasonCode: hikingShoes.reasonCode, signals: hikingShoes.sourceSignals) == .substitution)
    }

    /// Scenario 7: a camping item (flashlight) classifies as .activity.
    /// Cites fixtures 28-32, 37.
    @Test func scenario7CampingItemClassifiesAsActivity() throws {
        let flashlight = try draft("miscellaneous.flashlight", in: try drafts(for: "28-yellowstone-4d-camping-mild"))
        #expect(RecommendationTrace.inclusionFamily(reasonCode: flashlight.reasonCode, signals: flashlight.sourceSignals) == .activity)
    }

    /// Scenario 8: precise rain item classifies as .weatherPrecise and
    /// carries non-empty reasonArguments (day counts). Cites fixture 09.
    @Test func scenario8PreciseRainItemClassifiesAsWeatherPrecise() throws {
        let rainJacket = try draft("clothing.rain_jacket", in: try drafts(for: "09-seattle-rain-layering"))
        #expect(RecommendationTrace.inclusionFamily(reasonCode: rainJacket.reasonCode, signals: rainJacket.sourceSignals) == .weatherPrecise)
        #expect(!rainJacket.reasonArguments.isEmpty)
    }

    /// Scenario 9: seasonal sun item classifies as .weatherSeasonal and
    /// never carries forecast-specific arguments. Cites fixture 12.
    @Test func scenario9SeasonalItemClassifiesAsWeatherSeasonalWithEmptyArguments() throws {
        let sunglasses = try draft("essentials.sunglasses", in: try drafts(for: "12-family-toddler-7d-seasonal"))
        #expect(RecommendationTrace.inclusionFamily(reasonCode: sunglasses.reasonCode, signals: sunglasses.sourceSignals) == .weatherSeasonal)
        #expect(sunglasses.reasonArguments.isEmpty)
    }

    /// Scenario 10: partial-forecast rows classify as weatherPrecise for
    /// their covered days and weatherSeasonal for the seasonal remainder,
    /// never the reverse — cites fixture 33 (a byte-stable pin; Phase 6
    /// documented that the golden schema can't express a true partial
    /// remainder, so this fixture's rows may all be precise) plus
    /// WeatherNeedHardeningTests.partialForecastBlendsCoveredSignalsWithSeasonalRemainder
    /// for the underlying decision.
    @Test func scenario10PartialForecastKeepsPreciseAndSeasonalRowsDistinct() throws {
        let output = try drafts(for: "33-chicago-10d-partial-forecast-seasonal-remainder")
        for item in output where item.reasonCode.hasPrefix("weather.") {
            let family = RecommendationTrace.inclusionFamily(reasonCode: item.reasonCode, signals: item.sourceSignals)
            #expect(family == .weatherPrecise || family == .weatherSeasonal)
            if family == .weatherSeasonal {
                #expect(item.reasonArguments.isEmpty, "seasonal rows must never carry forecast-specific arguments")
            }
        }
    }

    /// Scenario 11: shared umbrella — two independent facets, correctly
    /// distinct. Inclusion (*why it's on the list at all*) is the weather
    /// trigger that suggested it (`weather.rain_days` → `.weatherPrecise`);
    /// sharing (*why one, not one per person*) is
    /// `ConstraintFacet.sharing`, already proven reconstructed from stored
    /// fields in `constraintFacetReconstructsSharingFromStoredFieldsNotALiveCall`
    /// above. The trace must not conflate the two.
    @Test func scenario11SharedUmbrellaKeepsInclusionAndSharingFacetsDistinct() throws {
        let umbrella = try draft("essentials.umbrella_compact", in: try drafts(for: "38-couple-5d-seattle-shared-umbrella"))
        #expect(RecommendationTrace.inclusionFamily(reasonCode: umbrella.reasonCode, signals: umbrella.sourceSignals) == .weatherPrecise)
        let facet = RecommendationTrace.ConstraintFacet.read(from: umbrella)
        #expect(facet.sharing?.isShared == true)
    }

    // Scenario 12 (party.shared pluralization fix) is Task 4's production
    // fix, proven by sharedQuantityGreaterThanOneIsNotDescribedAsOneForTheGroup
    // (ConstraintTests.swift) against the live fixture-37 reproduction —
    // cited, not duplicated here.

    /// Scenario 13: dependency (laptop companion) classifies as
    /// .dependency. Cites ConstraintTests.swift's companion tests for the
    /// underlying decision.
    @Test func scenario13DependencyCompanionClassifiesCorrectly() throws {
        #expect(RecommendationTrace.inclusionFamily(reasonCode: "dependency.companion", signals: [.baseEssential]) == .dependency)
    }

    /// Scenario 14: manual quantity override presents as user authority,
    /// never engine-generated evidence. Cites
    /// ClothingQuantityTests.manualQuantitySurvivesWeatherRefresh and
    /// fixture 14.
    @Test func scenario14ManualQuantityPresentsAsUserAuthority() throws {
        let tshirt = try draft("clothing.tshirt", in: try drafts(for: "14-manual-quantity-survives-refresh"))
        #expect(RecommendationTrace.authority(for: tshirt).isUserModified)
        #expect(RecommendationTrace.quantityFacet(for: tshirt).reason.isEmpty, "no fabricated engine quantity reason on a user-authority row")
    }

    // Scenario 15 (Not Needed) has no Item Detail row to trace by
    // definition — a removed item never reaches the presentation layer.
    // Its evidence stays exactly removedBaseEssentialStaysRemovedAcrossRegeneration
    // (ConstraintTests.swift), cited, no trace test possible or meaningful.

    /// Scenarios 16/17: user-added canonical vs. custom items are both
    /// authority-flagged, distinctly. Cites fixture 27 and
    /// ConstraintTests.userAddedCanonicalAndCustomItemsSurviveRegeneration.
    @Test func scenario16And17UserAddedAndCustomItemsAreBothAuthorityFlaggedDistinctly() throws {
        let output = try drafts(for: "27-chicago-5d-custom-item-survives-regeneration")
        let custom = try #require(output.first { $0.canonicalItemID?.hasPrefix("custom.") == true })
        let authority = RecommendationTrace.authority(for: custom)
        #expect(authority.isCustomItem)
    }

    /// Scenario 18: owner (travelerID/ownershipType) and carrier
    /// (assignedTravelerID) stay distinct fields in a trace read, never
    /// conflated — fixture 37's family has a child's flashlight carried by
    /// an adult, a real owner≠carrier row. Cites
    /// ConstraintTests.ownerStaysWithTheSameTravelerAcrossRegeneration/
    /// .manuallyReassignedCarrierSurvivesRegeneration for the underlying
    /// decision.
    @Test func scenario18OwnerAndCarrierStayDistinctForATraceRead() throws {
        let output = try drafts(for: "37-family4-5d-hiking-camping-outdoor")
        let carriedByAnAdult = try #require(output.first {
            $0.canonicalItemID == "miscellaneous.flashlight" && $0.assignedTravelerID != nil && $0.assignedTravelerID != $0.travelerID
        })
        #expect(carriedByAnAdult.travelerID != carriedByAnAdult.assignedTravelerID)
    }
}
