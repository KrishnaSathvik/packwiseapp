import SwiftData
import SwiftUI

struct TripDraft {
    var destination: Destination?
    var startDate = Calendar.current.startOfDay(for: Date.now)
    var endDate = Calendar.current.date(byAdding: .day, value: 4, to: Calendar.current.startOfDay(for: Date.now)) ?? Date.now
    var tripType: TripType = .vacation
    var activities: [String] = []
    var customActivity: String = ""
    var bagType: BagType = .notSure
    var packingStyle: PackingStyle = .balanced
    var chips: Set<ContextChip> = []
    var notes: String = ""
    var travelMode: TravelMode = .solo
    var partnerName: String = ""
    var partnerChips: Set<ContextChip> = []
    var partnerNotes: String = ""
    var adultCount: Int = 2
    var childProfiles: [ChildDraft] = [ChildDraft(ageGroup: .toddler)]
    var existingParty: TripParty?

    var duration: (days: Int, nights: Int) {
        TripDateMath.daysAndNights(from: startDate, to: endDate)
    }

    var personalChips: Set<ContextChip> {
        chips.subtracting(ContextChip.tripLevel)
    }

    var party: TripParty {
        TripPartyBuilder.make(
            mode: travelMode,
            selfChips: personalChips,
            partnerName: partnerName,
            partnerChips: partnerChips,
            partnerNotes: partnerNotes,
            adultCount: travelMode == .couple ? 2 : adultCount,
            childProfiles: travelMode == .family ? childProfiles : [],
            existing: existingParty
        )
    }

    static func fresh(preferences: TravelerPreferences) -> TripDraft {
        var draft = TripDraft()
        draft.packingStyle = preferences.packingStyle
        draft.bagType = preferences.preferredBag
        return draft
    }

    static func from(trip: TripRecord) -> TripDraft {
        let party = trip.party
        let partner = party.travelers.first { $0.role == .partner }
        var draft = TripDraft()
        draft.destination = trip.destination
        draft.startDate = trip.startDate
        draft.endDate = trip.endDate
        draft.tripType = trip.tripType
        draft.activities = trip.activities
        draft.bagType = trip.bagType
        draft.packingStyle = trip.packingStyle
        draft.chips = Set(trip.contextChips)
        draft.notes = trip.userNotes
        draft.travelMode = party.travelMode
        draft.partnerName = partner?.name ?? ""
        draft.partnerChips = partner?.chips ?? []
        draft.partnerNotes = partner?.notes ?? ""
        draft.adultCount = max(1, party.travelers.filter { $0.role != .child }.count)
        draft.childProfiles = party.travelers.filter { $0.role == .child }.map {
            ChildDraft(id: $0.id, name: $0.name, ageGroup: $0.ageGroup, needs: $0.needs)
        }
        if draft.childProfiles.isEmpty {
            draft.childProfiles = [ChildDraft(ageGroup: .toddler)]
        }
        draft.existingParty = party
        return draft
    }
}

enum SetupStep: Int, CaseIterable {
    case destination, dates, party, type, activities, bag, style, extras, review
}

struct TripSetupView: View {
    var existingTrip: TripRecord? = nil
    var onFinished: ((UUID) -> Void)? = nil

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var preferenceRecords: [PackingPreferenceRecord]

    @State private var draft = TripDraft()
    @State private var step: SetupStep = .destination
    @State private var search = ""
    @State private var destinationMatches: [Destination] = []
    @State private var customText = ""
    @State private var isBuilding = false
    @State private var dateError: String?
    @State private var didPrefill = false
    @State private var pendingDiff: RecommendationDiff?

    private var isEditing: Bool { existingTrip != nil }

    var body: some View {
        VStack(spacing: 0) {
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            footer
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { prefillIfNeeded() }
        .sheet(item: $pendingDiff) { diff in
            if let trip = existingTrip {
                RecommendationDiffSheet(diff: diff, trip: trip) {
                    finish(tripID: trip.id)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if step == .destination {
                    Button("Close") { dismiss() }
                } else {
                    Button("Back") { goBack() }
                }
            }
        }
    }

    private var title: String {
        switch step {
        case .destination: "Where are you going?"
        case .dates: "When are you going?"
        case .party: "Who's traveling?"
        case .type: "What kind of trip is it?"
        case .activities: "What will you be doing?"
        case .bag: "How are you traveling?"
        case .style: "How do you prefer to pack?"
        case .extras: "Anything PackWise should know?"
        case .review: "Review"
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .destination: destinationStep
        case .dates: datesStep
        case .party: partyStep
        case .type: typeStep
        case .activities: activitiesStep
        case .bag: bagStep
        case .style: styleStep
        case .extras: extrasStep
        case .review: reviewStep
        }
    }

    private var destinationStep: some View {
        List {
            Section {
                TextField("Search city or destination", text: $search)
                    .task(id: search) {
                        try? await Task.sleep(for: .milliseconds(280))
                        let results = await dependencies.destinationSearch.search(query: search)
                        destinationMatches = results.map { attachFixture($0) }
                    }
            }
            Section {
                ForEach(destinationMatches) { dest in
                    Button {
                        draft.destination = dest
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(dest.displayName)
                                Text(dest.subtitle).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if draft.destination == dest {
                                Image(systemName: "checkmark").foregroundStyle(PackWiseColor.accent)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    private var datesStep: some View {
        Form {
            DatePicker("Start", selection: $draft.startDate, in: Date.now..., displayedComponents: .date)
            DatePicker("End", selection: $draft.endDate, in: draft.startDate..., displayedComponents: .date)
            LabeledContent("Length", value: "\(draft.duration.days) days · \(draft.duration.nights) nights")
            if let dateError {
                Text(dateError).foregroundStyle(.red)
            }
        }
    }

    private var partyStep: some View {
        List {
            Section {
                ForEach(TravelMode.allCases) { mode in
                    Button {
                        draft.travelMode = mode
                        if mode == .family, draft.childProfiles.isEmpty {
                            draft.childProfiles = [ChildDraft(ageGroup: .toddler)]
                        }
                        if mode == .group {
                            draft.adultCount = max(draft.adultCount, 3)
                        }
                    } label: {
                        HStack {
                            Text(mode.title)
                            Spacer()
                            if draft.travelMode == mode {
                                Image(systemName: "checkmark").foregroundStyle(PackWiseColor.accent)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }

            if draft.travelMode == .couple {
                Section("Partner") {
                    TextField("Name (optional)", text: $draft.partnerName)
                }
                Section("Does your partner need anything different?") {
                    ForEach(ContextChip.partnerDifferences) { chip in
                        Toggle(chip.differenceTitle, isOn: Binding(
                            get: { draft.partnerChips.contains(chip) },
                            set: { on in
                                if on { draft.partnerChips.insert(chip) } else { draft.partnerChips.remove(chip) }
                            }
                        ))
                    }
                    TextField("Add note", text: $draft.partnerNotes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }

            if draft.travelMode == .family {
                Section {
                    Stepper("Adults  \(draft.adultCount)", value: $draft.adultCount, in: 1...6)
                    Stepper("Children  \(draft.childProfiles.count)", value: Binding(
                        get: { draft.childProfiles.count },
                        set: { count in
                            if count > draft.childProfiles.count {
                                draft.childProfiles.append(ChildDraft(ageGroup: .child))
                            } else if count < draft.childProfiles.count {
                                draft.childProfiles = Array(draft.childProfiles.prefix(count))
                            }
                        }
                    ), in: 0...6)
                }
                ForEach($draft.childProfiles) { $child in
                    Section("Child \(draft.childProfiles.firstIndex(where: { $0.id == child.id }).map { $0 + 1 } ?? 1)") {
                        TextField("Name (optional)", text: $child.name)
                        Picker("Age group", selection: $child.ageGroup) {
                            ForEach(AgeGroup.allCases.filter { $0 != .adult }) { group in
                                Text(group.title).tag(group)
                            }
                        }
                        if !ChildNeed.suggested(for: child.ageGroup).isEmpty {
                            Text("What should PackWise plan for?")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            ForEach(ChildNeed.suggested(for: child.ageGroup)) { need in
                                Toggle(need.title, isOn: Binding(
                                    get: { child.needs.contains(need) },
                                    set: { on in
                                        if on { child.needs.insert(need) } else { child.needs.remove(need) }
                                    }
                                ))
                            }
                        }
                    }
                }
            }

            if draft.travelMode == .group {
                Section {
                    Stepper("Adults  \(draft.adultCount)", value: $draft.adultCount, in: 2...8)
                    Text("PackWise will build personal lists plus a shared list. Collaboration across phones comes later.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var typeStep: some View {
        List(TripType.allCases) { type in
            Button {
                draft.tripType = type
                if draft.activities.isEmpty {
                    draft.activities = Array(type.suggestedActivityIDs.prefix(2))
                }
            } label: {
                Label(type.title, systemImage: type.symbol)
                    .badge(draft.tripType == type ? "Selected" : "")
            }
            .foregroundStyle(.primary)
        }
    }

    private var activitiesStep: some View {
        List {
            Section("Suggested") {
                FlowChips(
                    options: draft.tripType.suggestedActivityIDs,
                    selected: Set(draft.activities),
                    title: activityTitle
                ) { id in
                    toggleActivity(id)
                }
            }
            Section("Your activities") {
                ForEach(draft.activities, id: \.self) { activity in
                    Text(activityTitle(activity))
                }
            }
            Section {
                HStack {
                    TextField("Add something", text: $customText)
                    Button("Add") { addCustom() }
                        .disabled(customText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var bagStep: some View {
        List(BagType.allCases) { bag in
            Button {
                draft.bagType = bag
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(bag.title).font(.headline)
                        Spacer()
                        if draft.bagType == bag {
                            Image(systemName: "checkmark").foregroundStyle(PackWiseColor.accent)
                        }
                    }
                    Text(bag.implication).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        }
    }

    private var styleStep: some View {
        List(PackingStyle.allCases) { style in
            Button {
                draft.packingStyle = style
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(style.title).font(.headline)
                        Spacer()
                        if draft.packingStyle == style {
                            Image(systemName: "checkmark").foregroundStyle(PackWiseColor.accent)
                        }
                    }
                    Text(style.subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        }
    }

    private var extrasStep: some View {
        List {
            Section {
                ForEach(ContextChip.allCases) { chip in
                    Toggle(chip.title, isOn: Binding(
                        get: { draft.chips.contains(chip) },
                        set: { on in
                            if on { draft.chips.insert(chip) } else { draft.chips.remove(chip) }
                        }
                    ))
                }
            }
            Section("Add a note") {
                TextField("I'll probably do laundry halfway through.", text: $draft.notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
    }

    private var reviewStep: some View {
        List {
            if let dest = draft.destination {
                Section {
                    Text(dest.displayName).font(.title2.bold())
                    Text(dest.subtitle).foregroundStyle(.secondary)
                    Text("\(draft.startDate.formatted(.dateTime.month().day())) – \(draft.endDate.formatted(.dateTime.month().day()))")
                    Text("\(draft.duration.days) days · \(draft.duration.nights) nights")
                    Text(draft.tripType.title)
                    Text(draft.party.summary)
                    Text(draft.activities.map(activityTitle).joined(separator: ", "))
                    Text(draft.bagType.title)
                    Text("\(draft.packingStyle.title) packing")
                }
            }
        }
    }

    private var footer: some View {
        Button(step == .review ? reviewCTA : "Next") {
            Task { await advance() }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!canAdvance || isBuilding)
        .padding(16)
    }

    private var reviewCTA: String {
        if isBuilding {
            return isEditing ? "Updating your packing list" : "Building your packing list"
        }
        return isEditing ? "Update Packing List" : "Build My Packing List"
    }

    private var canAdvance: Bool {
        switch step {
        case .destination: draft.destination != nil
        case .dates: TripDateMath.isStartAllowed(draft.startDate) && draft.endDate >= draft.startDate
        default: true
        }
    }

    private func goBack() {
        if let previous = SetupStep(rawValue: step.rawValue - 1) {
            step = previous
        }
    }

    private func advance() async {
        if step == .dates && !TripDateMath.isStartAllowed(draft.startDate) {
            dateError = "Start date must be today or later."
            return
        }
        dateError = nil
        if step != .review {
            if let next = SetupStep(rawValue: step.rawValue + 1) {
                step = next
            }
            return
        }
        await saveTrip()
    }

    private func prefillIfNeeded() {
        guard !didPrefill else { return }
        didPrefill = true
        if let existingTrip {
            draft = TripDraft.from(trip: existingTrip)
            search = existingTrip.destinationDisplayName
        } else if let prefs = preferenceRecords.first?.preferences {
            draft = TripDraft.fresh(preferences: prefs)
        }
    }

    private func saveTrip() async {
        guard let destination = draft.destination else { return }
        isBuilding = true
        let prefs = preferenceRecords.first?.preferences ?? .deviceDefaults()
        let duration = draft.duration
        let notes = draft.notes
        var activities = dependencies.engine.interpretFreeTextActivities(notes + " " + draft.customActivity, selected: draft.activities)
        let party = draft.party
        let repository = TripRepository(context: modelContext)

        let resolved = await TripWeatherResolver.resolve(
            using: dependencies.weatherService,
            destination: destination,
            start: draft.startDate,
            end: draft.endDate,
            cached: existingTrip?.weatherSnapshots.first?.weatherContext
        )
        let weather = resolved.engineWeather

        if let existing = existingTrip {
            repository.apply(
                destination: destination,
                startDate: draft.startDate,
                endDate: draft.endDate,
                durationDays: duration.days,
                durationNights: duration.nights,
                tripType: draft.tripType,
                activities: activities,
                bagType: draft.bagType,
                packingStyle: draft.packingStyle,
                userNotes: notes,
                contextChips: Array(draft.chips),
                party: party,
                on: existing
            )
            var context = existing.context(preferences: prefs, weather: weather)
            context.party = party
            if !notes.isEmpty, let enrichment = try? await dependencies.intelligence.interpretTripNote(notes, context: context) {
                activities.append(contentsOf: enrichment.inferredActivities.filter { !activities.contains($0) })
                existing.activitiesRaw = activities.joined(separator: ",")
                var chips = Set(existing.contextChips)
                enrichment.inferredChips.forEach { chips.insert($0) }
                existing.contextChipsRaw = chips.map(\.rawValue).joined(separator: ",")
                context.activities = activities
                context.contextChips = chips
            }
            if let snapshot = resolved.snapshot {
                repository.storeWeather(snapshot, on: existing)
            }
            let existingItems = existing.items.map(\.draft)
            let overrides = existing.overrides.map(\.draft)
            let diff = dependencies.engine.recommendationDiff(
                context: context,
                existing: existingItems,
                overrides: overrides
            )
            try? modelContext.save()
            isBuilding = false
            if diff.isEmpty {
                finish(tripID: existing.id)
            } else {
                pendingDiff = diff
            }
            return
        }

        let trip = TripRecord(
            destination: destination,
            startDate: draft.startDate,
            endDate: draft.endDate,
            durationDays: duration.days,
            durationNights: duration.nights,
            tripType: draft.tripType,
            activities: activities,
            bagType: draft.bagType,
            packingStyle: draft.packingStyle,
            status: .packing,
            userNotes: notes,
            contextChips: Array(draft.chips),
            travelerCount: party.travelers.count,
            travelMode: party.travelMode
        )

        var context = trip.context(preferences: prefs, weather: weather)
        context.party = party
        if !notes.isEmpty {
            if let enrichment = try? await dependencies.intelligence.interpretTripNote(notes, context: context) {
                activities.append(contentsOf: enrichment.inferredActivities.filter { !activities.contains($0) })
                trip.activitiesRaw = activities.joined(separator: ",")
                var chips = Set(trip.contextChips)
                enrichment.inferredChips.forEach { chips.insert($0) }
                trip.contextChipsRaw = chips.map(\.rawValue).joined(separator: ",")
                context.activities = activities
                context.contextChips = chips
            }
        }

        let items = dependencies.engine.generate(context: context)
        modelContext.insert(trip)
        repository.attach(party: party, bagType: draft.bagType, on: trip)
        repository.replaceItems(on: trip, with: items)
        if let snapshot = resolved.snapshot {
            repository.storeWeather(snapshot, on: trip)
        }
        try? modelContext.save()
        isBuilding = false
        finish(tripID: trip.id)
    }

    private func finish(tripID: UUID) {
        onFinished?(tripID)
        dismiss()
    }

    private func toggleActivity(_ id: String) {
        if draft.activities.contains(id) {
            draft.activities.removeAll { $0 == id }
        } else {
            draft.activities.append(id)
        }
    }

    private func addCustom() {
        let text = customText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft.customActivity += " " + text
        draft.activities = dependencies.engine.interpretFreeTextActivities(text, selected: draft.activities)
        if !draft.activities.contains(where: { $0.caseInsensitiveCompare(text) == .orderedSame }) {
            draft.activities.append(text)
        }
        customText = ""
    }

    private func attachFixture(_ dest: Destination) -> Destination {
        var copy = dest
        if let match = dependencies.testDestinations.first(where: {
            $0.city.compare(dest.city, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            copy.fixtureID = match.fixtureID
            if copy.timeZone.isEmpty { copy.timeZone = match.timeZone }
        }
        return copy
    }

    private func activityTitle(_ id: String) -> String {
        switch id {
        case "swimming": "Swimming"
        case "beachDays": "Beach days"
        case "snorkeling": "Snorkeling"
        case "niceDinner": "Nice dinner"
        case "running": "Running"
        case "sightseeing": "Sightseeing"
        case "boatTrip": "Boat trip"
        case "walking": "Walking"
        case "nightlife": "Nightlife"
        case "shopping": "Shopping"
        case "museums": "Museums"
        case "work": "Work"
        case "hiking": "Hiking"
        case "yoga": "Yoga"
        case "photography": "Photography"
        case "wildlife": "Wildlife"
        default: id.capitalized
        }
    }
}

struct FlowChips: View {
    var options: [String]
    var selected: Set<String>
    var title: (String) -> String
    var toggle: (String) -> Void

    var body: some View {
        FlexibleChipWrap(options: options, selected: selected, title: title, toggle: toggle)
            .padding(.vertical, 8)
    }
}

struct FlexibleChipWrap: View {
    var options: [String]
    var selected: Set<String>
    var title: (String) -> String
    var toggle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(options, id: \.self) { option in
                SelectableChip(title: title(option), selected: selected.contains(option)) {
                    toggle(option)
                }
            }
        }
    }
}
