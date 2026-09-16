import Foundation
import Testing
@testable import PackWise

struct RecommendationReasonRendererTests {
    private func item(_ codes: [String] = [], types: [TripType] = [], id: String = "clothing.hat_sun") -> PackingItemDraft {
        PackingItemDraft(canonicalItemID: id, displayName: "Item", category: .clothing,
                         quantity: 1, importance: .normal, sourceSignals: [], reason: "NEVER DISPLAY",
                         travelerID: UUID(), provenance: codes.map {
            RecommendationProvenance(reasonCode: $0, reasonArguments: [:], sourceSignals: [])
        } + types.map { .tripType($0) })
    }
    private func text(_ item: PackingItemDraft) -> String? { RecommendationReasonRenderer.reason(for: item)?.text }

    @Test func everyTripTypeHasNaturalCopy() {
        let expected: [TripType: String] = [
            .vacation: "Useful for this trip.", .other: "Useful for this trip.",
            .cityBreak: "Useful for city days.", .beach: "Useful for the beach.",
            .business: "For work.", .outdoor: "For outdoor activities.",
            .roadTrip: "For the road trip.", .weddingEvent: "For the event.",
            .skiSnow: "For snow activities.", .festival: "For the festival.",
            .visitingFamily: "Useful while visiting family."
        ]
        for type in TripType.allCases { #expect(text(item(types: [type])) == expected[type]) }
    }

    @Test func compatibleSourcesCombineAndSpecificSourcesWin() {
        #expect(text(item(types: [.beach, .festival])) == "Useful for beach and festival days.")
        #expect(text(item(types: [.business, .weddingEvent])) == "For work and the event.")
        #expect(text(item(["activity.sightseeing"], types: [.cityBreak])) == "Useful for sightseeing and days around the city.")
        #expect(text(item(["weather.hot", "weather.uv"], types: [.beach])) == "For hot, sunny weather.")
        #expect(text(item(["weather.rain_days"], types: [.outdoor])) == "Rain is expected during your trip.")
        #expect(text(item(["activity.hiking", "weather.rain_days"], types: [.outdoor])) == "For hiking.")
        #expect(text(item(["activity.nightlife"], id: "clothing.nice_outfit")) == "For nights out.")
        #expect(text(item(["activity.niceDinner"], id: "clothing.nice_outfit")) == "For a nicer dinner.")
    }

    @Test func ownedDevicesAndChildNeedsStayOnTheirRecord() {
        #expect(text(item(["preference.bringingLaptop"], types: [.vacation], id: "electronics.laptop_charger")) == "For the laptop you're bringing.")
        let tablet = item(["preference.bringingTablet"], id: "electronics.tablet")
        #expect(RecommendationReasonRenderer.reason(for: tablet, context: .init(ownerName: "Adult 1", isPrimaryTraveler: false))?.text == "For the tablet they're bringing.")
        var child = item(id: "kids.diapers")
        child.provenance = [.init(reasonCode: "party.age_group", reasonArguments: ["name": "Child 1"], sourceSignals: [.userPreference])]
        #expect(text(child) == "For Child 1.")
        #expect(RecommendationReasonRenderer.reason(for: child, context: .init(ownerName: "Mia", isPrimaryTraveler: false))?.text == "For Mia.")
        let other = item(types: [.vacation], id: "electronics.laptop_charger")
        #expect(text(other) == "Useful for this trip.")
        child.travelerID = nil
        #expect(text(child) == "Useful for this trip.")
    }

    @Test func manualItemsAndMissingEvidenceDoNotInventReasons() {
        var manual = item(["activity.hiking"])
        manual.isUserAdded = true
        #expect(text(manual) == nil)
        manual.isUserAdded = false
        manual.canonicalItemID = "custom.test"
        #expect(text(manual) == nil)
        #expect(text(item()) == nil)
        var edited = item(["activity.hiking"])
        edited.isUserModified = true
        #expect(text(edited) == "For hiking.")
        #expect(RecommendationReasonRenderer.quantityExplanation(for: edited) == nil)
    }

    @Test func weatherMustBeInThisItemsTrace() {
        #expect(text(item(["weather.hot"])) == "For hot weather.")
        #expect(text(item(["weather.uv"])) == "Useful for strong sun.")
        #expect(text(item(["weather.seasonal_sun"]))?.contains("expected") == false)
        #expect(text(item(["activity.photography"], types: [.outdoor])) == "For outdoor activities.")
        // Metadata is intentionally not an input; unselected suggested activities
        // and another record's weather cannot contribute facts to this renderer.
        #expect(text(item(types: [.outdoor]))?.contains("hiking") == false)
    }

    @Test func sharingAndQuantityRemainSeparate() {
        var sunscreen = item(["weather.uv"], id: "toiletries.sunscreen")
        sunscreen.ownershipType = .shared
        sunscreen.quantity = 2
        sunscreen.quantityReasonArguments = ["sharingPolicy": "scaleByParty"]
        #expect(text(sunscreen) == "Useful for strong sun.")
        #expect(RecommendationReasonRenderer.quantityExplanation(for: sunscreen) == "2 for the group.")
        sunscreen.canonicalItemID = "travel_comfort.laundry_bag"
        sunscreen.provenance = [.init(reasonCode: "base.essential.travel_comfort", reasonArguments: [:], sourceSignals: [.baseEssential])]
        #expect(text(sunscreen) == "Useful for this trip.")
        #expect(RecommendationReasonRenderer.quantityExplanation(for: sunscreen) == "2 for the group.")
        var shirts = item(["base.essential.clothing"])
        shirts.quantityEvidence = ClothingQuantityEvidence(policyID: "test", basis: "test", requiredUses: 7,
            wearsPerItem: 1, laundryPlan: .none, laundryReduced: false, styleBuffer: 0,
            bagCap: 3, bagCapApplied: true, appearanceOffsetUses: 0, quantity: 3)
        #expect(text(shirts) == "Everyday clothing for the trip.")
        #expect(RecommendationReasonRenderer.quantityExplanation(for: shirts) == "Packed lighter to fit your luggage.")
        shirts.quantityEvidence?.bagCapApplied = false
        #expect(RecommendationReasonRenderer.quantityExplanation(for: shirts) == nil)
    }

    @Test func permutationsAndPersistenceDoNotChangeCopyOrDiscardFacts() {
        let original = item(["weather.hot", "weather.uv", "activity.sightseeing"], types: [.festival, .beach, .cityBreak])
        let expected = text(original)
        for shift in original.provenance.indices {
            var shuffled = original
            let facts = original.provenance
            shuffled.provenance = Array((Array(facts[shift...]) + Array(facts[..<shift])).reversed())
            #expect(text(shuffled) == expected)
            shuffled.provenance = RecommendationTrace.ProvenanceEncoding.decode(RecommendationTrace.ProvenanceEncoding.encode(shuffled.provenance))
            #expect(text(shuffled) == expected)
            #expect(Set(shuffled.provenance) == Set(original.provenance))
        }
    }

    @Test func taxonomyNeverBecomesCustomerCopy() {
        let banned = ["your other", "leisureGeneralTravel", "cityDayUse", "outdoorDayUse", "scaleByParty", "coverage requirement", "candidate", "canonical item", "provenance", "eligibility", "constraint resolver"]
        for code in banned {
            let rendered = text(item([code], types: [.other])) ?? ""
            for word in banned { #expect(!rendered.contains(word)) }
        }
    }

    @Test func allGeneratedFixtureReasonsAreSafeAndReadOnly() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try JSONDecoder().decode(GoldenEngineTests.GoldenFixtureFile.self,
            from: Data(contentsOf: root.appendingPathComponent("shared/fixtures/golden/golden-fixtures.json")))
        var examples: [String: String] = [:]
        for fixture in manifest.fixtures {
            for draft in try GoldenEngineTests().engineDrafts(for: fixture.id) {
                let before = draft
                let rendered = RecommendationReasonRenderer.reason(for: draft)
                #expect(before == draft)
                if let rendered {
                    #expect(rendered.text.count < 120)
                    for banned in ["your other", "scaleByParty", "candidate", "provenance", "eligibility", "explicitChildNeed", "leisureGeneralTravel", "cityDayUse", "outdoorDayUse"] {
                        #expect(!rendered.text.contains(banned))
                    }
                    if let id = draft.canonicalItemID, examples[id] == nil { examples[id] = rendered.text }
                }
            }
        }
        let data = try JSONEncoder().encode(examples)
        print("TASK13_EXAMPLES " + String(decoding: data, as: UTF8.self))
    }

    @Test func viewsCannotUseLegacyReasonOrSingularTripType() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for file in ["PackingListView.swift", "TripDetailView.swift", "RecommendationDiffSheet.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent("PackWise/Features/TripDetail/\(file)"), encoding: .utf8)
            #expect(!source.contains("PackingReasonPresentation"))
            #expect(source.range(of: #"\btrip\??\.tripType\b"#, options: .regularExpression) == nil)
            #expect(source.range(of: #"\bitem\.reason\b"#, options: .regularExpression) == nil)
        }
    }
}
