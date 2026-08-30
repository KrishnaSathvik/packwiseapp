import Foundation

struct QuantityEngine: Sendable {
    var policies: [String: QuantityPolicy]
    var reasons: ReasonTemplatesFile

    func quantity(
        kind: String,
        context: TripContext,
        itemName: String,
        traveler: Traveler? = nil,
        multipliers: [String: Double] = [:]
    ) -> (value: Int, reason: String) {
        let policy = resolve(kind)
        var value = compute(policy, kind: kind, context: context)
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

    private func resolve(_ kind: String) -> QuantityPolicy {
        var current = kind
        var guardCount = 0
        while guardCount < 4 {
            guard let policy = policies[current] else {
                return QuantityPolicy(kind: "fixed", value: 1, alias: nil, light: nil, balanced: nil, prepared: nil, thresholdDays: nil, lightDivisor: nil, balancedDivisor: nil, min: 1)
            }
            if policy.kind == "alias", let alias = policy.alias {
                current = alias
                guardCount += 1
                continue
            }
            return policy
        }
        return QuantityPolicy(kind: "fixed", value: 1, alias: nil, light: nil, balanced: nil, prepared: nil, thresholdDays: nil, lightDivisor: nil, balancedDivisor: nil, min: 1)
    }

    private func spec(_ policy: QuantityPolicy, style: PackingStyle) -> QuantityStyleSpec? {
        switch style {
        case .light: policy.light
        case .balanced: policy.balanced
        case .prepared: policy.prepared
        }
    }

    private func compute(_ policy: QuantityPolicy, kind: String, context: TripContext) -> Int {
        let days = context.durationDays
        let laundry = context.hasLaundry
        let style = context.packingStyle
        let styleSpec = spec(policy, style: style)

        switch policy.kind {
        case "fixed":
            return policy.value ?? 1
        case "style_factor":
            let factor = styleSpec?.factor ?? 1
            let minimum = styleSpec?.min ?? 1
            if laundry {
                let raw = Int((Double(days) * factor).rounded(.up))
                return max(minimum, raw - (styleSpec?.laundryMinus ?? 0))
            }
            if styleSpec?.noLaundryUseDays == true {
                return days
            }
            if let extra = styleSpec?.noLaundryPlus {
                return days + extra
            }
            if let minus = styleSpec?.noLaundryMinus {
                return max(minimum, days - minus)
            }
            return max(minimum, days)
        case "style_days":
            if style == .light {
                if laundry && styleSpec?.laundryUse == "days_capped_6" {
                    return min(days, 6)
                }
                return days
            }
            let plus = laundry ? (styleSpec?.laundryPlus ?? 0) : (styleSpec?.plus ?? 0)
            if style == .balanced && laundry {
                return days
            }
            return days + plus
        case "reuse_interval":
            let interval = styleSpec?.factor ?? 2.5
            return max(policy.min ?? 1, Int((Double(days) / interval).rounded(.up)))
        case "style_fixed":
            switch style {
            case .light: return policy.light?.factor.map { Int($0) } ?? 1
            case .balanced: return policy.balanced?.factor.map { Int($0) } ?? 1
            case .prepared: return policy.prepared?.factor.map { Int($0) } ?? 2
            }
        case "long_trip_backup":
            return days >= (policy.thresholdDays ?? 6) && style != .light ? 2 : 1
        case "workout":
            let divisor = style == .light ? (policy.lightDivisor ?? 3) : (policy.balancedDivisor ?? 2)
            let workouts = max(1, days / divisor)
            return laundry ? max(1, workouts - 1) : workouts
        default:
            return 1
        }
    }
}

enum ReasonRenderer {
    static func render(code: String, arguments: [String: String], templates: [String: String], fallback: String) -> String {
        guard !code.isEmpty, var template = templates[code] else { return fallback }
        for (key, value) in arguments {
            template = template.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return template
    }
}
