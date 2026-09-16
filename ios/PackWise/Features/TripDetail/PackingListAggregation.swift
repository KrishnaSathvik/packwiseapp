import Foundation

/// Product Experience V2, Task 11 — presentation aggregation for the Packing
/// List.
///
/// A family list holds one `PackingItemRecord` per traveler per item, and
/// that is right: ownership, quantity, packed state, and Not Needed are
/// per person. Showing four "Toothbrush" rows in the All scope is not. The
/// aggregator turns the records into presentation rows — one group per
/// identical personal item, real rows for everything else — and nothing
/// here is persisted or written back. Every group carries the record IDs
/// underneath, and every mutation targets one of those records.
///
/// Pure and deterministic: one grouping pass per category, stable sorting,
/// no dependence on input order.

/// The aggregator's view of one record. Built from a `PackingItemRecord`
/// (or a draft in tests); the record's `id` is the row's identity.
struct PackingListItem: Hashable, Identifiable, Sendable {
    var id: UUID
    var canonicalItemID: String?
    var displayName: String
    var category: PackingCategory
    var quantity: Int
    var packedQuantity: Int
    var importance: ItemImportance
    var ownershipType: PackingOwnership
    var travelerID: UUID?
    var assignedTravelerID: UUID?
    var isUserAdded: Bool

    /// The one Packed definition, shared with the record and the draft.
    var isPacked: Bool { packedQuantity >= max(1, quantity) }
    var isImportant: Bool { importance == .critical || importance == .important }
}

extension PackingListItem {
    init(record: PackingItemRecord) {
        self.init(
            id: record.id,
            canonicalItemID: record.canonicalItemID,
            displayName: record.displayName,
            category: record.category,
            quantity: record.quantity,
            packedQuantity: record.packedQuantity,
            importance: record.importance,
            ownershipType: record.ownershipType,
            travelerID: record.travelerID,
            assignedTravelerID: record.assignedTravelerID,
            isUserAdded: record.isUserAdded
        )
    }
}

/// The Status scope: none selected shows everything.
enum PackingStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case toPack = "To pack"
    case packed = "Packed"
    case important = "Important"
    var id: String { rawValue }
}

/// What the user has asked the list to show. Applied to the underlying
/// records *before* aggregation, so a group is visible when any of its
/// records matches and shows only the records that do.
struct PackingListQuery: Hashable, Sendable {
    var scope: PartyListFilter = .all
    var status: PackingStatusFilter? = nil
    var search: String = ""
    var hidePacked: Bool = false
}

/// One real record as a row, with its people context resolved to labels.
struct PackingListEntry: Hashable, Identifiable, Sendable {
    var item: PackingListItem
    /// The owner's label for a personal record; nil for shared.
    var travelerLabel: String?
    /// Who brings a shared record, when someone has been chosen.
    var carrierLabel: String?

    var id: UUID { item.id }

    /// The caption under a shared row: "Shared" or "Shared · Alex carries".
    var secondaryText: String? {
        guard item.ownershipType == .shared else { return nil }
        if let carrierLabel { return "\(TripParty.sharedLabel) · \(carrierLabel) carries" }
        return TripParty.sharedLabel
    }
}

/// One traveler's record inside a group.
struct PersonalItemGroupMember: Hashable, Identifiable, Sendable {
    /// The underlying record's ID.
    var id: UUID
    var travelerID: UUID
    var travelerLabel: String
    var quantity: Int
    var packedQuantity: Int
    var importance: ItemImportance
    var isComplete: Bool
}

/// Identical personal items across travelers, presented once. Not a
/// persisted thing: it has no quantity of its own to edit.
struct PersonalItemGroup: Hashable, Identifiable, Sendable {
    var canonicalItemID: String
    var category: PackingCategory
    var displayName: String
    /// In party order.
    var members: [PersonalItemGroupMember]

    var id: String { "group:\(category.rawValue):\(canonicalItemID)" }
    var recordIDs: [UUID] { members.map(\.id) }
    var travelerCount: Int { members.count }
    var completedTravelerCount: Int { members.filter(\.isComplete).count }
    var totalQuantity: Int { members.reduce(0) { $0 + $1.quantity } }
    /// The strongest importance among the records; never written back.
    var importance: ItemImportance {
        members.map(\.importance).max { ItemImportance.rank($0) < ItemImportance.rank($1) } ?? .normal
    }
    /// Record-level completion: every visible record is packed.
    var isComplete: Bool { !members.isEmpty && members.allSatisfy(\.isComplete) }
    /// Record-level progress, the same semantic the section headers use.
    var progressText: String { "\(completedTravelerCount) / \(travelerCount)" }

    /// "You ×5 · Alex ×5 · Child 1 ×9" when quantities matter; otherwise the
    /// plain count, "4 personal".
    var travelerSummary: String {
        if members.contains(where: { $0.quantity > 1 }) {
            return members.map { "\($0.travelerLabel) ×\($0.quantity)" }.joined(separator: " · ")
        }
        return "\(travelerCount) personal"
    }

    /// Reads the row, then the quantities only when they are few enough to
    /// be worth hearing.
    var accessibilityLabel: String {
        var label = "\(displayName). \(travelerCount) travelers. \(completedTravelerCount) of \(travelerCount) packed."
        if members.contains(where: { $0.quantity > 1 }), members.count <= 4 {
            label += " " + members.map { "\($0.travelerLabel) \($0.quantity)" }.joined(separator: ", ") + "."
        }
        return label
    }
}

private extension ItemImportance {
    static func rank(_ importance: ItemImportance) -> Int {
        switch importance {
        case .critical: 2
        case .important: 1
        default: 0
        }
    }
}

enum PackingListPresentationRow: Hashable, Identifiable, Sendable {
    case individual(PackingListEntry)
    case personalGroup(PersonalItemGroup)
    case shared(PackingListEntry)

    var id: String {
        switch self {
        case .individual(let entry): "record:\(entry.id.uuidString)"
        case .shared(let entry): "record:\(entry.id.uuidString)"
        case .personalGroup(let group): group.id
        }
    }

    var displayName: String {
        switch self {
        case .individual(let entry), .shared(let entry): entry.item.displayName
        case .personalGroup(let group): group.displayName
        }
    }

    var recordIDs: [UUID] {
        switch self {
        case .individual(let entry), .shared(let entry): [entry.id]
        case .personalGroup(let group): group.recordIDs
        }
    }
}

/// One category's rows plus its record-level counts.
struct PackingListSection: Hashable, Identifiable, Sendable {
    var category: PackingCategory
    var rows: [PackingListPresentationRow]
    var completedCount: Int
    var totalCount: Int

    var id: PackingCategory { category }
    var isComplete: Bool { totalCount > 0 && completedCount == totalCount }
}

/// A People chip.
struct PackingListScopeLabel: Hashable, Sendable {
    var scope: PartyListFilter
    var title: String
}

enum PackingListAggregator {
    // MARK: - Query

    static func matches(_ item: PackingListItem, scope: PartyListFilter, party: TripParty) -> Bool {
        switch scope {
        case .all: true
        case .shared: item.ownershipType == .shared
        case .traveler(let id): item.ownershipType == .personal && item.travelerID == id
        }
    }

    static func matches(_ item: PackingListItem, status: PackingStatusFilter?) -> Bool {
        switch status {
        case nil: true
        case .toPack: !item.isPacked
        case .packed: item.isPacked
        case .important: item.isImportant
        }
    }

    /// Display name, canonical ID, the owner's or carrier's label, and
    /// "Shared" — never a fuzzy match.
    static func matches(_ item: PackingListItem, search: String, labels: [UUID: String]) -> Bool {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        if item.displayName.localizedCaseInsensitiveContains(query) { return true }
        if item.canonicalItemID?.localizedCaseInsensitiveContains(query) == true { return true }
        if item.ownershipType == .shared, TripParty.sharedLabel.localizedCaseInsensitiveContains(query) { return true }
        if let owner = item.travelerID, labels[owner]?.localizedCaseInsensitiveContains(query) == true { return true }
        if let carrier = item.assignedTravelerID, item.ownershipType == .shared,
           labels[carrier]?.localizedCaseInsensitiveContains(query) == true { return true }
        return false
    }

    /// The records the People scope and search allow, before status and
    /// Hide packed — what the Status chips count.
    static func scoped(items: [PackingListItem], party: TripParty, query: PackingListQuery) -> [PackingListItem] {
        let labels = labelTable(for: party)
        return items.filter { matches($0, scope: query.scope, party: party) && matches($0, search: query.search, labels: labels) }
    }

    static func statusCounts(items: [PackingListItem], party: TripParty, query: PackingListQuery) -> [PackingStatusFilter: Int] {
        let scoped = scoped(items: items, party: party, query: query)
        var counts: [PackingStatusFilter: Int] = [:]
        for status in PackingStatusFilter.allCases {
            counts[status] = scoped.filter { matches($0, status: status) }.count
        }
        return counts
    }

    // MARK: - People

    /// The People chips: nothing for a solo list, otherwise the party's
    /// list filters with stable labels (names, else You / Adult N / Child N).
    static func scopeLabels(for party: TripParty) -> [PackingListScopeLabel] {
        guard !party.usesSimpleList else { return [] }
        return party.listFilters().map { scope in
            let title: String = switch scope {
            case .all: "All"
            case .shared: TripParty.sharedLabel
            case .traveler(let id): party.travelers.first { $0.id == id }.map(party.label(for:)) ?? "Traveler"
            }
            return PackingListScopeLabel(scope: scope, title: title)
        }
    }

    static func labelTable(for party: TripParty) -> [UUID: String] {
        Dictionary(uniqueKeysWithValues: party.travelers.map { ($0.id, party.label(for: $0)) })
    }

    // MARK: - Sections

    /// Filters the records, then groups within each category in `order`.
    /// Personal records aggregate only in the All scope of a party list,
    /// only when they share a canonical ID and a category, and only when
    /// there are at least two of them. Custom rows without a canonical ID
    /// never aggregate: a look-alike name is not an identity.
    ///
    /// A section's counts measure the whole category for the current
    /// People scope (Task 11.1): Status, search, and Hide packed change
    /// which rows are shown, not what the header means. A section with
    /// no visible rows is omitted.
    static func sections(
        items: [PackingListItem],
        party: TripParty,
        order: [PackingCategory],
        query: PackingListQuery
    ) -> [PackingListSection] {
        let labels = labelTable(for: party)
        let position = Dictionary(uniqueKeysWithValues: party.travelers.enumerated().map { ($1.id, $0) })
        let inScope = items.filter { matches($0, scope: query.scope, party: party) }
        let visible = inScope
            .filter { matches($0, search: query.search, labels: labels) }
            .filter { matches($0, status: query.status) && !(query.hidePacked && $0.isPacked) }
        let aggregates = query.scope == .all && !party.usesSimpleList

        var byCategory: [PackingCategory: [PackingListItem]] = [:]
        for item in visible { byCategory[item.category, default: []].append(item) }
        var scopeByCategory: [PackingCategory: (completed: Int, total: Int)] = [:]
        for item in inScope {
            let current = scopeByCategory[item.category] ?? (0, 0)
            scopeByCategory[item.category] = (current.completed + (item.isPacked ? 1 : 0), current.total + 1)
        }

        return order.compactMap { category in
            guard let categoryItems = byCategory[category], !categoryItems.isEmpty else { return nil }
            var rows: [PackingListPresentationRow] = []
            var groupable: [String: [PackingListItem]] = [:]
            for item in categoryItems {
                if aggregates, item.ownershipType == .personal, let canonical = item.canonicalItemID {
                    groupable[canonical, default: []].append(item)
                } else {
                    rows.append(row(for: item, labels: labels))
                }
            }
            for (canonical, members) in groupable {
                if members.count == 1, let only = members.first {
                    rows.append(row(for: only, labels: labels))
                } else {
                    let ordered = members.sorted { position[$0.travelerID ?? UUID()] ?? .max < position[$1.travelerID ?? UUID()] ?? .max }
                    rows.append(.personalGroup(PersonalItemGroup(
                        canonicalItemID: canonical,
                        category: category,
                        displayName: ordered[0].displayName,
                        members: ordered.map { member in
                            PersonalItemGroupMember(
                                id: member.id,
                                travelerID: member.travelerID ?? UUID(),
                                travelerLabel: member.travelerID.flatMap { labels[$0] } ?? "Traveler",
                                quantity: member.quantity,
                                packedQuantity: member.packedQuantity,
                                importance: member.importance,
                                isComplete: member.isPacked
                            )
                        }
                    )))
                }
            }
            rows.sort { lhs, rhs in
                let byName = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                if byName != .orderedSame { return byName == .orderedAscending }
                return sortKey(lhs, position: position) < sortKey(rhs, position: position)
            }
            let progress = scopeByCategory[category] ?? (0, 0)
            return PackingListSection(
                category: category,
                rows: rows,
                completedCount: progress.completed,
                totalCount: progress.total
            )
        }
    }

    private static func row(for item: PackingListItem, labels: [UUID: String]) -> PackingListPresentationRow {
        let entry = PackingListEntry(
            item: item,
            travelerLabel: item.ownershipType == .personal ? item.travelerID.flatMap { labels[$0] } : nil,
            carrierLabel: item.ownershipType == .shared ? item.assignedTravelerID.flatMap { labels[$0] } : nil
        )
        return item.ownershipType == .shared ? .shared(entry) : .individual(entry)
    }

    /// Tie-break for equal names: groups first, then personal rows in party
    /// order, then shared, then the record ID so the order is total.
    private static func sortKey(_ row: PackingListPresentationRow, position: [UUID: Int]) -> String {
        switch row {
        case .personalGroup(let group): "0:\(group.id)"
        case .individual(let entry): "1:\(String(format: "%04d", position[entry.item.travelerID ?? UUID()] ?? 9999)):\(entry.id.uuidString)"
        case .shared(let entry): "2:\(entry.id.uuidString)"
        }
    }
}
