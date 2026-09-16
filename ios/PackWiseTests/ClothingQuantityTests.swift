import Foundation
import Testing
@testable import PackWise

/// Property tests for the clothing quantity model — Engine V2 plan, Step 2.
///
/// These assert at the need level (directly on the policies), not per canonical
/// item, so substitution landing in Step 3 cannot turn a correct replacement
/// into a false monotonicity failure.
struct ClothingQuantityTests {
    /// The constraint chain from the plan, loosest packing to heaviest.
    private static let chain: [(style: PackingStyle, bag: BagType, laundry: LaundryAccess)] = [
        (.light, .personalItem, .planned),
        (.light, .carryOn, .planned),
        (.balanced, .carryOn, .possible),
        (.balanced, .checked, .none),
        (.prepared, .checked, .none)
    ]

    private static let dayGrid = [1, 2, 3, 5, 8, 10, 15, 21, 30]

    @Test func clothingContextProjectsOnlyNormalizedSnapshotFields() throws {
        let destination = try #require(try SharedLibrary.testDestinations().first)
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        let end = Calendar.current.date(byAdding: .day, value: 4, to: start)!
        var raw = TripContext(
            destination: destination,
            startDate: start,
            endDate: end,
            durationDays: 999,
            durationNights: 998,
            tripTypes: [.cityBreak],
            activities: ["running"],
            datedActivities: [DatedActivity(activityID: "running", date: start)],
            bagTypes: [.carryOn],
            packingStyle: .light,
            transportation: .unknown,
            laundryAccess: .none,
            travelerCount: 1,
            userNotes: "Laundry may be available",
            contextChips: [],
            weather: nil,
            preferences: .deviceDefaults()
        )
        raw.party = .solo()
        let snapshot = TripContextCompiler.compile(raw, rules: try SharedLibrary.rules())

        let clothing = ClothingQuantityContext(snapshot: snapshot)

        #expect(clothing.days == 5)
        #expect(clothing.laundry == .possible)
        #expect(clothing.selectedActivityIDs == ["running"])
        #expect(clothing.datedActivityUses == ["running": 1])
        #expect(clothing.party == snapshot.party)
    }

    private func value(
        _ policy: ClothingNeedPolicy,
        days: Int,
        style: PackingStyle,
        bag: BagType,
        laundry: LaundryAccess
    ) -> Int {
        let activities: Set<String>
        switch policy.usage {
        case let .workout(ids), let .swim(ids):
            activities = Set(ids.prefix(1))
        case .daily, .sleep:
            activities = []
        }
        let context = clothingContext(
            days: days,
            style: style,
            bag: bag,
            laundry: laundry,
            selectedActivityIDs: activities
        )
        return ClothingQuantityEngine.evaluate(policy, context: context).value
    }

    private func clothingContext(
        days: Int,
        style: PackingStyle = .balanced,
        bag: BagType = .carryOn,
        laundry: LaundryAccess = .none,
        selectedActivityIDs: Set<String> = [],
        datedActivityUses: [String: Int] = [:]
    ) -> ClothingQuantityContext {
        ClothingQuantityContext(
            days: days,
            style: style,
            luggage: .resolve(Set([bag])),
            laundry: laundry,
            selectedActivityIDs: selectedActivityIDs,
            datedActivityUses: datedActivityUses,
            party: .solo()
        )
    }

    private func engineContext(
        days: Int,
        tripType: TripType = .vacation,
        activities: [String] = [],
        datedActivities: [DatedActivity] = [],
        bag: BagType = .carryOn,
        style: PackingStyle = .balanced,
        laundry: LaundryAccess = .none,
        userNotes: String = "",
        party: TripParty = .solo()
    ) throws -> TripContext {
        let destination = try #require(try SharedLibrary.testDestinations().first { $0.city == "Chicago" })
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        let end = Calendar.current.date(byAdding: .day, value: days - 1, to: start)!
        let math = TripDateMath.daysAndNights(from: start, to: end)
        var preferences = TravelerPreferences.deviceDefaults()
        preferences.homeCountryCode = "US"
        preferences.homeCountrySource = .userConfirmed
        return TripContext(
            destination: destination,
            startDate: start,
            endDate: end,
            durationDays: math.days,
            durationNights: math.nights,
            tripTypes: [tripType],
            activities: activities,
            datedActivities: datedActivities,
            bagTypes: Set([bag].filter(BagType.stableOrder.contains)),
            packingStyle: style,
            transportation: .unknown,
            laundryAccess: laundry,
            travelerCount: party.travelers.count,
            userNotes: userNotes,
            contextChips: [],
            weather: nil,
            preferences: preferences,
            party: party
        )
    }

    // MARK: - Property 1: global non-decreasing

    /// Quantities are non-decreasing (not strictly increasing) across the
    /// constraint chain — flat sequences like sleepwear 1→1→1→2→2 are correct.
    @Test func quantitiesNonDecreasingAcrossConstraintChain() {
        for policy in ClothingNeedPolicy.all {
            for days in Self.dayGrid {
                let values = Self.chain.map {
                    value(policy, days: days, style: $0.style, bag: $0.bag, laundry: $0.laundry)
                }
                for i in 1..<values.count {
                    #expect(
                        values[i] >= values[i - 1],
                        "\(policy.needID) at \(days)d decreased across the chain: \(values)"
                    )
                }
            }
        }
    }

    // MARK: - Property 2: declared sensitivity must bite

    /// Every declared sensitivity produces at least one strict divergence.
    /// This is what keeps settings from becoming decorative — a policy that
    /// claims to care about laundry and never changes its output is a bug.
    @Test func declaredSensitivitiesProduceStrictDivergence() {
        let days = [5, 10, 15, 30]
        let styles = PackingStyle.allCases
        let bags: [BagType] = [.personalItem, .carryOn, .checked]

        for policy in ClothingNeedPolicy.all {
            if policy.influences.contains(.laundry) {
                let diverges = days.contains { d in
                    styles.contains { s in
                        bags.contains { b in
                            value(policy, days: d, style: s, bag: b, laundry: .planned)
                                != value(policy, days: d, style: s, bag: b, laundry: .none)
                        }
                    }
                }
                #expect(diverges, "\(policy.needID) declares laundry sensitivity but never diverges")
            }
            if policy.influences.contains(.style) {
                let diverges = days.contains { d in
                    bags.contains { b in
                        LaundryAccess.allCases.contains { l in
                            value(policy, days: d, style: .light, bag: b, laundry: l)
                                != value(policy, days: d, style: .prepared, bag: b, laundry: l)
                        }
                    }
                }
                #expect(diverges, "\(policy.needID) declares style sensitivity but never diverges")
            }
            if policy.influences.contains(.bag) {
                let diverges = days.contains { d in
                    styles.contains { s in
                        LaundryAccess.allCases.contains { l in
                            value(policy, days: d, style: s, bag: .personalItem, laundry: l)
                                != value(policy, days: d, style: s, bag: .checked, laundry: l)
                        }
                    }
                }
                #expect(diverges, "\(policy.needID) declares bag sensitivity but never diverges")
            }
        }
    }

    // MARK: - Property 3: plateau

    /// With planned laundry, 30 days packs within ±1 of 15 days for every
    /// need. Above the wash cycle, duration stops mattering.
    @Test func plannedLaundryPlateausAboveWashCycle() {
        for policy in ClothingNeedPolicy.all {
            for style in PackingStyle.allCases {
                for bag in [BagType.carryOn, .checked] {
                    let fifteen = value(policy, days: 15, style: style, bag: bag, laundry: .planned)
                    let thirty = value(policy, days: 30, style: style, bag: bag, laundry: .planned)
                    #expect(
                        abs(thirty - fifteen) <= 1,
                        "\(policy.needID) \(style)/\(bag): 15d=\(fifteen) vs 30d=\(thirty)"
                    )
                }
            }
        }
    }

    // MARK: - Property 4: contextual bounds

    /// Bounds are keyed to policy and context, not global constants: socks
    /// plateau near interval + buffer under planned laundry, but an 18-day
    /// no-laundry prepared trip may legitimately exceed the once-global
    /// "socks ≤ 10" and grow to the policy maximum instead.
    @Test func boundsAreContextualNotGlobal() throws {
        let socks = try #require(ClothingNeedPolicy.byKind["daily_socks"])
        for days in stride(from: 8, through: 30, by: 2) {
            for style in PackingStyle.allCases {
                let planned = value(socks, days: days, style: style, bag: .carryOn, laundry: .planned)
                let buffer = socks.styleBuffer[style] ?? 0
                #expect(
                    planned <= socks.washIntervalDays + buffer,
                    "socks with planned laundry should plateau near interval + buffer, got \(planned) at \(days)d"
                )
            }
        }
        let coldLongTrip = value(socks, days: 18, style: .prepared, bag: .checked, laundry: .none)
        #expect(coldLongTrip > 10, "a global socks ≤ 10 bound would wrongly cap this trip")
        #expect(coldLongTrip == socks.styleMaximum[.prepared], "no-laundry growth stops at the policy maximum")
    }

    /// Global sanity bounds are limited to floors that are always true.
    @Test func globalFloorsHold() throws {
        let tops = try #require(ClothingNeedPolicy.byKind["daily_top"])
        let underwear = try #require(ClothingNeedPolicy.byKind["daily_underwear"])
        for days in Self.dayGrid {
            for style in PackingStyle.allCases {
                for bag in [BagType.personalItem, .carryOn, .checked] {
                    for laundry in LaundryAccess.allCases {
                        #expect(value(tops, days: days, style: style, bag: bag, laundry: laundry) >= 2)
                        #expect(value(underwear, days: days, style: style, bag: bag, laundry: laundry) >= 2)
                    }
                }
            }
        }
    }

    // MARK: - Formal tops satisfy daily-top uses

    /// Two dress shirts plus the one nice-dinner outfit on a five-day
    /// prepared business trip cover three appearance uses. The remaining two
    /// daily uses plus the prepared buffer produce four t-shirts, rather than
    /// inflating every overlapping appearance signal independently.
    @Test func formalTopsReduceDailyTopCount() throws {
        let engine = PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
        let destination = try SharedLibrary.testDestinations().first { $0.city == "Chicago" }!
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        let end = Calendar.current.date(byAdding: .day, value: 4, to: start)!
        let math = TripDateMath.daysAndNights(from: start, to: end)
        var prefs = TravelerPreferences.deviceDefaults()
        prefs.homeCountryCode = "US"
        prefs.homeCountrySource = .userConfirmed
        let context = TripContext(
            destination: destination,
            startDate: start,
            endDate: end,
            durationDays: math.days,
            durationNights: math.nights,
            tripTypes: [.business],
            activities: ["work", "niceDinner"],
            datedActivities: [],
            bagTypes: [.checked],
            packingStyle: .prepared,
            transportation: .unknown,
            laundryAccess: .none,
            travelerCount: 1,
            userNotes: "",
            contextChips: [],
            weather: nil,
            preferences: prefs
        )
        let items = engine.generate(context: context)
        let dress = items.first { $0.canonicalItemID == "clothing.dress_shirt" }
        let tshirt = items.first { $0.canonicalItemID == "clothing.tshirt" }
        #expect(dress?.quantity == 2)
        #expect(tshirt?.quantity == 4, "2 remaining daily uses + prepared buffer of 2")
    }

    @Test func formalOffsetRespectsFloorAndScope() throws {
        let tops = try #require(ClothingNeedPolicy.byKind["daily_top"])
        let socks = try #require(ClothingNeedPolicy.byKind["daily_socks"])
        #expect(
            ClothingQuantityEngine.compute(tops, days: 5, style: .prepared, luggage: .resolve([.checked]), laundry: .none, formalTopUnits: 10) == 2,
            "any number of formal tops still leaves the floor of two daily tops"
        )
        #expect(
            ClothingQuantityEngine.compute(socks, days: 5, style: .prepared, luggage: .resolve([.checked]), laundry: .none, formalTopUnits: 10)
                == ClothingQuantityEngine.compute(socks, days: 5, style: .prepared, luggage: .resolve([.checked]), laundry: .none),
            "the offset applies only to the daily-top need"
        )
    }

    // MARK: - Task 4: laundry ordering

    /// The three `LaundryAccess` states must never invert: `planned` (wash
    /// regularly) is never heavier than `possible` (wash sometimes), which
    /// is never heavier than `none` (no laundry, pack for the whole trip).
    /// Scoped to policies that declare laundry sensitivity — a `.none`
    /// policy is free to hold the three states equal.
    @Test func laundryOrderingNeverInvertsForSensitivePolicies() {
        let days = [1, 3, 5, 8, 10, 15, 21, 30]
        let bags: [BagType] = [.personalItem, .carryOn, .checked]

        for policy in ClothingNeedPolicy.all where policy.influences.contains(.laundry) {
            for d in days {
                for style in PackingStyle.allCases {
                    for bag in bags {
                        let planned = value(policy, days: d, style: style, bag: bag, laundry: .planned)
                        let possible = value(policy, days: d, style: style, bag: bag, laundry: .possible)
                        let none = value(policy, days: d, style: style, bag: bag, laundry: .none)
                        #expect(
                            planned <= possible,
                            "\(policy.needID) \(d)d \(style)/\(bag): planned=\(planned) > possible=\(possible)"
                        )
                        #expect(
                            possible <= none,
                            "\(policy.needID) \(d)d \(style)/\(bag): possible=\(possible) > none=\(none)"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Task 4: style and bag ordering

    /// Style loosens from `.light` to `.prepared` — reuse assumptions ease
    /// and buffers grow, so quantity never drops as style relaxes.
    @Test func styleOrderingNeverInverts() {
        let days = [1, 3, 5, 8, 10, 15, 21, 30]
        let bags: [BagType] = [.personalItem, .carryOn, .checked]

        for policy in ClothingNeedPolicy.all {
            for d in days {
                for bag in bags {
                    for laundry in LaundryAccess.allCases {
                        let light = value(policy, days: d, style: .light, bag: bag, laundry: laundry)
                        let balanced = value(policy, days: d, style: .balanced, bag: bag, laundry: laundry)
                        let prepared = value(policy, days: d, style: .prepared, bag: bag, laundry: laundry)
                        #expect(light <= balanced, "\(policy.needID) \(d)d \(bag)/\(laundry): light=\(light) > balanced=\(balanced)")
                        #expect(balanced <= prepared, "\(policy.needID) \(d)d \(bag)/\(laundry): balanced=\(balanced) > prepared=\(prepared)")
                    }
                }
            }
        }
    }

    /// Bag space only ever loosens a cap, never tightens it, as the bag
    /// goes from a personal item to a constrained bag to an unconstrained
    /// one — by construction of `resolve`'s `min(buffered, cap)`.
    @Test func bagOrderingNeverInverts() {
        let days = [1, 3, 5, 8, 10, 15, 21, 30]

        for policy in ClothingNeedPolicy.all {
            for d in days {
                for style in PackingStyle.allCases {
                    for laundry in LaundryAccess.allCases {
                        let personal = value(policy, days: d, style: style, bag: .personalItem, laundry: laundry)
                        let carryOn = value(policy, days: d, style: style, bag: .carryOn, laundry: laundry)
                        let checked = value(policy, days: d, style: style, bag: .checked, laundry: laundry)
                        #expect(personal <= carryOn, "\(policy.needID) \(d)d \(style)/\(laundry): personalItem=\(personal) > carryOn=\(carryOn)")
                        #expect(carryOn <= checked, "\(policy.needID) \(d)d \(style)/\(laundry): carryOn=\(carryOn) > checked=\(checked)")
                    }
                }
            }
        }
    }

    // MARK: - Task 4: declared minimum and resolved maximum

    /// The style/bag cap actually enforced by `resolve` — the plan's
    /// `resolvedMaximum`. Mirrors the private capping logic in
    /// `ClothingQuantityEngine.resolve` so the bound is a real contextual
    /// ceiling, not a restated global constant.
    private func resolvedMaximum(_ policy: ClothingNeedPolicy, style: PackingStyle, bag: BagType) -> Int {
        var cap = policy.styleMaximum[style] ?? Int.max
        if bag == .personalItem {
            cap = min(cap, policy.personalItemMaximum)
        } else if [BagType.carryOn, .backpack].contains(bag) {
            cap = min(cap, policy.constrainedBagMaximum)
        }
        return cap
    }

    /// Every computed quantity sits between the policy's declared floor and
    /// its context-resolved ceiling — never below the minimum a traveler
    /// needs, never above what the style/bag combination allows.
    ///
    /// Caveat for `.sleep`: `ClothingQuantityEngine.compute()`'s `.sleep`
    /// branch returns a hardcoded `days >= 6 && style != .light ? 2 : 1`
    /// directly and never calls `resolve()`, so it never reads
    /// `styleMaximum`/`personalItemMaximum`/`constrainedBagMaximum` at all.
    /// The upper-bound assertion below passes for sleepwear only because
    /// that hardcoded output (1 or 2) happens to fit under the declared
    /// caps — not because those caps are actually enforced. Tracked as
    /// dead code for Task 6; do not read a green run here as proof that
    /// sleepwear's caps are wired up.
    @Test func everyPolicyStaysWithinItsDeclaredMinimumAndResolvedMaximum() {
        let bags: [BagType] = [.personalItem, .carryOn, .backpack, .checked, .roadTripLuggage]

        for policy in ClothingNeedPolicy.all {
            for d in Self.dayGrid {
                for style in PackingStyle.allCases {
                    for bag in bags {
                        for laundry in LaundryAccess.allCases {
                            let result = value(policy, days: d, style: style, bag: bag, laundry: laundry)
                            #expect(result >= policy.minimum, "\(policy.needID) \(d)d \(style)/\(bag)/\(laundry): \(result) below minimum \(policy.minimum)")
                            let ceiling = resolvedMaximum(policy, style: style, bag: bag)
                            #expect(result <= ceiling, "\(policy.needID) \(d)d \(style)/\(bag)/\(laundry): \(result) above resolved maximum \(ceiling)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Task 4: formal-top offset is scoped to daily_top

    /// `offsetByFormalTops` is declared true for exactly one need. Every
    /// other policy must be inert to `formalTopUnits` — the parameter is
    /// plumbed through every clothing need's `compute` call, so scope must
    /// come from the declaration, not from the caller only ever passing it
    /// to the daily-top need.
    @Test func formalTopOffsetIsInertOutsideDailyTop() {
        let scoped = ClothingNeedPolicy.all.filter(\.offsetByFormalTops)
        #expect(scoped.map(\.needID) == ["clothing.daily_top"])

        for policy in ClothingNeedPolicy.all where !policy.offsetByFormalTops {
            for d in [3, 5, 10] {
                for style in PackingStyle.allCases {
                    let activities: Set<String>
                    switch policy.usage {
                    case let .workout(ids), let .swim(ids): activities = Set(ids.prefix(1))
                    case .daily, .sleep: activities = []
                    }
                    let context = clothingContext(
                        days: d,
                        style: style,
                        bag: .checked,
                        laundry: .none,
                        selectedActivityIDs: activities
                    )
                    let withoutOffset = ClothingQuantityEngine.evaluate(policy, context: context).value
                    let withOffset = ClothingQuantityEngine.evaluate(policy, context: context, appearanceUnits: 5).value
                    #expect(
                        withoutOffset == withOffset,
                        "\(policy.needID) \(d)d \(style): formalTopUnits changed a non-offset need"
                    )
                }
            }
        }
    }

    // MARK: - Property 5: preservation

    /// A manual quantity edit survives regeneration with fresh weather. The
    /// golden fixtures 13/14 hold the full-output version of this guarantee.
    @Test func manualQuantitySurvivesWeatherRefresh() async throws {
        let engine = PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
        let destination = try SharedLibrary.testDestinations().first { $0.city == "Tokyo" }!
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 6))!
        let end = Calendar.current.date(byAdding: .day, value: 14, to: start)!
        let math = TripDateMath.daysAndNights(from: start, to: end)
        var prefs = TravelerPreferences.deviceDefaults()
        prefs.homeCountryCode = "US"
        prefs.homeCountrySource = .userConfirmed

        func context(weather: TripWeatherContext?) -> TripContext {
            TripContext(
                destination: destination,
                startDate: start,
                endDate: end,
                durationDays: math.days,
                durationNights: math.nights,
                tripTypes: [.vacation],
                activities: ["walking", "running"],
                datedActivities: [],
                bagTypes: [.carryOn],
                packingStyle: .light,
                transportation: .unknown,
                laundryAccess: .possible,
                travelerCount: 1,
                userNotes: "",
                contextChips: [],
                weather: weather,
                preferences: prefs
            )
        }

        let first = engine.generate(context: context(weather: nil))
        var tshirt = try #require(first.first { $0.canonicalItemID == "clothing.tshirt" })
        tshirt.quantity = 3
        tshirt.packedQuantity = 2
        tshirt.isUserModified = true
        let existing = first.map { $0.id == tshirt.id ? tshirt : $0 }

        let fixtures = try SharedLibrary.weatherFixtures()
        let weather = MockWeatherService.context(
            from: fixtures["TokyoMildSpring"]!,
            start: start,
            end: end,
            fixtureID: "TokyoMildSpring"
        )
        let refreshed = engine.generate(context: context(weather: weather), existing: existing)
        let preserved = refreshed.first { $0.canonicalItemID == "clothing.tshirt" }
        #expect(preserved?.quantity == 3)
        #expect(preserved?.packedQuantity == 2)
    }

    @Test func explicitWorkoutUsesDriveQuantityInsteadOfTripLength() throws {
        let policy = try #require(ClothingNeedPolicy.byKind["workout_top"])
        let fifteenDays = clothingContext(
            days: 15,
            laundry: .none,
            selectedActivityIDs: ["running"],
            datedActivityUses: ["running": 3]
        )
        let thirtyDays = clothingContext(
            days: 30,
            laundry: .none,
            selectedActivityIDs: ["running"],
            datedActivityUses: ["running": 3]
        )

        #expect(ClothingQuantityEngine.evaluate(policy, context: fifteenDays).value == 3)
        #expect(ClothingQuantityEngine.evaluate(policy, context: thirtyDays).value == 3)
    }

    @Test func workoutLaundryReducesDenseScheduledUses() throws {
        let policy = try #require(ClothingNeedPolicy.byKind["workout_top"])
        let none = clothingContext(
            days: 15,
            laundry: .none,
            selectedActivityIDs: ["running"],
            datedActivityUses: ["running": 6]
        )
        var planned = none
        planned.laundry = .planned
        var possible = none
        possible.laundry = .possible

        let noneValue = ClothingQuantityEngine.evaluate(policy, context: none).value
        let possibleValue = ClothingQuantityEngine.evaluate(policy, context: possible).value
        let plannedValue = ClothingQuantityEngine.evaluate(policy, context: planned).value
        #expect(plannedValue < noneValue)
        #expect(plannedValue <= possibleValue)
        #expect(possibleValue <= noneValue)
    }

    @Test func swimwearUsesDryingRotationInsteadOfOnePerDay() throws {
        let policy = try #require(ClothingNeedPolicy.byKind["swimwear"])
        let oneSwim = clothingContext(
            days: 10,
            selectedActivityIDs: ["swimming"],
            datedActivityUses: ["swimming": 1]
        )
        let manySwims = clothingContext(
            days: 30,
            selectedActivityIDs: ["swimming"],
            datedActivityUses: ["swimming": 8]
        )

        #expect(ClothingQuantityEngine.evaluate(policy, context: oneSwim).value == 1)
        #expect(ClothingQuantityEngine.evaluate(policy, context: manySwims).value == 2)
    }

    @Test func policyResultCarriesStructuredQuantityEvidence() throws {
        let policy = try #require(ClothingNeedPolicy.byKind["daily_top"])
        let context = clothingContext(days: 15, style: .light, bag: .personalItem, laundry: .planned)

        let result = ClothingQuantityEngine.evaluate(policy, context: context, appearanceUnits: 2, ageMultiplier: 1.15)

        #expect(result.evidence.policyID == "clothing.daily_top")
        #expect(result.evidence.basis == "dailyWear")
        #expect(result.evidence.requiredUses == 13)
        #expect(result.evidence.washIntervalDays == 7)
        #expect(result.evidence.laundryPlan == .planned)
        #expect(result.evidence.laundryReduced)
        #expect(result.evidence.appearanceOffsetUses == 2)
        #expect(result.evidence.ageMultiplier == 1.15)
        #expect(result.evidence.quantity == result.value)
    }

    @Test func packingItemDraftDefaultsToNoQuantityEvidence() {
        let item = PackingItemDraft(
            canonicalItemID: "essentials.wallet",
            displayName: "Wallet",
            category: .essentials,
            quantity: 1,
            importance: .critical,
            sourceSignals: [],
            reason: ""
        )

        #expect(item.quantityEvidence == nil)
    }

    @Test func engineClothingUsesNormalizedDurationAndLegacyLaundrySignal() throws {
        let engine = PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
        var context = try engineContext(days: 15, style: .light, laundry: .none, userNotes: "Laundry may be available")
        context.durationDays = 1
        context.durationNights = 0
        let snapshot = TripContextCompiler.compile(context, rules: try SharedLibrary.rules())
        let policy = try #require(ClothingNeedPolicy.byKind["daily_top"])
        let expected = ClothingQuantityEngine.evaluate(policy, context: ClothingQuantityContext(snapshot: snapshot)).value

        let tshirt = try #require(engine.generate(context: context).first { $0.canonicalItemID == "clothing.tshirt" })

        #expect(tshirt.quantity == expected)
        #expect(tshirt.quantityEvidence?.laundryPlan == .possible)
        #expect(tshirt.quantityEvidence?.requiredUses == 15)
    }

    @Test func engineWorkoutQuantityUsesExplicitDatedSessions() throws {
        let engine = PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
        var context = try engineContext(days: 15, activities: ["running"])
        context.datedActivities = [0, 3, 7].map { offset in
            DatedActivity(
                activityID: "running",
                date: Calendar.current.date(byAdding: .day, value: offset, to: context.startDate)
            )
        }

        let top = try #require(engine.generate(context: context).first { $0.canonicalItemID == "clothing.workout_top" })

        #expect(top.quantity == 3)
        #expect(top.quantityEvidence?.basis == "datedActivityUses")
        #expect(top.quantityEvidence?.requiredUses == 3)
    }

    @Test func swimsuitGetsDryingRotationWithoutDailyScaling() throws {
        let engine = PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
        let context = try engineContext(
            days: 5,
            tripType: .beach,
            activities: ["swimming", "beachDays"],
            bag: .personalItem,
            style: .light,
            laundry: .possible
        )

        let swimsuit = try #require(engine.generate(context: context).first { $0.canonicalItemID == "clothing.swimsuit" })

        #expect(swimsuit.quantity == 2)
        #expect(swimsuit.quantityEvidence?.basis == "dryingRotation")
    }

    @Test func niceOutfitOffsetsDailyTopOnceWithoutInflatingAppearanceItems() throws {
        let engine = PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
        let context = try engineContext(
            days: 5,
            tripType: .business,
            activities: ["work", "niceDinner"],
            bag: .checked,
            style: .prepared,
            laundry: .none
        )
        let items = engine.generate(context: context)

        #expect(items.first { $0.canonicalItemID == "clothing.dress_shirt" }?.quantity == 2)
        #expect(items.first { $0.canonicalItemID == "clothing.nice_outfit" }?.quantity == 1)
        let tshirt = try #require(items.first { $0.canonicalItemID == "clothing.tshirt" })
        #expect(tshirt.quantity == 4)
        #expect(tshirt.quantityEvidence?.appearanceOffsetUses == 3)
    }

    @Test func explicitlyAttributedToddlerUsesExistingAgeBufferAndEvidence() throws {
        let adult = Traveler(role: .self, ageGroup: .adult)
        var toddler = Traveler(role: .child, ageGroup: .toddler)
        toddler.guardianTravelerID = adult.id
        let party = TripParty(travelMode: .family, travelers: [adult, toddler])
        let context = try engineContext(days: 7, style: .balanced, party: party)
        let engine = PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())

        let toddlerTop = try #require(
            engine.generate(context: context).first {
                $0.canonicalItemID == "clothing.tshirt" && $0.travelerID == toddler.id
            }
        )

        #expect(toddlerTop.quantityEvidence?.ageMultiplier == 1.75)
        #expect(toddlerTop.quantityEvidence?.quantity == toddlerTop.quantity)
    }

    // MARK: - Product Experience V2, Task 5: luggage capacity

    /// Representative clothing on one 14-day no-laundry Miami trip (running,
    /// swimming, beach days), Balanced. Carry-on + Checked sizes exactly like
    /// Checked; quantities move only through the existing capacity caps, and
    /// a second bag never adds clothes.
    @Test func representativeClothingFollowsCapacityNotBagCount() throws {
        let engine = PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
        let destination = try #require(try SharedLibrary.testDestinations().first { $0.city == "Miami" })
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 6))!
        let end = Calendar.current.date(byAdding: .day, value: 13, to: start)!
        func quantities(_ bags: Set<BagType>) -> [String: Int] {
            let math = TripDateMath.daysAndNights(from: start, to: end)
            let context = TripContext(
                destination: destination, startDate: start, endDate: end,
                durationDays: math.days, durationNights: math.nights,
                tripTypes: [.beach], activities: ["running", "swimming", "beachDays"], datedActivities: [], bagTypes: bags,
                packingStyle: .balanced, transportation: .unknown, laundryAccess: .none, travelerCount: 1,
                userNotes: "", contextChips: [], weather: nil, preferences: .deviceDefaults()
            )
            return Dictionary(uniqueKeysWithValues: engine.generate(context: context)
                .compactMap { item in item.canonicalItemID.map { ($0, item.quantity) } })
        }
        let ids = ["clothing.tshirt", "clothing.underwear", "clothing.socks", "clothing.pants",
                   "clothing.sleepwear", "clothing.workout_top", "clothing.workout_bottom", "clothing.swimsuit"]
        let expected: [Set<BagType>: [Int]] = [
            [.carryOn]: [8, 10, 10, 5, 2, 4, 4, 2],
            [.carryOn, .checked]: [12, 12, 12, 6, 2, 5, 5, 2],
            [.personalItem]: [5, 7, 7, 3, 2, 2, 2, 2],
            [.checked]: [12, 12, 12, 6, 2, 5, 5, 2]
        ]
        for (bags, values) in expected {
            let actual = quantities(bags)
            #expect(ids.map { actual[$0] ?? -1 } == values, "\(bags)")
        }
        #expect(quantities([.carryOn, .checked]) .filter { $0.key.hasPrefix("clothing.") }
                == quantities([.checked]).filter { $0.key.hasPrefix("clothing.") })
    }
}
