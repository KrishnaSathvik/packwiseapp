import Foundation

/// One recorded constraint resolution. `summary` is the user-facing version
/// and must be one short, honest sentence in the user's terms — if the
/// resolution can't be stated that way, the resolution is too clever.
struct ConstraintDecision: Hashable, Sendable {
    /// Machine key, e.g. "bag.personal_item" or "style.prepared_vs_personal_item".
    var constraint: String
    var summary: String
    var travelerID: UUID?
    /// Canonical IDs the decision removed, sorted.
    var items: [String]
}

/// Where conflicts between trip constraints resolve — Engine V2, Step 5.
///
/// The decision hierarchy, top wins:
///
///   1. Explicit user state (added / removed / quantity edited / Not Needed)
///   2. Safety-critical non-mutating reminders (never edit the list)
///   3. Current trip requirements (weather, activities, party)
///   4. Traveler preferences (style, chips)
///   5. Packing Memory (later)
///   6. Contextual model recommendations
///   7. Generic defaults
///
/// Two rules must never fight silently: when constraints conflict — Prepared
/// says bring extras, a personal item says there's no room — the resolver
/// decides explicitly and the decision is recorded.
enum ConstraintResolver {
    /// Optional items carrying these tags survive a space-constrained bag:
    /// they're small or they matter more than space.
    static let essentialOptionalTags: Set<String> = ["base", "rain", "cold", "medication"]

    struct OptionalRuling {
        var keep: Bool
        /// Present when the drop should be recorded as a decision.
        var conflictKey: String?
    }

    /// Whether an optional item survives the bag/style combination.
    ///
    /// A personal item can't fit optional extras regardless of style — and
    /// when the style is Prepared, that's a genuine conflict (Prepared says
    /// bring backups; the bag says there's no room), resolved in the bag's
    /// favor and recorded under its own key. Carry-on and backpack only trim
    /// when packing light; checked and road-trip luggage never trim.
    static func optionalRuling(
        importance: ItemImportance,
        tags: [String],
        bag: BagType,
        style: PackingStyle
    ) -> OptionalRuling {
        guard importance == .optional,
              bag.appliesBagConstraint, bag.isSpaceConstrained else {
            return OptionalRuling(keep: true, conflictKey: nil)
        }
        let isEssentialOptional = tags.contains { essentialOptionalTags.contains($0) }
        if isEssentialOptional {
            return OptionalRuling(keep: true, conflictKey: nil)
        }
        if bag == .personalItem {
            let key = style == .prepared ? "style.prepared_vs_personal_item" : "bag.personal_item"
            return OptionalRuling(keep: false, conflictKey: key)
        }
        if style == .light {
            return OptionalRuling(keep: false, conflictKey: "bag.space_constrained")
        }
        return OptionalRuling(keep: true, conflictKey: nil)
    }

    /// The one-sentence, user-terms copy for each conflict key.
    static func summary(for key: String) -> String {
        switch key {
        case "bag.personal_item":
            return "Trimmed to fit a personal item."
        case "style.prepared_vs_personal_item":
            return "Trimmed to fit a personal item — Prepared adds backups where there's room."
        case "bag.space_constrained":
            return "Left out to keep the bag light."
        default:
            return "Adjusted for this trip's constraints."
        }
    }

    /// Aggregates raw drops into one recorded decision per conflict and
    /// traveler, items sorted, so the ledger stays compact and reviewable.
    static func decisions(
        from drops: [(travelerID: UUID?, canonicalItemID: String, key: String)]
    ) -> [ConstraintDecision] {
        var grouped: [String: (travelerID: UUID?, key: String, items: Set<String>)] = [:]
        for drop in drops {
            let groupKey = "\(drop.key)|\(drop.travelerID?.uuidString ?? "shared")"
            var entry = grouped[groupKey] ?? (drop.travelerID, drop.key, [])
            entry.items.insert(drop.canonicalItemID)
            grouped[groupKey] = entry
        }
        return grouped.values
            .map { entry in
                ConstraintDecision(
                    constraint: entry.key,
                    summary: summary(for: entry.key),
                    travelerID: entry.travelerID,
                    items: entry.items.sorted()
                )
            }
            .sorted {
                if $0.constraint != $1.constraint { return $0.constraint < $1.constraint }
                return ($0.travelerID?.uuidString ?? "") < ($1.travelerID?.uuidString ?? "")
            }
    }
}
