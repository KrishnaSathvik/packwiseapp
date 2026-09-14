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
            tripTypes: [type],
            activities: activities,
            datedActivities: [],
            bagTypes: Set([bag].filter(BagType.stableOrder.contains)),
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

    // MARK: - Phase 8, Task 1: bagStyleConstraintFact (Amendment 1)

    /// A pure reference reimplementation of optionalRuling's pre-Phase-8
    /// keep/conflictKey behavior — used only to prove the widened function
    /// (which now also surfaces wasConstraintLive/essentialTagProtected/
    /// wouldTrimUnderKey via a behavior-preserving reorder) is byte-identical
    /// on keep/conflictKey for every input the reorder could plausibly
    /// affect.
    private func referenceKeepAndConflictKey(
        importance: ItemImportance,
        tags: [String],
        bag: BagType,
        style: PackingStyle
    ) -> (keep: Bool, conflictKey: String?) {
        guard importance == .optional, bag.appliesBagConstraint, bag.isSpaceConstrained else {
            return (true, nil)
        }
        let isEssentialOptional = tags.contains { ConstraintResolver.essentialOptionalTags.contains($0) }
        if isEssentialOptional { return (true, nil) }
        if bag == .personalItem {
            let key = style == .prepared ? "style.prepared_vs_personal_item" : "bag.personal_item"
            return (false, key)
        }
        if style == .light { return (false, "bag.space_constrained") }
        return (true, nil)
    }

    @Test func optionalRulingReorderIsByteIdenticalOnKeepAndConflictKeyForEveryInput() {
        let tagSets: [[String]] = [[], ["medication"], ["rain"], ["cold"], ["base"], ["unrelated"], ["unrelated", "cold"]]
        for importance in ItemImportance.allCases {
            for bag in BagType.allCases {
                for style in PackingStyle.allCases {
                    for tags in tagSets {
                        let expected = referenceKeepAndConflictKey(importance: importance, tags: tags, bag: bag, style: style)
                        let actual = ConstraintResolver.optionalRuling(importance: importance, tags: tags, bag: bag, style: style)
                        #expect(actual.keep == expected.keep, "importance:\(importance) tags:\(tags) bag:\(bag) style:\(style)")
                        #expect(actual.conflictKey == expected.conflictKey, "importance:\(importance) tags:\(tags) bag:\(bag) style:\(style)")
                    }
                }
            }
        }
    }

    /// A personal-item bag trims optionals unless the item is tagged
    /// essential (rain/cold/medication/base) — an essential-tagged optional
    /// item on this bag survives via protection, and the trace must say so,
    /// not just "kept": `wouldTrimUnderKey` names what it was protected
    /// from.
    @Test func bagStyleConstraintFactRecordsEssentialTagProtectionOnASpaceConstrainedBag() throws {
        let engine = try makeEngine()
        let dest = try destination("Chicago")
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let freezing = forecast(start: start, days: 5, high: 25, low: 15, rain: 0)
        let generation = engine.generateDetailed(context: context(
            destination: dest, days: 5, bag: .personalItem, style: .light, weather: freezing
        ))
        let scarf = try #require(generation.items.first { $0.canonicalItemID == "clothing.scarf" })
        #expect(scarf.bagStyleConstraintFact?.survivedByEssentialTagProtection == true)
        #expect(scarf.bagStyleConstraintFact?.wouldTrimUnderKey == "bag.personal_item")
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

    // MARK: - Phase 8, Task 4: party.shared pluralization (routed finding)

    /// Scenario 12 (Phase 8 required scenarios): a shared quantity greater
    /// than one must not render "One for the group" — the routed finding
    /// from Phase 7's closure. Sunscreen for a family of 4 (`scaleByParty`,
    /// `per: 3`) resolves to quantity 2; the reason text must say "2", not
    /// "One". Reproduces fixture 37's live bug directly.
    @Test func sharedQuantityGreaterThanOneIsNotDescribedAsOneForTheGroup() throws {
        let engine = try makeEngine()
        let party = TripParty(travelMode: .family, travelers: [
            Traveler.primarySelf(), Traveler(name: "Sam", role: .partner, ageGroup: .adult),
            Traveler(name: "Jo", role: .child, ageGroup: .child),
            Traveler(name: "Em", role: .child, ageGroup: .toddler)
        ])
        let items = engine.generate(context: try sunnyContext(party: party))
        let sunscreen = try #require(items.first { $0.canonicalItemID == "toiletries.sunscreen" })
        #expect(sunscreen.quantity == 2, "ceil(4/3) = 2 — unchanged by this fix")
        #expect(sunscreen.quantityReason == "2 for the group — not one per person.")
        #expect(!sunscreen.quantityReason.localizedCaseInsensitiveContains("one for the group"))
        #expect(sunscreen.quantityReasonArguments["quantity"] == "2")
        #expect(sunscreen.quantityReasonArguments["travelerCount"] == "4")
    }

    /// The quantity==1 case must still read "One", not "1" — the wording
    /// this fix must not regress. `health.first_aid` is `singlePerParty`
    /// (always quantity 1 regardless of party size), so a couple still
    /// exercises the shared path at quantity 1.
    @Test func sharedQuantityOfOneStillReadsAsOneForTheGroup() throws {
        let engine = try makeEngine()
        let couple = TripParty(travelMode: .couple, travelers: [Traveler.primarySelf(), Traveler(name: "Sam", role: .partner, ageGroup: .adult)])
        let items = engine.generate(context: context(destination: try destination("Chicago"), type: .outdoor, party: couple))
        let firstAid = try #require(items.first { $0.canonicalItemID == "health.first_aid" })
        #expect(firstAid.ownershipType == .shared)
        #expect(firstAid.quantity == 1)
        #expect(firstAid.quantityReason == "One for the group — not one per person.")
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

    // MARK: - Task 5: dependency authority — user-added equivalent pre-empts the auto-companion

    /// A user who hand-adds the laptop charger themselves (not via the
    /// dependency mechanism, not via an override) pre-empts the automatic
    /// companion — the same de-duplication `companionNotDuplicatedWhenRulesAlreadyEmitIt`
    /// proves for a rules-suggested charger, exercised here for a
    /// user-added one, which is the case the task calls out specifically:
    /// "must respect user-added equivalents."
    @Test func userAddedChargerPreemptsTheAutomaticLaptopCompanion() throws {
        let laptop = PackingItemDraft(
            canonicalItemID: "electronics.laptop", displayName: "Laptop", category: .electronics,
            quantity: 1, importance: .normal, sourceSignals: [.userPreference], reason: "Added by you",
            isUserAdded: true
        )
        let ownCharger = PackingItemDraft(
            canonicalItemID: "electronics.laptop_charger", displayName: "My charger", category: .electronics,
            quantity: 1, importance: .normal, sourceSignals: [.userPreference], reason: "Added by you",
            isUserAdded: true
        )
        let items = try makeEngine().generate(
            context: context(destination: try destination("Chicago")),
            existing: [laptop, ownCharger]
        )
        #expect(items.filter { $0.canonicalItemID == "electronics.laptop_charger" }.count == 1)
        let charger = try #require(items.first { $0.canonicalItemID == "electronics.laptop_charger" })
        #expect(charger.id == ownCharger.id, "the user's own draft survives; the dependency pass never adds a second")
        #expect(charger.displayName == "My charger", "the user's own display name is not overwritten by the companion's rendering")
    }

    // MARK: - Task 6: bag/style conflict gates

    // Gate 1 (Prepared+personal item) is already proven —
    // `preparedVersusPersonalItemResolvesExplicitly` above. No new test.

    /// A checked bag never trims optional extras, regardless of style — the
    /// "checked and road-trip luggage never trim" half of
    /// `optionalRuling`'s doc comment, unproven by any existing test. Compares
    /// against the identical trip on a carry-on, which does trim under Light.
    @Test func lightStyleNeverTrimsOnACheckedBag() throws {
        let engine = try makeEngine()
        let dest = try destination("Chicago")
        let checked = engine.generateDetailed(context: context(destination: dest, type: .vacation, bag: .checked, style: .light))
        let carryOn = engine.generateDetailed(context: context(destination: dest, type: .vacation, bag: .carryOn, style: .light))
        #expect(checked.constraintDecisions.isEmpty, "a checked bag has nothing to trim under any style")
        #expect(!carryOn.constraintDecisions.isEmpty, "the same trip on a carry-on does trim under Light — the contrast proves the bag, not the style, gates the constraint")
    }

    // Gate 2's "prefer critical items / multifunction / compact-high-value,
    // suppress bulky optional backups" charter language is already satisfied
    // by the collaboration between optionalRuling's importance guard (only
    // .optional items are ever touched) and essentialOptionalTags (base/
    // rain/cold/medication tags survive regardless), cited via
    // essentialOptionalTagsSurvivePersonalItem above. No catalog tags for
    // "multifunction"/"compact"/"bulky" exist today, and introducing them
    // would be a catalog-vocabulary expansion outside this phase's file
    // list — the existing importance + essential-tag mechanism already
    // achieves the intended outcome without a new vocabulary.

    // MARK: - Task 7: party/sharing determinism (gate 13)

    /// Two consecutive generations of the same family/camping/sharing-heavy
    /// context produce byte-identical ownership, carrier, and shared-quantity
    /// output — the party-sharing surface Task 1/2 moved is new territory for
    /// a determinism claim; the Phase 1 baseline's whole-ledger determinism
    /// evidence (`docs/engine-audits/2026-09-03-phase-1-baseline.md`) is cited,
    /// not re-derived, for everything else.
    @Test func repeatedGenerationOnASharingHeavyPartyContextIsByteIdentical() throws {
        let party = TripParty(travelMode: .family, travelers: [
            Traveler.primarySelf(), Traveler(name: "Sam", role: .partner, ageGroup: .adult),
            Traveler(name: "Jo", role: .child, ageGroup: .child)
        ])
        let ctx = context(destination: try destination("Chicago"), days: 5, activities: ["hiking", "camping"], bag: .checked, party: party)
        let first = try makeEngine().generateDetailed(context: ctx)
        let second = try makeEngine().generateDetailed(context: ctx)
        // `PackingItemDraft.id` is a fresh `UUID()` per created draft, not
        // part of the determinism claim (ownership, carrier, and
        // shared-quantity output are) — normalized away before comparing,
        // the same way the golden harness excludes UUIDs from its
        // serialized comparison (see this file's header doc comment).
        // travelerID/assignedTravelerID are not normalized: they come from
        // `party`, which is the same value on both calls, so their
        // equality is itself part of what this test proves.
        func normalized(_ items: [PackingItemDraft]) -> [PackingItemDraft] {
            let zeroID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            return items.map { item in
                var copy = item
                copy.id = zeroID
                return copy
            }
        }
        #expect(normalized(first.items) == normalized(second.items))
        #expect(first.constraintDecisions == second.constraintDecisions)
        #expect(first.coverageSuppressions == second.coverageSuppressions)
    }
}
