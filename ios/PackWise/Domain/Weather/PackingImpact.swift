import Foundation

enum PackingImpactSignal: String, CaseIterable, Sendable {
    case meaningfulRain
    case persistentRain
    case coldEvenings
    case highUVExposure
    case highWindExposure
    case snowExposure
    case largeTemperatureSwing
    case hotOutdoorExposure
    case seasonal
}

enum PackingImpactEffect: String, Equatable, Sendable {
    case added
    case quantityIncreased
    case recommended
}

struct PackingImpactItem: Identifiable, Equatable, Sendable {
    var id: UUID { itemID }
    let itemID: UUID
    let canonicalItemID: String?
    let displayName: String
    let quantity: Int
    let effect: PackingImpactEffect
    let ownerLabel: String?
    let reasonCode: String
}

struct PackingImpact: Identifiable, Equatable, Sendable {
    var id: String { signal.rawValue }
    let signal: PackingImpactSignal
    let title: String
    let summary: String
    let affectedItems: [PackingImpactItem]
    let reasonCodes: Set<String>

    var isSeasonal: Bool { signal == .seasonal }

    var symbol: String {
        switch signal {
        case .meaningfulRain, .persistentRain: "umbrella"
        case .coldEvenings: "moon.stars"
        case .highUVExposure, .hotOutdoorExposure: "sun.max"
        case .highWindExposure: "wind"
        case .snowExposure: "snowflake"
        case .largeTemperatureSwing: "thermometer.medium"
        case .seasonal: "calendar"
        }
    }
}

enum PackingImpactBuilder {
    static let displayOrder: [PackingImpactSignal] = [
        .persistentRain, .meaningfulRain, .snowExposure, .coldEvenings,
        .hotOutdoorExposure, .highUVExposure, .highWindExposure, .largeTemperatureSwing, .seasonal
    ]

    static func build(
        items: [PackingItemDraft],
        party: TripParty,
        signalAdds: [String: [String]] = [:],
        templates: [String: String] = [:]
    ) -> [PackingImpact] {
        let weatherItems = items.filter { item in
            !item.isUserAdded && item.sourceSignals.contains(.weather)
        }
        guard !weatherItems.isEmpty else { return [] }

        var grouped: [PackingImpactSignal: [PackingItemDraft]] = [:]
        for item in weatherItems {
            guard let signal = signal(for: item, signalAdds: signalAdds) else { continue }
            grouped[signal, default: []].append(item)
        }

        if grouped[.persistentRain] != nil, let rain = grouped.removeValue(forKey: .meaningfulRain) {
            grouped[.persistentRain, default: []].append(contentsOf: rain)
        }

        return displayOrder.compactMap { signal in
            guard let drafts = grouped[signal], !drafts.isEmpty else { return nil }
            let impactItems = drafts.map { draft in
                PackingImpactItem(
                    itemID: draft.id,
                    canonicalItemID: draft.canonicalItemID,
                    displayName: draft.displayName,
                    quantity: draft.quantity,
                    effect: effect(for: draft),
                    ownerLabel: ownerLabel(for: draft, party: party),
                    reasonCode: draft.reasonCode
                )
            }
            .sorted { lhs, rhs in
                if lhs.ownerLabel != rhs.ownerLabel {
                    return (lhs.ownerLabel ?? "") < (rhs.ownerLabel ?? "")
                }
                return lhs.displayName < rhs.displayName
            }
            let arguments = mergedArguments(from: drafts)
            return PackingImpact(
                signal: signal,
                title: PackingImpactCopy.title(signal: signal, arguments: arguments, templates: templates),
                summary: PackingImpactCopy.summary(signal: signal, items: impactItems, party: party, templates: templates),
                affectedItems: impactItems,
                reasonCodes: Set(drafts.map(\.reasonCode).filter { !$0.isEmpty })
            )
        }
    }

    static func signal(for item: PackingItemDraft, signalAdds: [String: [String]]) -> PackingImpactSignal? {
        if let fromCode = signal(fromReasonCode: item.reasonCode, arguments: item.reasonArguments) {
            return fromCode
        }
        return reverseLookup(canonicalID: item.canonicalItemID, signalAdds: signalAdds)
    }

    static func signal(fromReasonCode code: String, arguments: [String: String]) -> PackingImpactSignal? {
        switch code {
        case "weather.rain_weekday":
            return .meaningfulRain
        case "weather.rain_days":
            let days = Int(arguments["rainDays"] ?? "1") ?? 1
            return days >= 2 ? .persistentRain : .meaningfulRain
        case "weather.cool_evenings", "weather.cold":
            return .coldEvenings
        case "weather.uv":
            return .highUVExposure
        case "weather.wind":
            return .highWindExposure
        case "weather.snow":
            return .snowExposure
        case "weather.temperature_swing":
            return .largeTemperatureSwing
        case "weather.hot":
            return .hotOutdoorExposure
        case "weather.seasonal_layer", "weather.seasonal_sun":
            return .seasonal
        default:
            return nil
        }
    }

    private static func reverseLookup(canonicalID: String?, signalAdds: [String: [String]]) -> PackingImpactSignal? {
        guard let canonicalID else { return nil }
        let order: [PackingImpactSignal] = [
            .persistentRain, .meaningfulRain, .snowExposure, .coldEvenings,
            .hotOutdoorExposure, .highUVExposure, .highWindExposure, .largeTemperatureSwing
        ]
        for signal in order {
            if signalAdds[signal.rawValue]?.contains(canonicalID) == true {
                return signal
            }
        }
        if signalAdds["coldRain"]?.contains(canonicalID) == true {
            return .meaningfulRain
        }
        return nil
    }

    private static func effect(for item: PackingItemDraft) -> PackingImpactEffect {
        if item.importance == .optional || item.category == .toiletries {
            return .recommended
        }
        return .added
    }

    private static func ownerLabel(for item: PackingItemDraft, party: TripParty) -> String? {
        guard !party.usesSimpleList else { return nil }
        if item.ownershipType == .shared { return "Shared" }
        return party.travelers.first { $0.id == item.travelerID }?.displayName
    }

    private static func mergedArguments(from drafts: [PackingItemDraft]) -> [String: String] {
        var merged: [String: String] = [:]
        for draft in drafts {
            for (key, value) in draft.reasonArguments where merged[key] == nil {
                merged[key] = value
            }
        }
        return merged
    }
}

enum PackingImpactCopy {
    static func title(
        signal: PackingImpactSignal,
        arguments: [String: String],
        templates: [String: String]
    ) -> String {
        switch signal {
        case .meaningfulRain:
            if let weekday = arguments["weekday"], !weekday.isEmpty {
                return ReasonRenderer.render(
                    code: "impact.rain.weekday",
                    arguments: arguments,
                    templates: templates,
                    fallback: "Rain expected \(weekday)"
                )
            }
            if let rainDays = arguments["rainDays"] {
                return ReasonRenderer.render(
                    code: "impact.rain.days",
                    arguments: arguments,
                    templates: templates,
                    fallback: "Rain expected on \(rainDays) days"
                )
            }
            return "Rain expected"
        case .persistentRain:
            if let rainDays = arguments["rainDays"] {
                return ReasonRenderer.render(
                    code: "impact.rain.days",
                    arguments: arguments,
                    templates: templates,
                    fallback: "Rain expected on \(rainDays) days"
                )
            }
            return "Rain expected"
        case .coldEvenings:
            return ReasonRenderer.render(code: "impact.cool_evenings", arguments: [:], templates: templates, fallback: "Cool evenings")
        case .highUVExposure:
            return ReasonRenderer.render(code: "impact.high_uv", arguments: [:], templates: templates, fallback: "High UV")
        case .highWindExposure:
            return ReasonRenderer.render(code: "impact.wind", arguments: [:], templates: templates, fallback: "Windy conditions")
        case .snowExposure:
            return ReasonRenderer.render(code: "impact.snow", arguments: [:], templates: templates, fallback: "Snow expected")
        case .largeTemperatureSwing:
            return ReasonRenderer.render(code: "impact.temperature_swing", arguments: [:], templates: templates, fallback: "Large temperature swing")
        case .hotOutdoorExposure:
            return ReasonRenderer.render(code: "impact.hot", arguments: [:], templates: templates, fallback: "Hot weather")
        case .seasonal:
            return ReasonRenderer.render(code: "impact.seasonal", arguments: [:], templates: templates, fallback: "Seasonal conditions")
        }
    }

    static func summary(
        signal: PackingImpactSignal,
        items: [PackingImpactItem],
        party: TripParty,
        templates: [String: String]
    ) -> String {
        if signal == .seasonal {
            let codes = Set(items.map(\.reasonCode))
            if codes.contains("weather.seasonal_sun") && !codes.contains("weather.seasonal_layer") {
                return ReasonRenderer.render(
                    code: "impact.seasonal.sun",
                    arguments: [:],
                    templates: templates,
                    fallback: "Sun protection is recommended for typical conditions this time of year."
                )
            }
            return ReasonRenderer.render(
                code: "impact.seasonal.layer",
                arguments: [:],
                templates: templates,
                fallback: "A light layer is recommended for typical conditions this time of year."
            )
        }
        return itemPhrase(signal: signal, items: items, party: party)
    }

    private static func itemPhrase(signal: PackingImpactSignal, items: [PackingImpactItem], party: TripParty) -> String {
        let recommended = items.allSatisfy { $0.effect == .recommended }
        let verb = recommended ? "recommended" : "added"
        if party.usesSimpleList {
            let names = uniqueNames(items)
            return "\(joined(names)) \(verb)"
        }
        let shared = items.filter { $0.ownerLabel == "Shared" }
        let personal = items.filter { $0.ownerLabel != "Shared" }
        var parts: [String] = []
        if !personal.isEmpty {
            let isRain = signal == .meaningfulRain || signal == .persistentRain
            if isRain, personal.count >= 2 {
                parts.append("Rain layers")
            } else {
                parts.append(collapsedPersonalPhrase(personal))
            }
        }
        for item in shared {
            parts.append(sharedPhrase(item))
        }
        return "\(joined(parts)) \(verb)"
    }

    private static func sharedPhrase(_ item: PackingImpactItem) -> String {
        if item.canonicalItemID == "essentials.umbrella_compact" {
            return item.quantity > 1 ? "\(item.quantity) shared umbrellas" : "shared umbrella"
        }
        if item.quantity > 1 {
            return "\(item.quantity) shared \(item.displayName.lowercased())s"
        }
        return "shared \(item.displayName.lowercased())"
    }

    private static func collapsedPersonalPhrase(_ items: [PackingImpactItem]) -> String {
        if items.count > 1, Set(items.compactMap(\.canonicalItemID)).count == 1 {
            return items[0].displayName
        }
        return joined(uniqueNames(items))
    }

    private static func uniqueNames(_ items: [PackingImpactItem]) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for item in items {
            if seen.insert(item.displayName).inserted {
                names.append(item.displayName)
            }
        }
        return names
    }

    private static func joined(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default:
            let head = names.dropLast().joined(separator: ", ")
            return "\(head), and \(names.last ?? "")"
        }
    }
}
