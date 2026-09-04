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
}
