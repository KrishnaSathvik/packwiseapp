import Foundation

/// The closed capability vocabulary — Engine V2, Step 3 (footwear + outerwear).
///
/// Adding a case is a design decision, not a line an engineer writes while
/// authoring a rule: an open vocabulary degenerates into per-item labels with
/// no generalization. Two families currently use ten of the fifteen-to-twenty
/// budget; a test pins the count so growth is deliberate.
///
/// The `capabilities` arrays in the catalog JSON are an older open-string
/// vocabulary and are deliberately not read here.
enum PackingCapability: String, CaseIterable, Sendable {
    case everydayWalking = "footwear.everyday_walking"
    case running = "footwear.running"
    case hiking = "footwear.hiking"
    case beach = "footwear.beach"
    case formal = "footwear.formal"
    case coldFootwear = "footwear.cold"
    case rainShell = "outerwear.rain_shell"
    case windShell = "outerwear.wind_shell"
    case warmthLight = "outerwear.warmth_light"
    case warmthHeavy = "outerwear.warmth_heavy"
}

/// One suppression decision, recorded from the start so the ledger says which
/// need an item was covering and what covered it instead — evidence the
/// resolver reasoned, not that a rule stopped firing.
struct CoverageSuppression: Hashable, Sendable {
    var travelerID: UUID?
    var canonicalItemID: String
    /// The capabilities the item would have contributed, as raw values.
    var capabilities: [String]
    /// Items already covering those needs. Empty means the need itself was
    /// absent (e.g. a rain shell on a hot trip).
    var coveredBy: [String]
}

/// Greedy coverage for footwear and outerwear. Set cover is NP-hard in
/// general and irrelevant at this scale — a deterministic greedy pass over an
/// explicit priority order is easier to test, debug, and explain.
enum CoverageResolver {
    /// Priority is this array's order: versatile items first so they claim
    /// shared needs, single-purpose items later so they survive only when
    /// their own need is real and uncovered.
    static let priority: [String] = [
        "footwear.running_shoes",
        "footwear.hiking_shoes",
        "footwear.boots",
        "footwear.dress_shoes",
        "footwear.sandals",
        "footwear.walking_shoes",
        "footwear.flip_flops",
        "clothing.winter_coat",
        "clothing.rain_jacket",
        "clothing.light_sweater",
        "clothing.light_jacket",
        "clothing.windbreaker"
    ]

    /// A winter coat deliberately does not claim `warmthLight`: a coat is not
    /// a substitute for an indoor or mild-evening layer, and claiming it
    /// would delete the sweater a snow trip layers underneath.
    static let itemCapabilities: [String: Set<PackingCapability>] = [
        "footwear.running_shoes": [.running, .everydayWalking],
        "footwear.hiking_shoes": [.hiking, .everydayWalking],
        "footwear.boots": [.coldFootwear],
        "footwear.dress_shoes": [.formal],
        "footwear.sandals": [.beach],
        "footwear.walking_shoes": [.everydayWalking],
        "footwear.flip_flops": [.beach],
        "clothing.winter_coat": [.warmthHeavy, .windShell],
        "clothing.rain_jacket": [.rainShell, .windShell],
        "clothing.light_sweater": [.warmthLight],
        "clothing.light_jacket": [.warmthLight, .windShell],
        "clothing.windbreaker": [.windShell]
    ]

    /// Needs derive from trip signals, never from which items happened to be
    /// emitted — deriving them from item capabilities would let a versatile
    /// item manufacture the need that justifies itself.
    static func needs(context: TripContext, thresholds: WeatherThresholds) -> Set<PackingCapability> {
        var needs: Set<PackingCapability> = [.everydayWalking]
        let activities = Set(context.activities)

        if activities.contains("running") || context.contextChips.contains(.runWhileTraveling) {
            needs.insert(.running)
        }
        if activities.contains("hiking") {
            needs.insert(.hiking)
        }
        if context.tripType == .beach
            || !activities.isDisjoint(with: ["swimming", "beachDays", "snorkeling", "boatTrip"]) {
            needs.insert(.beach)
        }
        if context.tripType == .business || context.tripType == .weddingEvent
            || !activities.isDisjoint(with: ["work", "niceDinner"])
            || context.contextChips.contains(.needFormalOutfit) {
            needs.insert(.formal)
        }

        if let weather = context.weather, weather.isPreciseForecast || !weather.dailyForecast.isEmpty {
            let conditions = WeatherSignalExtractor.extract(
                weather: weather,
                thresholds: thresholds,
                outdoorActivities: context.outdoorActivities,
                tripDays: context.durationDays
            )
            let rain = !conditions.signals.isDisjoint(with: [.meaningfulRain, .persistentRain, .coldRain])
            let hot = conditions.signals.contains(.hotOutdoorExposure)
            let coldRain = conditions.signals.contains(.coldRain)
            // Warm rain is umbrella weather, not shell weather: nobody wears
            // a rain jacket at 90°F, so the wearable-shell need only exists
            // when the rain isn't hot (or is cold outright).
            if rain && (!hot || coldRain) {
                needs.insert(.rainShell)
            }
            if conditions.signals.contains(.coldEvenings)
                || conditions.signals.contains(.largeTemperatureSwing)
                || coldRain {
                needs.insert(.warmthLight)
            }
            if conditions.signals.contains(.snowExposure)
                || weather.minTemperatureF <= thresholds.coldMaxF {
                needs.insert(.warmthHeavy)
            }
            if conditions.signals.contains(.highWindExposure) {
                needs.insert(.windShell)
            }
            if conditions.signals.contains(.snowExposure) {
                needs.insert(.coldFootwear)
            }
        } else {
            // Mirror the seasonal fallback: winter at meaningful latitude
            // suggests a warm layer even without a forecast.
            let month = Calendar.current.component(.month, from: context.startDate)
            let lat = context.destination.latitude
            let winter = lat >= 0 ? [12, 1, 2].contains(month) : [6, 7, 8].contains(month)
            if winter && abs(lat) > 30 {
                needs.insert(.warmthLight)
            }
        }
        return needs
    }

    /// Greedy resolution over one traveler's items. User-added and
    /// user-modified items are never suppressed, but they do claim coverage —
    /// a manually added pair of running shoes makes suggested walking shoes
    /// redundant. Items outside the vocabulary pass through untouched, and a
    /// weather-emitted item whose need is absent is suppressed as refuted.
    static func resolve(
        items: [PackingItemDraft],
        needs: Set<PackingCapability>
    ) -> (kept: [PackingItemDraft], suppressions: [CoverageSuppression]) {
        var covered: [PackingCapability: String] = [:]
        var kept: [PackingItemDraft] = []
        var suppressions: [CoverageSuppression] = []

        let priorityIndex = { (item: PackingItemDraft) -> Int in
            item.canonicalItemID.flatMap { priority.firstIndex(of: $0) } ?? Int.max
        }
        let ordered = items.enumerated().sorted {
            let lhs = priorityIndex($0.element)
            let rhs = priorityIndex($1.element)
            return lhs != rhs ? lhs < rhs : $0.offset < $1.offset
        }.map(\.element)

        for item in ordered {
            guard let canonical = item.canonicalItemID,
                  let capabilities = itemCapabilities[canonical] else {
                kept.append(item)
                continue
            }
            let needed = capabilities.intersection(needs)
            if item.isUserAdded || item.isUserModified {
                kept.append(item)
                for capability in needed where covered[capability] == nil {
                    covered[capability] = canonical
                }
                continue
            }
            if needed.isEmpty {
                if item.sourceSignals == [.weather] {
                    suppressions.append(CoverageSuppression(
                        travelerID: item.travelerID,
                        canonicalItemID: canonical,
                        capabilities: capabilities.map(\.rawValue).sorted(),
                        coveredBy: []
                    ))
                } else {
                    kept.append(item)
                }
                continue
            }
            if needed.allSatisfy({ covered[$0] != nil }) {
                let coverers = Set(needed.compactMap { covered[$0] })
                suppressions.append(CoverageSuppression(
                    travelerID: item.travelerID,
                    canonicalItemID: canonical,
                    capabilities: needed.map(\.rawValue).sorted(),
                    coveredBy: coverers.sorted()
                ))
                continue
            }
            kept.append(item)
            for capability in needed where covered[capability] == nil {
                covered[capability] = canonical
            }
        }
        return (kept, suppressions)
    }
}
