import SwiftData
import SwiftUI

/// Presentation-only wording for recommendations that share one engine
/// signal but have different practical consequences. Structured provenance
/// remains unchanged.
enum PackingReasonPresentation {
    static func inclusionReason(
        canonicalItemID: String?,
        reasonCode: String,
        tripType: TripType?,
        original: String
    ) -> String {
        if reasonCode == "activity.sightseeing" {
            switch canonicalItemID {
            case "health.blister_pads":
                return "Helpful for long walking and sightseeing days."
            case "activities.daypack":
                return "Useful for carrying daily essentials while sightseeing."
            case "electronics.power_bank":
                return "Sightseeing can keep you away from outlets for long periods."
            default:
                break
            }
        }
        if reasonCode == "trip_type.generic", let tripType {
            return "Useful for your \(tripType.title.lowercased())."
        }
        return original
    }
}

/// Phase 8, Task 6: presentation over `RecommendationTrace.Authority` —
/// reads persisted trace only, never calls `PackingEngine`,
/// `CoverageResolver`, `ConstraintResolver`, or `WeatherSignalExtractor`.
enum PackingTracePresentation {
    /// One short, honest line distinguishing a user's own decision from the
    /// engine's — never invents provenance for a user-authority row.
    static func authorityLine(_ authority: RecommendationTrace.Authority) -> String? {
        if authority.isCustomItem { return "Added by you." }
        if authority.isUserModified { return "You changed this." }
        if authority.isUserAdded { return "Added by you." }
        return nil
    }
}

#if DEBUG
enum PackingListDebugPresentation {
    case itemDetailMedium
    case itemDetailLarge
    case addItem
    case addItemCategory
    /// Task 11 capture states: a preset People/Status/search state, an
    /// opened group, or a scroll target.
    case list(PackingListDebugState)
}

struct PackingListDebugState {
    enum Scope { case all, traveler(Int), shared }
    var scope: Scope = .all
    var status: PackingStatusFilter? = nil
    var hidePacked = false
    var search = ""
    /// Canonical ID of a personal group to open.
    var openGroup: String? = nil
    var scrollTo: PackingCategory? = nil
}
#endif

private enum AddItemRoute: Hashable {
    case category
}

/// The checklist.
///
/// Reminders-style rows under flat section headers, not a stack of cards:
/// `.insetGrouped` draws every category `Section` as its own rounded
/// container, which is what made the old screen so heavy. Filters stay pinned
/// above the list rather than scrolling away with the first category.
struct PackingListView: View {
    @Bindable var trip: TripRecord
    /// Category to bring into view when arriving from a summary row.
    var focusedCategory: PackingCategory?
#if DEBUG
    var debugPresentation: PackingListDebugPresentation?
#endif

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var partyFilter: PartyListFilter = .all
    @State private var status: PackingStatusFilter?
    @State private var search = ""
    @State private var adding = false
    @State private var hidePacked = false
    @State private var selectedItem: PackingItemRecord?
    @State private var selectedGroup: PersonalItemGroup?
    @State private var newItemName = ""
    @State private var newItemQuantity = 1
    @State private var newItemCategory: PackingCategory = .clothing
    @State private var newItemOwner: PartyListFilter = .all
    @State private var newItemImportant = false
    @State private var addPath: [AddItemRoute] = []
    @State private var itemDetailDetent: PresentationDetent = .medium
#if DEBUG
    @State private var appliedDebugPresentation = false
    @State private var debugScrollTarget: PackingCategory?
#endif

    /// The floating add control's footprint plus breathing room, so the last
    /// row can always scroll clear of it (Task 11).
    private static let addButtonClearance: CGFloat = PackWiseSize.floatingControl + PackWiseSpacing.loose * 2 + PackWiseSpacing.regular

    var body: some View {
        VStack(spacing: 0) {
            filters
            PackWiseRowDivider(inset: 0)
            list
        }
        .navigationTitle("Packing List")
        .navigationBarTitleDisplayMode(.inline)
        // Pushed from Trips → trip → list. The root tabs belong to the root,
        // and here they only cost vertical space and compete with the add
        // button floating in the same corner.
        .toolbar(.hidden, for: .tabBar)
        .searchable(
            text: $search,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search items or people"
        )
        .overlay(alignment: .bottomTrailing) { addButton }
        .sheet(item: $selectedItem) { item in
            NavigationStack {
                itemDetail(item)
            }
            .presentationDetents([.medium, .large], selection: $itemDetailDetent)
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedGroup) { group in
            PackingGroupDetailView(
                group: group,
                trip: trip,
                onNotNeeded: { notNeeded($0) },
                onDelete: { delete($0) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $adding) { addSheet }
#if DEBUG
        .onAppear { applyDebugPresentationIfNeeded() }
#endif
    }

    // MARK: - List

    private var list: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.rows) { row in
                            presentationRow(row)
                        }
                    } header: {
                        sectionHeader(section)
                    }
                    .id(section.category)
                }

                if sections.isEmpty {
                    emptyState
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            // So the last rows can scroll clear of the floating add button
            // rather than sitting underneath it.
            .contentMargins(.bottom, Self.addButtonClearance, for: .scrollContent)
            .onAppear {
                guard let target = scrollTarget else { return }
                proxy.scrollTo(target, anchor: .top)
            }
#if DEBUG
            // The capture state is applied by the outer view's onAppear,
            // which runs after this list's own, so scroll once it lands.
            .onChange(of: debugScrollTarget) { _, target in
                guard let target else { return }
                proxy.scrollTo(target, anchor: .top)
            }
#endif
        }
    }

    private var scrollTarget: PackingCategory? {
#if DEBUG
        focusedCategory ?? debugScrollTarget
#else
        focusedCategory
#endif
    }

    private func sectionHeader(_ section: PackingListSection) -> some View {
        HStack(spacing: PackWiseSpacing.snug) {
            if section.isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(PackWiseColor.success)
                    .accessibilityLabel("All packed")
            }
            PackWiseSectionHeader(
                title: section.category.title,
                style: .micro,
                trailing: "\(section.completedCount) / \(section.totalCount)"
            )
        }
        .padding(.horizontal, PackWiseSpacing.comfortable)
        .padding(.top, PackWiseSpacing.snug)
        .padding(.bottom, PackWiseSpacing.tight)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A plain list pins its section headers. The header was drawn
        // without a fill, so rows scrolled straight through it and the two
        // rendered on top of each other. The insets move to the padding
        // above so the fill spans the full width.
        .background(PackWiseColor.screen)
        .listRowInsets(EdgeInsets())
    }

    @ViewBuilder
    private func presentationRow(_ row: PackingListPresentationRow) -> some View {
        switch row {
        case .individual(let entry):
            if let record = recordsByID[entry.id] {
                recordRow(record, caption: showsOwners ? entry.travelerLabel : nil)
            }
        case .shared(let entry):
            if let record = recordsByID[entry.id] {
                recordRow(record, caption: entry.secondaryText)
            }
        case .personalGroup(let group):
            PackingGroupRow(group: group)
                .contentShape(Rectangle())
                .onTapGesture { selectedGroup = group }
        }
    }

    /// Owner captions belong to the All scope of a party list. A traveler's
    /// own scope is their checklist, so the name would only repeat.
    private var showsOwners: Bool {
        !trip.party.usesSimpleList && partyFilter == .all
    }

    private func recordRow(_ item: PackingItemRecord, caption: String?) -> some View {
        PackingRow(
            item: item,
            travelerName: caption,
            showsOwner: caption != nil
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedItem = item }
        .swipeActions(edge: .leading) {
            Button("Pack") { pack(item) }
                .tint(PackWiseColor.accent)
        }
        // Not Needed and Delete are different operations: declining a
        // recommendation records an override the engine must respect;
        // deleting a custom item records nothing. Each row offers only the
        // one that matches its origin — a "Delete" on a recommendation would
        // silently lose the override signal.
        .swipeActions(edge: .trailing) {
            if item.isUserAdded {
                Button("Delete", role: .destructive) { delete(item) }
            } else if item.canonicalItemID != nil {
                Button("Not Needed") { notNeeded(item) }
                    .tint(PackWiseColor.important)
            }
        }
        .contextMenu {
            Button("Why this item?") { selectedItem = item }
            Button("Change quantity") { selectedItem = item }
            if item.isUserAdded {
                Button("Delete", role: .destructive) { delete(item) }
            } else if item.canonicalItemID != nil {
                Button("Mark not needed") { notNeeded(item) }
            }
        }
    }

    private func itemDetail(_ item: PackingItemRecord) -> some View {
        ItemDetailView(
            item: item,
            travelers: trip.party.travelers,
            showsAssignment: !trip.party.usesSimpleList && item.ownershipType == .shared,
            onNotNeeded: !item.isUserAdded && item.canonicalItemID != nil
                ? { notNeeded(item) } : nil,
            onDelete: item.isUserAdded ? { delete(item) } : nil
        )
    }

    @ViewBuilder
    private var emptyState: some View {
        if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            ContentUnavailableView(
                status == .packed ? "Nothing packed yet" : "Nothing here",
                systemImage: "suitcase",
                description: Text(
                    status == .packed
                        ? "Items you pack will show up here."
                        : "No items match this filter."
                )
            )
        }
    }

    // MARK: - Filters

    /// Two dimensions, each named: who the rows belong to, and where they
    /// stand. A solo list has one person and shows no People row at all.
    private var filters: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            let people = PackingListAggregator.scopeLabels(for: trip.party)
            if !people.isEmpty {
                scopeRow("People") {
                    ForEach(people, id: \.scope) { option in
                        PackWiseChip(
                            title: option.title,
                            symbol: partyFilter == option.scope ? "checkmark" : nil,
                            isSelected: partyFilter == option.scope
                        ) {
                            partyFilter = option.scope
                        }
                    }
                }
            }
            scopeRow("Status") {
                ForEach(PackingStatusFilter.allCases) { option in
                    PackWiseChip(
                        title: statusTitle(option),
                        symbol: status == option ? "checkmark" : nil,
                        isSelected: status == option
                    ) {
                        status = status == option ? nil : option
                    }
                }
                PackWiseChip(
                    title: "Hide packed",
                    symbol: hidePacked ? "checkmark" : "eye.slash",
                    isSelected: hidePacked
                ) {
                    hidePacked.toggle()
                }
            }
        }
        .padding(.vertical, PackWiseSpacing.snug)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PackWiseColor.screen)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    /// A named row of chips. At accessibility sizes the name sits above the
    /// chips instead of beside them, so it never wraps mid-word.
    private func scopeRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        let label = Text(title)
            .font(.caption.weight(.semibold))
            .kerning(0.5)
            .textCase(.uppercase)
            .foregroundStyle(PackWiseColor.textSecondary)
            .accessibilityHidden(true)
        let chips = ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PackWiseSpacing.snug) {
                content()
            }
            .padding(.trailing, PackWiseSpacing.comfortable)
        }
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: PackWiseSpacing.tight) {
                    label.padding(.leading, PackWiseSpacing.comfortable)
                    chips.padding(.leading, PackWiseSpacing.comfortable)
                }
            } else {
                HStack(alignment: .center, spacing: PackWiseSpacing.snug) {
                    label
                        .frame(width: 58, alignment: .leading)
                        .padding(.leading, PackWiseSpacing.comfortable)
                    chips
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    /// Counts sit on the chip so the split is legible before tapping; they
    /// count underlying records in the current People scope and search.
    private func statusTitle(_ option: PackingStatusFilter) -> String {
        guard option != .important else { return option.rawValue }
        let count = statusCounts[option] ?? 0
        return "\(option.rawValue) \(count)"
    }

    private var addButton: some View {
        Button {
            adding = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: PackWiseSize.floatingControl, height: PackWiseSize.floatingControl)
                .background(PackWiseColor.accent, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .padding(PackWiseSpacing.loose)
        .accessibilityLabel("Add Item")
    }

    /// A full sheet with a proper primary action — not a grayed nav-bar
    /// "Add".
    private var addSheet: some View {
        NavigationStack(path: $addPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: PackWiseSpacing.comfortable) {
                    PackWiseCard {
                        VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
                            TextField("Item name", text: $newItemName)
                                .font(.title3)
                            PackWiseRowDivider(inset: 0)
                            NavigationLink(value: AddItemRoute.category) {
                                HStack {
                                    Text("Category")
                                        .foregroundStyle(PackWiseColor.textPrimary)
                                    Spacer()
                                    Text(newItemCategory.title)
                                        .foregroundStyle(PackWiseColor.textSecondary)
                                }
                            }
                            PackWiseRowDivider(inset: 0)
                            Stepper("Quantity  \(newItemQuantity)", value: $newItemQuantity, in: 1...20)
                            PackWiseRowDivider(inset: 0)
                            VStack(alignment: .leading, spacing: PackWiseSpacing.tight) {
                                Toggle(isOn: $newItemImportant) {
                                    HStack(spacing: PackWiseSpacing.snug) {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .foregroundStyle(PackWiseColor.accent)
                                        Text("Important")
                                    }
                                }
                                Text("Important items are flagged and stay visible in the Important filter.")
                                    .font(.footnote)
                                    .foregroundStyle(PackWiseColor.textSecondary)
                            }
                            if !trip.party.usesSimpleList {
                                PackWiseRowDivider(inset: 0)
                                HStack {
                                    Text("For")
                                    Spacer()
                                    Picker("For", selection: $newItemOwner) {
                                        Text("Shared").tag(PartyListFilter.shared)
                                        ForEach(trip.party.travelers) { traveler in
                                            Text(trip.party.label(for: traveler)).tag(PartyListFilter.traveler(traveler.id))
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                }
                            }
                        }
                    }

                    Button("Save item") { addCustomItem() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(PackWiseSpacing.comfortable)
            }
            .background(PackWiseColor.screen)
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { adding = false } }
            }
            .navigationDestination(for: AddItemRoute.self) { route in
                switch route {
                case .category: categorySelection
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var categorySelection: some View {
        List(PackingCategory.allCases) { category in
            Button {
                newItemCategory = category
            } label: {
                HStack(spacing: PackWiseSpacing.regular) {
                    PackWiseIconBadge(symbol: category.style.symbol, tint: category.style.tint)
                    Text(category.title)
                        .foregroundStyle(PackWiseColor.textPrimary)
                    Spacer()
                    if newItemCategory == category {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(PackWiseColor.accent)
                            .accessibilityLabel("Selected")
                    }
                }
                .frame(minHeight: PackWiseSize.tapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(newItemCategory == category ? .isSelected : [])
        }
        .listStyle(.plain)
        .navigationTitle("Choose Category")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Data

    private var visibleCategories: [PackingCategory] {
        PackingCategory.displayOrder(international: trip.isInternational, tripTypes: trip.tripTypes)
    }

    private var query: PackingListQuery {
        PackingListQuery(scope: partyFilter, status: status, search: search, hidePacked: hidePacked)
    }

    private var listItems: [PackingListItem] {
        trip.items.map(PackingListItem.init(record:))
    }

    /// The rows on screen: filtered underlying records, aggregated within
    /// each category. Presentation only; see `PackingListAggregator`.
    private var sections: [PackingListSection] {
        PackingListAggregator.sections(items: listItems, party: trip.party, order: visibleCategories, query: query)
    }

    private var statusCounts: [PackingStatusFilter: Int] {
        PackingListAggregator.statusCounts(items: listItems, party: trip.party, query: query)
    }

    private var recordsByID: [UUID: PackingItemRecord] {
        Dictionary(trip.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

#if DEBUG
    private func applyDebugPresentationIfNeeded() {
        guard !appliedDebugPresentation, let debugPresentation else { return }
        appliedDebugPresentation = true
        switch debugPresentation {
        case .itemDetailMedium:
            itemDetailDetent = .medium
            selectedItem = trip.items.first { $0.canonicalItemID == "clothing.tshirts" } ?? trip.items.first
        case .itemDetailLarge:
            itemDetailDetent = .large
            selectedItem = trip.items.first { $0.canonicalItemID == "clothing.tshirts" } ?? trip.items.first
        case .addItem:
            adding = true
        case .addItemCategory:
            newItemCategory = .clothing
            addPath = [.category]
            adding = true
        case .list(let state):
            switch state.scope {
            case .all: partyFilter = .all
            case .shared: partyFilter = .shared
            case .traveler(let index):
                let travelers = trip.party.travelers
                if travelers.indices.contains(index) { partyFilter = .traveler(travelers[index].id) }
            }
            status = state.status
            hidePacked = state.hidePacked
            search = state.search
            debugScrollTarget = state.scrollTo
            if let canonical = state.openGroup {
                selectedGroup = sections.flatMap(\.rows).compactMap { row -> PersonalItemGroup? in
                    if case .personalGroup(let group) = row, group.canonicalItemID == canonical { group } else { nil }
                }.first
            }
        }
    }
#endif

    // MARK: - Actions

    private func pack(_ item: PackingItemRecord) {
        item.packedQuantity = item.quantity
        item.updatedAt = .now
        trip.updatedAt = .now
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        try? modelContext.save()
    }

    private func notNeeded(_ item: PackingItemRecord) {
        TripRepository(context: modelContext).markNotNeeded(item, on: trip)
        try? modelContext.save()
    }

    private func delete(_ item: PackingItemRecord) {
        TripRepository(context: modelContext).deleteItem(item, on: trip)
        try? modelContext.save()
    }

    private func addCustomItem() {
        let name = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        let match = dependencies.catalog.search(name).first
        let ownership: PackingOwnership
        let travelerID: UUID?
        if trip.party.usesSimpleList {
            ownership = .personal
            travelerID = trip.party.primary.id
        } else if case .traveler(let id) = newItemOwner {
            ownership = .personal
            travelerID = id
        } else {
            ownership = .shared
            travelerID = nil
        }
        let draft = PackingItemDraft(
            canonicalItemID: match?.id,
            displayName: match?.displayName ?? name,
            category: match?.category ?? newItemCategory,
            quantity: newItemQuantity,
            importance: newItemImportant ? .important : (match?.importance ?? .normal),
            sourceSignals: [.userPreference],
            reason: "Added by you",
            isUserAdded: true,
            ownershipType: ownership,
            travelerID: travelerID
        )
        TripRepository(context: modelContext).addItem(draft, to: trip)
        try? modelContext.save()
        newItemName = ""
        newItemQuantity = 1
        newItemImportant = false
        adding = false
    }
}


/// One personal item across several travelers, presented once (Task 11).
/// The leading glyph reports the group's state and is not a control: a
/// group has no single record to pack. Tapping opens the real records.
struct PackingGroupRow: View {
    let group: PersonalItemGroup

    var body: some View {
        HStack(alignment: .top, spacing: PackWiseSpacing.regular) {
            Image(systemName: stateSymbol)
                .font(.title3)
                .foregroundStyle(stateTint)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                HStack(alignment: .firstTextBaseline, spacing: PackWiseSpacing.snug) {
                    Text(group.displayName)
                        .strikethrough(group.isComplete)
                        .foregroundStyle(group.isComplete ? PackWiseColor.textSecondary : PackWiseColor.textPrimary)
                    Spacer(minLength: PackWiseSpacing.tight)
                    Text(group.progressText)
                        .font(.subheadline)
                        .foregroundStyle(PackWiseColor.textSecondary)
                        .monospacedDigit()
                    if let importanceTint {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(importanceTint)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: PackWiseSpacing.tight) {
                    Text(group.travelerSummary)
                        .font(.footnote)
                        .foregroundStyle(PackWiseColor.textSecondary)
                    Spacer(minLength: PackWiseSpacing.tight)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(PackWiseColor.textTertiary)
                }
            }
        }
        .padding(.vertical, PackWiseSpacing.snug)
        .frame(minHeight: PackWiseSize.tapTarget)
        .listRowInsets(EdgeInsets(
            top: 0,
            leading: PackWiseSpacing.comfortable,
            bottom: 0,
            trailing: PackWiseSpacing.comfortable
        ))
        .alignmentGuide(.listRowSeparatorLeading) { _ in
            26 + PackWiseSpacing.regular
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(group.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows each traveler's item")
    }

    private var stateSymbol: String {
        if group.isComplete { return "checkmark.circle.fill" }
        return group.completedTravelerCount > 0 ? "circle.lefthalf.filled" : "circle"
    }

    private var stateTint: Color {
        group.completedTravelerCount > 0 ? PackWiseColor.success : PackWiseColor.textTertiary
    }

    private var importanceTint: Color? {
        switch group.importance {
        case .critical: PackWiseColor.important
        case .important: PackWiseColor.accent
        default: nil
        }
    }
}

/// The real records behind a group row, each with its own pack control and
/// its own detail. Nothing here edits the group: there is no such record.
struct PackingGroupDetailView: View {
    let group: PersonalItemGroup
    @Bindable var trip: TripRecord
    var onNotNeeded: (PackingItemRecord) -> Void
    var onDelete: (PackingItemRecord) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(members, id: \.id) { record in
                        NavigationLink(value: record.id) {
                            PackingRow(item: record, title: label(for: record) ?? record.displayName)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Pack") { pack(record) }
                                .tint(PackWiseColor.accent)
                        }
                        .swipeActions(edge: .trailing) {
                            if record.isUserAdded {
                                Button("Delete", role: .destructive) { onDelete(record) }
                            } else if record.canonicalItemID != nil {
                                Button("Not Needed") { onNotNeeded(record) }
                                    .tint(PackWiseColor.important)
                            }
                        }
                    }
                } header: {
                    summary
                }
            }
            .listStyle(.plain)
            .background(PackWiseColor.screen)
            .navigationTitle(group.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .navigationDestination(for: UUID.self) { id in
                if let record = members.first(where: { $0.id == id }) {
                    ItemDetailView(
                        item: record,
                        travelers: trip.party.travelers,
                        onNotNeeded: !record.isUserAdded && record.canonicalItemID != nil ? { onNotNeeded(record) } : nil,
                        onDelete: record.isUserAdded ? { onDelete(record) } : nil
                    )
                }
            }
        }
    }

    /// Live records, in the group's traveler order. A record that was
    /// marked Not Needed drops out on its own.
    private var members: [PackingItemRecord] {
        group.recordIDs.compactMap { id in trip.items.first { $0.id == id } }
    }

    private var summary: some View {
        let packed = members.filter(\.isPacked).count
        return HStack(spacing: PackWiseSpacing.snug) {
            PackWiseIconBadge(symbol: group.category.style.symbol, tint: group.category.style.tint)
            VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                Text("\(members.count) travelers · \(packed) of \(members.count) packed")
                    .font(.subheadline)
                    .foregroundStyle(PackWiseColor.textSecondary)
                Text(group.category.title)
                    .font(.caption)
                    .foregroundStyle(PackWiseColor.textTertiary)
            }
        }
        .textCase(nil)
        .padding(.horizontal, PackWiseSpacing.comfortable)
        .padding(.vertical, PackWiseSpacing.snug)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PackWiseColor.screen)
        .listRowInsets(EdgeInsets())
    }

    private func label(for record: PackingItemRecord) -> String? {
        trip.party.travelers.first { $0.id == record.travelerID }.map(trip.party.label(for:))
    }

    private func pack(_ record: PackingItemRecord) {
        record.packedQuantity = record.quantity
        record.updatedAt = .now
        trip.updatedAt = .now
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

/// One checklist row, in the shape Reminders uses: a tap target, the item, and
/// only the secondary text that earns its place.
struct PackingRow: View {
    @Bindable var item: PackingItemRecord
    var travelerName: String? = nil
    var showsOwner: Bool = false
    /// Replaces the item name as the row title — inside a group sheet every
    /// row is the same item, so the traveler is the title (Task 11).
    var title: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: PackWiseSpacing.regular) {
            Button(action: toggle) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isPacked ? "Packed \(item.displayName)" : "Mark \(item.displayName) packed")

            VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                HStack(alignment: .firstTextBaseline, spacing: PackWiseSpacing.snug) {
                    Text(title ?? item.displayName)
                        .strikethrough(item.isPacked)
                        .foregroundStyle(item.isPacked ? PackWiseColor.textSecondary : PackWiseColor.textPrimary)
                    Spacer(minLength: PackWiseSpacing.tight)
                    if showsOwner, let travelerName {
                        Text(travelerName)
                            .font(.caption)
                            .foregroundStyle(PackWiseColor.textSecondary)
                    }
                    if item.quantity > 1 {
                        // A styled badge, not plain gray text.
                        Text("×\(item.quantity)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PackWiseColor.textSecondary)
                            .monospacedDigit()
                            .padding(.horizontal, PackWiseSpacing.snug)
                            .padding(.vertical, PackWiseSpacing.tight)
                            .background(PackWiseColor.surfaceAlt, in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(PackWiseColor.border, lineWidth: 1)
                            }
                    }
                    if let importanceTint {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(importanceTint)
                            .accessibilityLabel(
                                item.importance == .critical ? "Critical" : "Important"
                            )
                    }
                }
                if showsReason {
                    // The chevron makes the tap-through to detail
                    // discoverable on rows that have more to say.
                    HStack(spacing: PackWiseSpacing.tight) {
                        Text(presentedReason)
                            .font(.footnote)
                            .foregroundStyle(PackWiseColor.textSecondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(PackWiseColor.textTertiary)
                    }
                }
            }
        }
        // The row owns its own height rather than inheriting a 44pt glyph
        // frame plus padding plus the list's default insets, which stacked up
        // to roughly double the board's row.
        .padding(.vertical, PackWiseSpacing.snug)
        .frame(minHeight: PackWiseSize.tapTarget)
        .listRowInsets(EdgeInsets(
            top: 0,
            leading: PackWiseSpacing.comfortable,
            bottom: 0,
            trailing: PackWiseSpacing.comfortable
        ))
        // Separator starts at the title, Reminders-style, not under the circle.
        .alignmentGuide(.listRowSeparatorLeading) { _ in
            26 + PackWiseSpacing.regular
        }
        .accessibilityElement(children: .combine)
    }

    private func toggle() {
        item.packedQuantity = item.isPacked ? 0 : item.quantity
        item.updatedAt = .now
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// The leading control is always the checkbox — every row can be packed.
    /// Importance never occupies this slot; it renders as a trailing glyph.
    private var symbol: String {
        item.isPacked ? "checkmark.circle.fill" : "circle"
    }

    private var tint: Color {
        item.isPacked ? PackWiseColor.success : PackWiseColor.textTertiary
    }

    /// Critical gets the warning hue, important the accent, everything else
    /// nothing — per spec, an `exclamationmark.circle.fill` at the trailing
    /// edge, never a star and never in the checkbox slot.
    private var importanceTint: Color? {
        switch item.importance {
        case .critical: PackWiseColor.important
        case .important: PackWiseColor.accent
        default: nil
        }
    }

    /// A reason earns a line only when it says something about *this* trip.
    ///
    /// Baseline essentials all carry copy of the form "a core item for almost
    /// every trip". Correct provenance, but repeated under fifteen rows it is
    /// noise, and the user already knows what a toothbrush is.
    private var showsReason: Bool {
        guard !item.reason.isEmpty else { return false }
        return item.sourceSignals.contains { $0 != .baseEssential }
    }

    private var presentedReason: String {
        PackingReasonPresentation.inclusionReason(
            canonicalItemID: item.canonicalItemID,
            reasonCode: item.reasonCode,
            tripType: item.trip?.tripType,
            original: item.reason
        )
    }
}

struct ItemDetailView: View {
    @Bindable var item: PackingItemRecord
    var travelers: [Traveler] = []
    var showsAssignment: Bool = false
    /// Absent for user-added items, which are deleted rather than declined.
    var onNotNeeded: (() -> Void)?
    /// Present only for user-added items; deleting records no override.
    var onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PackWiseSpacing.loose) {
                header
                reasons
                if showsAssignment {
                    assignment
                }
                actions
            }
            .padding(PackWiseSpacing.comfortable)
        }
        .background(PackWiseColor.screen)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        PackWiseCard {
            VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
                headerIdentity
                PackWiseRowDivider(inset: 0)
                Stepper("Quantity  \(item.quantity)", value: $item.quantity, in: 1...30)
                    .onChange(of: item.quantity) {
                        item.isUserModified = true
                        item.updatedAt = .now
                    }
                PackWiseRowDivider(inset: 0)
                // Outside a Form a Picker renders its selection only, so the
                // label is supplied explicitly.
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                            Text("Category")
                            categoryPicker
                        }
                    } else {
                        HStack {
                            Text("Category")
                            Spacer()
                            categoryPicker
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var headerIdentity: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                HStack(spacing: PackWiseSpacing.regular) {
                    PackWiseIconBadge(symbol: item.category.style.symbol, tint: item.category.style.tint)
                    Text(item.displayName)
                        .font(.title3.weight(.semibold))
                }
                Text(item.category.title)
                    .foregroundStyle(PackWiseColor.textSecondary)
                if !item.isUserAdded {
                    PackWiseStatusBadge(title: "Recommended")
                }
            }
        } else {
            HStack(spacing: PackWiseSpacing.regular) {
                PackWiseIconBadge(symbol: item.category.style.symbol, tint: item.category.style.tint)
                VStack(alignment: .leading, spacing: PackWiseSpacing.tight) {
                    Text(item.displayName)
                        .font(.title3.weight(.semibold))
                    HStack(spacing: PackWiseSpacing.snug) {
                        Text(item.category.title)
                            .font(.subheadline)
                            .foregroundStyle(PackWiseColor.textSecondary)
                        if !item.isUserAdded {
                            PackWiseStatusBadge(title: "Recommended")
                        }
                    }
                }
            }
        }
    }

    private var categoryPicker: some View {
        Picker("Category", selection: $item.categoryRaw) {
            ForEach(PackingCategory.allCases) { category in
                Text(category.title).tag(category.rawValue)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private var reasons: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            PackWiseSectionHeader(title: "Why it's on your list")
            PackWiseCard {
                VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
                    if let authorityLine = PackingTracePresentation.authorityLine(
                        RecommendationTrace.authority(for: item.draft)
                    ) {
                        Text(authorityLine)
                            .font(.caption)
                            .foregroundStyle(PackWiseColor.textSecondary)
                    }
                    Text(item.reason.isEmpty ? "Added for this trip." : presentedReason)
                    if !item.quantityReason.isEmpty {
                        PackWiseRowDivider(inset: 0)
                        VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                            Text("Why this quantity")
                                .font(.subheadline.weight(.semibold))
                            Text(item.quantityReason)
                                .foregroundStyle(PackWiseColor.textSecondary)
                        }
                    }
                    if !item.sourceSignals.isEmpty {
                        PackWiseRowDivider(inset: 0)
                        PackWiseFlowLayout {
                            ForEach(item.sourceSignals, id: \.self) { signal in
                                Text(signal.customerLabel)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, PackWiseSpacing.snug)
                                    .padding(.vertical, PackWiseSpacing.tight)
                                    .background(PackWiseColor.surfaceAlt, in: Capsule())
                            }
                        }
                    }
                }
            }
        }
    }

    private var presentedReason: String {
        PackingReasonPresentation.inclusionReason(
            canonicalItemID: item.canonicalItemID,
            reasonCode: item.reasonCode,
            tripType: item.trip?.tripType,
            original: item.reason
        )
    }

    private var assignment: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            PackWiseSectionHeader(title: "Who is bringing it?")
            PackWiseCard {
                VStack(spacing: 0) {
                    assignmentRow(title: "Unassigned", selected: item.assignedTravelerID == nil) {
                        item.assignedTravelerID = nil
                    }
                    ForEach(travelers) { traveler in
                        PackWiseRowDivider(inset: 0)
                        assignmentRow(
                            title: traveler.displayName,
                            selected: item.assignedTravelerID == traveler.id
                        ) {
                            item.assignedTravelerID = traveler.id
                        }
                    }
                }
            }
        }
    }

    private func assignmentRow(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(PackWiseColor.accent)
                }
            }
            .padding(.vertical, PackWiseSpacing.snug)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var actions: some View {
        VStack(spacing: PackWiseSpacing.regular) {
            Button(item.isPacked ? "Mark not packed" : "Mark packed") {
                item.packedQuantity = item.isPacked ? 0 : item.quantity
                item.updatedAt = .now
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())

            if let onNotNeeded {
                Button("Not needed on this trip") {
                    onNotNeeded()
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            if let onDelete {
                Button("Remove item", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}
