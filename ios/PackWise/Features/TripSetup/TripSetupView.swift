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
    /// Bag and style are one screen, as the board draws them. The underlying
    /// draft still records them separately.
    case destination, dates, party, type, activities, bagAndStyle, extras, review
}

struct TripSetupView: View {
    var existingTrip: TripRecord? = nil
    var onFinished: ((UUID) -> Void)? = nil
    /// Where the flow opens. Always the first step in the app; the Debug
    /// capture harness uses it to photograph a step without walking to it.
    var initialStep: SetupStep = .destination

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
            ScrollView {
                VStack(alignment: .leading, spacing: PackWiseSpacing.loose) {
                    stepContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(PackWiseSpacing.comfortable)
            }
            footer
        }
        .background(Color(.systemGroupedBackground))
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
            // design-system.md: trip setup uses a top Back / Next header, not
            // custom wizard chrome. Review keeps its own primary action.
            if step != .review {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") { Task { await advance() } }
                        .disabled(!canAdvance)
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
        case .bagAndStyle: "How are you traveling?"
        case .extras: "Anything PackWise should know?"
        case .review: "Review"
        }
    }

    private var subtitle: String? {
        switch step {
        case .party: "Help us personalize your packing list."
        case .activities: "Choose activities that apply to your trip."
        case .extras: "Optional, but it makes the list fit better."
        default: nil
        }
    }

    /// The board puts the step's question in the content, with only Back and
    /// Next in the navigation bar.
    private var heading: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.tight) {
            Text(title)
                .font(.title.bold())
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        heading
        switch step {
        case .destination: destinationStep
        case .dates: datesStep
        case .party: partyStep
        case .type: typeStep
        case .activities: activitiesStep
        case .bagAndStyle: bagAndStyleStep
        case .extras: extrasStep
        case .review: reviewStep
        }
    }

    /// Rows grouped into one card, separated rather than boxed individually.
    private func group<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        PackWiseCard {
            VStack(spacing: 0) {
                content()
            }
        }
    }

    // MARK: - Destination

    private var destinationStep: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.comfortable) {
            HStack(spacing: PackWiseSpacing.snug) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search city or destination", text: $search)
                    .autocorrectionDisabled()
                if !search.isEmpty {
                    Button {
                        search = ""
                        destinationMatches = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(PackWiseSpacing.regular)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: PackWiseRadius.control, style: .continuous))
            .task(id: search) {
                try? await Task.sleep(for: .milliseconds(280))
                let results = await dependencies.destinationSearch.search(query: search)
                destinationMatches = results.map { attachFixture($0) }
            }

            if !destinationMatches.isEmpty {
                group {
                    ForEach(Array(destinationMatches.enumerated()), id: \.element.id) { index, destination in
                        if index > 0 { Divider() }
                        Button {
                            draft.destination = destination
                        } label: {
                            HStack(spacing: PackWiseSpacing.regular) {
                                PackWiseIconBadge(symbol: "mappin.circle", tint: .blue)
                                VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                                    Text(destination.displayName)
                                        .foregroundStyle(.primary)
                                    Text(destination.subtitle)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: PackWiseSpacing.snug)
                                if draft.destination == destination {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(PackWiseColor.accent)
                                }
                            }
                            .padding(.vertical, PackWiseSpacing.regular)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // A map, not Look Around: this screen answers "did I pick the
            // right Chicago?", which a street-level view does not.
            if let destination = draft.destination {
                VStack(alignment: .leading, spacing: 0) {
                    DestinationVisualView(destination: destination, purpose: .destinationPreview)
                        .frame(height: PackWiseSize.previewHeight)
                    HStack(spacing: PackWiseSpacing.regular) {
                        VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                            Text(destination.city.isEmpty ? destination.displayName : destination.city)
                                .font(.headline)
                            Text(destination.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(.secondary)
                    }
                    .padding(PackWiseSpacing.comfortable)
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: PackWiseRadius.card, style: .continuous))
            }
        }
    }

    // MARK: - Dates

    private var datesStep: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.comfortable) {
            PackWiseCard {
                PackWiseDateRangePicker(
                    start: $draft.startDate,
                    end: $draft.endDate,
                    earliest: Calendar.current.startOfDay(for: .now)
                )
            }
            HStack(alignment: .firstTextBaseline, spacing: PackWiseSpacing.snug) {
                Text(draft.startDate.formatted(.dateTime.month(.abbreviated).day()))
                Image(systemName: "arrow.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(draft.endDate.formatted(.dateTime.month(.abbreviated).day()))
            }
            .font(.title3.weight(.semibold))
            Text("\(draft.duration.days) days · \(draft.duration.nights) nights")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let dateError {
                Label(dateError, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Party

    private var partyStep: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.comfortable) {
            group {
                ForEach(Array(TravelMode.allCases.enumerated()), id: \.element.id) { index, mode in
                    if index > 0 { Divider() }
                    PackWiseSelectionRow(
                        symbol: mode.symbol,
                        tint: mode.tint,
                        title: mode.title,
                        subtitle: mode.subtitle,
                        isSelected: draft.travelMode == mode
                    ) {
                        draft.travelMode = mode
                        if mode == .family, draft.childProfiles.isEmpty {
                            draft.childProfiles = [ChildDraft(ageGroup: .toddler)]
                        }
                        if mode == .group {
                            draft.adultCount = max(draft.adultCount, 3)
                        }
                    }
                }
            }

            if draft.travelMode == .couple { partnerDetails }
            if draft.travelMode == .family { familyDetails }
            if draft.travelMode == .group { groupDetails }
        }
    }

    private var partnerDetails: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            PackWiseSectionHeader(title: "Partner")
            PackWiseCard {
                VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
                    TextField("Name (optional)", text: $draft.partnerName)
                    Divider()
                    Text("Does your partner need anything different?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    PackWiseFlowLayout {
                        ForEach(ContextChip.partnerDifferences) { chip in
                            SelectableChip(
                                title: chip.differenceTitle,
                                selected: draft.partnerChips.contains(chip)
                            ) {
                                if draft.partnerChips.contains(chip) {
                                    draft.partnerChips.remove(chip)
                                } else {
                                    draft.partnerChips.insert(chip)
                                }
                            }
                        }
                    }
                    Divider()
                    TextField("Add note", text: $draft.partnerNotes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
        }
    }

    private var familyDetails: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.comfortable) {
            PackWiseCard {
                VStack(spacing: PackWiseSpacing.regular) {
                    Stepper("Adults  \(draft.adultCount)", value: $draft.adultCount, in: 1...6)
                    Divider()
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
            }

            ForEach($draft.childProfiles) { $child in
                let number = draft.childProfiles.firstIndex(where: { $0.id == child.id }).map { $0 + 1 } ?? 1
                VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                    PackWiseSectionHeader(title: "Child \(number)")
                    PackWiseCard {
                        VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
                            TextField("Name (optional)", text: $child.name)
                            Divider()
                            HStack {
                                Text("Age group")
                                Spacer()
                                Picker("Age group", selection: $child.ageGroup) {
                                    ForEach(AgeGroup.allCases.filter { $0 != .adult }) { group in
                                        Text(group.title).tag(group)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                            if !ChildNeed.suggested(for: child.ageGroup).isEmpty {
                                Divider()
                                Text("What should PackWise plan for?")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                PackWiseFlowLayout {
                                    ForEach(ChildNeed.suggested(for: child.ageGroup)) { need in
                                        SelectableChip(
                                            title: need.title,
                                            selected: child.needs.contains(need)
                                        ) {
                                            if child.needs.contains(need) {
                                                child.needs.remove(need)
                                            } else {
                                                child.needs.insert(need)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var groupDetails: some View {
        PackWiseCard {
            VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
                Stepper("Adults  \(draft.adultCount)", value: $draft.adultCount, in: 2...8)
                Text("PackWise will build personal lists plus a shared list. Collaboration across phones comes later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Trip type

    private var typeStep: some View {
        group {
            ForEach(Array(TripType.allCases.enumerated()), id: \.element.id) { index, type in
                if index > 0 { Divider() }
                PackWiseSelectionRow(
                    symbol: type.symbol,
                    tint: type.tint,
                    title: type.title,
                    subtitle: nil,
                    isSelected: draft.tripType == type
                ) {
                    draft.tripType = type
                    if draft.activities.isEmpty {
                        draft.activities = Array(type.suggestedActivityIDs.prefix(2))
                    }
                }
            }
        }
    }

    // MARK: - Activities

    private var activitiesStep: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.comfortable) {
            PackWiseFlowLayout {
                ForEach(suggestedActivities, id: \.self) { id in
                    SelectableChip(
                        title: activityTitle(id),
                        selected: draft.activities.contains(id)
                    ) {
                        toggleActivity(id)
                    }
                }
            }

            HStack(spacing: PackWiseSpacing.snug) {
                Image(systemName: "plus")
                    .foregroundStyle(PackWiseColor.accent)
                TextField("Add something", text: $customText)
                    .onSubmit { addCustom() }
                if !customText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Add") { addCustom() }
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(PackWiseSpacing.regular)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: PackWiseRadius.control, style: .continuous))

            if !draft.activities.isEmpty {
                VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                    PackWiseSectionHeader(title: "Your activities")
                    PackWiseFlowLayout {
                        ForEach(draft.activities, id: \.self) { id in
                            Button {
                                toggleActivity(id)
                            } label: {
                                HStack(spacing: PackWiseSpacing.tight) {
                                    Text(activityTitle(id))
                                    Image(systemName: "xmark")
                                        .font(.caption2.weight(.semibold))
                                }
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, PackWiseSpacing.regular)
                                .frame(minHeight: PackWiseSize.tapTarget)
                                .foregroundStyle(.primary)
                                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(activityTitle(id))")
                        }
                    }
                }
            }
        }
    }

    /// Suggestions for the trip type, plus anything already chosen that is not
    /// among them, so a selection never disappears from the field it lives in.
    private var suggestedActivities: [String] {
        var ids = draft.tripType.suggestedActivityIDs
        ids.append(contentsOf: draft.activities.filter { !ids.contains($0) })
        return ids
    }

    // MARK: - Bag and style

    private var bagAndStyleStep: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.loose) {
            group {
                ForEach(Array(BagType.allCases.enumerated()), id: \.element.id) { index, bag in
                    if index > 0 { Divider() }
                    PackWiseSelectionRow(
                        symbol: bag.symbol,
                        tint: bag.tint,
                        title: bag.title,
                        subtitle: bag.setupSubtitle,
                        isSelected: draft.bagType == bag
                    ) {
                        draft.bagType = bag
                    }
                }
            }

            VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
                Text("How do you prefer to pack?")
                    .font(.title3.bold())
                group {
                    ForEach(Array(PackingStyle.allCases.enumerated()), id: \.element.id) { index, style in
                        if index > 0 { Divider() }
                        PackWiseSelectionRow(
                            symbol: style.symbol,
                            tint: style.tint,
                            title: style.title,
                            subtitle: style.subtitle,
                            isSelected: draft.packingStyle == style
                        ) {
                            draft.packingStyle = style
                        }
                    }
                }
            }
        }
    }

    // MARK: - Extras

    private var extrasStep: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.comfortable) {
            PackWiseFlowLayout {
                ForEach(ContextChip.allCases) { chip in
                    SelectableChip(title: chip.title, selected: draft.chips.contains(chip)) {
                        if draft.chips.contains(chip) {
                            draft.chips.remove(chip)
                        } else {
                            draft.chips.insert(chip)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                PackWiseSectionHeader(title: "Add a note")
                PackWiseCard {
                    TextField("I'll probably do laundry halfway through.", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
        }
    }

    // MARK: - Review

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.comfortable) {
            if let destination = draft.destination {
                PackWiseCard {
                    HStack(spacing: PackWiseSpacing.regular) {
                        DestinationVisualView(destination: destination, purpose: .tripThumbnail)
                            .frame(width: PackWiseSize.tripThumbnail, height: PackWiseSize.tripThumbnail)
                            .clipShape(RoundedRectangle(cornerRadius: PackWiseRadius.control, style: .continuous))
                        VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                            Text(destination.displayName)
                                .font(.title3.weight(.semibold))
                            Text(destination.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }

                group {
                    reviewRow("Dates", "\(draft.startDate.formatted(.dateTime.month(.abbreviated).day())) – \(draft.endDate.formatted(.dateTime.month(.abbreviated).day()))")
                    Divider()
                    reviewRow("Trip length", "\(draft.duration.days) days · \(draft.duration.nights) nights")
                    Divider()
                    reviewRow("Trip type", draft.tripType.title)
                    Divider()
                    reviewRow("Travelers", draft.party.summary)
                    if !draft.activities.isEmpty {
                        Divider()
                        reviewRow("Activities", draft.activities.map(activityTitle).joined(separator: ", "))
                    }
                    Divider()
                    reviewRow("Bag", draft.bagType.title)
                    Divider()
                    reviewRow("Style", draft.packingStyle.title)
                    if !draft.notes.isEmpty {
                        Divider()
                        reviewRow("Notes", draft.notes)
                    }
                }
            }
        }
    }

    private func reviewRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: PackWiseSpacing.regular) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: PackWiseSpacing.snug)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, PackWiseSpacing.regular)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var footer: some View {
        if step == .review {
            Button(reviewCTA) {
                Task { await advance() }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canAdvance || isBuilding)
            .padding(PackWiseSpacing.comfortable)
            .background(.bar)
        }
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
        step = initialStep
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

/// Terse subtitles for the bag step.
///
/// `BagType.implication` is domain copy — it explains to the engine's user
/// what choosing a bag does to the list, and it is kept intact for that. At
/// six options on one screen those full sentences make the rows twice the
/// height the board draws, so the setup step gets its own short labels. This
/// lives here rather than in `Domain/` because it is presentation only.
private extension BagType {
    var setupSubtitle: String {
        switch self {
        case .personalItem: "Smallest and most compact"
        case .carryOn: "Best for most trips"
        case .checked: "More flexibility"
        case .backpack: "Great for flexible travel"
        case .roadTripLuggage: "Traveling by car"
        case .notSure: "Choose later"
        }
    }
}
