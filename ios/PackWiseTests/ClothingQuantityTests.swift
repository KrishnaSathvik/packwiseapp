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
