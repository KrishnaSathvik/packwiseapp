import Foundation
import Testing
@testable import PackWise

struct PackingEngineTests {
    private func makeEngine() throws -> PackingEngine {
        PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
    }

    private func destination(_ name: String) throws -> Destination {
        try SharedLibrary.testDestinations().first { $0.city == name }!
    }

    private func context(
        destination: Destination,
        days: Int = 6,
        type: TripType = .cityBreak,
        activities: [String] = ["sightseeing", "walking"],
        bag: BagType = .carryOn,
        style: PackingStyle = .light,
        chips: Set<ContextChip> = [.laundryAvailable],
        home: String = "US",
        homeSource: HomeCountrySource = .userConfirmed,
        weather: TripWeatherContext? = nil,
        laundry: LaundryAccess = .planned
    ) -> TripContext {
        let start = Calendar.current.startOfDay(for: Date.now)
        let end = Calendar.current.date(byAdding: .day, value: days - 1, to: start)!
        var prefs = TravelerPreferences.deviceDefaults()
        prefs.homeCountryCode = home
        prefs.homeCountrySource = homeSource
        let math = TripDateMath.daysAndNights(from: start, to: end)
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
            laundryAccess: laundry,
            travelerCount: 1,
            userNotes: laundry == .planned ? "I'll probably do laundry halfway through." : "",
            contextChips: chips,
            weather: weather,
            preferences: prefs
        )
    }

    @Test func sixDayLightLaundryQuantities() throws {
        let items = try makeEngine().generate(context: context(destination: try destination("Chicago")))
        #expect(items.first { $0.canonicalItemID == "clothing.tshirt" }?.quantity == 4)
        #expect(items.first { $0.canonicalItemID == "clothing.underwear" }?.quantity == 6)
        #expect(items.first { $0.canonicalItemID == "clothing.pants" }?.quantity == 2)
    }

    @Test func hikingAddsTrailKit() throws {
        let items = try makeEngine().generate(
            context: context(
                destination: try destination("Chicago"),
                type: .outdoor,
                activities: ["hiking"],
                bag: .notSure,
                style: .balanced,
                chips: [],
                laundry: .none
            )
        )
        let ids = Set(items.compactMap(\.canonicalItemID))
        #expect(ids.contains("footwear.hiking_shoes"))
        #expect(ids.contains("activities.daypack"))
        #expect(ids.contains("hydration.water_bottle"))
    }

    @Test func rainyChicagoAddsRainJacket() async throws {
        let destination = try destination("Chicago")
        let weather = try await MockWeatherService.bundled().weather(for: destination, start: Date.now, end: Calendar.current.date(byAdding: .day, value: 4, to: Date.now)!)
        guard case .forecast(let tripWeather) = weather else {
            Issue.record("Expected fixture forecast")
            return
        }
        let items = try makeEngine().generate(context: context(destination: destination, days: 5, weather: tripWeather))
        #expect(items.contains { $0.canonicalItemID == "clothing.rain_jacket" })
        #expect(items.contains { $0.canonicalItemID == "clothing.rain_jacket" && !$0.reasonCode.isEmpty })
    }

    @Test func overrideKeepsRemovedItemOut() throws {
        let ctx = context(destination: try destination("Chicago"), bag: .checked, style: .prepared, chips: [], laundry: .none)
        let overrides = [RecommendationOverrideDraft(canonicalItemID: "travel_comfort.neck_pillow", action: "removed")]
        let second = try makeEngine().generate(context: ctx, overrides: overrides)
        #expect(!second.contains { $0.canonicalItemID == "travel_comfort.neck_pillow" })
    }

    @Test func notSureBagDoesNotAssumeCarryOn() throws {
        let engine = try makeEngine()
        let constrained = engine.generate(context: context(destination: try destination("Chicago"), bag: .carryOn, style: .light, chips: []))
        let open = engine.generate(context: context(destination: try destination("Chicago"), bag: .notSure, style: .light, chips: []))
        #expect(Set(constrained.compactMap(\.canonicalItemID)).contains("travel_comfort.empty_security_bottle"))
        #expect(!Set(open.compactMap(\.canonicalItemID)).contains("travel_comfort.empty_security_bottle"))
    }

    @Test func internationalRequiresConfirmedHome() throws {
        let engine = try makeEngine()
        let confirmed = engine.generate(context: context(destination: try destination("Tokyo"), homeSource: .userConfirmed))
        let suggested = engine.generate(context: context(destination: try destination("Tokyo"), chips: [], homeSource: .deviceSuggested))
        #expect(confirmed.contains { $0.canonicalItemID == "documents.passport" })
        #expect(!suggested.contains { $0.canonicalItemID == "documents.passport" })
        #expect(confirmed.contains { $0.canonicalItemID == "documents.visa" && $0.reasonCode == "documents.visa_check" })
    }

    @Test func startDateMustBeTodayOrLater() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date.now)!
        #expect(TripDateMath.isStartAllowed(yesterday) == false)
        #expect(TripDateMath.isStartAllowed(Date.now))
    }

    @Test func generationSucceedsWithoutWeather() throws {
        let items = try makeEngine().generate(context: context(destination: try destination("Chicago"), weather: nil))
        #expect(!items.isEmpty)
        #expect(items.contains { $0.canonicalItemID == "essentials.wallet" })
    }

    @Test func runningShoesCoverWalking() throws {
        let items = try makeEngine().generate(
            context: context(
                destination: try destination("Chicago"),
                activities: ["running", "sightseeing", "walking"],
                bag: .notSure,
                style: .balanced,
                chips: [],
                laundry: .none
            )
        )
        #expect(items.contains { $0.canonicalItemID == "footwear.running_shoes" })
        #expect(!items.contains { $0.canonicalItemID == "footwear.walking_shoes" })
    }

    @Test func userAddedItemsSurviveRegeneration() throws {
        let custom = PackingItemDraft(
            canonicalItemID: nil,
            displayName: "Portable fan",
            category: .travelComfort,
            quantity: 1,
            importance: .optional,
            sourceSignals: [.userPreference],
            reason: "Added by you",
            isUserAdded: true
        )
        let items = try makeEngine().generate(context: context(destination: try destination("Chicago")), existing: [custom])
        #expect(items.contains { $0.displayName == "Portable fan" && $0.isUserAdded })
    }

    /// Fixtures describe a party declaratively so a family scenario can assert
    /// child items without the test hand-building travelers each time.
    private static func party(from eval: PartyEval?) -> TripParty? {
        guard let eval else { return nil }
        var travelers: [Traveler] = []
        for row in eval.travelers {
            travelers.append(
                Traveler(
                    role: TravelerRole(rawValue: row.role) ?? .otherAdult,
                    ageGroup: AgeGroup(rawValue: row.ageGroup) ?? .adult,
                    chips: Set((row.chips ?? []).compactMap(ContextChip.init(rawValue:))),
                    needs: Set((row.needs ?? []).compactMap(ChildNeed.init(rawValue:)))
                )
            )
        }
        let guardianID = travelers.first { $0.ageGroup.isAdult }?.id
        travelers = travelers.map { traveler in
            guard traveler.ageGroup.isYoungChild else { return traveler }
            var child = traveler
            child.guardianTravelerID = guardianID
            return child
        }
        return TripParty(
            travelMode: TravelMode(rawValue: eval.travelMode) ?? .family,
            travelers: travelers
        )
    }

    @Test func tripEvalFixtures() async throws {
        let engine = try makeEngine()
        let destinations = try SharedLibrary.testDestinations()
        let weatherService = try MockWeatherService.bundled()
        let evals = try SharedLibrary.tripEvals()
        #expect(!evals.isEmpty)

        for eval in evals {
            let dest = destinations.first { $0.city == eval.destinationFixture }!
            var weather: TripWeatherContext?
            if let fixtureID = dest.fixtureID ?? eval.weatherFixture {
                var destWithFixture = dest
                destWithFixture.fixtureID = fixtureID
                if case .forecast(let context) = await weatherService.availability(
                    for: destWithFixture,
                    start: Date.now,
                    end: Calendar.current.date(byAdding: .day, value: eval.days - 1, to: Date.now)!
                ) {
                    weather = context
                }
            }
            var prefs = TravelerPreferences.deviceDefaults()
            prefs.homeCountryCode = eval.homeCountryCode
            prefs.homeCountrySource = HomeCountrySource(rawValue: eval.homeCountrySource) ?? .userConfirmed
            let start = Calendar.current.startOfDay(for: Date.now)
            let end = Calendar.current.date(byAdding: .day, value: eval.days - 1, to: start)!
            let math = TripDateMath.daysAndNights(from: start, to: end)
            let chips = Set((eval.chips ?? []).compactMap(ContextChip.init(rawValue:)))
            let party = Self.party(from: eval.party)
            let context = TripContext(
                destination: dest,
                startDate: start,
                endDate: end,
                durationDays: math.days,
                durationNights: math.nights,
                tripType: TripType(rawValue: eval.tripType) ?? .other,
                activities: eval.activities,
                datedActivities: eval.activities.map { DatedActivity(activityID: $0, date: nil) },
                bagType: BagType(rawValue: eval.bag) ?? .notSure,
                packingStyle: PackingStyle(rawValue: eval.style) ?? .balanced,
                transportation: .unknown,
                laundryAccess: chips.contains(.laundryAvailable) ? .planned : .none,
                travelerCount: party?.travelers.count ?? eval.travelerCount ?? 1,
                userNotes: eval.note ?? "",
                contextChips: chips,
                weather: weather,
                preferences: prefs,
                party: party ?? .solo(chips: chips)
            )
            let existing = (eval.existing ?? []).map { row in
                PackingItemDraft(
                    canonicalItemID: row.canonicalItemID,
                    displayName: row.displayName,
                    category: PackingCategory(rawValue: row.category) ?? .miscellaneous,
                    quantity: row.quantity,
                    importance: .normal,
                    sourceSignals: [],
                    reason: "",
                    isUserModified: row.isUserModified
                )
            }
            let overrides = (eval.overrides ?? []).map { RecommendationOverrideDraft(canonicalItemID: $0.canonicalItemID, action: $0.action) }
            let items = engine.generate(context: context, existing: existing, overrides: overrides)
            let ids = Set(items.compactMap(\.canonicalItemID))
            for required in eval.mustInclude {
                #expect(ids.contains(required), "\(eval.id) missing \(required)")
            }
            for banned in eval.mustNotInclude ?? [] {
                #expect(!ids.contains(banned), "\(eval.id) unexpectedly included \(banned)")
            }
            if let exact = eval.expectedExactQuantities {
                for (id, value) in exact {
                    #expect(items.first { $0.canonicalItemID == id }?.quantity == value, "\(eval.id) quantity \(id)")
                }
            }
            if let ranges = eval.expectedQuantityRanges {
                for (id, range) in ranges where range.count == 2 {
                    let quantity = items.first { $0.canonicalItemID == id }?.quantity ?? -1
                    #expect(quantity >= range[0] && quantity <= range[1], "\(eval.id) range \(id)")
                }
            }
        }
    }

    @Test func soloListStaysPersonal() throws {
        let items = try makeEngine().generate(context: context(destination: try destination("Chicago")))
        #expect(!items.isEmpty)
        #expect(items.allSatisfy { $0.ownershipType == .personal })
        #expect(!items.contains { $0.canonicalItemID == "kids.diapers" })
    }

    @Test func familyToddlerGetsMoreTopsThanAdult() throws {
        let adult = Traveler.primarySelf()
        let toddler = Traveler(name: "Emma", role: .child, ageGroup: .toddler)
        var ctx = context(
            destination: try destination("Chicago"),
            days: 5,
            style: .light,
            chips: [.laundryAvailable],
            laundry: .planned
        )
        ctx.party = TripParty(travelMode: .family, travelers: [adult, toddler])
        ctx.travelerCount = 2
        let items = try makeEngine().generate(context: ctx)
        let adultTops = items.first { $0.canonicalItemID == "clothing.tshirt" && $0.travelerID == adult.id }
        let toddlerTops = items.first { $0.canonicalItemID == "clothing.tshirt" && $0.travelerID == toddler.id }
        #expect(adultTops?.quantity == 4)
        #expect(toddlerTops?.quantity == 7)
        #expect(!items.contains { $0.canonicalItemID == "kids.diapers" })
        #expect(!items.contains { $0.canonicalItemID == "kids.comfort_item" })
        #expect(toddlerTops?.quantityReason.contains("Emma") == true)
        #expect(items.contains { $0.canonicalItemID == "kids.extra_outfits" && $0.travelerID == toddler.id })
    }

    @Test func familySharesSunscreenInsteadOfMultiplying() throws {
        let adult = Traveler.primarySelf()
        let partner = Traveler(name: "Partner", role: .partner, ageGroup: .adult)
        let child = Traveler(name: "Sam", role: .child, ageGroup: .child)
        let toddler = Traveler(name: "Emma", role: .child, ageGroup: .toddler)
        var ctx = context(
            destination: try destination("Miami"),
            days: 5,
            type: .beach,
            activities: ["beachDays", "swimming"],
            bag: .checked,
            style: .balanced,
            chips: [],
            laundry: .none
        )
        ctx.party = TripParty(travelMode: .family, travelers: [adult, partner, child, toddler])
        ctx.travelerCount = 4
        let items = try makeEngine().generate(context: ctx)
        let sunscreens = items.filter { $0.canonicalItemID == "toiletries.sunscreen" }
        #expect(sunscreens.count == 1)
        #expect(sunscreens.first?.ownershipType == .shared)
        #expect(sunscreens.first?.quantity == 2)
        #expect(!items.contains { $0.canonicalItemID == "toiletries.sunscreen" && $0.ownershipType == .personal })
    }

    @Test func infantAddsCareKitAndSkipsAdultClothes() throws {
        let adult = Traveler.primarySelf()
        let infant = Traveler(
            name: "Baby",
            role: .child,
            ageGroup: .infant,
            packingResponsibility: .guardian,
            guardianTravelerID: adult.id,
            needs: [.diapers, .formula, .stroller]
        )
        var ctx = context(destination: try destination("Chicago"), bag: .checked, style: .balanced, chips: [], laundry: .none)
        ctx.party = TripParty(travelMode: .family, travelers: [adult, infant])
        let items = try makeEngine().generate(context: ctx)
        #expect(items.contains { $0.canonicalItemID == "kids.diapers" && $0.travelerID == infant.id })
        #expect(items.contains { $0.canonicalItemID == "kids.diapers" && $0.assignedTravelerID == adult.id })
        #expect(items.contains { $0.canonicalItemID == "kids.bottles" })
        #expect(!items.contains { $0.canonicalItemID == "clothing.tshirt" && $0.travelerID == infant.id })
        #expect(items.contains { $0.canonicalItemID == "kids.stroller" && $0.ownershipType == .shared })
    }

    @Test func toddlerWithoutNeedsDoesNotAssumeDiapers() throws {
        let adult = Traveler.primarySelf()
        let toddler = Traveler(name: "Emma", role: .child, ageGroup: .toddler)
        var ctx = context(destination: try destination("Chicago"), bag: .checked, style: .balanced, chips: [], laundry: .none)
        ctx.party = TripParty(travelMode: .family, travelers: [adult, toddler])
        let items = try makeEngine().generate(context: ctx)
        #expect(!items.contains { $0.canonicalItemID == "kids.diapers" })
        #expect(!items.contains { $0.canonicalItemID == "kids.stroller" })
        #expect(items.contains { $0.canonicalItemID == "kids.extra_outfits" })
        #expect(items.contains { $0.canonicalItemID == "clothing.sleepwear" && $0.travelerID == toddler.id })
    }

    @Test func toddlerSkipsAdultCareItemsAndCarryables() throws {
        let adult = Traveler.primarySelf()
        let toddler = Traveler(name: "Ada", role: .child, ageGroup: .toddler, needs: [.diapers])
        var ctx = context(destination: try destination("Chicago"), days: 7, type: .vacation, bag: .checked, style: .balanced, chips: [], laundry: .none)
        ctx.party = TripParty(travelMode: .family, travelers: [adult, toddler])
        let items = try makeEngine().generate(context: ctx)
        let toddlerIDs = Set(items.filter { $0.travelerID == toddler.id }.map(\.canonicalItemID))
        for id in [
            "toiletries.deodorant", "health.pain_reliever", "health.blister_pads", "documents.id",
            "electronics.headphones", "travel_comfort.book", "travel_comfort.compression_packing",
            "travel_comfort.laundry_bag", "travel_comfort.toiletry_bag"
        ] {
            #expect(!toddlerIDs.contains(id), "\(id) should not be packed for a toddler")
        }
        // The gate is per-traveler: the same items stay on the adult's list.
        let adultIDs = Set(items.filter { $0.travelerID == adult.id }.map(\.canonicalItemID))
        #expect(adultIDs.contains("toiletries.deodorant"))
        #expect(adultIDs.contains("documents.id"))
        #expect(adultIDs.contains("travel_comfort.book"))
    }

    @Test func schoolAgeChildKeepsCarryablesButNotAdultCareItems() throws {
        // A school-age child plausibly has headphones, a book, and their own
        // packing organizers; deodorant, adult pain relief, and a photo ID
        // stay off the list.
        let adult = Traveler.primarySelf()
        let child = Traveler(name: "Sam", role: .child, ageGroup: .child)
        var ctx = context(destination: try destination("Chicago"), days: 7, type: .vacation, bag: .checked, style: .balanced, chips: [], laundry: .none)
        ctx.party = TripParty(travelMode: .family, travelers: [adult, child])
        let items = try makeEngine().generate(context: ctx)
        let childIDs = Set(items.filter { $0.travelerID == child.id }.map(\.canonicalItemID))
        #expect(childIDs.contains("electronics.headphones"))
        #expect(childIDs.contains("travel_comfort.book"))
        #expect(!childIDs.contains("toiletries.deodorant"))
        #expect(!childIDs.contains("health.pain_reliever"))
        #expect(!childIDs.contains("documents.id"))
    }

    @Test func partyListFiltersUseNamesAndCollapseKids() {
        let krishna = Traveler.primarySelf(name: "Krishna")
        let maya = Traveler(name: "Maya", role: .partner, ageGroup: .adult)
        let arjun = Traveler(name: "Arjun", role: .child, ageGroup: .child)
        let emma = Traveler(name: "Emma", role: .child, ageGroup: .toddler)

        let couple = TripParty(travelMode: .couple, travelers: [krishna, maya])
        #expect(couple.listFilters() == [.all, .traveler(krishna.id), .traveler(maya.id), .shared])

        let oneChild = TripParty(travelMode: .family, travelers: [krishna, maya, arjun])
        #expect(oneChild.listFilters() == [.all, .traveler(krishna.id), .traveler(maya.id), .traveler(arjun.id), .shared])

        let twoKids = TripParty(travelMode: .family, travelers: [krishna, maya, arjun, emma])
        #expect(twoKids.listFilters() == [.all, .traveler(krishna.id), .traveler(maya.id), .kids, .shared])
    }

    @Test func partyInvariantsRejectBrokenOwnership() {
        let adult = Traveler.primarySelf()
        let child = Traveler(
            name: "Emma",
            role: .child,
            ageGroup: .toddler,
            packingResponsibility: .guardian,
            guardianTravelerID: adult.id
        )
        let party = TripParty(travelMode: .family, travelers: [adult, child])
        #expect(PartyInvariants.violations(party: party).isEmpty)

        let sharedWithOwner = PackingItemDraft(
            canonicalItemID: "toiletries.sunscreen",
            displayName: "Sunscreen",
            category: .toiletries,
            quantity: 1,
            importance: .important,
            sourceSignals: [],
            reason: "",
            ownershipType: .shared,
            travelerID: adult.id
        )
        #expect(PartyInvariants.violations(party: party, items: [sharedWithOwner]).contains(.sharedItemHasOwner))

        let personalWithoutOwner = PackingItemDraft(
            canonicalItemID: "clothing.tshirt",
            displayName: "T-shirts",
            category: .clothing,
            quantity: 1,
            importance: .normal,
            sourceSignals: [],
            reason: "",
            ownershipType: .personal,
            travelerID: nil
        )
        #expect(PartyInvariants.violations(party: party, items: [personalWithoutOwner]).contains(.personalItemMissingOwner))

        let outsider = UUID()
        let assignedOutside = PackingItemDraft(
            canonicalItemID: "toiletries.sunscreen",
            displayName: "Sunscreen",
            category: .toiletries,
            quantity: 1,
            importance: .important,
            sourceSignals: [],
            reason: "",
            ownershipType: .shared,
            assignedTravelerID: outsider
        )
        #expect(PartyInvariants.violations(party: party, items: [assignedOutside]).contains(.assignedTravelerNotInParty))
    }

    @Test func partyInvariantsRejectInvalidGuardianAndBagOwner() {
        let adult = Traveler.primarySelf()
        let otherAdult = Traveler(name: "Maya", role: .partner, ageGroup: .adult)
        let outsider = UUID()
        let childBadGuardian = Traveler(
            name: "Emma",
            role: .child,
            ageGroup: .toddler,
            packingResponsibility: .guardian,
            guardianTravelerID: outsider
        )
        let adultWithGuardian = Traveler(
            name: "Alex",
            role: .otherAdult,
            ageGroup: .adult,
            guardianTravelerID: adult.id
        )
        #expect(
            PartyInvariants.violations(
                party: TripParty(travelMode: .family, travelers: [adult, childBadGuardian])
            ).contains(.guardianNotInParty)
        )
        #expect(
            PartyInvariants.violations(
                party: TripParty(travelMode: .family, travelers: [adult, adultWithGuardian])
            ).contains(.guardianNotAllowed)
        )

        let teenGuardian = Traveler(name: "Sam", role: .child, ageGroup: .teen)
        let toddler = Traveler(
            name: "Emma",
            role: .child,
            ageGroup: .toddler,
            packingResponsibility: .guardian,
            guardianTravelerID: teenGuardian.id
        )
        #expect(
            PartyInvariants.violations(
                party: TripParty(travelMode: .family, travelers: [adult, teenGuardian, toddler])
            ).contains(.guardianNotAdult)
        )

        let bag = TripBag(name: "Carry-on", bagType: .carryOn, ownerTravelerID: outsider, ownershipType: .personal)
        #expect(
            PartyInvariants.violations(
                party: TripParty(travelMode: .couple, travelers: [adult, otherAdult]),
                bags: [bag]
            ).contains(.bagOwnerNotInParty)
        )
    }

    @Test func generatedFamilyListSatisfiesPartyInvariants() throws {
        let adult = Traveler.primarySelf()
        let toddler = Traveler(
            name: "Emma",
            role: .child,
            ageGroup: .toddler,
            packingResponsibility: .guardian,
            guardianTravelerID: adult.id,
            needs: [.diapers]
        )
        var ctx = context(destination: try destination("Chicago"), days: 5)
        ctx.party = TripParty(travelMode: .family, travelers: [adult, toddler])
        let items = try makeEngine().generate(context: ctx)
        #expect(PartyInvariants.violations(party: ctx.party, items: items).isEmpty)
        #expect(items.filter { $0.ownershipType == .shared }.allSatisfy { $0.travelerID == nil })
        #expect(items.filter { $0.ownershipType == .personal }.allSatisfy { $0.travelerID != nil })
    }

    @Test func unconfirmedHomeDoesNotClaimVisaRequired() throws {
        let items = try makeEngine().generate(context: context(destination: try destination("Tokyo"), homeSource: .userConfirmed))
        let visa = items.first { $0.canonicalItemID == "documents.visa" }
        #expect(!(visa?.reason.lowercased().contains("visa required") ?? false))
    }

    @Test func recommendationDiffIsEmptyWhenContextIsUnchanged() throws {
        let engine = try makeEngine()
        let ctx = context(destination: try destination("Chicago"))
        let existing = engine.generate(context: ctx)
        let diff = engine.recommendationDiff(context: ctx, existing: existing, overrides: [])
        #expect(diff.isEmpty)
    }

    @Test func recommendationDiffPreservesPackedCustomAndModified() throws {
        let engine = try makeEngine()
        let ctx = context(
            destination: try destination("Chicago"),
            type: .cityBreak,
            activities: ["sightseeing", "walking"],
            bag: .checked,
            style: .balanced,
            chips: [],
            laundry: .none
        )
        var existing = engine.generate(context: ctx)
        if let index = existing.firstIndex(where: { $0.canonicalItemID == "clothing.tshirt" }) {
            existing[index].packedQuantity = existing[index].quantity
        }
        if let index = existing.firstIndex(where: { $0.canonicalItemID == "clothing.pants" }) {
            existing[index].isUserModified = true
            existing[index].quantity = 9
        }
        existing.append(
            PackingItemDraft(
                canonicalItemID: nil,
                displayName: "Portable fan",
                category: .travelComfort,
                quantity: 1,
                packedQuantity: 1,
                importance: .optional,
                sourceSignals: [.userPreference],
                reason: "Added by you",
                isUserAdded: true
            )
        )
        var hiking = ctx
        hiking.activities = ["sightseeing", "walking", "hiking"]
        let diff = engine.recommendationDiff(context: hiking, existing: existing, overrides: [])
        #expect(diff.add.contains { $0.canonicalItemID == "footwear.hiking_shoes" })
        #expect(!diff.removeCandidates.contains { $0.displayName == "Portable fan" })
        #expect(!diff.quantityChanges.contains { $0.item.canonicalItemID == "clothing.pants" })
        #expect(existing.contains { $0.canonicalItemID == "clothing.tshirt" && $0.isPacked })
    }

    /// The reported failure: a 15-day balanced carry-on trip rendering
    /// T-shirts ×15 and socks ×16 — the naive duration formula. Laundry,
    /// style, and bag must each move the numbers.
    @Test func longBalancedTripRespondsToLaundryAndStyle() throws {
        let engine = try makeEngine()
        let dest = try destination("Chicago")

        func quantities(style: PackingStyle, laundry: Bool) throws -> (tops: Int, underwear: Int, socks: Int) {
            let items = engine.generate(
                context: context(
                    destination: dest,
                    days: 15,
                    bag: .carryOn,
                    style: style,
                    chips: laundry ? [.laundryAvailable] : [],
                    laundry: laundry ? .planned : .none
                )
            )
            func quantity(_ id: String) throws -> Int {
                try #require(items.first { $0.canonicalItemID == id }).quantity
            }
            return (
                try quantity("clothing.tshirt"),
                try quantity("clothing.underwear"),
                try quantity("clothing.socks")
            )
        }

        let balancedNoLaundry = try quantities(style: .balanced, laundry: false)
        let balancedLaundry = try quantities(style: .balanced, laundry: true)
        let lightLaundry = try quantities(style: .light, laundry: true)

        // Laundry pulls every daily count below the no-laundry figure.
        #expect(balancedLaundry.tops < balancedNoLaundry.tops)
        #expect(balancedLaundry.underwear < balancedNoLaundry.underwear)
        #expect(balancedLaundry.socks < balancedNoLaundry.socks)
        // Style modulates on top of laundry.
        #expect(lightLaundry.tops < balancedLaundry.tops)
        // The specific rendered numbers from the clothing need policies:
        // planned laundry bounds at the wash interval plus the style buffer;
        // no laundry grows to the bag cap, not to trip days.
        #expect(balancedLaundry.tops == 7)
        #expect(balancedNoLaundry.tops == 8)
        #expect(balancedLaundry.underwear == 8)
        #expect(balancedNoLaundry.underwear == 10)
    }

    /// Toggling laundry on an existing trip must surface quantity changes in
    /// the diff — otherwise the setup edit appears to do nothing.
    @Test func addingLaundryProducesQuantityChangeSuggestions() throws {
        let engine = try makeEngine()
        let dest = try destination("Chicago")
        let before = context(destination: dest, days: 15, bag: .carryOn, style: .balanced, chips: [], laundry: .none)
        let existing = engine.generate(context: before)
        let after = context(destination: dest, days: 15, bag: .carryOn, style: .balanced, chips: [.laundryAvailable], laundry: .planned)
        let diff = engine.recommendationDiff(context: after, existing: existing, overrides: [])
        let tshirt = diff.quantityChanges.first { $0.item.canonicalItemID == "clothing.tshirt" }
        #expect(tshirt?.suggestedQuantity == 7)
    }

    @Test func recommendationDiffHonorsNotNeededOverride() throws {
        let engine = try makeEngine()
        let ctx = context(destination: try destination("Chicago"), bag: .checked, style: .prepared, chips: [], laundry: .none)
        let existing = engine.generate(context: ctx).filter { $0.canonicalItemID != "travel_comfort.neck_pillow" }
        let overrides = [RecommendationOverrideDraft(canonicalItemID: "travel_comfort.neck_pillow", action: "removed")]
        let diff = engine.recommendationDiff(context: ctx, existing: existing, overrides: overrides)
        #expect(!diff.add.contains { $0.canonicalItemID == "travel_comfort.neck_pillow" })
    }

    @Test func partyBuilderReusesTravelerIDsOnEdit() {
        let original = TripPartyBuilder.make(mode: .couple, partnerName: "Maya")
        let edited = TripPartyBuilder.make(mode: .couple, partnerName: "Maya", existing: original)
        #expect(original.primary.id == edited.primary.id)
        #expect(
            original.travelers.first { $0.role == .partner }?.id
                == edited.travelers.first { $0.role == .partner }?.id
        )
        let child = ChildDraft(ageGroup: .toddler, needs: [.comfortItem])
        let family = TripPartyBuilder.make(mode: .family, adultCount: 2, childProfiles: [child])
        let familyAgain = TripPartyBuilder.make(
            mode: .family,
            adultCount: 2,
            childProfiles: [child],
            existing: family
        )
        #expect(family.primary.id == familyAgain.primary.id)
        #expect(family.travelers.contains { $0.id == child.id })
        #expect(familyAgain.travelers.contains { $0.id == child.id })
    }
}
