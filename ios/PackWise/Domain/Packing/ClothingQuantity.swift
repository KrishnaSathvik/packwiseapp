import Foundation

/// How strongly a clothing need's quantity claims to respond to an input.
///
/// Declarations, not implementation details: the property tests require every
/// declared sensitivity to produce at least one strict divergence, so a policy
/// cannot claim to care about laundry or bag and then never change its output.
enum NeedSensitivity: Sendable {
    case none
    case low
    case high
}

/// Quantity policy for one clothing need — Engine V2, Step 2 (clothing only).
///
/// Quantity derives from required uses bounded by the reuse cycle, not from
/// trip days:
///
///     planned laundry  → bounded by the wash interval + style buffer
///     possible laundry → conservative reduction, not the full plateau
///     no laundry       → growth capped by policy maximum; bag becomes binding
///
/// Every other family still flows through the legacy `QuantityEngine`.
struct ClothingNeedPolicy: Sendable {
    enum Usage: Sendable {
        /// Worn through the day; reuse varies with packing style.
        case daily
        /// One set, a backup on longer non-light trips. Mirrors V1 exactly.
        case sleep
        /// One set per workout, workout frequency varies with style.
        case workout
    }

    var needID: String
    /// Catalog `quantity_kind` values this need owns. Routing key — the
    /// catalog itself is frozen during this step.
    var kinds: [String]
    var usage: Usage
    /// Days of wear one item gives before it needs washing.
    var wearsPerItem: [PackingStyle: Double]
    /// Days between washes when laundry is planned.
    var washIntervalDays: Int
    /// Style backups, added after the laundry decision.
    var styleBuffer: [PackingStyle: Int]
    var minimum: Int
    /// No-laundry growth stops here even with unlimited space.
    var styleMaximum: [PackingStyle: Int]
    /// Binding cap for carry-on and backpack.
    var constrainedBagMaximum: Int
    /// Binding cap for a personal item only.
    var personalItemMaximum: Int
    /// Formal tops satisfy some of this need's uses: a five-day business
    /// trip with two dress shirts needs daily tops for the remaining days,
    /// not seven t-shirts beside them. True only for the daily-top need.
    var offsetByFormalTops: Bool = false

    var laundrySensitivity: NeedSensitivity
    var styleSensitivity: NeedSensitivity
    var bagSensitivity: NeedSensitivity

    static let all: [ClothingNeedPolicy] = [
        ClothingNeedPolicy(
            needID: "clothing.daily_top",
            kinds: ["daily_top"],
            usage: .daily,
            wearsPerItem: [.light: 1.5, .balanced: 1.25, .prepared: 1.0],
            washIntervalDays: 7,
            styleBuffer: [.light: 0, .balanced: 1, .prepared: 2],
            minimum: 2,
            styleMaximum: [.light: 8, .balanced: 12, .prepared: 15],
            constrainedBagMaximum: 8,
            personalItemMaximum: 5,
            offsetByFormalTops: true,
            laundrySensitivity: .high,
            styleSensitivity: .high,
            bagSensitivity: .low
        ),
        ClothingNeedPolicy(
            needID: "clothing.daily_underwear",
            kinds: ["daily_underwear"],
            usage: .daily,
            wearsPerItem: [.light: 1.0, .balanced: 1.0, .prepared: 1.0],
            washIntervalDays: 7,
            styleBuffer: [.light: 0, .balanced: 1, .prepared: 2],
            minimum: 2,
            styleMaximum: [.light: 10, .balanced: 12, .prepared: 15],
            constrainedBagMaximum: 10,
            personalItemMaximum: 7,
            laundrySensitivity: .high,
            styleSensitivity: .low,
            bagSensitivity: .low
        ),
        ClothingNeedPolicy(
            needID: "clothing.daily_socks",
            kinds: ["daily_socks"],
            usage: .daily,
            wearsPerItem: [.light: 1.0, .balanced: 1.0, .prepared: 1.0],
            washIntervalDays: 7,
            styleBuffer: [.light: 0, .balanced: 1, .prepared: 2],
            minimum: 2,
            styleMaximum: [.light: 10, .balanced: 12, .prepared: 15],
            constrainedBagMaximum: 10,
            personalItemMaximum: 7,
            laundrySensitivity: .high,
            styleSensitivity: .low,
            bagSensitivity: .low
        ),
        ClothingNeedPolicy(
            needID: "clothing.bottoms",
            kinds: ["bottoms", "hot_bottoms"],
            usage: .daily,
            wearsPerItem: [.light: 3.0, .balanced: 2.5, .prepared: 2.0],
            washIntervalDays: 10,
            styleBuffer: [.light: 0, .balanced: 0, .prepared: 0],
            minimum: 1,
            styleMaximum: [.light: 5, .balanced: 6, .prepared: 8],
            constrainedBagMaximum: 5,
            personalItemMaximum: 3,
            laundrySensitivity: .low,
            styleSensitivity: .high,
            bagSensitivity: .low
        ),
        ClothingNeedPolicy(
            needID: "clothing.sleepwear",
            kinds: ["sleepwear"],
            usage: .sleep,
            wearsPerItem: [:],
            washIntervalDays: 7,
            styleBuffer: [:],
            minimum: 1,
            styleMaximum: [.light: 1, .balanced: 2, .prepared: 2],
            constrainedBagMaximum: 2,
            personalItemMaximum: 2,
            laundrySensitivity: .none,
            styleSensitivity: .low,
            bagSensitivity: .none
        ),
        ClothingNeedPolicy(
            needID: "clothing.workout",
            kinds: ["workout_top", "workout_bottom"],
            usage: .workout,
            wearsPerItem: [:],
            washIntervalDays: 7,
            styleBuffer: [.light: 0, .balanced: 0, .prepared: 0],
            minimum: 1,
            styleMaximum: [.light: 4, .balanced: 5, .prepared: 6],
            constrainedBagMaximum: 4,
            personalItemMaximum: 2,
            laundrySensitivity: .high,
            styleSensitivity: .high,
            bagSensitivity: .low
        )
    ]

    static let byKind: [String: ClothingNeedPolicy] = {
        var map: [String: ClothingNeedPolicy] = [:]
        for policy in all {
            for kind in policy.kinds {
                map[kind] = policy
            }
        }
        return map
    }()
}

struct ClothingQuantityEngine: Sendable {
    var reasons: ReasonTemplatesFile

    static func handles(_ kind: String) -> Bool {
        ClothingNeedPolicy.byKind[kind] != nil
    }

    /// Same contract as `QuantityEngine.quantity`, including age-group
    /// multiplier handling, so `PackingEngine` can route by kind and nothing
    /// downstream learns which engine produced the number.
    func quantity(
        kind: String,
        context: TripContext,
        itemName: String,
        traveler: Traveler? = nil,
        multipliers: [String: Double] = [:],
        formalTopUnits: Int = 0
    ) -> (value: Int, reason: String) {
        guard let policy = ClothingNeedPolicy.byKind[kind] else {
            return (1, "")
        }
        var value = Self.compute(policy, context: context, formalTopUnits: formalTopUnits)
        if let traveler, let multiplier = multipliers[kind], multiplier > 1 {
            value = max(1, Int((Double(value) * multiplier).rounded(.up)))
            let reason = ReasonRenderer.render(
                code: "quantity.age_extra",
                arguments: [
                    "quantity": "\(value)",
                    "item": itemName.lowercased(),
                    "name": traveler.displayName,
                    "days": "\(context.durationDays)",
                    "ageGroup": traveler.ageGroup.title.lowercased()
                ],
                templates: reasons.templates,
                fallback: "\(value) \(itemName.lowercased()) for \(traveler.displayName). \(context.durationDays) travel days plus extra changes for a \(traveler.ageGroup.title.lowercased())."
            )
            return (value, reason)
        }
        let reason = ReasonRenderer.render(
            code: kind == "daily_top" ? "quantity.daily_top" : "",
            arguments: [
                "days": "\(context.durationDays)",
                "styleClause": context.packingStyle == .light ? ", packing light" : "",
                "laundryClause": context.hasLaundry ? ", and you indicated laundry access" : ""
            ],
            templates: reasons.templates,
            fallback: value == 1 ? "" : "\(value) based on a \(context.durationDays)-day trip."
        )
        return (value, kind == "daily_top" ? "Why \(value) \(itemName.lowercased())? \(reason)" : reason)
    }

    static func compute(_ policy: ClothingNeedPolicy, context: TripContext, formalTopUnits: Int = 0) -> Int {
        compute(
            policy,
            days: context.durationDays,
            style: context.packingStyle,
            bag: context.bagType,
            laundry: context.laundryPlan,
            formalTopUnits: formalTopUnits
        )
    }

    static func compute(
        _ policy: ClothingNeedPolicy,
        days: Int,
        style: PackingStyle,
        bag: BagType,
        laundry: LaundryAccess,
        formalTopUnits: Int = 0
    ) -> Int {
        switch policy.usage {
        case .sleep:
            // V1's long_trip_backup, preserved: a backup set above five
            // nights unless packing light.
            return days >= 6 && style != .light ? 2 : 1
        case .daily:
            let wears = policy.wearsPerItem[style] ?? 1
            // Formal tops on the same list cover some of the daily-top
            // days at the same reuse factor; the minimum floor still holds.
            let covered = policy.offsetByFormalTops
                ? Int(Double(formalTopUnits) * wears)
                : 0
            let effectiveDays = max(0, days - covered)
            let items = { (uses: Int) in Int((Double(uses) / wears).rounded(.up)) }
            return resolve(
                policy,
                none: items(effectiveDays),
                planned: items(min(effectiveDays, policy.washIntervalDays)),
                style: style,
                bag: bag,
                laundry: laundry
            )
        case .workout:
            let divisor = style == .light ? 3 : 2
            let uses = max(1, days / divisor)
            return resolve(
                policy,
                none: uses,
                planned: min(uses, ceilDiv(policy.washIntervalDays, divisor)),
                style: style,
                bag: bag,
                laundry: laundry
            )
        }
    }

    private static func resolve(
        _ policy: ClothingNeedPolicy,
        none: Int,
        planned: Int,
        style: PackingStyle,
        bag: BagType,
        laundry: LaundryAccess
    ) -> Int {
        var cap = policy.styleMaximum[style] ?? Int.max
        if bag == .personalItem {
            cap = min(cap, policy.personalItemMaximum)
        } else if bag.isSpaceConstrained {
            cap = min(cap, policy.constrainedBagMaximum)
        }
        let base: Int
        switch laundry {
        case .none:
            base = none
        case .planned:
            base = planned
        case .possible:
            // A third of the way from the planned plateau toward what a
            // no-laundry trip would realistically pack (the capped value).
            base = planned + ceilDiv(max(0, min(none, cap) - planned), 3)
        }
        let buffered = base + (policy.styleBuffer[style] ?? 0)
        return max(policy.minimum, min(buffered, cap))
    }

    private static func ceilDiv(_ a: Int, _ b: Int) -> Int {
        (a + b - 1) / b
    }
}
