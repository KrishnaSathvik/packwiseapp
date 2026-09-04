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
    case coldHands = "hand_protection.cold"
    case snowSportHands = "hand_protection.snow_sport"
}

/// The normalized context surface the capability-coverage **and activity**
/// families are allowed to read — one projection of the snapshot, shared, so
/// neither family derives a second set of signals from raw `TripContext`.
/// Weather signals and the seasonal fallback deliberately reproduce the
/// pre-Phase-4 resolver semantics; Phase 6 owns weather interpretation.
///
/// The name is Phase 4's and is deliberately kept: renaming it would be
/// cosmetic churn across every Phase 4 file, and is routed forward if a third
/// family ever joins.
struct CoverageContext: Hashable, Sendable {
    var tripType: TripType
    var activityIDs: Set<String>
    var contextChips: Set<ContextChip>
    var weatherSignals: Set<WeatherSignal>
    var hasForecastWeather: Bool
    var usesColdMinimumHeavyWarmth: Bool
    var usesSeasonalWarmthFallback: Bool
    var party: TripParty

    init(snapshot: TripContextSnapshot, thresholds: WeatherThresholds) {
        tripType = snapshot.tripType
        activityIDs = Set(snapshot.knownActivityIDs)
        contextChips = snapshot.contextChips
        party = snapshot.party

        let outdoor = !activityIDs.isDisjoint(with: ["hiking", "sightseeing", "walking", "running", "beachDays"])
        let month = Calendar.current.component(.month, from: snapshot.startDate)
        let latitude = snapshot.destination.latitude
        let northWinter = latitude >= 0 && [12, 1, 2].contains(month)
        let southWinter = latitude < 0 && [6, 7, 8].contains(month)
        let seasonalWarmthEligible = (northWinter || southWinter) && abs(latitude) > 30

        switch snapshot.weatherQuality {
        case .complete, .partial:
            // weatherQuality is derived from snapshot.weather, so a non-nil value
            // here is guaranteed by construction (TripContextSnapshot.swift:201).
            let forecast = snapshot.weather ?? .seasonal()
            weatherSignals = WeatherSignalExtractor.extract(
                weather: forecast, thresholds: thresholds,
                outdoorActivities: outdoor, tripDays: snapshot.durationDays
            ).signals
            hasForecastWeather = true
            usesColdMinimumHeavyWarmth = forecast.minTemperatureF <= thresholds.coldMaxF
            usesSeasonalWarmthFallback = {
                if case .partial = snapshot.weatherQuality { return seasonalWarmthEligible }
                return false  // .complete never falls back
            }()
        case .seasonalOnly, .missing:
            weatherSignals = []
            hasForecastWeather = false
            usesColdMinimumHeavyWarmth = false
            usesSeasonalWarmthFallback = seasonalWarmthEligible
        }
    }
}

/// One capability-to-item fact behind a suppression decision.
struct CapabilityCoverage: Hashable, Sendable {
    var capability: PackingCapability
    var coveringItemID: String
}

/// One suppression decision, recorded from the start so the ledger says which
/// need an item was covering and what covered it instead — evidence the
/// resolver reasoned, not that a rule stopped firing.
struct CoverageSuppression: Hashable, Sendable {
    var travelerID: UUID?
    var canonicalItemID: String
    var covered: [CapabilityCoverage]
    var refutedCapabilities: [PackingCapability]

    /// Stable compatibility views retained while the golden schema migrates.
    var capabilities: [String] {
        Set(covered.map(\.capability)).union(refutedCapabilities)
            .map(\.rawValue).sorted()
    }

    var coveredBy: [String] {
        Set(covered.map(\.coveringItemID)).sorted()
    }
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
        "clothing.windbreaker",
        "activities.ski_gloves",
        "clothing.gloves"
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
        "clothing.windbreaker": [.windShell],
        "activities.ski_gloves": [.snowSportHands, .coldHands],
        "clothing.gloves": [.coldHands]
    ]

    /// Needs derive from trip signals, never from which items happened to be
    /// emitted — deriving them from item capabilities would let a versatile
    /// item manufacture the need that justifies itself.
    static func needs(context: CoverageContext) -> Set<PackingCapability> {
        var needs: Set<PackingCapability> = [.everydayWalking]
        let activities = context.activityIDs

        if activities.contains("running") || context.contextChips.contains(.runWhileTraveling) {
            needs.insert(.running)
        }
        // Derived from the typed activity contract rather than the literal id
        // `"hiking"`: the rule is that trail footwear implies the hiking
        // capability, which generalizes to any contract that declares the
        // need. Today Hiking is the only one that does, so this is
        // behaviour-identical to the string test it replaces.
        needs.formUnion(ActivityContracts.capabilities(for: ActivityContracts.needs(for: activities)))
        if context.tripType == .beach
            || !activities.isDisjoint(with: ["swimming", "beachDays", "snorkeling", "boatTrip"]) {
            needs.insert(.beach)
        }
        if context.tripType == .business || context.tripType == .weddingEvent
            || !activities.isDisjoint(with: ["work", "niceDinner"])
            || context.contextChips.contains(.needFormalOutfit) {
            needs.insert(.formal)
        }
        if context.tripType == .skiSnow {
            needs.insert(.coldHands)
            needs.insert(.snowSportHands)
        }

        if context.hasForecastWeather {
            let rain = !context.weatherSignals.isDisjoint(with: [.meaningfulRain, .persistentRain, .coldRain])
            let hot = context.weatherSignals.contains(.hotOutdoorExposure)
            let coldRain = context.weatherSignals.contains(.coldRain)
            // Warm rain is umbrella weather, not shell weather: nobody wears
            // a rain jacket at 90°F, so the wearable-shell need only exists
            // when the rain isn't hot (or is cold outright).
            if rain && (!hot || coldRain) {
                needs.insert(.rainShell)
            }
            if context.weatherSignals.contains(.coldEvenings)
                || context.weatherSignals.contains(.largeTemperatureSwing)
                || coldRain {
                needs.insert(.warmthLight)
            }
            if context.weatherSignals.contains(.snowExposure)
                || context.usesColdMinimumHeavyWarmth {
                needs.insert(.warmthHeavy)
            }
            if context.weatherSignals.contains(.highWindExposure) {
                needs.insert(.windShell)
            }
            if context.weatherSignals.contains(.snowExposure) {
                needs.insert(.coldFootwear)
            }
            if !context.weatherSignals.isDisjoint(with: [.snowExposure, .sustainedCold, .freezingCold]) {
                needs.insert(.coldHands)
            }
        } else if context.usesSeasonalWarmthFallback {
            needs.insert(.warmthLight)
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
                var copy = item
                copy.satisfiedCapabilities = needed.map(\.rawValue).sorted()
                kept.append(copy)
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
                        covered: [],
                        refutedCapabilities: capabilities.sorted { $0.rawValue < $1.rawValue }
                    ))
                } else {
                    kept.append(item)   // satisfiedCapabilities stays empty — correct
                }
                continue
            }
            if needed.allSatisfy({ covered[$0] != nil }) {
                let coverage = needed.compactMap { capability -> CapabilityCoverage? in
                    guard let coveringItemID = covered[capability] else { return nil }
                    return CapabilityCoverage(capability: capability, coveringItemID: coveringItemID)
                }.sorted {
                    if $0.capability.rawValue != $1.capability.rawValue {
                        return $0.capability.rawValue < $1.capability.rawValue
                    }
                    return $0.coveringItemID < $1.coveringItemID
                }
                suppressions.append(CoverageSuppression(
                    travelerID: item.travelerID,
                    canonicalItemID: canonical,
                    covered: coverage,
                    refutedCapabilities: []
                ))
                continue
            }
            var copy = item
            copy.satisfiedCapabilities = needed.map(\.rawValue).sorted()
            kept.append(copy)
            for capability in needed where covered[capability] == nil {
                covered[capability] = canonical
            }
        }
        return (kept, suppressions)
    }
}
