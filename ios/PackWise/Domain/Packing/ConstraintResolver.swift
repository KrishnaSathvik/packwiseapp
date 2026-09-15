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
    /// The normalized luggage decision behind the trim (Product Experience
    /// V2, Task 5): the resolved capacity and the selected bags in
    /// `BagType.stableOrder`, never selection order.
    var capacity: LuggageContext.Capacity
    var selectedBags: [BagType]
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
    /// Optional items carrying these tags survive constrained luggage:
    /// they're small or they matter more than space.
    static let essentialOptionalTags: Set<String> = ["base", "rain", "cold", "medication"]

    struct OptionalRuling {
        var keep: Bool
        /// Present when the drop should be recorded as a decision.
        var conflictKey: String?
        /// False whenever this call's own no-op guard short-circuited
        /// (importance != .optional, or the bag/style combination doesn't
        /// constrain space) — every other field is trivial in that case.
        var wasConstraintLive: Bool = false
        /// True when keep == true only because an essentialOptionalTags tag
        /// protected the item from a trim that was otherwise live.
        var essentialTagProtected: Bool = false
        /// The conflictKey this bag/style combination would use for a
        /// non-protected optional item; nil when this combination doesn't
        /// trim optionals at all.
        var wouldTrimUnderKey: String? = nil
    }

    /// Whether an optional item survives the luggage capacity and style.
    ///
    /// Reads the resolved `LuggageContext` capacity only, never the selected
    /// bags (Product Experience V2, Task 5). Very constrained capacity (a
    /// personal item alone) can't fit optional extras regardless of style —
    /// and when the style is Prepared, that's a genuine conflict (Prepared
    /// says bring backups; capacity says there's no room), resolved in
    /// capacity's favor and recorded under its own key. Compact, carry-on
    /// constrained, and moderate capacity only trim when packing light.
    /// Unspecified and checked-available capacity never trim, so a checked
    /// bag defeats every trim whatever else is selected.
    ///
    /// The would-be conflict key is computed *before* the essential-tag
    /// check (not just on the non-protected path) so a trace can answer
    /// "would this have trimmed the item absent tag protection" — a
    /// behavior-preserving reorder: every `keep`/`conflictKey` output is
    /// unchanged for every input.
    static func optionalRuling(
        importance: ItemImportance,
        tags: [String],
        luggage: LuggageContext,
        style: PackingStyle
    ) -> OptionalRuling {
        guard importance == .optional, luggage.appliesCapacityConstraint else {
            return OptionalRuling(keep: true, conflictKey: nil, wasConstraintLive: false, essentialTagProtected: false, wouldTrimUnderKey: nil)
        }
        let wouldBeKey: String? = switch luggage.capacity {
        case .veryConstrained:
            style == .prepared ? "style.prepared_vs_personal_item" : "bag.personal_item"
        case .compact, .carryOnConstrained, .moderate:
            style == .light ? "bag.space_constrained" : nil
        case .unspecified, .checkedAvailable:
            nil  // unreachable: the guard above already returned
        }
        let isEssentialOptional = tags.contains { essentialOptionalTags.contains($0) }
        if isEssentialOptional {
            return OptionalRuling(keep: true, conflictKey: nil, wasConstraintLive: true, essentialTagProtected: true, wouldTrimUnderKey: wouldBeKey)
        }
        if let wouldBeKey {
            return OptionalRuling(keep: false, conflictKey: wouldBeKey, wasConstraintLive: true, essentialTagProtected: false, wouldTrimUnderKey: wouldBeKey)
        }
        return OptionalRuling(keep: true, conflictKey: nil, wasConstraintLive: true, essentialTagProtected: false, wouldTrimUnderKey: nil)
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
        from drops: [(travelerID: UUID?, canonicalItemID: String, key: String)],
        luggage: LuggageContext
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
                    items: entry.items.sorted(),
                    capacity: luggage.capacity,
                    selectedBags: luggage.orderedBagTypes
                )
            }
            .sorted {
                if $0.constraint != $1.constraint { return $0.constraint < $1.constraint }
                return ($0.travelerID?.uuidString ?? "") < ($1.travelerID?.uuidString ?? "")
            }
    }
}

extension ConstraintResolver {
    /// Whether an item is shared across the party or stays personal, and if
    /// shared, its resolved quantity and user-facing reason. The one place
    /// `PackingEngine` asks this, replacing two independent
    /// `sharedByDefault` membership checks and the free-standing
    /// `sharedQuantity`/`sharedQuantityReason` pair.
    enum SharingResolution: Hashable, Sendable {
        case personal
        case shared(quantity: Int, reason: String)

        var isShared: Bool { if case .shared = self { true } else { false } }
    }

    static func sharingResolution(
        for canonicalItemID: String,
        rules: PartyRulesFile,
        context: TripContext,
        party: TripParty
    ) -> SharingResolution {
        guard rules.sharedByDefault.contains(canonicalItemID) else { return .personal }
        let policy = rules.sharingPolicies[canonicalItemID]
            ?? SharingPolicyRule(policy: .singlePerParty, per: nil, min: 1, value: 1)
        // Required amendment: a `.personalOnly` item never reaches the
        // shared-draft path at all — `generateForParty` calls `.isShared`,
        // so this early return is what keeps such an item on the ordinary
        // per-traveler personal path with a real `travelerID`, closing the
        // fallthrough-to-ownerless-shared-draft bug the personalOnly
        // contract tests guard. This is the fix, not a stub — do not remove
        // it.
        guard policy.policy != .personalOnly else { return .personal }
        let quantity = sharedQuantity(policy, context: context, party: party)
        let reason = sharedQuantityReason(canonicalItemID, quantity: quantity, context: context, party: party)
        return .shared(quantity: quantity, reason: reason)
    }

    private static func sharedQuantity(_ rule: SharingPolicyRule, context: TripContext, party: TripParty) -> Int {
        let minimum = rule.min ?? 1
        let per = max(1, rule.per ?? 1)
        switch rule.policy {
        case .singlePerParty, .personalOnly:
            return rule.value ?? 1
        case .scaleByParty:
            return max(minimum, Int((Double(party.travelers.count) / Double(per)).rounded(.up)))
        case .scaleByDevices:
            return max(minimum, Int((Double(max(1, party.adults.count)) / Double(per)).rounded(.up)))
        case .scaleByDurationAndParty:
            return max(minimum, Int((Double(party.travelers.count * context.durationDays) / Double(per)).rounded(.up)))
        }
    }

    /// Moved verbatim from `PackingEngine.sharedQuantityReason`. Rendering
    /// templated reason strings requires `rules.reasons.templates`, which
    /// `ConstraintResolver` does not otherwise depend on — this stays a
    /// plain-string fallback builder here, and `PackingEngine.applyQuantities`
    /// re-renders this exact fallback shape through its own
    /// `render(_:_:fallback:)` (umbrella special case + generic "N for the
    /// group" case), preserving today's templated-string behavior without
    /// giving `ConstraintResolver` a `PackingRulesFile` dependency it
    /// doesn't otherwise need.
    private static func sharedQuantityReason(_ canonical: String, quantity: Int, context: TripContext, party: TripParty) -> String {
        if canonical == "essentials.umbrella_compact", let weather = context.weather, weather.rainDays > 0 {
            // Templates can't pluralize, so the phrases arrive pre-built:
            // never "1 days", never "1 umbrellas", and a couple is a group,
            // not a "family".
            let rainDaysPhrase = weather.rainDays == 1 ? "1 day" : "\(weather.rainDays) days"
            let umbrellaPhrase = quantity == 1 ? "One umbrella" : "\(quantity) umbrellas"
            return "Rain is expected on \(rainDaysPhrase). \(umbrellaPhrase) should cover your group — no need to pack one each."
        }
        return quantity == 1
            ? "One for the group — not one per person."
            : "\(quantity) for the group — not one per person."
    }
}

extension ConstraintResolver {
    /// True when a draft carries explicit current-trip user state no
    /// lower-priority layer may override: a manual quantity edit or a
    /// hand-added item. Replaces the identical `isUserAdded || isUserModified`
    /// check written independently in `resolve()` and `applyQuantities()`.
    static func hasUserAuthority(_ item: PackingItemDraft) -> Bool {
        item.isUserAdded || item.isUserModified
    }

    /// True when an explicit "Not Needed" override exists for this
    /// candidate, scoped to ownership and traveler. Moved verbatim from
    /// `PackingEngine.isRemoved` — same scoping, same behavior.
    static func isExplicitlyRemoved(
        _ canonicalItemID: String,
        ownership: PackingOwnership,
        travelerID: UUID?,
        overrides: [RecommendationOverrideDraft]
    ) -> Bool {
        overrides.contains { override in
            guard override.action == "removed", override.canonicalItemID == canonicalItemID else { return false }
            if let overrideTraveler = override.travelerID, overrideTraveler != travelerID { return false }
            if let overrideOwnership = override.ownershipType, overrideOwnership != ownership { return false }
            return true
        }
    }
}
