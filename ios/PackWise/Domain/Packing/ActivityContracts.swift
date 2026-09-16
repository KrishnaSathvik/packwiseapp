import Foundation

/// The closed activity-need vocabulary — Phase 5.
///
/// A need is admitted only when more than one contract can plausibly want it
/// or when it must route into the Phase 4 capability model. An open
/// vocabulary degenerates into one label per item and generalizes nothing,
/// which is exactly the failure `PackingCapability` was closed to avoid.
enum ActivityNeed: String, CaseIterable, Hashable, Sendable {
    case trailFootwear = "activity.trail_footwear"
    case dayCarry = "activity.day_carry"
    case hydration = "activity.hydration"
    case blisterCare = "activity.blister_care"
    case portableLight = "activity.portable_light"
    case insectProtection = "activity.insect_protection"
    case sunProtection = "activity.sun_protection"
    /// The only weather-gated need. Resolves to nothing unless an existing
    /// cold signal is already present — camping never assumes cold nights.
    case overnightWarmth = "activity.overnight_warmth"

    var isWeatherGated: Bool { self == .overnightWarmth }
}

/// One surfaced activity's product contract.
enum ActivityContract: Hashable, Sendable {
    /// Drives generation. `needs` may be empty when the activity's effect is
    /// still expressed by its `rules.activities` row.
    case deterministic(needs: Set<ActivityNeed>)
    /// Surfaced and stored, with no independent engine effect.
    case contextOnly
}

/// The single activity authority, the way `CoverageResolver` is the single
/// coverage authority. Typed and closed in Swift; `activity-rules.json`
/// remains the surfaced vocabulary and the item adds not yet migrated here.
enum ActivityContracts {
    static let all: [String: ActivityContract] = [
        // Hiking is the only contract that declares `.trailFootwear`, and so
        // the only one that claims `PackingCapability.hiking`.
        "hiking": .deterministic(needs: [.trailFootwear, .dayCarry, .hydration, .blisterCare]),
        // Camping deliberately omits `.trailFootwear`: car camping,
        // campgrounds, festivals and cabins are camping too, and none of them
        // require trail shoes or justify suppressing ordinary walking shoes.
        "camping": .deterministic(needs: [
            .hydration, .portableLight,
            .insectProtection, .sunProtection, .overnightWarmth
        ]),
        "walking": .deterministic(needs: []),
        "running": .deterministic(needs: []),
        "sightseeing": .deterministic(needs: []),
        "niceDinner": .deterministic(needs: []),
        "nightlife": .deterministic(needs: []),
        "shopping": .deterministic(needs: []),
        "museums": .deterministic(needs: []),
        "work": .deterministic(needs: []),
        "wildlife": .deterministic(needs: []),
        "swimming": .deterministic(needs: []),
        "beachDays": .deterministic(needs: []),
        "snorkeling": .deterministic(needs: []),
        "boatTrip": .deterministic(needs: []),
        "yoga": .deterministic(needs: []),
        "photography": .deterministic(needs: [])
    ]

    /// Sorted so callers never depend on dictionary iteration order.
    static let needCandidates: [ActivityNeed: [String]] = [
        .trailFootwear: ["footwear.hiking_shoes"],
        .dayCarry: ["activities.daypack"],
        .hydration: ["hydration.water_bottle"],
        .blisterCare: ["health.blister_pads"],
        .portableLight: ["miscellaneous.flashlight"],
        .insectProtection: ["toiletries.insect_repellent"],
        .sunProtection: ["toiletries.sunscreen"],
        .overnightWarmth: ["clothing.thermal_top"]
    ]

    /// The only bridge from an activity need into Phase 4's closed coverage
    /// vocabulary. Phase 5 adds no capability.
    ///
    /// This mapping is a general rule about what trail footwear *is*, not a
    /// statement about any one activity: it holds for any contract that ever
    /// declares `.trailFootwear`. Today exactly one does.
    static let needCapabilities: [ActivityNeed: PackingCapability] = [
        .trailFootwear: .hiking
    ]

    static func contract(for activityID: String) -> ActivityContract? {
        all[activityID]
    }

    static func needs(for activityIDs: some Sequence<String>) -> Set<ActivityNeed> {
        activityIDs.reduce(into: Set<ActivityNeed>()) { result, id in
            if case .deterministic(let needs) = all[id] { result.formUnion(needs) }
        }
    }

    static func candidates(for needs: Set<ActivityNeed>) -> [String] {
        needs.flatMap { needCandidates[$0] ?? [] }.sorted()
    }

    static func capabilities(for needs: Set<ActivityNeed>) -> Set<PackingCapability> {
        Set(needs.compactMap { needCapabilities[$0] })
    }

    /// The activity that owns a need-derived item's reason: the first
    /// declaring activity in the trip's own normalized selection order, which
    /// is exactly what `for activity in context.activities` already does.
    static func originatingActivity(for need: ActivityNeed, in orderedActivityIDs: [String]) -> String? {
        orderedActivityIDs.first { id in
            if case .deterministic(let needs) = all[id] { return needs.contains(need) }
            return false
        }
    }
}
