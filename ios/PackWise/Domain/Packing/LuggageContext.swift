import Foundation

// Product Experience V2, Task 5 — normalized luggage capacity.
//
//     Set<BagType> → LuggageContext.resolve → capacity
//
// Bags describe available capacity, never separate packing plans. This file is
// the only place that asks which bags were selected; constraints, quantities,
// and the snapshot consume the resolved capacity. Packing style is a separate
// input and is not read here. No bin-packing or per-bag allocation exists.

/// The one engine-facing interpretation of the selected bags. Derived, never
/// persisted (design section 7).
struct LuggageContext: Hashable, Sendable {
    enum Capacity: String, Codable, CaseIterable, Sendable {
        /// Nothing selected ("Not sure yet"): no capacity constraint.
        case unspecified
        /// A personal item and nothing else.
        case veryConstrained
        /// A backpack, with or without a personal item.
        case compact
        /// A carry-on, with or without a personal item.
        case carryOnConstrained
        /// A carry-on and a backpack, no checked bag.
        case moderate
        /// Any selection containing a checked bag.
        case checkedAvailable
    }

    /// Physical V2 bags only. Legacy `notSure`/`roadTripLuggage` never enter.
    let bagTypes: Set<BagType>
    let capacity: Capacity
    let appliesCapacityConstraint: Bool

    /// Precedence is deterministic and order-independent: a checked bag wins
    /// outright, then carry-on (moderate when a backpack joins it), then
    /// backpack, then personal item. A personal item beside a larger bag
    /// never lowers capacity.
    static func resolve(_ selected: Set<BagType>) -> LuggageContext {
        let bags = selected.intersection(BagType.stableOrder)
        let capacity: Capacity
        if bags.contains(.checked) {
            capacity = .checkedAvailable
        } else if bags.contains(.carryOn) {
            capacity = bags.contains(.backpack) ? .moderate : .carryOnConstrained
        } else if bags.contains(.backpack) {
            capacity = .compact
        } else if bags.contains(.personalItem) {
            capacity = .veryConstrained
        } else {
            capacity = .unspecified
        }
        return LuggageContext(bagTypes: bags, capacity: capacity, appliesCapacityConstraint: capacity.isConstrained)
    }

    /// Whether an airline cabin bag (a personal item or carry-on) is among the
    /// selection. Not a capacity: it carries forward the pre-V2 "carry-on or
    /// personal item" trigger for the empty security bottle, generalized to a
    /// set without a primary bag. A checked bag beside one doesn't change it.
    var includesCabinBag: Bool {
        !bagTypes.isDisjoint(with: [.personalItem, .carryOn])
    }

    /// Selected bags in `BagType.stableOrder` — the only order a trace or
    /// signature may use.
    var orderedBagTypes: [BagType] {
        BagType.stableOrder.filter(bagTypes.contains)
    }
}

extension LuggageContext.Capacity {
    var isConstrained: Bool {
        switch self {
        case .veryConstrained, .compact, .carryOnConstrained, .moderate: true
        case .unspecified, .checkedAvailable: false
        }
    }
}

extension TripContext {
    /// The trip's resolved luggage. Engine code reads this, never `bagTypes`.
    var luggage: LuggageContext { .resolve(bagTypes) }
}
