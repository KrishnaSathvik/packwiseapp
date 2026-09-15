import Foundation
import Testing
@testable import PackWise

/// Product Experience V2, Task 7 — given eligible recommendations, is an item
/// personal or shared, and how does a shared quantity scale? Sharing never
/// decides eligibility and never changes owner or carrier semantics.
struct FamilySharingTests {
    private static let rules: PackingRulesFile = try! SharedLibrary.rules()
    private static let engine = PackingEngine(catalog: try! SharedLibrary.catalog(), rules: rules)

    private static func context(
        city: String = "Chicago",
        party: TripParty,
        activities: [String] = ["sightseeing", "walking"],
        weatherFixture: String? = nil,
        days: Int = 5
    ) throws -> TripContext {
        let destination = try #require(try SharedLibrary.testDestinations().first { $0.city == city })
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5))!
        let end = Calendar.current.date(byAdding: .day, value: days - 1, to: start)!
        var weather: TripWeatherContext?
        if let weatherFixture {
            let fixture = try #require(try SharedLibrary.weatherFixtures()[weatherFixture])
            weather = MockWeatherService.context(from: fixture, start: start, end: end, fixtureID: fixture.id)
        }
        var preferences = TravelerPreferences.deviceDefaults()
        preferences.homeCountryCode = "US"
        preferences.homeCountrySource = .userConfirmed
        let math = TripDateMath.daysAndNights(from: start, to: end)
        return TripContext(
            destination: destination, startDate: start, endDate: end,
            durationDays: math.days, durationNights: math.nights,
            tripTypes: [.vacation], activities: activities, datedActivities: [], bagTypes: [.checked],
            packingStyle: .balanced, transportation: .unknown, laundryAccess: .none,
            travelerCount: party.travelers.count, userNotes: "", contextChips: [],
            weather: weather, preferences: preferences, party: party
        )
    }

    private static let couple = TripParty(travelMode: .couple, travelers: [.primarySelf(), Traveler(role: .partner, ageGroup: .adult)])
    private static func familyWithToddler() -> TripParty {
        let you = Traveler.primarySelf()
        return TripParty(travelMode: .family, travelers: [
            you, Traveler(role: .partner, ageGroup: .adult),
            Traveler(role: .child, ageGroup: .toddler, guardianTravelerID: you.id)
        ])
    }
    private static func largerFamily() -> TripParty {
        let you = Traveler.primarySelf()
        return TripParty(travelMode: .family, travelers: [
            you, Traveler(role: .partner, ageGroup: .adult), Traveler(role: .otherAdult, ageGroup: .adult),
            Traveler(role: .child, ageGroup: .child, guardianTravelerID: you.id)
        ])
    }
    private static let group = TripParty(travelMode: .group, travelers: [.primarySelf()] + (1...3).map { _ in Traveler(role: .otherAdult, ageGroup: .adult) })

    private static func rows(_ items: [PackingItemDraft], _ id: String) -> [PackingItemDraft] {
        items.filter { $0.canonicalItemID == id }
    }

    private static let sharedToiletries = ["toiletries.toothpaste", "toiletries.shampoo", "toiletries.body_wash"]

    // MARK: - Scenarios

    @Test func coupleSharesToiletriesButKeepsToothbrushesAndChargersPersonal() throws {
        let items = Self.engine.generate(context: try Self.context(city: "Seattle", party: Self.couple, weatherFixture: "SeattleWetCity"))
        let brushes = Self.rows(items, "toiletries.toothbrush")
        #expect(brushes.count == 2 && brushes.allSatisfy { $0.ownershipType == .personal })
        #expect(Set(brushes.compactMap(\.travelerID)) == Set(Self.couple.travelers.map(\.id)))
        for id in Self.sharedToiletries + ["health.pain_reliever", "travel_comfort.laundry_bag"] {
            let found = Self.rows(items, id)
            #expect(found.count == 1 && found[0].ownershipType == .shared && found[0].quantity == 1, "\(id): \(found.map(\.quantity))")
        }
        let umbrella = try #require(Self.rows(items, "essentials.umbrella_compact").first)
        #expect(umbrella.ownershipType == .shared && umbrella.quantity == 1)
        let chargers = Self.rows(items, "electronics.phone_charger")
        #expect(chargers.count == 2 && chargers.allSatisfy { $0.ownershipType == .personal }, "one per device owner")
    }

    @Test func familyWithToddlerKeepsClothingPersonalAndSharesConsumablesOnce() throws {
        let party = Self.familyWithToddler()
        let items = Self.engine.generate(context: try Self.context(party: party))
        for id in ["clothing.tshirt", "clothing.socks", "footwear.walking_shoes", "clothing.sleepwear"] {
            let found = Self.rows(items, id)
            #expect(found.count == 3 && found.allSatisfy { $0.ownershipType == .personal }, "\(id) stays personal per traveler")
        }
        for id in Self.sharedToiletries {
            let found = Self.rows(items, id)
            #expect(found.count == 1 && found[0].ownershipType == .shared && found[0].quantity == 1, "\(id)")
        }
        #expect(!items.contains { $0.ownershipType == .personal && Self.sharedToiletries.contains($0.canonicalItemID ?? "") })
    }

    @Test func largerFamilyScalesSharedQuantitiesByPolicyInsteadOfRepeatingRows() throws {
        let party = Self.largerFamily()
        let items = Self.engine.generate(context: try Self.context(party: party))
        for item in items where item.ownershipType == .shared {
            #expect(Self.rows(items, item.canonicalItemID ?? "").count == 1, "\(item.canonicalItemID ?? "") appears once")
        }
        #expect(Self.rows(items, "travel_comfort.laundry_bag").first?.quantity == 2, "scaleByParty per 3: four travelers → 2")
        #expect(Self.rows(items, "toiletries.toothpaste").first?.quantity == 1, "scaleByParty per 4: four travelers → 1")
        #expect(Self.rows(items, "clothing.tshirt").count == 4, "personal clothing is one row per traveler")
    }

    @Test func groupOfAdultsSharesWithoutAssumingFamilyRelationships() throws {
        let items = Self.engine.generate(context: try Self.context(city: "Tokyo", party: Self.group))
        #expect(!items.contains { $0.canonicalItemID?.hasPrefix("kids.") == true })
        #expect(items.allSatisfy { $0.assignedTravelerID == nil || $0.ownershipType == .personal }, "no shared item gets a guessed carrier")
        #expect(Self.rows(items, "documents.passport").count == 4, "passports stay personal")
        #expect(Self.rows(items, "documents.travel_insurance").map(\.ownershipType) == [.shared])
        #expect(Self.rows(items, "electronics.travel_adapter").first?.quantity == 2, "scaleByDevices per 2: four device owners → 2")
        #expect(Self.rows(items, "toiletries.shampoo").first?.quantity == 1)
    }

    @Test func soloListsStayPersonalWithUnchangedQuantities() throws {
        let items = Self.engine.generate(context: try Self.context(party: .solo()))
        #expect(items.allSatisfy { $0.ownershipType == .personal })
        for id in Self.sharedToiletries {
            #expect(Self.rows(items, id).map(\.quantity) == [1], "\(id)")
        }
    }

    @Test func flashlightStaysPersonalAndBeachTowelsAreOnePerTraveler() throws {
        let party = Self.largerFamily()
        let camping = Self.engine.generate(context: try Self.context(city: "Yellowstone", party: party, activities: ["camping"]))
        let lights = Self.rows(camping, "miscellaneous.flashlight")
        #expect(!lights.isEmpty && lights.allSatisfy { $0.ownershipType == .personal })
        #expect(!Self.rules.party.sharedByDefault.contains("miscellaneous.flashlight"))

        let beach = Self.engine.generate(context: try Self.context(city: "Miami", party: party, activities: ["beachDays"]))
        let towels = Self.rows(beach, "activities.beach_towel")
        #expect(towels.count == party.travelers.count && towels.allSatisfy { $0.ownershipType == .personal })
    }

    /// The less common shared policies introduced by the audit, each on a
    /// trip that really emits them: every one lands once, in the shared group.
    @Test func auditedTripExtrasResolveOncePerParty() throws {
        let you = Traveler.primarySelf()
        let party = TripParty(travelMode: .family, travelers: [
            you, Traveler(role: .partner, ageGroup: .adult), Traveler(role: .otherAdult, ageGroup: .adult),
            Traveler(role: .child, ageGroup: .child, guardianTravelerID: you.id),
            Traveler(role: .child, ageGroup: .toddler, guardianTravelerID: you.id),
            Traveler(role: .child, ageGroup: .infant, guardianTravelerID: you.id, needs: [.carrier])
        ])
        var context = try Self.context(city: "Miami", party: party, activities: ["boatTrip", "wildlife", "beachDays", "shopping"])
        context.contextChips = [.laundryAvailable]
        let items = Self.engine.generate(context: context)
        let expected: [String: Int] = [
            "activities.binoculars": 1, "health.motion_sickness": 1, "kids.sunscreen": 1,
            "toiletries.laundry_sheets": 1, "kids.carrier": 1, "essentials.reusable_bag": 1,
            "activities.dry_bag": 2  // scaleByParty per 4: six travelers → 2
        ]
        for (id, quantity) in expected {
            let found = Self.rows(items, id)
            #expect(found.count == 1 && found.first?.ownershipType == .shared && found.first?.quantity == quantity,
                    "\(id): \(found.map { "\($0.ownershipType.rawValue)×\($0.quantity)" })")
        }
    }

    // MARK: - Evidence

    /// Every shared quantity above one names its scaling basis in the one
    /// Phase 8 quantity trace, and its prose pluralizes.
    @Test func everySharedQuantityAboveOneCarriesItsScalingBasis() throws {
        let party = Self.largerFamily()
        let items = Self.engine.generate(context: try Self.context(city: "Seattle", party: party, weatherFixture: "SeattleWetCity"))
        let multiples = items.filter { $0.ownershipType == .shared && $0.quantity > 1 }
        #expect(!multiples.isEmpty)
        for item in multiples {
            let args = item.quantityReasonArguments
            let policy = try #require(args["sharingPolicy"].flatMap(SharingPolicy.init(rawValue:)), "\(item.canonicalItemID ?? "")")
            #expect(args["quantity"] == "\(item.quantity)")
            switch policy {
            case .scaleByParty, .scaleByDurationAndParty: #expect(args["travelerCount"] == "4" && args["per"] != nil)
            case .scaleByDevices: #expect(args["deviceCount"] == "3" && args["per"] != nil)
            case .singlePerParty, .personalOnly: Issue.record("\(item.canonicalItemID ?? ""): \(policy) resolved above one")
            }
            #expect(item.quantityReason.contains("\(item.quantity)"), "\(item.quantityReason)")
            #expect(!item.quantityReason.hasPrefix("One"), "a plural quantity never reads as one: \(item.quantityReason)")
        }
        let single = try #require(Self.rows(items, "health.pain_reliever").first)
        #expect(single.quantityReasonArguments["sharingPolicy"] == SharingPolicy.singlePerParty.rawValue)
        #expect(single.quantityReason.hasPrefix("One"))
    }

    // MARK: - Invariants

    @Test func sharingNeverChangesOwnerOrCarrierSemantics() throws {
        let party = Self.familyWithToddler()
        let context = try Self.context(party: party)
        var existing = Self.engine.generate(context: context)
        #expect(PartyInvariants.violations(party: party, items: existing).isEmpty)

        let partner = try #require(party.travelers.first { $0.role == .partner })
        let toothpaste = try #require(existing.firstIndex { $0.canonicalItemID == "toiletries.toothpaste" })
        existing[toothpaste].assignedTravelerID = partner.id
        let sharedID = existing[toothpaste].id
        let custom = PackingItemDraft(canonicalItemID: nil, displayName: "Night-time story book", category: .kids,
                                      quantity: 1, importance: .optional, sourceSignals: [], reason: "", isUserAdded: true,
                                      ownershipType: .personal, travelerID: party.travelers[2].id, assignedTravelerID: partner.id)
        existing.append(custom)

        let regenerated = Self.engine.generate(context: context, existing: existing)
        let kept = try #require(regenerated.first { $0.id == sharedID })
        #expect(kept.ownershipType == .shared && kept.travelerID == nil, "a shared item stays shared")
        #expect(kept.assignedTravelerID == partner.id, "an explicit carrier survives and does not make it personal")
        let keptCustom = try #require(regenerated.first { $0.id == custom.id })
        #expect(keptCustom.travelerID == party.travelers[2].id && keptCustom.assignedTravelerID == partner.id, "owner and carrier stay distinct")
        #expect(PartyInvariants.violations(party: party, items: regenerated).isEmpty)
    }

    /// Sharing reads no age and no traveler signal: eligibility is decided
    /// once, upstream, by `TravelerEligibilityResolver`.
    @Test func sharingAuthorityNeverReimplementsEligibility() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PackWise/Domain/Packing/ConstraintResolver.swift"), encoding: .utf8)
        for token in ["ageGroup", ".needs", ".chips", "isYoungChild", "EligibilityFamily", "TravelerEligibilityResolver"] {
            #expect(!source.contains(token), "ConstraintResolver mentions \(token)")
        }
        for policy in Self.rules.party.sharingPolicies.keys {
            #expect(Self.rules.party.sharedByDefault.contains(policy), "\(policy) has a policy but is never shared")
        }
    }
}
