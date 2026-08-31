import SwiftData
import SwiftUI

enum PackingFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case left = "Left to pack"
    case packed = "Packed"
    case important = "Important"

    var id: String { rawValue }
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

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var modelContext
    @Query private var preferenceRecords: [PackingPreferenceRecord]

    @State private var filter: PackingFilter = .all
    @State private var partyFilter: PartyListFilter = .all
    @State private var search = ""
    @State private var adding = false
    @State private var hidePacked = false
    @State private var selectedItem: PackingItemRecord?
    @State private var newItemName = ""
    @State private var newItemQuantity = 1
    @State private var newItemCategory: PackingCategory = .miscellaneous
    @State private var newItemOwner: PartyListFilter = .all
    @State private var newItemImportant = false

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
            prompt: "Search items"
        )
        .overlay(alignment: .bottomTrailing) { addButton }
        // A push, not a sheet — the detail is a full screen in the trip's
        // navigation, per spec.
        .navigationDestination(item: $selectedItem) { item in
            ItemDetailView(
                item: item,
                travelers: trip.party.travelers,
                showsAssignment: !trip.party.usesSimpleList && item.ownershipType == .shared,
                onNotNeeded: !item.isUserAdded && item.canonicalItemID != nil
                    ? { notNeeded(item) } : nil,
                onDelete: item.isUserAdded ? { delete(item) } : nil
            )
        }
        .sheet(isPresented: $adding) { addSheet }
    }

    // MARK: - List

    private var list: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(visibleCategories, id: \.self) { category in
                    let items = filteredItems.filter { $0.category == category }
                    if !items.isEmpty {
                        Section {
                            ForEach(items, id: \.id) { item in
                                row(item)
                            }
                        } header: {
                            HStack(spacing: PackWiseSpacing.snug) {
                                if items.allSatisfy(\.isPacked) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(PackWiseColor.success)
                                        .accessibilityLabel("All packed")
                                }
                                PackWiseSectionHeader(
                                    title: category.title,
                                    style: .micro,
                                    trailing: "\(items.filter(\.isPacked).count) / \(items.count)"
                                )
                            }
                            .padding(.horizontal, PackWiseSpacing.comfortable)
                            .padding(.top, PackWiseSpacing.snug)
                            .padding(.bottom, PackWiseSpacing.tight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // A plain list pins its section headers. The header
                            // was drawn without a fill, so rows scrolled
                            // straight through it and the two rendered on top
                            // of each other — "TOILETRIES" and the row above it
                            // sharing the same pixels. The insets move to the
                            // padding above so the fill spans the full width.
                            .background(PackWiseColor.screen)
                            .listRowInsets(EdgeInsets())
                        }
                        .id(category)
                    }
                }

                if filteredItems.isEmpty {
                    emptyState
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            // So the last rows can scroll clear of the floating add button
            // rather than sitting underneath it.
            .contentMargins(.bottom, 76, for: .scrollContent)
            .onAppear {
                guard let focusedCategory else { return }
                proxy.scrollTo(focusedCategory, anchor: .top)
            }
        }
    }

    private func row(_ item: PackingItemRecord) -> some View {
        PackingRow(
            item: item,
            travelerName: travelerName(for: item),
            showsOwner: !trip.party.usesSimpleList
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

    @ViewBuilder
    private var emptyState: some View {
        if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            ContentUnavailableView(
                filter == .packed ? "Nothing packed yet" : "Nothing here",
                systemImage: "suitcase",
                description: Text(
                    filter == .packed
                        ? "Items you pack will show up here."
                        : "No items match this filter."
                )
            )
        }
    }

    // MARK: - Filters

    private var filters: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            if !trip.party.usesSimpleList {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PackWiseSpacing.snug) {
                        ForEach(partyFilterOptions, id: \.id) { option in
                            SelectableChip(title: partyFilterTitle(option), selected: partyFilter == option) {
                                partyFilter = option
                            }
                        }
                    }
                    .padding(.horizontal, PackWiseSpacing.comfortable)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PackWiseSpacing.snug) {
                    ForEach(PackingFilter.allCases) { option in
                        SelectableChip(title: filterTitle(option), selected: filter == option) {
                            filter = option
                        }
                    }
                    SelectableChip(title: "Hide packed", selected: hidePacked) {
                        hidePacked.toggle()
                    }
                }
                .padding(.horizontal, PackWiseSpacing.comfortable)
            }
        }
        .padding(.vertical, PackWiseSpacing.snug)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PackWiseColor.screen)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    /// Counts sit on the filter itself so the split is legible before tapping.
    private func filterTitle(_ option: PackingFilter) -> String {
        let count = scopedItems.filter { matches($0, filter: option) }.count
        return option == .important ? option.rawValue : "\(option.rawValue) \(count)"
    }

    private var addButton: some View {
        Button {
            adding = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(PackWiseColor.accent, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .padding(PackWiseSpacing.loose)
        .accessibilityLabel("Add Item")
    }

    /// A full sheet with a proper primary action — not a grayed nav-bar
    /// "Add".
    private var addSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PackWiseSpacing.comfortable) {
                    PackWiseCard {
                        VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
                            TextField("Item name", text: $newItemName)
                                .font(.title3)
                            PackWiseRowDivider(inset: 0)
                            HStack {
                                Text("Category")
                                Spacer()
                                Picker("Category", selection: $newItemCategory) {
                                    ForEach(PackingCategory.allCases) { category in
                                        Text(category.title).tag(category)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
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
                                            Text(traveler.displayName).tag(PartyListFilter.traveler(traveler.id))
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
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Data

    private var visibleCategories: [PackingCategory] {
        PackingCategory.displayOrder(international: trip.contextChips.contains(.travelingInternationally) || isInternational, outdoor: trip.tripType == .outdoor)
    }

    private var isInternational: Bool {
        let home = preferenceRecords.first?.homeCountryCode ?? Locale.current.region?.identifier ?? "US"
        return trip.destinationCountryCode.uppercased() != home.uppercased()
    }

    private var partyFilterOptions: [PartyListFilter] {
        trip.party.listFilters()
    }

    private func partyFilterTitle(_ filter: PartyListFilter) -> String {
        switch filter {
        case .all: "All"
        case .shared: "Shared"
        case .kids: "Kids"
        case .traveler(let id):
            trip.party.travelers.first { $0.id == id }?.displayName ?? "Traveler"
        }
    }

    private func travelerName(for item: PackingItemRecord) -> String? {
        if item.ownershipType == .shared { return "Shared" }
        return trip.party.travelers.first { $0.id == item.travelerID }?.displayName
    }

    private func matches(_ item: PackingItemRecord, filter: PackingFilter) -> Bool {
        switch filter {
        case .all: true
        case .left: !item.isPacked
        case .packed: item.isPacked
        case .important: item.importance == .critical || item.importance == .important
        }
    }

    /// Everything the party filter and search allow, before the packed/left
    /// split — so the filter chips can count what each option would show.
    private var scopedItems: [PackingItemRecord] {
        trip.items
            .filter { item in
                switch partyFilter {
                case .all: true
                case .shared: item.ownershipType == .shared
                case .kids:
                    item.ownershipType == .personal && trip.party.children.contains { $0.id == item.travelerID }
                case .traveler(let id):
                    item.ownershipType == .personal && item.travelerID == id
                }
            }
            .filter { item in
                search.isEmpty
                    || item.displayName.localizedCaseInsensitiveContains(search)
                    || (item.canonicalItemID?.localizedCaseInsensitiveContains(search) ?? false)
            }
    }

    private var filteredItems: [PackingItemRecord] {
        scopedItems
            .filter { matches($0, filter: filter) }
            .filter { !(hidePacked && $0.isPacked) }
            .sorted { $0.displayName < $1.displayName }
    }

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

/// One checklist row, in the shape Reminders uses: a tap target, the item, and
/// only the secondary text that earns its place.
struct PackingRow: View {
    @Bindable var item: PackingItemRecord
    var travelerName: String? = nil
    var showsOwner: Bool = false

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
                    Text(item.displayName)
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
                        Text(item.reason)
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
                HStack(spacing: PackWiseSpacing.regular) {
                    PackWiseIconBadge(
                        symbol: item.category.style.symbol,
                        tint: item.category.style.tint
                    )
                    VStack(alignment: .leading, spacing: PackWiseSpacing.tight) {
                        Text(item.displayName)
                            .font(.title3.weight(.semibold))
                        HStack(spacing: PackWiseSpacing.snug) {
                            Text(item.category.title)
                                .font(.subheadline)
                                .foregroundStyle(PackWiseColor.textSecondary)
                            if !item.isUserAdded {
                                // PackWise put it here; the sheet below says
                                // why.
                                PackWiseStatusBadge(title: "Recommended")
                            }
                        }
                    }
                }
                PackWiseRowDivider(inset: 0)
                Stepper("Quantity  \(item.quantity)", value: $item.quantity, in: 1...30)
                    .onChange(of: item.quantity) {
                        item.isUserModified = true
                        item.updatedAt = .now
                    }
                PackWiseRowDivider(inset: 0)
                // Outside a Form a Picker renders its selection only, so the
                // label is supplied explicitly.
                HStack {
                    Text("Category")
                    Spacer()
                    Picker("Category", selection: $item.categoryRaw) {
                        ForEach(PackingCategory.allCases) { category in
                            Text(category.title).tag(category.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private var reasons: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            PackWiseSectionHeader(title: "Why it's on your list")
            PackWiseCard {
                VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
                    Text(item.reason.isEmpty ? "Added for this trip." : item.reason)
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
