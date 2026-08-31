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

    var body: some View {
        VStack(spacing: 0) {
            filters
            Divider()
            list
        }
        .navigationTitle("Packing List")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $search,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search items"
        )
        .overlay(alignment: .bottomTrailing) { addButton }
        .sheet(item: $selectedItem) { item in
            ItemDetailSheet(
                item: item,
                travelers: trip.party.travelers,
                showsAssignment: !trip.party.usesSimpleList && item.ownershipType == .shared,
                onNotNeeded: item.canonicalItemID == nil ? nil : { notNeeded(item) }
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
                            PackWiseSectionHeader(
                                title: category.title,
                                trailing: "\(items.filter(\.isPacked).count) / \(items.count)"
                            )
                            .padding(.top, PackWiseSpacing.snug)
                            .listRowInsets(EdgeInsets(
                                top: 0,
                                leading: PackWiseSpacing.comfortable,
                                bottom: PackWiseSpacing.tight,
                                trailing: PackWiseSpacing.comfortable
                            ))
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
            .contentMargins(.bottom, 88, for: .scrollContent)
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
        .swipeActions(edge: .trailing) {
            if item.canonicalItemID != nil {
                Button("Not Needed") { notNeeded(item) }
                    .tint(.orange)
            }
            Button("Delete", role: .destructive) { delete(item) }
        }
        .contextMenu {
            Button("Why this item?") { selectedItem = item }
            Button("Change quantity") { selectedItem = item }
            if item.canonicalItemID != nil {
                Button("Mark not needed") { notNeeded(item) }
            }
            Button("Delete", role: .destructive) { delete(item) }
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
                .frame(width: 56, height: 56)
                .background(PackWiseColor.accent, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .padding(PackWiseSpacing.loose)
        .accessibilityLabel("Add Item")
    }

    private var addSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PackWiseSpacing.comfortable) {
                    PackWiseCard {
                        VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
                            TextField("Item", text: $newItemName)
                                .font(.title3)
                            Divider()
                            Stepper("Quantity  \(newItemQuantity)", value: $newItemQuantity, in: 1...20)
                            Divider()
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
                            if !trip.party.usesSimpleList {
                                Divider()
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
                }
                .padding(PackWiseSpacing.comfortable)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { adding = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addCustomItem() }
                        .disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
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
            importance: match?.importance ?? .normal,
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
                        .foregroundStyle(item.isPacked ? .secondary : .primary)
                    Spacer(minLength: PackWiseSpacing.tight)
                    if showsOwner, let travelerName {
                        Text(travelerName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if item.quantity > 1 {
                        Text("×\(item.quantity)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                if showsReason {
                    Text(item.reason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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

    /// Shape carries state as well as colour, so packed and critical remain
    /// distinguishable without relying on hue.
    private var symbol: String {
        if item.isPacked { return "checkmark.circle.fill" }
        return item.importance == .critical ? "exclamationmark.circle" : "circle"
    }

    private var tint: Color {
        if item.isPacked { return PackWiseColor.accent }
        return item.importance == .critical ? .orange : .secondary
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

struct ItemDetailSheet: View {
    @Bindable var item: PackingItemRecord
    var travelers: [Traveler] = []
    var showsAssignment: Bool = false
    /// Absent for user-added items, which are deleted rather than declined.
    var onNotNeeded: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
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
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        PackWiseCard {
            VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
                HStack(spacing: PackWiseSpacing.regular) {
                    PackWiseIconBadge(
                        symbol: item.category.style.symbol,
                        tint: item.category.style.tint
                    )
                    VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                        Text(item.displayName)
                            .font(.title3.weight(.semibold))
                        Text(item.category.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                Stepper("Quantity  \(item.quantity)", value: $item.quantity, in: 1...30)
                    .onChange(of: item.quantity) {
                        item.isUserModified = true
                        item.updatedAt = .now
                    }
                Divider()
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
                        Divider()
                        VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                            Text("Why this quantity")
                                .font(.subheadline.weight(.semibold))
                            Text(item.quantityReason)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !item.sourceSignals.isEmpty {
                        Divider()
                        PackWiseFlowLayout {
                            ForEach(item.sourceSignals, id: \.self) { signal in
                                Text(signal.customerLabel)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, PackWiseSpacing.snug)
                                    .padding(.vertical, PackWiseSpacing.tight)
                                    .background(Color(.tertiarySystemFill), in: Capsule())
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
                        Divider()
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
        }
    }
}
