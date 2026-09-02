import Foundation

/// Per-use quantities for the child-care family — Slice 8.
///
/// Step 2 moved clothing to needs-based quantities but scoped to clothing
/// only, so care items stayed on duration arithmetic: "9 based on a 7-day
/// trip" for diapers, which a toddler runs through in two days. Care items
/// are consumed per use, so quantity derives from a daily rate — with a
/// restock plateau on long trips, because nobody hauls a month of diapers.
///
/// Routed by canonical item id: the catalog and its `quantity_kind` values
/// are frozen, and `kids.diapers` shares a kind with `kids.extra_outfits`.
enum CareQuantityEngine {
    struct Result: Sendable {
        var value: Int
        var reasonCode: String
        var arguments: [String: String]
        var fallback: String
    }

    /// Diapers packed for at most this many days; beyond it the reason says
    /// to buy more at the destination.
    static let diaperRestockDays = 7
    /// Underwear kept beside diapers as a training/accident backup — the
    /// coverage claim is deliberately partial, so a potty-training toddler
    /// whose parent ticked diapers is still covered.
    static let diaperedUnderwearBackup = 3

    static func dailyDiaperRate(for ageGroup: AgeGroup) -> Int {
        ageGroup == .infant ? 8 : 5
    }

    static func handles(_ canonicalID: String) -> Bool {
        canonicalID == "kids.diapers" || canonicalID == "kids.extra_outfits"
    }

    static func quantity(canonicalID: String, days: Int, traveler: Traveler?) -> Result? {
        let name = traveler?.displayName ?? "your child"
        switch canonicalID {
        case "kids.diapers":
            let rate = dailyDiaperRate(for: traveler?.ageGroup ?? .toddler)
            let needed = rate * max(1, days)
            let capped = min(needed, rate * diaperRestockDays)
            let arguments = ["quantity": "\(capped)", "rate": "\(rate)", "name": name, "days": "\(days)"]
            if needed > capped {
                return Result(
                    value: capped,
                    reasonCode: "quantity.diapers_restock",
                    arguments: arguments,
                    fallback: "About \(rate) a day for \(name). \(capped) covers the first week — plan to buy more there."
                )
            }
            return Result(
                value: capped,
                reasonCode: "quantity.diapers",
                arguments: arguments,
                fallback: "About \(rate) a day for \(name) — \(capped) for \(days) days."
            )
        case "kids.extra_outfits":
            // ceil(days / 3), clamped: an accident buffer beside the daily
            // clothing the age multipliers already scale, not a second
            // wardrobe.
            let value = min(3, max(1, (days + 2) / 3))
            let arguments = ["quantity": "\(value)", "name": name]
            if value == 1 {
                return Result(
                    value: value,
                    reasonCode: "quantity.extra_outfit_single",
                    arguments: arguments,
                    fallback: "A spare outfit for \(name) — spills and surprises happen."
                )
            }
            return Result(
                value: value,
                reasonCode: "quantity.extra_outfits",
                arguments: arguments,
                fallback: "\(value) spare outfits for \(name) — spills and surprises happen."
            )
        default:
            return nil
        }
    }
}
