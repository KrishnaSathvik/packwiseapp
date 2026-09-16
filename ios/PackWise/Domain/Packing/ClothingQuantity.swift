import Foundation

/// The normalized context surface the clothing family is allowed to read.
/// Other engine families remain on `TripContext` until their own hardening
/// phase; this projection keeps Phase 3's migration intentionally narrow.
struct ClothingQuantityContext: Hashable, Sendable {
    var days: Int
    var style: PackingStyle
    var luggage: LuggageContext
    var laundry: LaundryAccess
    var selectedActivityIDs: Set<String>
    var datedActivityUses: [String: Int]
    var party: TripParty

    init(
        days: Int,
        style: PackingStyle,
        luggage: LuggageContext,
        laundry: LaundryAccess,
        selectedActivityIDs: Set<String>,
        datedActivityUses: [String: Int],
        party: TripParty
    ) {
        self.days = max(1, days)
        self.style = style
        self.luggage = luggage
        self.laundry = laundry
        self.selectedActivityIDs = selectedActivityIDs
        self.datedActivityUses = datedActivityUses
        self.party = party
    }

    init(snapshot: TripContextSnapshot) {
        days = snapshot.durationDays
        style = snapshot.packingStyle
        luggage = snapshot.luggage
        laundry = snapshot.laundryPlan
        selectedActivityIDs = Set(snapshot.knownActivityIDs)
        datedActivityUses = snapshot.knownDatedActivityUses
        party = snapshot.party
    }
}

/// Inputs a clothing policy explicitly claims can change its quantity.
enum ClothingQuantityInfluence: Hashable, Sendable {
    case laundry
    case style
    case bag
}

struct ClothingQuantityEvidence: Hashable, Codable, Sendable {
    var policyID: String
    var basis: String
    var requiredUses: Int
    var wearsPerItem: Double
    var washIntervalDays: Int?
    var laundryPlan: LaundryAccess
    var laundryReduced: Bool
    var styleBuffer: Int
    var bagCap: Int?
    var bagCapApplied: Bool
    var appearanceOffsetUses: Int
    var ageMultiplier: Double?
    var quantity: Int
}

struct ClothingQuantityResult: Hashable, Sendable {
    var value: Int
    var reason: String
    var evidence: ClothingQuantityEvidence
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
        case workout(activityIDs: [String])
        /// One suit for one use; two provide a drying rotation for repeated use.
        case swim(activityIDs: [String])
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
    /// Binding cap for compact, carry-on constrained, and moderate capacity.
    var constrainedBagMaximum: Int
    /// Binding cap for very constrained capacity (a personal item alone).
    var personalItemMaximum: Int
    /// Formal tops satisfy some of this need's uses: a five-day business
    /// trip with two dress shirts needs daily tops for the remaining days,
    /// not seven t-shirts beside them. True only for the daily-top need.
    var offsetByFormalTops: Bool = false

    var influences: Set<ClothingQuantityInfluence>

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
            influences: [.laundry, .style, .bag]
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
            influences: [.laundry, .style, .bag]
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
            influences: [.laundry, .style, .bag]
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
            influences: [.laundry, .style, .bag]
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
            influences: [.style]
        ),
        ClothingNeedPolicy(
            needID: "clothing.workout",
            kinds: ["workout_top", "workout_bottom"],
            usage: .workout(activityIDs: ["running", "yoga"]),
            wearsPerItem: [:],
            washIntervalDays: 7,
            styleBuffer: [.light: 0, .balanced: 0, .prepared: 0],
            minimum: 1,
            styleMaximum: [.light: 4, .balanced: 5, .prepared: 6],
            constrainedBagMaximum: 4,
            personalItemMaximum: 2,
            influences: [.laundry, .style, .bag]
        ),
        ClothingNeedPolicy(
            needID: "clothing.swimwear",
            kinds: ["swimwear"],
            usage: .swim(activityIDs: ["swimming", "beachDays", "snorkeling", "boatTrip"]),
            wearsPerItem: [:],
            washIntervalDays: 1,
            styleBuffer: [:],
            minimum: 1,
            styleMaximum: [.light: 2, .balanced: 2, .prepared: 2],
            constrainedBagMaximum: 2,
            personalItemMaximum: 2,
            influences: []
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

/// Slice 9: warm layers rotate on genuinely cold trips.
///
/// The needs model above scales daily clothing but has no temperature
/// dimension, so an 8°F week used to pack six t-shirts and one light
/// sweater. On a sustained-cold trip (warmest day at or below the cold
/// threshold) the mid layers rotate like clothing instead of appearing
/// once; at or below freezing the thermal base layers rotate too.
///
/// Routed by canonical id: these items' catalog quantity kinds are frozen
/// fixed-count kinds.
enum WarmLayerQuantities {
    static func quantity(
        canonicalID: String,
        days: Int,
        weather: TripWeatherContext?,
        thresholds: WeatherThresholds
    ) -> (value: Int, reasonCode: String, arguments: [String: String], fallback: String)? {
        guard let weather, weather.isPreciseForecast else { return nil }
        let freezing = weather.maxTemperatureF <= thresholds.freezingMaxF
        let cold = weather.maxTemperatureF <= thresholds.coldMaxF
        guard cold else { return nil }
        // ceil(days / 3): a mid or base layer is re-worn about three days
        // before it needs a wash; capped so long trips plateau.
        let rotation = min(3, max(1, (days + 2) / 3))
        let value: Int
        switch canonicalID {
        case "clothing.light_sweater":
            value = max(freezing ? 2 : 1, rotation)
        case "clothing.thermal_top" where freezing:
            value = max(2, rotation)
        case "clothing.thermal_bottom" where freezing:
            value = days >= 5 ? 2 : 1
        default:
            return nil
        }
        guard value > 1 else { return nil }
        return (
            value,
            "quantity.warm_rotation",
            ["quantity": "\(value)", "days": "\(days)"],
            "\(value) to rotate through \(days) cold days."
        )
    }
}

struct ClothingQuantityEngine: Sendable {
    var reasons: ReasonTemplatesFile

    static func handles(_ kind: String) -> Bool {
        ClothingNeedPolicy.byKind[kind] != nil
    }

    func quantity(
        kind: String,
        context: ClothingQuantityContext,
        itemName: String,
        traveler: Traveler? = nil,
        multipliers: [String: Double] = [:],
        appearanceUnits: Int = 0
    ) -> ClothingQuantityResult {
        precondition(ClothingNeedPolicy.byKind[kind] != nil, "Unsupported clothing quantity kind: \(kind)")
        let policy = ClothingNeedPolicy.byKind[kind]!
        let multiplier = multipliers[kind]
        var result = Self.evaluate(
            policy,
            context: context,
            appearanceUnits: appearanceUnits,
            ageMultiplier: multiplier
        )
        if let traveler, result.evidence.ageMultiplier != nil {
            result.reason = ReasonRenderer.render(
                code: "quantity.age_extra",
                arguments: [
                    "quantity": "\(result.value)",
                    "item": itemName.lowercased(),
                    "name": traveler.displayName,
                    "days": "\(context.days)",
                    "ageGroup": traveler.ageGroup.title.lowercased()
                ],
                templates: reasons.templates,
                fallback: "\(result.value) \(itemName.lowercased()) for \(traveler.displayName), including the supported \(traveler.ageGroup.title.lowercased()) change buffer."
            )
            return result
        }
        if kind == "daily_top" {
            let rendered = ReasonRenderer.render(
                code: "quantity.daily_top",
                arguments: [
                    "days": "\(context.days)",
                    "styleClause": context.style == .light ? ", packing light" : "",
                    "laundryClause": context.laundry == .none ? "" : ", with laundry in the plan"
                ],
                templates: reasons.templates,
                fallback: "\(result.value) for \(result.evidence.requiredUses) uncovered wear days."
            )
            result.reason = "Why \(result.value) \(itemName.lowercased())? \(rendered)"
            return result
        }
        let laundryClause = result.evidence.laundryReduced ? " Laundry reduces the rotation." : ""
        switch result.evidence.basis {
        case "sleepRotation":
            result.reason = "\(result.value) sleep set\(result.value == 1 ? "" : "s") with repeat wear."
        case "datedActivityUses":
            result.reason = "\(result.value) for \(result.evidence.requiredUses) scheduled uses.\(laundryClause)"
        case "selectedActivityEstimate":
            result.reason = "\(result.value) for the workout plan.\(laundryClause)"
        case "dryingRotation":
            result.reason = "\(result.value) for swim use and drying rotation."
        default:
            result.reason = "\(result.value) for \(result.evidence.requiredUses) wear days.\(laundryClause)"
        }
        return result
    }

    static func compute(_ policy: ClothingNeedPolicy, context: TripContext, formalTopUnits: Int = 0) -> Int {
        compute(
            policy,
            days: context.durationDays,
            style: context.packingStyle,
            luggage: context.luggage,
            laundry: context.laundryPlan,
            formalTopUnits: formalTopUnits
        )
    }

    static func compute(
        _ policy: ClothingNeedPolicy,
        days: Int,
        style: PackingStyle,
        luggage: LuggageContext,
        laundry: LaundryAccess,
        formalTopUnits: Int = 0
    ) -> Int {
        let selectedActivityIDs: Set<String>
        switch policy.usage {
        case let .workout(ids), let .swim(ids): selectedActivityIDs = Set(ids.prefix(1))
        case .daily, .sleep: selectedActivityIDs = []
        }
        let context = ClothingQuantityContext(
            days: days,
            style: style,
            luggage: luggage,
            laundry: laundry,
            selectedActivityIDs: selectedActivityIDs,
            datedActivityUses: [:],
            party: .solo()
        )
        return evaluate(policy, context: context, appearanceUnits: formalTopUnits).value
    }

    static func evaluate(
        _ policy: ClothingNeedPolicy,
        context: ClothingQuantityContext,
        appearanceUnits: Int = 0,
        ageMultiplier: Double? = nil
    ) -> ClothingQuantityResult {
        let style = context.style
        let wears = policy.wearsPerItem[style] ?? 1
        let appearanceOffset = policy.offsetByFormalTops ? max(0, appearanceUnits) : 0
        let requiredUses: Int
        let basis: String
        let none: Int
        let planned: Int

        switch policy.usage {
        case .daily:
            basis = "dailyWear"
            requiredUses = max(0, context.days - appearanceOffset)
            none = units(for: requiredUses, wearsPerItem: wears)
            planned = units(for: min(requiredUses, policy.washIntervalDays), wearsPerItem: wears)
        case .sleep:
            basis = "sleepRotation"
            requiredUses = context.days
            none = context.days >= 6 && style != .light ? 2 : 1
            planned = none
        case let .workout(activityIDs):
            let explicitUses = activityIDs.reduce(0) { $0 + (context.datedActivityUses[$1] ?? 0) }
            let selected = !context.selectedActivityIDs.isDisjoint(with: activityIDs)
            let divisor = style == .light ? 3 : 2
            requiredUses = explicitUses > 0 ? explicitUses : (selected ? max(1, context.days / divisor) : 1)
            basis = explicitUses > 0 ? "datedActivityUses" : "selectedActivityEstimate"
            none = requiredUses
            planned = max(1, unitsWithinWashCycle(uses: requiredUses, days: context.days, washIntervalDays: policy.washIntervalDays))
        case let .swim(activityIDs):
            let explicitUses = activityIDs.reduce(0) { $0 + (context.datedActivityUses[$1] ?? 0) }
            let selected = !context.selectedActivityIDs.isDisjoint(with: activityIDs)
            requiredUses = explicitUses > 0 ? explicitUses : (selected ? max(1, ceilDiv(context.days, 3)) : 1)
            basis = explicitUses > 0 ? "datedActivityUses" : "dryingRotation"
            none = min(2, requiredUses)
            planned = none
        }

        let resolved = resolve(policy, none: none, planned: planned, context: context)
        let multiplier = ageMultiplier.flatMap { $0 > 1 ? $0 : nil }
        let multiplied = multiplier.map { Int((Double(resolved.value) * $0).rounded(.up)) } ?? resolved.value
        // Existing supported age buffers apply after the adult policy has
        // resolved its family/style/bag bounds, matching the pre-Phase-3
        // party behavior rather than inventing a new age model here.
        let value = max(policy.minimum, multiplied)
        let evidence = ClothingQuantityEvidence(
            policyID: policy.needID,
            basis: basis,
            requiredUses: requiredUses,
            wearsPerItem: wears,
            washIntervalDays: policy.influences.contains(.laundry) ? policy.washIntervalDays : nil,
            laundryPlan: context.laundry,
            laundryReduced: resolved.laundryReduced,
            styleBuffer: resolved.styleBuffer,
            bagCap: resolved.bagCap,
            bagCapApplied: resolved.bagCapApplied,
            appearanceOffsetUses: appearanceOffset,
            ageMultiplier: multiplier,
            quantity: value
        )
        return ClothingQuantityResult(value: value, reason: "", evidence: evidence)
    }

    private static func resolve(
        _ policy: ClothingNeedPolicy,
        none: Int,
        planned: Int,
        context: ClothingQuantityContext
    ) -> (value: Int, laundryReduced: Bool, styleBuffer: Int, bagCap: Int?, bagCapApplied: Bool) {
        let style = context.style
        var cap = policy.styleMaximum[style] ?? Int.max
        // Capacity, never the number or identity of selected bags, sets the
        // cap: more bags never mean more clothes.
        var bagCap: Int?
        if policy.influences.contains(.bag) {
            switch context.luggage.capacity {
            case .veryConstrained:
                bagCap = policy.personalItemMaximum
            case .compact, .carryOnConstrained, .moderate:
                bagCap = policy.constrainedBagMaximum
            case .unspecified, .checkedAvailable:
                bagCap = nil
            }
            if let bagCap { cap = min(cap, bagCap) }
        }
        let base: Int
        if !policy.influences.contains(.laundry) {
            base = none
        } else {
            switch context.laundry {
            case .none:
                base = none
            case .planned:
                base = planned
            case .possible:
                // A third of the way from the planned plateau toward what a
                // no-laundry trip would realistically pack (the capped value).
                base = planned + ceilDiv(max(0, min(none, cap) - planned), 3)
            }
        }
        let styleBuffer = policy.influences.contains(.style) ? (policy.styleBuffer[style] ?? 0) : 0
        let buffered = base + styleBuffer
        return (
            max(policy.minimum, min(buffered, cap)),
            policy.influences.contains(.laundry) && base < none,
            styleBuffer,
            bagCap,
            bagCap != nil && buffered > cap
        )
    }

    private static func units(for uses: Int, wearsPerItem: Double) -> Int {
        Int((Double(uses) / max(1, wearsPerItem)).rounded(.up))
    }

    private static func unitsWithinWashCycle(uses: Int, days: Int, washIntervalDays: Int) -> Int {
        Int((Double(uses) * Double(min(days, washIntervalDays)) / Double(max(1, days))).rounded(.up))
    }

    private static func ceilDiv(_ a: Int, _ b: Int) -> Int {
        (a + b - 1) / b
    }
}
