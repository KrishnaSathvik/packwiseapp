import Foundation
import Testing
@testable import PackWise

/// Product Experience V2, Task 6 — one traveler eligibility authority, applied
/// before quantities and sharing. Eligibility answers whether a generated
/// recommendation is appropriate for a traveler; never how many, whether it
/// is shared, who carries it, or what covers it.
struct TravelerEligibilityTests {
    private static let catalog: PackingCatalog = try! SharedLibrary.catalog()
    private static let rules: PackingRulesFile = try! SharedLibrary.rules()
    private static let engine = PackingEngine(catalog: catalog, rules: rules)

    private static let devices = [
        "essentials.phone", "electronics.phone_charger", "electronics.headphones",
        "electronics.laptop", "electronics.laptop_charger", "electronics.power_bank"
    ]
    private static let childEquipment = ["kids.stroller", "kids.car_seat", "kids.diapers", "kids.wipes", "kids.comfort_item", "kids.baby_medication"]

    private static func context(
        city: String = "Chicago",
        party: TripParty,
        tripTypes: Set<TripType> = [.vacation],
        activities: [String] = ["sightseeing", "walking"],
        chips: Set<ContextChip> = [],
        homeCountry: String = "US",
        days: Int = 5,
        month: Int = 10,
        weatherFixture: String? = nil,
        preferences edit: (inout TravelerPreferences) -> Void = { _ in }
    ) throws -> TripContext {
        let destination = try #require(try SharedLibrary.testDestinations().first { $0.city == city })
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: month, day: 5))!
        let end = Calendar.current.date(byAdding: .day, value: days - 1, to: start)!
        var weather: TripWeatherContext?
        if let weatherFixture {
            let fixture = try #require(try SharedLibrary.weatherFixtures()[weatherFixture])
            weather = MockWeatherService.context(from: fixture, start: start, end: end, fixtureID: fixture.id)
        }
        var preferences = TravelerPreferences.deviceDefaults()
        preferences.homeCountryCode = homeCountry
        preferences.homeCountrySource = .userConfirmed
        edit(&preferences)
        let math = TripDateMath.daysAndNights(from: start, to: end)
        return TripContext(
            destination: destination, startDate: start, endDate: end,
            durationDays: math.days, durationNights: math.nights,
            tripTypes: tripTypes, activities: activities, datedActivities: [], bagTypes: [.checked],
            packingStyle: .balanced, transportation: .unknown, laundryAccess: .none,
            travelerCount: party.travelers.count, userNotes: "", contextChips: chips,
            weather: weather, preferences: preferences, party: party,
            origin: TripOrigin(seededFrom: preferences)
        )
    }

    private static func ids(_ items: [PackingItemDraft], for traveler: Traveler) -> Set<String> {
        Set(items.filter { $0.ownershipType == .personal && $0.travelerID == traveler.id }.compactMap(\.canonicalItemID))
    }

    private static func family(adults: Int = 2, child: Traveler) -> (TripParty, Traveler) {
        var travelers = [Traveler.primarySelf()]
        for index in 1..<max(1, adults) {
            travelers.append(Traveler(role: index == 1 ? .partner : .otherAdult, ageGroup: .adult))
        }
        var child = child
        child.guardianTravelerID = travelers[0].id
        travelers.append(child)
        return (TripParty(travelMode: .family, travelers: travelers), child)
    }

    // MARK: - Metadata

    @Test func everyCatalogItemHasClosedEligibilityMetadata() {
        let missing = Self.catalog.items.map(\.id).filter { Self.rules.party.eligibility.families[$0] == nil }
        #expect(missing.isEmpty, "unclassified: \(missing)")
        #expect(Set(Self.rules.party.eligibility.families.keys).isSubset(of: Set(Self.catalog.items.map(\.id))))
    }

    /// An age group's automatic adds must be eligible for that age with no
    /// explicit signal, and each need's candidates must require exactly that
    /// need — otherwise the rule file and the authority disagree.
    @Test func ageGroupRulesAgreeWithTheEligibilityAuthority() throws {
        for (raw, rule) in Self.rules.party.ageGroups {
            let age = try #require(AgeGroup(rawValue: raw))
            let traveler = Traveler(role: age.isAdult ? .otherAdult : .child, ageGroup: age)
            for id in rule.add {
                let decision = TravelerEligibilityResolver.evaluate(
                    canonicalItemID: id, traveler: traveler, explicitNeeds: [], signals: [], catalog: Self.catalog, rules: Self.rules.party.eligibility
                )
                #expect(decision.isEligible, "\(age) add \(id): \(decision)")
            }
            for (needRaw, ids) in rule.candidates {
                let need = try #require(ChildNeed(rawValue: needRaw))
                for id in ids {
                    let without = TravelerEligibilityResolver.evaluate(
                        canonicalItemID: id, traveler: traveler, explicitNeeds: [], signals: [], catalog: Self.catalog, rules: Self.rules.party.eligibility
                    )
                    let with = TravelerEligibilityResolver.evaluate(
                        canonicalItemID: id, traveler: traveler, explicitNeeds: [need], signals: [], catalog: Self.catalog, rules: Self.rules.party.eligibility
                    )
                    #expect(!without.isEligible && with.isEligible, "\(age) \(need) candidate \(id)")
                }
            }
        }
    }

    @Test func missingMetadataResolvesConservatively() {
        var empty = Self.rules.party.eligibility
        empty.families = [:]
        let adult = TravelerEligibilityResolver.evaluate(
            canonicalItemID: "electronics.phone_charger", traveler: .primarySelf(), explicitNeeds: [], signals: [], catalog: Self.catalog, rules: empty
        )
        let toddler = TravelerEligibilityResolver.evaluate(
            canonicalItemID: "electronics.phone_charger", traveler: Traveler(role: .child, ageGroup: .toddler), explicitNeeds: [], signals: [], catalog: Self.catalog, rules: empty
        )
        #expect(adult.isEligible, "adult behavior never depends on metadata")
        #expect(toddler == .ineligible(.missingMetadata), "never permissively attaches to a child")
    }

    // MARK: - Toddler

    @Test func toddlerWithNoSignalsGetsClothingButNoDevicesMedicationContactsOrEquipment() throws {
        let (party, toddler) = Self.family(child: Traveler(name: "Emma", role: .child, ageGroup: .toddler))
        let items = Self.engine.generate(context: try Self.context(city: "Minneapolis", party: party, month: 1))
        let mine = Self.ids(items, for: toddler)
        let banned = Self.devices + Self.childEquipment + [
            "toiletries.deodorant", "health.daily_medication", "health.pain_reliever",
            "toiletries.contacts_solution", "toiletries.contact_case", "documents.id",
            "essentials.wallet", "essentials.keys"
        ]
        #expect(mine.isDisjoint(with: banned), "toddler got \(mine.intersection(banned))")
        #expect(!items.contains { $0.canonicalItemID.map(Self.childEquipment.contains) == true }, "no child equipment anywhere without a need")
        #expect(mine.isSuperset(of: ["clothing.tshirt", "clothing.pants", "clothing.socks", "clothing.sleepwear", "footwear.walking_shoes"]))
        #expect(mine.contains { ["clothing.light_sweater", "clothing.light_jacket", "clothing.winter_coat"].contains($0) }, "weather-supported layer")
    }

    @Test func eachToddlerNeedContributesOnlyItsOwnFamily() throws {
        let baseline = try toddlerIDs(needs: [])
        let expected: [ChildNeed: Set<String>] = [
            .diapers: ["kids.diapers", "kids.wipes"],
            .stroller: ["kids.stroller"],
            .carSeat: ["kids.car_seat"],
            .medication: ["kids.baby_medication"],
            .comfortItem: ["kids.comfort_item"]
        ]
        for (need, family) in expected {
            let added = try toddlerIDs(needs: [need]).subtracting(baseline)
            #expect(added == family, "\(need) added \(added)")
        }
    }

    private func toddlerIDs(needs: Set<ChildNeed>) throws -> Set<String> {
        let (party, _) = Self.family(child: Traveler(role: .child, ageGroup: .toddler, needs: needs))
        return Set(Self.engine.generate(context: try Self.context(party: party)).compactMap(\.canonicalItemID))
    }

    @Test func infantWithNoNeedsGetsNoAdultBaselineItems() throws {
        let (party, infant) = Self.family(child: Traveler(role: .child, ageGroup: .infant))
        let mine = Self.ids(Self.engine.generate(context: try Self.context(city: "Miami", party: party, month: 7)), for: infant)
        let banned = Self.devices + [
            "activities.daypack", "essentials.sunglasses", "footwear.walking_shoes",
            "toiletries.toothbrush", "toiletries.toothpaste", "toiletries.shampoo", "toiletries.body_wash",
            "kids.diapers", "kids.formula", "kids.bottles", "kids.pacifiers", "kids.stroller", "kids.carrier"
        ]
        #expect(mine.isDisjoint(with: banned), "infant got \(mine.intersection(banned))")
        #expect(mine.isSuperset(of: ["kids.extra_outfits", "kids.sleep_sack", "kids.burp_cloths"]))
    }

    @Test func schoolAgeChildAndTeenFollowAgeWithoutDeviceInference() throws {
        let (childParty, child) = Self.family(child: Traveler(role: .child, ageGroup: .child))
        let childIDs = Self.ids(Self.engine.generate(context: try Self.context(party: childParty)), for: child)
        #expect(childIDs.isDisjoint(with: Self.devices + ["electronics.earbuds_case", "essentials.wallet", "essentials.keys", "documents.id", "toiletries.deodorant"]),
                "child got \(childIDs)")
        #expect(childIDs.isSuperset(of: ["clothing.tshirt", "footwear.walking_shoes", "toiletries.toothbrush"]))

        let (teenParty, teen) = Self.family(child: Traveler(role: .child, ageGroup: .teen))
        let teenIDs = Self.ids(Self.engine.generate(context: try Self.context(party: teenParty)), for: teen)
        #expect(teenIDs.isSuperset(of: ["documents.id", "toiletries.deodorant"]), "a teen keeps age-appropriate ID and care items")
        #expect(teenIDs.isDisjoint(with: Self.devices + ["electronics.earbuds_case"]),
                "Task 7.1: age is not device ownership — teen got \(teenIDs.intersection(Self.devices + ["electronics.earbuds_case"]))")
    }

    // MARK: - Attribution

    @Test func primaryLaptopAndMedicationNeverReachTheChild() throws {
        let (party, toddler) = Self.family(child: Traveler(role: .child, ageGroup: .toddler))
        let items = Self.engine.generate(context: try Self.context(party: party, chips: [.bringingLaptop, .dailyMedication, .wearContacts]))
        let primary = Self.ids(items, for: party.primary)
        #expect(primary.isSuperset(of: ["electronics.laptop", "electronics.laptop_charger", "health.daily_medication"]))
        let child = Self.ids(items, for: toddler)
        #expect(child.isDisjoint(with: ["electronics.laptop", "electronics.laptop_charger", "health.daily_medication",
                                        "health.prescription_copy", "toiletries.contacts_solution", "kids.baby_medication"]))
        let partner = try #require(party.travelers.first { $0.role == .partner })
        #expect(Self.ids(items, for: partner).isDisjoint(with: ["electronics.laptop", "health.daily_medication"]), "no cross-adult propagation")
    }

    @Test func childMedicationComesOnlyFromTheChildsOwnNeed() throws {
        let (party, toddler) = Self.family(child: Traveler(role: .child, ageGroup: .toddler, needs: [.medication]))
        let items = Self.engine.generate(context: try Self.context(party: party))
        #expect(Self.ids(items, for: toddler).contains("kids.baby_medication"))
        #expect(!Self.ids(items, for: party.primary).contains("kids.baby_medication"))
        #expect(!Self.ids(items, for: toddler).contains("health.daily_medication"))
    }

    /// Trip-wide device context (a Work activity, a Business trip type) names
    /// no traveler, so it can never make a child eligible for a device.
    @Test func unattributedDeviceContextClaimsNoChild() throws {
        let (party, child) = Self.family(child: Traveler(role: .child, ageGroup: .child))
        let items = Self.engine.generate(context: try Self.context(party: party, tripTypes: [.business], activities: ["work"]))
        #expect(Self.ids(items, for: child).isDisjoint(with: ["electronics.laptop", "electronics.laptop_charger", "electronics.headphones"]))
    }

    @Test func aChildsOwnDeviceSignalIsHonored() {
        let child = Traveler(role: .child, ageGroup: .child, chips: [.bringingLaptop])
        let decision = TravelerEligibilityResolver.evaluate(
            canonicalItemID: "electronics.laptop", traveler: child, explicitNeeds: [], signals: [.bringingLaptop],
            catalog: Self.catalog, rules: Self.rules.party.eligibility
        )
        #expect(decision.isEligible)
        let phone = TravelerEligibilityResolver.evaluate(
            canonicalItemID: "electronics.phone_charger", traveler: child, explicitNeeds: [], signals: [.bringingLaptop],
            catalog: Self.catalog, rules: Self.rules.party.eligibility
        )
        #expect(phone == .requiresExplicitSignal(.phone), "a laptop signal is not a phone signal")
    }

    // MARK: - Device ownership (Task 7.1)

    /// Age answers "can this traveler use it?", never "does this traveler
    /// own it?". A laptop needs a signal attributed to its traveler; trip-wide
    /// Business/Work context names no one on a party list.
    @Test func deviceOwnershipRequiresATravelerScopedSignal() throws {
        let laptop: Set<String> = ["electronics.laptop", "electronics.laptop_charger"]
        let adult1 = Traveler(role: .otherAdult, ageGroup: .adult)
        let businessFamily = TripParty(travelMode: .group, travelers: [.primarySelf(), adult1])

        struct Row {
            var name: String
            var party: TripParty
            var tripTypes: Set<TripType>
            /// You's own Laptop choice (Task 8.2: never the Me preference).
            var youChoseLaptop: Bool
            /// Role → whether that traveler gets the laptop and its charger.
            var expected: [(TravelerRole, AgeGroup, Bool)]
        }
        let rows = [
            Row(name: "solo adult + Laptop", party: .solo(), tripTypes: [.vacation], youChoseLaptop: true,
                expected: [(.self, .adult, true)]),
            Row(name: "solo Business, no preference: the trip is the traveler's own", party: .solo(), tripTypes: [.business], youChoseLaptop: false,
                expected: [(.self, .adult, true)]),
            Row(name: "Business party, only You has Laptop", party: businessFamily, tripTypes: [.business], youChoseLaptop: true,
                expected: [(.self, .adult, true), (.otherAdult, .adult, false)]),
            Row(name: "Business party, no signal anywhere → nobody", party: businessFamily, tripTypes: [.business], youChoseLaptop: false,
                expected: [(.self, .adult, false), (.otherAdult, .adult, false)]),
        ]
        for row in rows {
            let items = Self.engine.generate(context: try Self.context(
                party: row.party, tripTypes: row.tripTypes, activities: ["work"], chips: row.youChoseLaptop ? [.bringingLaptop] : []
            ))
            for (role, age, gets) in row.expected {
                let traveler = try #require(row.party.travelers.first { $0.role == role && $0.ageGroup == age })
                let mine = row.party.usesSimpleList
                    ? Set(items.compactMap(\.canonicalItemID))
                    : Self.ids(items, for: traveler)
                #expect(mine.isSuperset(of: laptop) == gets && (gets || mine.isDisjoint(with: laptop)),
                        "\(row.name): \(role) laptop rows \(mine.intersection(laptop))")
            }
        }
    }

    @Test func phoneAndInterimDevicesReachOnlyThePrimaryTraveler() throws {
        let partner = Traveler(role: .partner, ageGroup: .adult)
        let (party, teen) = { () -> (TripParty, Traveler) in
            let you = Traveler.primarySelf()
            let teen = Traveler(role: .child, ageGroup: .teen, guardianTravelerID: you.id)
            return (TripParty(travelMode: .family, travelers: [you, partner, teen]), teen)
        }()
        let items = Self.engine.generate(context: try Self.context(party: party))
        #expect(Self.ids(items, for: party.primary).isSuperset(of: ["essentials.phone", "electronics.phone_charger"]),
                "You run PackWise on your own phone")
        for companion in [partner, teen] {
            #expect(Self.ids(items, for: companion).isDisjoint(with: Self.devices + ["electronics.earbuds_case"]),
                    "\(companion.role): no device signal, no device")
        }
        let decision = TravelerEligibilityResolver.evaluate(
            canonicalItemID: "essentials.phone", traveler: partner, explicitNeeds: [], signals: [],
            catalog: Self.catalog, rules: Self.rules.party.eligibility
        )
        #expect(decision == .requiresExplicitSignal(.phone))
    }

    /// D1 (Tasks 7.2–8.1): PackWise running on the primary traveler's phone
    /// is an implicit phone-ownership signal — a phone and what charges it,
    /// nothing more. Every other device, the primary's included, needs its
    /// own explicit signal; the interim carryover is gone.
    @Test func implicitPrimaryPhoneIsNotGenericDeviceOwnership() {
        let phoneFamily = Set(Self.rules.party.eligibility.families.filter { $0.value == .phoneOwnership }.keys)
        #expect(phoneFamily == ["essentials.phone", "electronics.phone_charger", "miscellaneous.car_charger"])

        func decide(_ id: String, _ traveler: Traveler, signals: Set<ContextChip> = []) -> EligibilityDecision {
            TravelerEligibilityResolver.evaluate(canonicalItemID: id, traveler: traveler, explicitNeeds: [], signals: signals,
                                                 catalog: Self.catalog, rules: Self.rules.party.eligibility)
        }
        let you = Traveler.primarySelf()
        #expect(decide("essentials.phone", you) == .eligible(.implicitPrimaryPhone))
        #expect(decide("electronics.phone_charger", you) == .eligible(.implicitPrimaryPhone), "the charger follows the owned phone")
        let explicit: [(String, ContextChip)] = [
            ("electronics.headphones", .bringingHeadphones), ("electronics.power_bank", .bringingPowerBank),
            ("electronics.camera", .bringingCamera), ("electronics.camera_charger", .bringingCamera), ("electronics.memory_card", .bringingCamera),
        ]
        for (id, chip) in explicit {
            #expect(decide(id, you) == .requiresExplicitSignal(.device(chip)), "\(id) is not proven by the phone")
            #expect(decide(id, you, signals: [chip]) == .eligible(.travelerSignal), "\(id) with You's own choice")
            #expect(decide(id, you, signals: [.bringingPhone, .bringingLaptop]) != .eligible(.travelerSignal), "\(id): another device never stands in")
        }
        for id in ["electronics.earbuds_case", "electronics.kindle", "electronics.watch_charger"] {
            #expect(decide(id, you) == .requiresExplicitSignal(.device(nil)), "\(id): no signal, no automatic row, even for You")
        }
        #expect(decide("electronics.tablet", you) == .requiresExplicitSignal(.device(.bringingTablet)),
                "Task 8: a tablet is a chosen device, never implied by the phone")
        #expect(decide("electronics.tablet", Traveler(role: .otherAdult, ageGroup: .adult), signals: [.bringingTablet]) == .eligible(.travelerSignal))
        #expect(decide("essentials.phone", Traveler(role: .otherAdult, ageGroup: .adult), signals: [.bringingPhone]) == .eligible(.travelerSignal),
                "Task 8: a companion's explicit phone choice")
        #expect(decide("electronics.laptop", you) == .requiresExplicitSignal(.device(.bringingLaptop)), "a phone never proves a laptop on a party list")

        for traveler in [Traveler(role: .partner, ageGroup: .adult), Traveler(role: .otherAdult, ageGroup: .adult),
                         Traveler(role: .child, ageGroup: .teen), Traveler(role: .child, ageGroup: .child)] {
            #expect(decide("essentials.phone", traveler) == .requiresExplicitSignal(.phone), "\(traveler.role)/\(traveler.ageGroup)")
            #expect(decide("electronics.phone_charger", traveler) == .requiresExplicitSignal(.phone))
            #expect(decide("electronics.headphones", traveler) == .requiresExplicitSignal(.device(.bringingHeadphones)))
        }
    }

    @Test func aTeensOwnLaptopSignalIsHonoredWithoutAddingOtherDevices() throws {
        let you = Traveler.primarySelf()
        let teen = Traveler(role: .child, ageGroup: .teen, guardianTravelerID: you.id, chips: [.bringingLaptop])
        let party = TripParty(travelMode: .family, travelers: [you, Traveler(role: .partner, ageGroup: .adult), teen])
        let mine = Self.ids(Self.engine.generate(context: try Self.context(party: party)), for: teen)
        #expect(mine.isSuperset(of: ["electronics.laptop", "electronics.laptop_charger"]))
        #expect(mine.isDisjoint(with: ["essentials.phone", "electronics.phone_charger", "electronics.power_bank"]),
                "a laptop signal is not a phone signal")
        #expect(!Self.ids(Self.engine.generate(context: try Self.context(party: party)), for: you).contains("electronics.laptop"),
                "the teen's signal never propagates to You")
    }

    /// An explicitly added device for any traveler is user intent, never
    /// evaluated; a user-added laptop still brings its charger.
    @Test func explicitlyAddedChildAndCompanionElectronicsSurvive() throws {
        let (party, child) = Self.family(child: Traveler(role: .child, ageGroup: .child))
        let partner = try #require(party.travelers.first { $0.role == .partner })
        let context = try Self.context(party: party, tripTypes: [.business], activities: ["work"])
        func added(_ id: String, _ name: String, for traveler: Traveler) -> PackingItemDraft {
            PackingItemDraft(canonicalItemID: id, displayName: name, category: .electronics, quantity: 1, importance: .normal,
                             sourceSignals: [], reason: "", isUserAdded: true, ownershipType: .personal, travelerID: traveler.id)
        }
        let tablet = added("electronics.tablet", "Tablet", for: child)
        let laptop = added("electronics.laptop", "Laptop", for: partner)
        let regenerated = Self.engine.generate(context: context, existing: [tablet, laptop])
        #expect(regenerated.contains { $0.id == tablet.id && $0.travelerID == child.id })
        #expect(regenerated.contains { $0.id == laptop.id && $0.travelerID == partner.id })
        #expect(Self.ids(regenerated, for: partner).contains("electronics.laptop_charger"), "companion follows the user's laptop")
        let diff = Self.engine.recommendationDiff(context: context, existing: [tablet, laptop], overrides: [])
        #expect(!diff.removeCandidates.contains { $0.id == tablet.id || $0.id == laptop.id })
    }

    // MARK: - Formal events (Task 7.1)

    @Test func childrenAtAWeddingGetAFormalOutfitButNoAdultAccessories() throws {
        for age in [AgeGroup.child, .toddler] {
            let (party, kid) = Self.family(child: Traveler(role: .child, ageGroup: age))
            let items = Self.engine.generate(context: try Self.context(party: party, tripTypes: [.weddingEvent]))
            let mine = Self.ids(items, for: kid)
            #expect(mine.contains("clothing.formal_outfit"), "\(age) at a wedding gets an event outfit")
            #expect(mine.isDisjoint(with: ["footwear.dress_shoes", "clothing.blazer", "clothing.dress_shirt", "clothing.tie"]),
                    "\(age) got adult formal accessories: \(mine)")
            #expect(Self.ids(items, for: party.primary).contains("clothing.formal_outfit"))
        }
        let (infantParty, infant) = Self.family(child: Traveler(role: .child, ageGroup: .infant))
        #expect(!Self.ids(Self.engine.generate(context: try Self.context(party: infantParty, tripTypes: [.weddingEvent])), for: infant)
            .contains("clothing.formal_outfit"), "infant clothing stays the infant model")
        let (plainParty, plainChild) = Self.family(child: Traveler(role: .child, ageGroup: .child))
        #expect(!Self.ids(Self.engine.generate(context: try Self.context(party: plainParty)), for: plainChild).contains("clothing.formal_outfit"),
                "no formal context, no formal outfit")
    }

    // MARK: - Infant sun protection (Task 7.1)

    @Test func sunnyInfantTripsAddASunHatOnlyWithSunContext() throws {
        let (party, infant) = Self.family(child: Traveler(role: .child, ageGroup: .infant))
        let sunny = Self.ids(Self.engine.generate(context: try Self.context(city: "Miami", party: party, month: 7, weatherFixture: "MiamiHotBeach")), for: infant)
        #expect(sunny.contains("clothing.hat_sun"), "infant + hot/high-UV → sun hat")
        #expect(sunny.isDisjoint(with: ["essentials.sunglasses", "kids.sunscreen"]), "no new infant sun-care inference")

        let beach = Self.ids(Self.engine.generate(context: try Self.context(city: "Miami", party: party, tripTypes: [.beach], month: 7)), for: infant)
        #expect(beach.contains("clothing.hat_sun"), "beach sun-exposure need → sun hat")

        let mild = Self.ids(Self.engine.generate(context: try Self.context(city: "Seattle", party: party, weatherFixture: "SeattleWetCity")), for: infant)
        #expect(!mild.contains("clothing.hat_sun"), "no sun need, no hat")

        for age in [AgeGroup.toddler, .child, .adult] {
            let decision = TravelerEligibilityResolver.evaluate(
                canonicalItemID: "clothing.hat_sun", traveler: Traveler(role: age.isAdult ? .otherAdult : .child, ageGroup: age),
                explicitNeeds: [], signals: [], catalog: Self.catalog, rules: Self.rules.party.eligibility
            )
            #expect(decision.isEligible, "\(age) unchanged")
        }
    }

    // MARK: - Travel documents (design 9.3)

    @Test func internationalFamilyDocumentsFollowTheApprovedMatrix() throws {
        let (party, toddler) = Self.family(child: Traveler(role: .child, ageGroup: .toddler))
        let items = Self.engine.generate(context: try Self.context(city: "Tokyo", party: party))
        for traveler in party.travelers {
            let mine = Self.ids(items, for: traveler)
            #expect(mine.contains("documents.passport"), "\(traveler.role) passport")
            #expect(mine.contains("documents.visa"), "\(traveler.role) entry documents")
            #expect(mine.contains("documents.id") == traveler.ageGroup.isAdult, "\(traveler.role) photo ID")
        }
        #expect(!Self.ids(items, for: toddler).contains("documents.id"))
    }

    // MARK: - Ledger

    @Test func ineligibleCandidatesAreRecordedNotSilentlyDropped() throws {
        let (party, toddler) = Self.family(child: Traveler(role: .child, ageGroup: .toddler))
        let generation = Self.engine.generateDetailed(context: try Self.context(party: party))
        let entries = generation.eligibilityDecisions.filter { $0.travelerID == toddler.id }
        let phone = try #require(entries.first { $0.reason == "device_signal.phone" })
        #expect(phone.result == .requiresExplicitSignal)
        #expect(phone.items == ["electronics.phone_charger", "essentials.phone"])
        let device = try #require(entries.first { $0.reason == "device_signal.bringingPowerBank" })
        #expect(device.items.contains("electronics.power_bank"))
        #expect(entries.contains { $0.reason == "adult_or_teen_only" && $0.items.contains("essentials.wallet") })
        #expect(generation.eligibilityDecisions.filter { $0.travelerID == party.primary.id }.allSatisfy { $0.reason.hasPrefix("device_signal.") },
                "You lose nothing but devices you didn't choose")
    }

    @Test func soloRecordsNoEligibilityDecisionsAndAdultPartiesOnlyWithheldDevices() throws {
        let deviceOnly: (EngineGeneration) -> Bool = { generation in
            generation.eligibilityDecisions.allSatisfy { $0.reason.hasPrefix("device_signal.") && !$0.items.contains { $0.hasPrefix("electronics.laptop") } }
        }
        let solo = Self.engine.generateDetailed(context: try Self.context(party: .solo(), chips: [.bringingLaptop, .dailyMedication]))
        #expect(deviceOnly(solo), "solo withholds only unchosen devices: \(solo.eligibilityDecisions)")
        let soloBusiness = Self.engine.generateDetailed(context: try Self.context(party: .solo(), tripTypes: [.business], activities: ["work"]))
        #expect(deviceOnly(soloBusiness), "a solo trip's work context is its traveler's laptop; nothing else is implied")
        #expect(soloBusiness.items.contains { $0.canonicalItemID == "electronics.laptop" })
        #expect(!soloBusiness.items.contains { $0.canonicalItemID == "electronics.headphones" }, "Task 8.1: Work never implies headphones")

        let group = TripParty(travelMode: .group, travelers: [.primarySelf()] + (1...3).map { _ in Traveler(role: .otherAdult, ageGroup: .adult) })
        let generation = Self.engine.generateDetailed(context: try Self.context(city: "Tokyo", party: group, tripTypes: [.business], activities: ["work"]))
        let primaryWithheld = generation.eligibilityDecisions.filter { $0.travelerID == group.primary.id }
        #expect(primaryWithheld.map(\.reason) == ["device_signal.bringingHeadphones", "device_signal.bringingLaptop"],
                "unattributed work context withholds the laptop and headphones from You…")
        #expect(generation.eligibilityDecisions.allSatisfy { $0.result == .requiresExplicitSignal && $0.reason.hasPrefix("device_signal") },
                "…and adults lose nothing but unevidenced devices: \(generation.eligibilityDecisions)")
        #expect(!generation.items.contains { $0.canonicalItemID == "electronics.laptop" }, "no one has a laptop signal")
    }

    // MARK: - User authority

    @Test func explicitChildRowsSurviveRegenerationDespiteDefaultEligibility() throws {
        let (party, toddler) = Self.family(child: Traveler(role: .child, ageGroup: .toddler))
        let context = try Self.context(party: party)
        var existing = Self.engine.generate(context: context)

        let headphones = PackingItemDraft(
            canonicalItemID: "electronics.headphones", displayName: "Headphones", category: .electronics,
            quantity: 1, importance: .normal, sourceSignals: [], reason: "", isUserAdded: true,
            ownershipType: .personal, travelerID: toddler.id
        )
        existing.append(headphones)
        // A manual quantity edit on a row the old engine generated for the
        // child and default eligibility would no longer produce.
        let charger = PackingItemDraft(
            canonicalItemID: "electronics.phone_charger", displayName: "Phone charger", category: .electronics,
            quantity: 2, importance: .important, sourceSignals: [.baseEssential], reason: "", isUserModified: true,
            ownershipType: .personal, travelerID: toddler.id, assignedTravelerID: party.primary.id
        )
        existing.append(charger)
        let shirt = try #require(existing.firstIndex { $0.canonicalItemID == "clothing.tshirt" && $0.travelerID == toddler.id })
        existing[shirt].quantity = 4
        existing[shirt].isUserModified = true
        let partner = try #require(party.travelers.first { $0.role == .partner })
        let socks = try #require(existing.firstIndex { $0.canonicalItemID == "clothing.socks" && $0.travelerID == toddler.id })
        existing[socks].assignedTravelerID = partner.id

        let overrides = [RecommendationOverrideDraft(canonicalItemID: "clothing.pants", action: "removed", travelerID: toddler.id, ownershipType: .personal)]
        let regenerated = Self.engine.generate(context: context, existing: existing, overrides: overrides)

        #expect(regenerated.contains { $0.id == headphones.id && $0.travelerID == toddler.id }, "user-added child item survives with its owner")
        let keptCharger = try #require(regenerated.first { $0.id == charger.id })
        #expect(keptCharger.quantity == 2 && keptCharger.assignedTravelerID == party.primary.id, "manual child quantity and carrier survive")
        #expect(regenerated.first { $0.canonicalItemID == "clothing.tshirt" && $0.travelerID == toddler.id }?.quantity == 4)
        #expect(regenerated.first { $0.canonicalItemID == "clothing.socks" && $0.travelerID == toddler.id }?.assignedTravelerID == partner.id,
                "explicit carrier survives")
        #expect(!regenerated.contains { $0.canonicalItemID == "clothing.pants" && $0.travelerID == toddler.id }, "Not Needed stays on the child")
        #expect(regenerated.contains { $0.canonicalItemID == "clothing.pants" && $0.travelerID == party.primary.id }, "…and only the child")

        let diff = Self.engine.recommendationDiff(context: context, existing: existing, overrides: overrides)
        #expect(!diff.removeCandidates.contains { $0.id == headphones.id || $0.id == charger.id })
    }
}
