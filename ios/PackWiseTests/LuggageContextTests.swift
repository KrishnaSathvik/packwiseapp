import Foundation
import Testing
@testable import PackWise

/// Product Experience V2, Task 5 — the selected bag set resolves once into
/// one normalized luggage-capacity context.
struct LuggageContextTests {
    /// The complete approved table (design section 7): every subset of the
    /// four physical bags, written out rather than derived, so the test is
    /// the table and not a second implementation of it.
    private static let truthTable: [(bags: Set<BagType>, capacity: LuggageContext.Capacity)] = [
        ([], .unspecified),
        ([.personalItem], .veryConstrained),
        ([.backpack], .compact),
        ([.personalItem, .backpack], .compact),
        ([.carryOn], .carryOnConstrained),
        ([.personalItem, .carryOn], .carryOnConstrained),
        ([.carryOn, .backpack], .moderate),
        ([.personalItem, .carryOn, .backpack], .moderate),
        ([.checked], .checkedAvailable),
        ([.checked, .carryOn], .checkedAvailable),
        ([.checked, .personalItem], .checkedAvailable),
        ([.checked, .backpack], .checkedAvailable),
        ([.checked, .carryOn, .personalItem], .checkedAvailable),
        ([.checked, .carryOn, .backpack], .checkedAvailable),
        ([.checked, .personalItem, .backpack], .checkedAvailable),
        ([.checked, .carryOn, .personalItem, .backpack], .checkedAvailable)
    ]

    @Test func everyBagSubsetResolvesToItsApprovedCapacity() {
        #expect(Self.truthTable.count == 16, "all 2^4 subsets of the physical bags")
        #expect(Set(Self.truthTable.map { $0.bags.map(\.rawValue).sorted() }).count == 16, "no subset listed twice")
        for row in Self.truthTable {
            let luggage = LuggageContext.resolve(row.bags)
            #expect(luggage.capacity == row.capacity, "\(row.bags)")
            #expect(luggage.bagTypes == row.bags)
        }
    }

    @Test func onlyConstrainedCapacitiesApplyACapacityConstraint() {
        for row in Self.truthTable {
            let constrained: Set<LuggageContext.Capacity> = [.veryConstrained, .compact, .carryOnConstrained, .moderate]
            #expect(LuggageContext.resolve(row.bags).appliesCapacityConstraint == constrained.contains(row.capacity), "\(row.bags)")
        }
        #expect(LuggageContext.resolve([]).appliesCapacityConstraint == false, "Not sure yet applies no constraint")
    }

    /// A checked bag always defeats carry-on-only and personal-item-only
    /// trimming, whatever else is selected and whatever the style.
    @Test func anyCheckedBagDefeatsEveryCapacityTrim() {
        for row in Self.truthTable where row.bags.contains(.checked) {
            let luggage = LuggageContext.resolve(row.bags)
            #expect(!luggage.appliesCapacityConstraint, "\(row.bags)")
            for style in PackingStyle.allCases {
                let ruling = ConstraintResolver.optionalRuling(importance: .optional, tags: [], luggage: luggage, style: style)
                #expect(ruling.keep && ruling.conflictKey == nil && !ruling.wasConstraintLive, "\(row.bags) \(style)")
            }
        }
    }

    /// Legacy `notSure`/`roadTripLuggage` are migration-only: they never
    /// count as a bag, so they never change capacity.
    @Test func legacyBagValuesNeverEnterV2Behavior() {
        #expect(LuggageContext.resolve([.notSure]) == LuggageContext.resolve([]))
        #expect(LuggageContext.resolve([.roadTripLuggage]) == LuggageContext.resolve([]))
        #expect(LuggageContext.resolve([.roadTripLuggage, .carryOn]) == LuggageContext.resolve([.carryOn]))
        #expect(LuggageContext.resolve([.notSure, .personalItem, .checked]) == LuggageContext.resolve([.personalItem, .checked]))
    }

    @Test func resolutionIsIndependentOfInsertionOrder() {
        let orders: [[BagType]] = [
            [.personalItem, .carryOn, .checked, .backpack],
            [.backpack, .checked, .carryOn, .personalItem],
            [.checked, .personalItem, .backpack, .carryOn]
        ]
        for count in 1...4 {
            for order in orders {
                var inserted = Set<BagType>(minimumCapacity: 8)
                for bag in order.prefix(count).reversed() { inserted.insert(bag) }
                let members = Set(order.prefix(count))
                #expect(LuggageContext.resolve(inserted) == LuggageContext.resolve(members))
            }
        }
        let a = LuggageContext.resolve([.checked, .carryOn, .personalItem])
        let b = LuggageContext.resolve([.personalItem, .carryOn, .checked])
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        #expect(a.orderedBagTypes == [.personalItem, .carryOn, .checked], "trace order is BagType.stableOrder, never selection order")
        #expect(b.orderedBagTypes == a.orderedBagTypes)
    }

    // MARK: - The levers each capacity drives (existing single-bag policy)

    @Test func optionalTrimKeysFollowCapacityAndStyleOnly() {
        func key(_ bags: Set<BagType>, _ style: PackingStyle) -> String? {
            ConstraintResolver.optionalRuling(importance: .optional, tags: [], luggage: .resolve(bags), style: style).conflictKey
        }
        for style in PackingStyle.allCases {
            let personal = style == .prepared ? "style.prepared_vs_personal_item" : "bag.personal_item"
            let light = style == .light ? "bag.space_constrained" : nil
            #expect(key([.personalItem], style) == personal)
            #expect(key([.backpack], style) == light)
            #expect(key([.personalItem, .backpack], style) == light, "a backpack beside a personal item is compact, not very constrained")
            #expect(key([.carryOn], style) == light)
            #expect(key([.personalItem, .carryOn], style) == light, "carry-on semantics, not personal-item semantics")
            #expect(key([.carryOn, .backpack], style) == light)
            #expect(key([], style) == nil)
            #expect(key([.carryOn, .checked], style) == nil, "no carry-on trim beside a checked bag")
        }
    }

    @Test func essentialTagsStillProtectOptionalItemsUnderEveryConstrainedCapacity() {
        for row in Self.truthTable where LuggageContext.resolve(row.bags).appliesCapacityConstraint {
            let ruling = ConstraintResolver.optionalRuling(
                importance: .optional, tags: ["rain"], luggage: .resolve(row.bags), style: .light
            )
            #expect(ruling.keep && ruling.essentialTagProtected, "\(row.bags)")
        }
    }

    @Test func clothingCapsFollowCapacity() {
        let tops = ClothingNeedPolicy.byKind["daily_top"]!
        func cap(_ bags: Set<BagType>) -> Int? {
            ClothingQuantityEngine.evaluate(tops, context: ClothingQuantityContext(
                days: 30, style: .prepared, luggage: .resolve(bags), laundry: .none,
                selectedActivityIDs: [], datedActivityUses: [:], party: .solo()
            )).evidence.bagCap
        }
        #expect(cap([.personalItem]) == tops.personalItemMaximum)
        for bags: Set<BagType> in [[.backpack], [.personalItem, .backpack], [.carryOn], [.personalItem, .carryOn], [.carryOn, .backpack]] {
            #expect(cap(bags) == tops.constrainedBagMaximum, "\(bags)")
        }
        for bags: Set<BagType> in [[], [.checked], [.carryOn, .checked], [.personalItem, .carryOn, .checked], [.backpack, .checked]] {
            #expect(cap(bags) == nil, "\(bags)")
        }
    }

    /// More bags never means more clothes: a quantity depends on capacity,
    /// never on how many bags were selected.
    @Test func bagCountNeverMultipliesClothing() {
        for policy in ClothingNeedPolicy.all {
            let kind = policy.kinds[0]
            for style in PackingStyle.allCases {
                func value(_ bags: Set<BagType>) -> Int {
                    ClothingQuantityEngine.evaluate(ClothingNeedPolicy.byKind[kind]!, context: ClothingQuantityContext(
                        days: 9, style: style, luggage: .resolve(bags), laundry: .none,
                        selectedActivityIDs: [], datedActivityUses: [:], party: .solo()
                    )).value
                }
                #expect(value([.checked]) == value([.personalItem, .carryOn, .checked, .backpack]), "\(kind) \(style)")
                #expect(value([.carryOn]) == value([.personalItem, .carryOn]), "\(kind) \(style)")
                #expect(value([.backpack]) == value([.personalItem, .backpack]), "\(kind) \(style)")
                #expect(value([]) == value([.checked]), "\(kind) \(style): unconstrained is unconstrained")
            }
        }
    }

    // MARK: - Single luggage authority

    /// Structural guard: engine decision files never ask which bags were
    /// selected, never promote a primary bag, and never name a bag case.
    /// Only `LuggageContext.swift` interprets the set.
    @Test func engineDecisionFilesNeverInterpretBagsDirectly() throws {
        let packing = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PackWise/Domain")
        let files = [
            "Packing/PackingEngine.swift", "Packing/ConstraintResolver.swift", "Packing/ClothingQuantity.swift",
            "Packing/QuantityEngine.swift", "Packing/CareQuantity.swift", "Packing/CoverageResolver.swift",
            "TripContextSnapshot.swift"
        ]
        let forbidden = [
            #"bagTypes\.(contains|first|isDisjoint|count|intersection|sorted|filter|map)"#,
            #"\.bagType\b"#, #"primaryBag"#, #"preferredBag"#,
            #"\.(personalItem|carryOn|checked|backpack|notSure|roadTripLuggage)\b"#
        ]
        for file in files {
            let source = try String(contentsOf: packing.appendingPathComponent(file), encoding: .utf8)
            for pattern in forbidden {
                #expect(source.range(of: pattern, options: .regularExpression) == nil, "\(file) matches \(pattern)")
            }
        }
    }
}
