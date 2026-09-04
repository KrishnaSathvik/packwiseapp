import Foundation
import Testing
@testable import PackWise

/// Constraint resolver tests — Engine V2 plan, Step 5: dependencies,
/// explicit conflicts, and the family sharing rules that must never drift.
struct ConstraintTests {
    private func makeEngine() throws -> PackingEngine {
        PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
    }

    private func destination(_ name: String) throws -> Destination {
        try SharedLibrary.testDestinations().first { $0.city == name }!
    }

    private func context(
        destination: Destination,
        days: Int = 5,
        type: TripType = .cityBreak,
        activities: [String] = ["sightseeing", "walking"],
        bag: BagType = .carryOn,
        style: PackingStyle = .balanced,
        chips: Set<ContextChip> = [],
        party: TripParty? = nil,
        weather: TripWeatherContext? = nil
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
            contextChips: chips,
            weather: weather,
            preferences: prefs,
            party: party ?? .solo()
        )
    }

    /// Built the same way `WeatherChangeTests.swift`'s private `forecast(...)`
    /// helper builds a `TripWeatherContext` — a minimal, deterministic
    /// fixture, not a fetched forecast.
    private func forecast(
        start: Date,
        days: Int,
        high: Double,
        low: Double,
        rain: Double,
        uv: Double = 4,
        wind: Double = 8
    ) -> TripWeatherContext {
        let calendar = Calendar.current
        let daily: [DailyForecast] = (0..<days).map { index in
            let day = calendar.date(byAdding: .day, value: index, to: start)!
            return DailyForecast(
                date: calendar.startOfDay(for: day),
                symbol: rain >= 0.35 ? "cloud.rain" : "sun.max",
                highF: high,
                lowF: low,
                rainProbability: rain,
                uvIndex: uv,
                windMph: wind,
                snowExpected: false,
                summary: rain >= 0.35 ? "Rain" : "Sunny"
            )
        }
        let rainDays = daily.filter { $0.rainProbability >= 0.35 }.count
        return TripWeatherContext(
            minTemperatureF: daily.map(\.lowF).min() ?? low,
            maxTemperatureF: daily.map(\.highF).max() ?? high,
            dailyForecast: daily,
            rainDays: rainDays,
            heavyRainDays: daily.filter { $0.rainProbability >= 0.6 }.count,
            snowDays: 0,
            outdoorRainOverlapDays: rainDays,
            maxDailyTemperatureSwing: daily.map(\.swingF).max() ?? 0,
            uvRange: daily.map(\.uvIndex).max() ?? 0,
            windRange: daily.map(\.windMph).max() ?? 0,
            weatherSummary: "Test",
            fetchedAt: start,
            providerFetchedAt: start,
            providerExpiresAt: calendar.date(byAdding: .hour, value: 1, to: start),
            coverageStart: daily.first?.date,
            coverageEnd: daily.last?.date,
            forecastAvailableForWholeTrip: true,
            forecastAvailableForPartialTrip: false,
            isPreciseForecast: true,
            source: .fixture,
            fixtureID: "test",
            alerts: [],
            attribution: nil
        )
    }

    // MARK: - Party sharing resolution

    /// The one function `generateForParty`/`addCompanions`/`applyQuantities`
    /// all ask instead of independently testing `sharedByDefault` membership.
    @Test func sharingResolutionMatchesTodaysSharedByDefaultMembership() throws {
        let rules = try SharedLibrary.rules()
        let solo = TripParty.solo()
        let couple = TripParty(travelMode: .couple, travelers: [Traveler.primarySelf(), Traveler(name: "Sam", role: .partner, ageGroup: .adult)])
        let ctx = context(destination: try destination("Chicago"), party: couple)

        // Shared, singlePerParty (no explicit policy row falls to the default).
        let firstAid = ConstraintResolver.sharingResolution(
            for: "health.first_aid", rules: rules.party, context: ctx, party: couple
        )
        guard case .shared(let quantity, _) = firstAid else {
            Issue.record("expected health.first_aid to resolve shared")
            return
        }
        #expect(quantity == 1)

        // Not in sharedByDefault → personal, regardless of party size.
        #expect(ConstraintResolver.sharingResolution(
            for: "miscellaneous.flashlight", rules: rules.party, context: ctx, party: couple
        ) == .personal)
        #expect(ConstraintResolver.sharingResolution(
            for: "miscellaneous.flashlight", rules: rules.party, context: context(destination: try destination("Chicago"), party: solo), party: solo
        ) == .personal)
    }

    /// `.personalOnly` must behave exactly like "not shared" — one draft per
    /// traveler, real `travelerID`, `ownershipType == .personal` — never an
    /// `ownershipType == .shared` draft with `travelerID == nil` produced by
    /// falling through `applyQuantities`'s old shared-quantity branch. Tested
    /// against a synthetic policy row so no `party.json` row is added; a real
    /// per-traveler item (`toiletries.toothbrush`) stands in as the subject so
    /// the assertion is about actual generated items, not the bare function.
    private func rulesWithSyntheticPersonalOnly(for canonicalItemID: String = "toiletries.toothbrush") throws -> PackingRulesFile {
        var rules = try SharedLibrary.rules()
        rules.party.sharedByDefault.append(canonicalItemID)
        rules.party.sharingPolicies[canonicalItemID] = SharingPolicyRule(policy: .personalOnly, per: nil, min: 1, value: 1)
        return rules
    }

    @Test func personalOnlySoloProducesOneOwnedPersonalItem() throws {
        let engine = PackingEngine(catalog: try SharedLibrary.catalog(), rules: try rulesWithSyntheticPersonalOnly())
        let items = engine.generate(context: context(destination: try destination("Chicago"), party: .solo()))
        let matches = items.filter { $0.canonicalItemID == "toiletries.toothbrush" }
        #expect(matches.count == 1)
        #expect(matches.allSatisfy { $0.ownershipType == .personal && $0.travelerID != nil })
    }

    @Test func personalOnlyCoupleProducesOnePersonalRowPerTraveler() throws {
        let engine = PackingEngine(catalog: try SharedLibrary.catalog(), rules: try rulesWithSyntheticPersonalOnly())
        let couple = TripParty(travelMode: .couple, travelers: [Traveler.primarySelf(), Traveler(name: "Sam", role: .partner, ageGroup: .adult)])
        let items = engine.generate(context: context(destination: try destination("Chicago"), party: couple))
        let matches = items.filter { $0.canonicalItemID == "toiletries.toothbrush" }
        #expect(matches.count == 2)
        #expect(matches.allSatisfy { $0.ownershipType == .personal })
        #expect(Set(matches.compactMap(\.travelerID)) == Set(couple.travelers.map(\.id)))
    }

    @Test func personalOnlyFamilyNeverProducesAnOwnerlessSharedDraft() throws {
        let engine = PackingEngine(catalog: try SharedLibrary.catalog(), rules: try rulesWithSyntheticPersonalOnly())
        let family = TripParty(travelMode: .family, travelers: [
            Traveler.primarySelf(),
            Traveler(name: "Sam", role: .partner, ageGroup: .adult),
            Traveler(name: "Emma", role: .child, ageGroup: .child)
        ])
        let items = engine.generate(context: context(destination: try destination("Chicago"), party: family))
        let matches = items.filter { $0.canonicalItemID == "toiletries.toothbrush" }
        #expect(matches.count == family.travelers.count)
        // The exact defect this test exists to prevent: never travelerID == nil
        // merely because a .personalOnly item fell through the old shared path.
        #expect(matches.allSatisfy { $0.ownershipType != .shared && $0.travelerID != nil })
    }

    /// The pure-function boundary, so a future edit to `sharingResolution`
    /// cannot silently reintroduce the fallthrough without failing here first.
    @Test func sharingResolutionNeverReturnsSharedForPersonalOnlyPolicy() throws {
        let rules = try rulesWithSyntheticPersonalOnly()
        let result = ConstraintResolver.sharingResolution(
            for: "toiletries.toothbrush", rules: rules.party,
            context: context(destination: try destination("Chicago")), party: .solo()
        )
        #expect(result == .personal)
    }

    // MARK: - Explicit authority gate

    @Test func hasUserAuthorityIsTrueForAddedOrModifiedOnly() {
        let plain = PackingItemDraft(canonicalItemID: "clothing.tshirt", displayName: "T-Shirt", category: .clothing, quantity: 1, importance: .normal, sourceSignals: [], reason: "")
        var added = plain; added.isUserAdded = true
        var modified = plain; modified.isUserModified = true
        #expect(!ConstraintResolver.hasUserAuthority(plain))
        #expect(ConstraintResolver.hasUserAuthority(added))
        #expect(ConstraintResolver.hasUserAuthority(modified))
    }

    @Test func isExplicitlyRemovedMatchesTravelerAndOwnershipScoping() {
        let travelerA = UUID()
        let travelerB = UUID()
        let overrides = [RecommendationOverrideDraft(canonicalItemID: "clothing.hat_sun", action: "removed", travelerID: travelerA, ownershipType: .personal)]
        #expect(ConstraintResolver.isExplicitlyRemoved("clothing.hat_sun", ownership: .personal, travelerID: travelerA, overrides: overrides))
        #expect(!ConstraintResolver.isExplicitlyRemoved("clothing.hat_sun", ownership: .personal, travelerID: travelerB, overrides: overrides))
        #expect(!ConstraintResolver.isExplicitlyRemoved("clothing.hat_sun", ownership: .shared, travelerID: nil, overrides: overrides))
    }

    // MARK: - Priority hierarchy proof (task requirement: provable, not asserted)

    /// Explicit user state must survive a regeneration that simultaneously
    /// changes weather, activities, and duration — three independent
    /// current-trip-constraint recomputations at once, not one at a time as
    /// each single-fact test above exercises. This is the multi-dimensional
    /// conflict the priority hierarchy names: rung 1/2 (explicit decisions)
    /// must never lose to rung 3 (current trip constraints) no matter how
    /// many rung-3 facts move together.
    @Test func explicitUserStateSurvivesASimultaneousMultiDimensionalRefresh() throws {
        let engine = try makeEngine()
        let dest = try destination("Chicago")
        var partner = Traveler(name: "Sam", role: .partner, ageGroup: .adult)
        // wearContacts gives the partner toiletries.contacts_solution, which
        // this test's carrier-reassignment fact (rung 1/2 fact 4) needs.
        partner.chips = [.wearContacts]
        let party = TripParty(travelMode: .couple, travelers: [Traveler.primarySelf(), partner])

        var first = engine.generate(context: context(destination: dest, days: 5, activities: ["sightseeing", "walking"], bag: .checked, party: party))

        // Rung 1/2 fact 1: manual quantity edit ("T-shirts 7 → 3" shape).
        guard let tshirtIndex = first.firstIndex(where: { $0.canonicalItemID == "clothing.tshirt" && $0.travelerID == party.primary.id }) else {
            Issue.record("Expected a primary t-shirt row")
            return
        }
        first[tshirtIndex].quantity = 3
        first[tshirtIndex].isUserModified = true

        // Rung 1/2 fact 2: Not Needed override (rain jacket, "must not silently return" shape).
        let overrides = [RecommendationOverrideDraft(canonicalItemID: "clothing.rain_jacket", action: "removed")]

        // Rung 1/2 fact 3: user-added custom item.
        first.append(PackingItemDraft(
            canonicalItemID: nil, displayName: "Travel journal", category: .travelComfort,
            quantity: 1, importance: .optional, sourceSignals: [.userPreference], reason: "Added by you",
            isUserAdded: true, ownershipType: .personal, travelerID: party.primary.id
        ))

        // Rung 1/2 fact 4: explicit carrier reassignment (owner unchanged, carrier moved).
        if let contactsIndex = first.firstIndex(where: { $0.canonicalItemID == "toiletries.contacts_solution" }) {
            first[contactsIndex].assignedTravelerID = party.primary.id
        }

        // Three rung-3 dimensions move together: longer trip, new activity,
        // and rain weather that would otherwise re-suggest the rain jacket.
        let rainy = forecast(
            start: Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 14))!,
            days: 8, high: 62, low: 50, rain: 0.7
        )
        let second = engine.generate(
            context: context(destination: dest, days: 8, activities: ["sightseeing", "walking", "museum"], bag: .checked, party: party, weather: rainy),
            existing: first,
            overrides: overrides
        )

        let tshirt = try #require(second.first { $0.canonicalItemID == "clothing.tshirt" && $0.travelerID == party.primary.id })
        #expect(tshirt.quantity == 3, "manual quantity must survive weather + activity + duration change together")
        #expect(!second.contains { $0.canonicalItemID == "clothing.rain_jacket" }, "Not Needed must not silently return even with fresh rain weather")
        #expect(second.contains { $0.displayName == "Travel journal" && $0.isUserAdded })
        let contactsSolution = try #require(second.first { $0.canonicalItemID == "toiletries.contacts_solution" })
        #expect(contactsSolution.assignedTravelerID == party.primary.id, "carrier reassignment must survive")
        #expect(contactsSolution.travelerID == partner.id, "owner must remain the partner despite the carrier move")
    }

    // MARK: - Dependencies

    /// Adding a camera by hand pulls in its charger — a different trust
    /// posture than the up-front list, so the add must name its trigger.
    @Test func userAddedCameraSurfacesChargerWithNamingReason() throws {
        let camera = PackingItemDraft(
            canonicalItemID: "electronics.camera",
            displayName: "Camera",
            category: .electronics,
            quantity: 1,
            importance: .normal,
            sourceSignals: [.userPreference],
            reason: "Added by you",
            isUserAdded: true
        )
        let items = try makeEngine().generate(
            context: context(destination: try destination("Chicago")),
            existing: [camera]
        )
        let charger = items.first { $0.canonicalItemID == "electronics.camera_charger" }
        #expect(charger != nil)
        #expect(charger?.reasonCode == "dependency.companion")
        #expect(charger?.reason.localizedCaseInsensitiveContains("camera") == true)
    }

    /// When the rules already emitted the companion, the dependency pass
    /// must not duplicate it.
    @Test func companionNotDuplicatedWhenRulesAlreadyEmitIt() throws {
        let items = try makeEngine().generate(
            context: context(destination: try destination("Chicago"), type: .business, activities: ["work"], bag: .checked, style: .prepared)
        )
        #expect(items.filter { $0.canonicalItemID == "electronics.laptop_charger" }.count == 1)
    }

    /// Explicit user decisions outrank dependencies: a removed companion
    /// stays removed.
    @Test func removedCompanionStaysRemoved() throws {
        let camera = PackingItemDraft(
            canonicalItemID: "electronics.camera",
            displayName: "Camera",
            category: .electronics,
            quantity: 1,
            importance: .normal,
            sourceSignals: [.userPreference],
            reason: "Added by you",
            isUserAdded: true
        )
        let overrides = [RecommendationOverrideDraft(canonicalItemID: "electronics.camera_charger", action: "removed")]
        let items = try makeEngine().generate(
            context: context(destination: try destination("Chicago")),
            existing: [camera],
            overrides: overrides
        )
        #expect(!items.contains { $0.canonicalItemID == "electronics.camera_charger" })
    }

    /// The chip adds contact solution; the solution's companion adds the case.
    @Test func contactsChainAddsCase() throws {
        let items = try makeEngine().generate(
            context: context(destination: try destination("Chicago"), chips: [.wearContacts])
        )
        let ids = Set(items.compactMap(\.canonicalItemID))
        #expect(ids.contains("toiletries.contacts_solution"))
        #expect(ids.contains("toiletries.contact_case"))
    }

    // MARK: - Explicit conflicts

    /// Prepared says bring extras; a personal item says there's no room. The
    /// bag wins for optional extras, and the decision is recorded with
    /// one-sentence user-terms copy — two rules never fight silently.
    @Test func preparedVersusPersonalItemResolvesExplicitly() throws {
        let engine = try makeEngine()
        let dest = try destination("Chicago")
        let roomy = engine.generateDetailed(context: context(destination: dest, type: .vacation, bag: .checked, style: .prepared))
        let tight = engine.generateDetailed(context: context(destination: dest, type: .vacation, bag: .personalItem, style: .prepared))

        let roomyIDs = Set(roomy.items.compactMap(\.canonicalItemID))
        let tightIDs = Set(tight.items.compactMap(\.canonicalItemID))
        let decision = tight.constraintDecisions.first { $0.constraint == "style.prepared_vs_personal_item" }
        #expect(decision != nil, "the conflict must be recorded, not resolved silently")
        for dropped in decision?.items ?? [] {
            #expect(roomyIDs.contains(dropped), "\(dropped) should exist when there's room")
            #expect(!tightIDs.contains(dropped), "\(dropped) should be trimmed for a personal item")
        }
        #expect(decision?.items.isEmpty == false)
        #expect(decision?.summary.hasPrefix("Trimmed to fit a personal item") == true)
        #expect(roomy.constraintDecisions.isEmpty, "a checked bag has no conflict to record")
    }

    /// Optional items that are small or safety-relevant survive the trim.
    @Test func essentialOptionalTagsSurvivePersonalItem() {
        let ruling = ConstraintResolver.optionalRuling(
            importance: .optional,
            tags: ["medication"],
            bag: .personalItem,
            style: .light
        )
        #expect(ruling.keep)
    }

    // MARK: - Task 4: authority — removed canonical item

    /// A rule-suggested (not just a companion) canonical item stays out once
    /// removed — the same explicit-state authority as `removedCompanionStaysRemoved`,
    /// exercised on a base essential the up-front rules emit directly.
    @Test func removedBaseEssentialStaysRemovedAcrossRegeneration() throws {
        let engine = try makeEngine()
        let dest = try destination("Chicago")
        let overrides = [RecommendationOverrideDraft(canonicalItemID: "toiletries.toothbrush", action: "removed")]
        let first = engine.generate(context: context(destination: dest), overrides: overrides)
        #expect(!first.contains { $0.canonicalItemID == "toiletries.toothbrush" })

        // Regenerating with a materially different context (longer trip,
        // more activities) must not resurrect it — the override is
        // context-independent explicit state, not a one-time suppression.
        let second = engine.generate(
            context: context(destination: dest, days: 10, activities: ["sightseeing", "walking", "museum"]),
            existing: first,
            overrides: overrides
        )
        #expect(!second.contains { $0.canonicalItemID == "toiletries.toothbrush" })
    }

    // MARK: - Task 4: authority — manual quantity

    /// A hand-edited quantity on a non-clothing base essential survives
    /// regeneration under a changed context — `manualQuantitySurvivesWeatherRefresh`
    /// in ClothingQuantityTests covers the clothing/weather path; this is
    /// the same guarantee for the legacy `QuantityEngine` family.
    @Test func manualQuantitySurvivesRegenerationWithChangedContext() throws {
        let engine = try makeEngine()
        let dest = try destination("Chicago")
        var first = engine.generate(context: context(destination: dest, days: 5))
        guard let index = first.firstIndex(where: { $0.canonicalItemID == "toiletries.toothbrush" }) else {
            Issue.record("Expected toiletries.toothbrush in the base list")
            return
        }
        first[index].quantity = 4
        first[index].isUserModified = true

        let second = engine.generate(
            context: context(destination: dest, days: 12, activities: ["sightseeing", "walking", "museum"]),
            existing: first
        )
        let toothbrush = second.first { $0.canonicalItemID == "toiletries.toothbrush" }
        #expect(toothbrush?.quantity == 4, "the manual edit must survive an unrelated context change")
        #expect(toothbrush?.isUserModified == true)
    }

    // MARK: - Task 4: authority — user-added canonical and custom items

    /// A user-added canonical item and a fully custom item (no canonical ID
    /// at all) both pass through regeneration untouched — the up-front
    /// rules never own them, and neither can be silently dropped or renamed.
    @Test func userAddedCanonicalAndCustomItemsSurviveRegeneration() throws {
        let canonical = PackingItemDraft(
            canonicalItemID: "electronics.camera",
            displayName: "Camera",
            category: .electronics,
            quantity: 1,
            importance: .normal,
            sourceSignals: [.userPreference],
            reason: "Added by you",
            isUserAdded: true
        )
        let custom = PackingItemDraft(
            canonicalItemID: nil,
            displayName: "Lucky travel charm",
            category: .travelComfort,
            quantity: 2,
            importance: .optional,
            sourceSignals: [.userPreference],
            reason: "Added by you",
            isUserAdded: true
        )
        let engine = try makeEngine()
        let items = engine.generate(
            context: context(destination: try destination("Chicago")),
            existing: [canonical, custom]
        )
        let keptCanonical = items.first { $0.id == canonical.id }
        let keptCustom = items.first { $0.id == custom.id }
        #expect(keptCanonical?.canonicalItemID == "electronics.camera")
        #expect(keptCanonical?.quantity == 1)
        #expect(keptCustom?.displayName == "Lucky travel charm")
        #expect(keptCustom?.canonicalItemID == nil)
        #expect(keptCustom?.quantity == 2)
    }

    // MARK: - Task 4: authority — packed state

    /// Packed state is derived (`packedQuantity >= quantity`), not a sticky
    /// flag: it survives regeneration when the recommended quantity does
    /// not change.
    @Test func packedStateSurvivesRegenerationWhenQuantityIsUnchanged() throws {
        let engine = try makeEngine()
        let dest = try destination("Chicago")
        var first = engine.generate(context: context(destination: dest, days: 5))
        guard let index = first.firstIndex(where: { $0.canonicalItemID == "toiletries.toothbrush" }) else {
            Issue.record("Expected toiletries.toothbrush in the base list")
            return
        }
        first[index].packedQuantity = first[index].quantity
        #expect(first[index].isPacked)

        let second = engine.generate(context: context(destination: dest, days: 5), existing: first)
        let toothbrush = try #require(second.first { $0.canonicalItemID == "toiletries.toothbrush" })
        #expect(toothbrush.isPacked, "packed state should survive a no-op regeneration")
    }

    // MARK: - Task 4: authority — owner and carrier

    /// A party member's owned item keeps that traveler as its owner across
    /// two generations of the same party context — ownership is resolved
    /// per traveler, never guessed or swapped.
    @Test func ownerStaysWithTheSameTravelerAcrossRegeneration() throws {
        var partner = Traveler(name: "Sam", role: .partner, ageGroup: .adult)
        partner.chips = [.wearContacts]
        let party = TripParty(travelMode: .couple, travelers: [Traveler.primarySelf(), partner])
        let engine = try makeEngine()
        let dest = try destination("Chicago")
        let first = engine.generate(context: context(destination: dest, days: 5, bag: .checked, party: party))
        let solution = try #require(first.first { $0.canonicalItemID == "toiletries.contacts_solution" })
        #expect(solution.travelerID == partner.id)

        let second = engine.generate(
            context: context(destination: dest, days: 8, bag: .checked, party: party),
            existing: first
        )
        let solutionAgain = try #require(second.first { $0.canonicalItemID == "toiletries.contacts_solution" })
        #expect(solutionAgain.travelerID == partner.id, "owner must not drift to a different traveler on regeneration")
    }

    /// A manually reassigned carrier (`assignedTravelerID`, set from the UI
    /// without marking the item user-modified) survives regeneration —
    /// distinct from the owner, and `resolve` only fills a carrier in when
    /// none was chosen.
    @Test func manuallyReassignedCarrierSurvivesRegeneration() throws {
        var partner = Traveler(name: "Sam", role: .partner, ageGroup: .adult)
        partner.chips = [.wearContacts]
        let party = TripParty(travelMode: .couple, travelers: [Traveler.primarySelf(), partner])
        let engine = try makeEngine()
        let dest = try destination("Chicago")
        var first = engine.generate(context: context(destination: dest, days: 5, bag: .checked, party: party))
        guard let index = first.firstIndex(where: { $0.canonicalItemID == "toiletries.contacts_solution" }) else {
            Issue.record("Expected toiletries.contacts_solution for the partner")
            return
        }
        #expect(first[index].assignedTravelerID == partner.id, "carrier defaults to the owner")
        // The UI can reassign a carrier without marking the item user-modified.
        first[index].assignedTravelerID = party.primary.id

        let second = engine.generate(
            context: context(destination: dest, days: 8, bag: .checked, party: party),
            existing: first
        )
        let solution = try #require(second.first { $0.canonicalItemID == "toiletries.contacts_solution" })
        #expect(
            solution.assignedTravelerID == party.primary.id,
            "an explicit carrier reassignment must survive regeneration even without isUserModified"
        )
        #expect(solution.travelerID == partner.id, "the owner is unchanged by a carrier reassignment")
    }

    // MARK: - Family sharing (fixture 12 is the risk, not the gate)

    /// Sunscreen shared across the party is right; medication never is; a
    /// stroller belongs to the group. These must hold as the sharing rules
    /// evolve.
    @Test func familySharingKeepsMedicationPersonal() throws {
        let rules = try SharedLibrary.rules()
        let medicationIDs = ["health.daily_medication", "kids.medication", "health.prescription_copy"]
        for id in medicationIDs {
            #expect(!rules.party.sharedByDefault.contains(id), "\(id) must never be shared by default")
        }

        var partner = Traveler(name: "Sam", role: .partner, ageGroup: .adult)
        partner.chips = [.dailyMedication]
        let party = TripParty(
            travelMode: .family,
            travelers: [Traveler.primarySelf(), partner, Traveler(name: "Emma", role: .child, ageGroup: .toddler)]
        )
        let generation = try makeEngine().generateDetailed(
            context: context(destination: try destination("Chicago"), days: 7, bag: .checked, party: party)
        )
        let medication = generation.items.filter { $0.canonicalItemID == "health.daily_medication" }
        #expect(medication.count == 1)
        #expect(medication.first?.ownershipType == .personal)
        #expect(medication.first?.travelerID == partner.id, "the partner's medication belongs to the partner")
        // Its companion follows the trigger's owner, not the shared pile.
        let copy = generation.items.first { $0.canonicalItemID == "health.prescription_copy" }
        if let copy {
            #expect(copy.ownershipType == .personal)
            #expect(copy.travelerID == partner.id)
        }
        let shared = generation.items.filter { $0.ownershipType == .shared }.compactMap(\.canonicalItemID)
        #expect(!shared.contains("health.daily_medication"))
    }

    // MARK: - Task 4: sharing policy scenarios (gates 3, 4, 12)

    private func rainyContext(party: TripParty) throws -> TripContext {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        let rainy = forecast(start: start, days: 5, high: 65, low: 55, rain: 0.7)
        return context(destination: try destination("Chicago"), party: party, weather: rainy)
    }

    private func sunnyContext(party: TripParty) throws -> TripContext {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        let sunny = forecast(start: start, days: 5, high: 95, low: 75, rain: 0.1, uv: 8)
        return context(destination: try destination("Chicago"), party: party, weather: sunny)
    }

    /// A couple with rain in the forecast gets one shared umbrella
    /// (`scaleByParty`, `per: 2`, `min: 1`) — the exact case the task names.
    @Test func coupleWithRainSharesOneUmbrellaNotOnePerPerson() throws {
        let engine = try makeEngine()
        let couple = TripParty(travelMode: .couple, travelers: [Traveler.primarySelf(), Traveler(name: "Sam", role: .partner, ageGroup: .adult)])
        let items = engine.generate(context: try rainyContext(party: couple))
        let umbrellas = items.filter { $0.canonicalItemID == "essentials.umbrella_compact" }
        #expect(umbrellas.count == 1)
        #expect(umbrellas.first?.ownershipType == .shared)
        #expect(umbrellas.first?.quantity == 1, "per:2 with a 2-person party rounds up to 1")
        #expect(umbrellas.first?.quantityReason.localizedCaseInsensitiveContains("group") == true)
    }

    /// A family of 5 scales sunscreen (`scaleByParty`, `per: 3`, `min: 1`) —
    /// one bottle per three travelers, rounded up, never one per person.
    @Test func familyOfFiveScalesSharedSunscreenByPartySize() throws {
        let engine = try makeEngine()
        let party = TripParty(travelMode: .family, travelers: [
            Traveler.primarySelf(), Traveler(name: "Sam", role: .partner, ageGroup: .adult),
            Traveler(name: "Jo", role: .child, ageGroup: .teen),
            Traveler(name: "Ali", role: .child, ageGroup: .child),
            Traveler(name: "Em", role: .child, ageGroup: .toddler)
        ])
        let items = engine.generate(context: try sunnyContext(party: party))
        let sunscreen = try #require(items.first { $0.canonicalItemID == "toiletries.sunscreen" })
        #expect(sunscreen.ownershipType == .shared)
        #expect(sunscreen.quantity == 2, "ceil(5/3) = 2")
    }

    /// `scaleByDevices` (travel adapter) scales by adult/teen count, not full
    /// party size — a toddler doesn't carry a device. Uses an explicit
    /// `travelingInternationally` chip rather than a `.international` trip
    /// type (no such `TripType` case exists) to make the adapter a candidate.
    @Test func travelAdapterScalesByDeviceCarryingTravelersOnly() throws {
        let engine = try makeEngine()
        let party = TripParty(travelMode: .family, travelers: [
            Traveler.primarySelf(), Traveler(name: "Sam", role: .partner, ageGroup: .adult),
            Traveler(name: "Em", role: .child, ageGroup: .toddler)
        ])
        let items = engine.generate(context: context(destination: try destination("Chicago"), chips: [.travelingInternationally], party: party))
        let adapter = try #require(items.first { $0.canonicalItemID == "electronics.travel_adapter" })
        #expect(adapter.quantity == 1, "ceil(2 adults / 2 per) = 1, the toddler does not count")
    }

    /// An explicit party item with no chosen traveler stays unassigned rather
    /// than being guessed onto the primary — `PackingEngine`'s fail-safe,
    /// exercised generically (Task 3's F-5 test exercises the same path
    /// specifically for the flashlight).
    @Test func ambiguousExplicitPersonalItemStaysUnassignedInAPartyList() throws {
        let engine = try makeEngine()
        let couple = TripParty(travelMode: .couple, travelers: [Traveler.primarySelf(), Traveler(name: "Sam", role: .partner, ageGroup: .adult)])
        let extra = PackingItemDraft(
            canonicalItemID: nil, displayName: "Shared travel journal", category: .travelComfort,
            quantity: 1, importance: .optional, sourceSignals: [.userPreference], reason: "Added by you",
            isUserAdded: true, ownershipType: .personal, travelerID: nil
        )
        let generation = engine.generateDetailed(context: context(destination: try destination("Chicago"), party: couple), existing: [extra])
        let unassigned = try #require(generation.items.first { $0.id == extra.id })
        #expect(unassigned.travelerID == nil)
        #expect(unassigned.ownershipType == .personal, "stays personal-but-unowned, not silently promoted to shared")
    }
}
