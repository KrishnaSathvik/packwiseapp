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
/// Split out of Trip Detail, which is now an overview: understanding the trip
/// and doing the packing are different jobs and no longer share one long
/// scroll. Reached from the category summary or its See All control.
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
        ScrollViewReader { proxy in
            List {
                filters
                ForEach(visibleCategories, id: \.self) { category in
                    let items = filteredItems.filter { $0.category == category }
                    if !items.isEmpty {
                        Section {
                            ForEach(items, id: \.id) { item in
                                PackingRow(item: item, travelerName: travelerName(for: item), showsOwner: !trip.party.usesSimpleList)
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
                        } header: {
                            let packed = items.filter(\.isPacked).count
                            Text("\(category.title)  \(packed) / \(items.count)")
                        }
                        .id(category)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .onAppear {
                guard let focusedCategory else { return }
                proxy.scrollTo(focusedCategory, anchor: .top)
            }
        }
        .navigationTitle("Packing List")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search items")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    adding = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Item")
            }
        }
        .sheet(item: $selectedItem) { item in
            ItemDetailSheet(item: item, travelers: trip.party.travelers, showsAssignment: !trip.party.usesSimpleList && item.ownershipType == .shared)
        }
        .sheet(isPresented: $adding) {
            addSheet
        }
    }

    private var filters: some View {
        Section {
            VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                if !trip.party.usesSimpleList {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(partyFilterOptions, id: \.id) { option in
                                SelectableChip(title: partyFilterTitle(option), selected: partyFilter == option) {
                                    partyFilter = option
                                }
                            }
                        }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(PackingFilter.allCases) { option in
                            SelectableChip(title: option.rawValue, selected: filter == option) {
                                filter = option
                            }
                        }
                        SelectableChip(title: "Hide packed", selected: hidePacked) {
                            hidePacked.toggle()
                        }
                    }
                }
            }
        }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                TextField("Item", text: $newItemName)
                Stepper("Quantity  \(newItemQuantity)", value: $newItemQuantity, in: 1...20)
                Picker("Category", selection: $newItemCategory) {
                    ForEach(PackingCategory.allCases) { category in
                        Text(category.title).tag(category)
                    }
                }
                if !trip.party.usesSimpleList {
                    Picker("For", selection: $newItemOwner) {
                        Text("Shared").tag(PartyListFilter.shared)
                        ForEach(trip.party.travelers) { traveler in
                            Text(traveler.displayName).tag(PartyListFilter.traveler(traveler.id))
                        }
                    }
                }
            }
            .navigationTitle("Add Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { adding = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addCustomItem() }.disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

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

    private var filteredItems: [PackingItemRecord] {
        trip.items.filter { item in
            switch filter {
            case .all: true
            case .left: !item.isPacked
            case .packed: item.isPacked
            case .important: item.importance == .critical || item.importance == .important
            }
        }
        .filter { item in
            if hidePacked && item.isPacked { return false }
            return true
        }
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
        .sorted { $0.displayName < $1.displayName }
    }

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

struct PackingRow: View {
    @Bindable var item: PackingItemRecord
    var travelerName: String? = nil
    var showsOwner: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                if item.isPacked {
                    item.packedQuantity = 0
                } else {
                    item.packedQuantity = item.quantity
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: item.isPacked ? "checkmark.circle.fill" : (item.importance == .critical ? "exclamationmark.circle" : "circle"))
                    .font(.title3)
                    .foregroundStyle(item.isPacked ? PackWiseColor.accent : (item.importance == .critical ? .orange : .secondary))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isPacked ? "Packed \(item.displayName)" : "Mark \(item.displayName) packed")

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.displayName)
                        .strikethrough(item.isPacked)
                    if item.quantity > 1 {
                        Text("×\(item.quantity)")
                            .foregroundStyle(.secondary)
                    }
                    if showsOwner, let travelerName {
                        Text(travelerName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !item.reason.isEmpty {
                    Text(item.reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ItemDetailSheet: View {
    @Bindable var item: PackingItemRecord
    var travelers: [Traveler] = []
    var showsAssignment: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(item.displayName).font(.title2.bold())
                    Stepper("Quantity  \(item.quantity)", value: $item.quantity, in: 1...30)
                        .onChange(of: item.quantity) {
                            item.isUserModified = true
                            item.updatedAt = .now
                        }
                }
                if showsAssignment {
                    Section("Who is bringing it?") {
                        Button {
                            item.assignedTravelerID = nil
                        } label: {
                            HStack {
                                Text("Unassigned")
                                Spacer()
                                if item.assignedTravelerID == nil {
                                    Image(systemName: "checkmark").foregroundStyle(PackWiseColor.accent)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                        ForEach(travelers) { traveler in
                            Button {
                                item.assignedTravelerID = traveler.id
                            } label: {
                                HStack {
                                    Text(traveler.displayName)
                                    Spacer()
                                    if item.assignedTravelerID == traveler.id {
                                        Image(systemName: "checkmark").foregroundStyle(PackWiseColor.accent)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                Section("Why it's on your list") {
                    Text(item.reason.isEmpty ? "Added for this trip." : item.reason)
                }
                if !item.quantityReason.isEmpty {
                    Section("Why this quantity") {
                        Text(item.quantityReason)
                    }
                }
                Section("Recommended by") {
                    ForEach(item.sourceSignals, id: \.self) { signal in
                        Text(signal.customerLabel)
                    }
                }
                Picker("Category", selection: $item.categoryRaw) {
                    ForEach(PackingCategory.allCases) { category in
                        Text(category.title).tag(category.rawValue)
                    }
                }
            }
            .navigationTitle(item.displayName)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
