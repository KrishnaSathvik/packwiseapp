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

    private func value(
        _ policy: ClothingNeedPolicy,
        days: Int,
        style: PackingStyle,
        bag: BagType,
        laundry: LaundryAccess
    ) -> Int {
        ClothingQuantityEngine.compute(policy, days: days, style: style, bag: bag, laundry: laundry)
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
            if policy.laundrySensitivity != .none {
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
            if policy.styleSensitivity != .none {
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
            if policy.bagSensitivity != .none {
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

    /// Two dress shirts on a five-day prepared business trip leave three
    /// days for t-shirts — five with the style buffer, not seven beside the
    /// dress shirts. The offset applies only to the daily-top need, and the
    /// always-true floor of two survives any number of formal tops.
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
            tripType: .business,
            activities: ["work", "niceDinner"],
            datedActivities: [],
            bagType: .checked,
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
        #expect(tshirt?.quantity == 5, "3 remaining days + prepared buffer of 2")
    }

    @Test func formalOffsetRespectsFloorAndScope() throws {
        let tops = try #require(ClothingNeedPolicy.byKind["daily_top"])
        let socks = try #require(ClothingNeedPolicy.byKind["daily_socks"])
        #expect(
            ClothingQuantityEngine.compute(tops, days: 5, style: .prepared, bag: .checked, laundry: .none, formalTopUnits: 10) == 2,
            "any number of formal tops still leaves the floor of two daily tops"
        )
        #expect(
            ClothingQuantityEngine.compute(socks, days: 5, style: .prepared, bag: .checked, laundry: .none, formalTopUnits: 10)
                == ClothingQuantityEngine.compute(socks, days: 5, style: .prepared, bag: .checked, laundry: .none),
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

        for policy in ClothingNeedPolicy.all where policy.laundrySensitivity != .none {
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
        } else if bag.isSpaceConstrained {
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

    // MARK: - Task 4: 15d/30d plateau across every laundry state

    /// Property 3 above pins the plateau under planned laundry. The same
    /// shape holds under `.possible` and `.none` too: the style/bag cap
    /// forces convergence well before 30 days even when nothing is ever
    /// washed.
    @Test func plateauHoldsAcrossEveryLaundryState() {
        for policy in ClothingNeedPolicy.all {
            for style in PackingStyle.allCases {
                for bag in [BagType.carryOn, .checked] {
                    for laundry in LaundryAccess.allCases {
                        let fifteen = value(policy, days: 15, style: style, bag: bag, laundry: laundry)
                        let thirty = value(policy, days: 30, style: style, bag: bag, laundry: laundry)
                        #expect(
                            abs(thirty - fifteen) <= 1,
                            "\(policy.needID) \(style)/\(bag)/\(laundry): 15d=\(fifteen) vs 30d=\(thirty)"
                        )
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
                    let withoutOffset = value(policy, days: d, style: style, bag: .checked, laundry: .none)
                    let withOffset = ClothingQuantityEngine.compute(
                        policy, days: d, style: style, bag: .checked, laundry: .none, formalTopUnits: 5
                    )
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
                tripType: .vacation,
                activities: ["walking", "running"],
                datedActivities: [],
                bagType: .carryOn,
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
        #expect(refreshed.first { $0.canonicalItemID == "clothing.tshirt" }?.quantity == 3)
    }
}
