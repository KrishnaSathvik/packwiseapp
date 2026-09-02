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
    var laundry: LaundryAccess = .none
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
        draft.laundry = trip.laundryAccess
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
    /// Steps after the first, in visit order. The destination step is the
    /// stack's root; Next pushes, Back pops.
    @State private var stepPath: [SetupStep] = []
    @State private var search = ""
    @State private var destinationMatches: [Destination] = []
    @State private var customText = ""
    @State private var addingCustom = false
    @FocusState private var customFieldFocused: Bool
    @State private var isBuilding = false
    @State private var dateError: String?
    @State private var didPrefill = false
    @State private var pendingDiff: RecommendationDiff?

    private var isEditing: Bool { existingTrip != nil }

    var body: some View {
        // The flow owns its NavigationStack: it is presented full screen, and
        // each of the eight steps is a real push, not swapped-in content.
        NavigationStack(path: $stepPath) {
            stepScreen(.destination)
                .navigationDestination(for: SetupStep.self) { stepScreen($0) }
                // Editing an existing trip can move its recommendations; the
                // proposal pushes as the flow's final screen.
                .navigationDestination(item: $pendingDiff) { diff in
                    if let trip = existingTrip {
                        RecommendationDiffScreen(diff: diff, trip: trip) {
                            finish(tripID: trip.id)
                        }
                    }
                }
        }
        .overlay {
            if isBuilding {
                buildingOverlay
            }
        }
        .onAppear { prefillIfNeeded() }
    }

    private func stepScreen(_ step: SetupStep) -> some View {
        VStack(spacing: 0) {
            progressBar(for: step)
            ScrollView {
                VStack(alignment: .leading, spacing: PackWiseSpacing.comfortable) {
                    stepContent(for: step)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PackWiseSpacing.comfortable)
                .padding(.top, PackWiseSpacing.snug)
                .padding(.bottom, PackWiseSpacing.section)
            }
            footer(for: step)
        }
        .background(PackWiseColor.screen)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { setupToolbar(for: step) }
    }

    /// A thin bar under the navigation bar tracking position through the
    /// eight steps — at eight, page dots would be noise.
    private func progressBar(for step: SetupStep) -> some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(PackWiseColor.accent)
                .frame(
                    width: proxy.size.width
                        * Double(step.rawValue + 1) / Double(SetupStep.allCases.count)
                )
        }
        .frame(height: 2)
        .background(PackWiseColor.border)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(SetupStep.allCases.count)")
    }

    // design-system.md: trip setup uses a top Back / Next header, not custom
    // wizard chrome. Review keeps its own primary action.
    //
    // On iOS 26 a toolbar item is wrapped in Liquid Glass by default, and
    // `.buttonStyle(.plain)` does not opt out of it — the button keeps the
    // capsule and, for the back item, gets squeezed until "Back" truncates to
    // an ellipsis. `sharedBackgroundVisibility(.hidden)` is the actual opt-out,
    // and it lives on the toolbar item rather than on the button. It is iOS 26
    // only, so the pre-26 path keeps the plain items it already drew correctly.
    @ToolbarContentBuilder
    private func setupToolbar(for step: SetupStep) -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .cancellationAction) { leadingButton(for: step) }
                .sharedBackgroundVisibility(.hidden)
            if step != .review {
                ToolbarItem(placement: .confirmationAction) { nextButton(for: step) }
                    .sharedBackgroundVisibility(.hidden)
            }
        } else {
            ToolbarItem(placement: .cancellationAction) { leadingButton(for: step) }
            if step != .review {
                ToolbarItem(placement: .confirmationAction) { nextButton(for: step) }
            }
        }
    }

    @ViewBuilder
    private func leadingButton(for step: SetupStep) -> some View {
        if step == .destination {
            // "Cancel", never truncated — the leading item must keep its
            // intrinsic width or the bar squeezes it to "Cl…".
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(PackWiseColor.accent)
                .lineLimit(1)
                .fixedSize()
        } else {
            Button {
                goBack()
            } label: {
                // Without `fixedSize` the toolbar sizes this item to the
                // glyph and clips the word to "B".
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .foregroundStyle(PackWiseColor.accent)
        }
    }

    private func nextButton(for step: SetupStep) -> some View {
        // A filled blue pill, not plain bar text.
        Button("Next") { Task { await advance(from: step) } }
            .buttonStyle(NavPillButtonStyle())
            .disabled(!canAdvance(for: step))
    }

    private func title(for step: SetupStep) -> String {
        switch step {
        case .destination: "Where are you going?"
        case .dates: "When are you going?"
        case .party: "Who's traveling?"
        case .type: "What kind of trip is it?"
        case .activities: "What will you be doing?"
        case .bagAndStyle: "How are you traveling?"
        case .extras: "Anything PackWise should know?"
        case .review: "Review your trip"
        }
    }

    private func subtitle(for step: SetupStep) -> String? {
        switch step {
        case .destination: "Search for a city, region, or country."
        case .party: "Help us personalize your packing list."
        case .activities: "Choose activities that apply to your trip."
        case .extras: "Optional, but it makes the list fit better."
        case .type: "This helps tailor your packing list."
        case .bagAndStyle: "This affects what you can bring."
        case .review: "One look before PackWise builds your list."
        case .dates: nil
        }
    }

    /// The board puts the step's question in the content, with only Back and
    /// Next in the navigation bar.
    private func heading(for step: SetupStep) -> some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            Text(title(for: step))
                .font(PackWiseFont.screenTitle)
                .foregroundStyle(PackWiseColor.textPrimary)
            if let subtitle = subtitle(for: step) {
                Text(subtitle)
                    .font(PackWiseFont.screenSubtitle)
                    .foregroundStyle(PackWiseColor.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func stepContent(for step: SetupStep) -> some View {
        heading(for: step)
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
                    .foregroundStyle(PackWiseColor.textSecondary)
                TextField("Search city or destination", text: $search)
                    .autocorrectionDisabled()
                if !search.isEmpty {
                    Button {
                        search = ""
                        destinationMatches = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(PackWiseColor.textTertiary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(PackWiseSpacing.regular)
            .background(PackWiseColor.surfaceAlt, in: RoundedRectangle(cornerRadius: PackWiseRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PackWiseRadius.control, style: .continuous)
                    .strokeBorder(PackWiseColor.border, lineWidth: 1)
            }
            .task(id: search) {
                try? await Task.sleep(for: .milliseconds(280))
                let results = await dependencies.destinationSearch.search(query: search)
                destinationMatches = results.map { attachFixture($0) }
            }

            if !destinationMatches.isEmpty {
                group {
                    ForEach(Array(destinationMatches.enumerated()), id: \.element.id) { index, destination in
                        if index > 0 { PackWiseRowDivider() }
                        Button {
                            draft.destination = destination
                        } label: {
                            HStack(spacing: PackWiseSpacing.regular) {
                                PackWiseIconBadge(symbol: "mappin.circle", tint: PackWiseColor.accent)
                                VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                                    Text(destination.displayName)
                                        .font(PackWiseFont.rowTitle)
                                        .foregroundStyle(PackWiseColor.textPrimary)
                                    Text(destination.subtitle)
                                        .font(PackWiseFont.rowSubtitle)
                                        .foregroundStyle(PackWiseColor.textSecondary)
                                }
                                Spacer(minLength: PackWiseSpacing.snug)
                                if draft.destination == destination {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(PackWiseColor.onAccent, PackWiseColor.accent)
                                }
                            }
                            .padding(.vertical, PackWiseSpacing.regular)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Destination photography, with the name and a location pin
            // below — never a map embed.
            if let destination = draft.destination {
                VStack(alignment: .leading, spacing: 0) {
                    DestinationVisualView(destination: destination, purpose: .destinationPreview)
                        .frame(height: PackWiseSize.previewHeight)
                    HStack(spacing: PackWiseSpacing.regular) {
                        VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                            Text(destination.city.isEmpty ? destination.displayName : destination.city)
                                .font(PackWiseFont.cardTitle)
                                .foregroundStyle(PackWiseColor.textPrimary)
                            Text(destination.subtitle)
                                .font(PackWiseFont.rowSubtitle)
                                .foregroundStyle(PackWiseColor.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(PackWiseColor.accent)
                    }
                    .padding(PackWiseSpacing.comfortable)
                }
                .background(PackWiseColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: PackWiseRadius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PackWiseRadius.card, style: .continuous)
                        .strokeBorder(PackWiseColor.border, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
            }
        }
    }

    // MARK: - Dates

    private var datesStep: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
            PackWiseCard {
                PackWiseDateRangePicker(
                    start: $draft.startDate,
                    end: $draft.endDate,
                    earliest: Calendar.current.startOfDay(for: .now)
                )
            }

            // The span and its length are one fact, so they read as one row
            // rather than as two stacked lines below a very tall calendar.
            PackWiseCard {
                HStack(spacing: PackWiseSpacing.regular) {
                    PackWiseIconBadge(symbol: "calendar", tint: PackWiseColor.accent)
                    VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                        HStack(alignment: .firstTextBaseline, spacing: PackWiseSpacing.snug) {
                            Text(draft.startDate.formatted(.dateTime.month(.abbreviated).day()))
                            Image(systemName: "arrow.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(PackWiseColor.textSecondary)
                            Text(draft.endDate.formatted(.dateTime.month(.abbreviated).day()))
                        }
                        .font(.headline)
                        Text("\(draft.duration.days) days · \(draft.duration.nights) nights")
                            .font(.subheadline)
                            .foregroundStyle(PackWiseColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
            }

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
                    if index > 0 { PackWiseRowDivider() }
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
                    PackWiseRowDivider(inset: 0)
                    Text("Does your partner need anything different?")
                        .font(.subheadline)
                        .foregroundStyle(PackWiseColor.textSecondary)
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
                    PackWiseRowDivider(inset: 0)
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
                    PackWiseRowDivider(inset: 0)
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
                            PackWiseRowDivider(inset: 0)
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
                                PackWiseRowDivider(inset: 0)
                                Text("What should PackWise plan for?")
                                    .font(.subheadline)
                                    .foregroundStyle(PackWiseColor.textSecondary)
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
                    .foregroundStyle(PackWiseColor.textSecondary)
            }
        }
    }

    // MARK: - Trip type

    private var typeStep: some View {
        group {
            ForEach(Array(TripType.allCases.enumerated()), id: \.element.id) { index, type in
                if index > 0 { PackWiseRowDivider() }
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
            // Plain text tokens made this field read as a filter bar. The
            // glyph is what tells "Nice dinner" from "Nightlife" at a glance.
            PackWiseFlowLayout {
                ForEach(suggestedActivities, id: \.self) { id in
                    PackWiseChip(
                        title: activityTitle(id),
                        symbol: PackWiseActivityStyle.symbol(for: id),
                        tint: PackWiseActivityStyle.tint(for: id),
                        isSelected: draft.activities.contains(id)
                    ) {
                        toggleActivity(id)
                    }
                }
                if !addingCustom {
                    // "+ Add something" lives inline in the flow as a white
                    // pill with blue text, not as a full-width field.
                    Button {
                        addingCustom = true
                        customFieldFocused = true
                    } label: {
                        HStack(spacing: PackWiseSpacing.tight + 2) {
                            Image(systemName: "plus")
                                .font(.footnote.weight(.semibold))
                            Text("Add something")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(PackWiseColor.accent)
                        .padding(.horizontal, PackWiseSpacing.comfortable)
                        .frame(minHeight: 40)
                        .background { Capsule().fill(PackWiseColor.surface) }
                        .overlay { Capsule().strokeBorder(PackWiseColor.border, lineWidth: 1) }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if addingCustom {
                HStack(spacing: PackWiseSpacing.snug) {
                    Image(systemName: "plus")
                        .foregroundStyle(PackWiseColor.accent)
                    TextField("Add something", text: $customText)
                        .focused($customFieldFocused)
                        .onSubmit { addCustom() }
                    if !customText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button("Add") { addCustom() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PackWiseColor.accent)
                    }
                }
                .padding(PackWiseSpacing.regular)
                .background(PackWiseColor.surfaceAlt, in: RoundedRectangle(cornerRadius: PackWiseRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PackWiseRadius.control, style: .continuous)
                        .strokeBorder(PackWiseColor.border, lineWidth: 1)
                }
            }

            if !draft.activities.isEmpty {
                VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                    Text("Your activities")
                        .font(PackWiseFont.sectionTitle)
                        .foregroundStyle(PackWiseColor.textSecondary)
                    PackWiseFlowLayout {
                        ForEach(draft.activities, id: \.self) { id in
                            PackWiseRemovableChip(
                                title: activityTitle(id),
                                symbol: PackWiseActivityStyle.symbol(for: id)
                            ) {
                                toggleActivity(id)
                            }
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
                    if index > 0 { PackWiseRowDivider() }
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
                        if index > 0 { PackWiseRowDivider() }
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

            VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
                Text("Laundry on this trip?")
                    .font(.title3.bold())
                group {
                    ForEach(Array(LaundryAccess.allCases.enumerated()), id: \.element.rawValue) { index, laundry in
                        if index > 0 { PackWiseRowDivider() }
                        PackWiseSelectionRow(
                            symbol: laundry.setupSymbol,
                            tint: laundry.setupTint,
                            title: laundry.setupTitle,
                            subtitle: laundry.setupSubtitle,
                            isSelected: draft.laundry == laundry
                        ) {
                            draft.laundry = laundry
                        }
                    }
                }
            }
        }
    }

    // MARK: - Extras

    /// Nine identical grey pills on a grey page communicate no importance and
    /// no structure. The same nine facts split into "you" and "this trip",
    /// each carrying a glyph, give the screen something to be read by.
    private var extrasStep: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.comfortable) {
            chipField(
                "About you",
                ContextChip.allCases.filter { !ContextChip.tripLevel.contains($0) }
            )
            chipField(
                "About this trip",
                // Laundry moved to the bag-and-style step as a three-way
                // control; the boolean chip stays in the enum for old trips.
                ContextChip.allCases.filter { ContextChip.tripLevel.contains($0) && $0 != .laundryAvailable }
            )

            VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                PackWiseSectionHeader(title: "Add a note")
                PackWiseCard {
                    TextField("I'll probably do laundry halfway through.", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
        }
    }

    private func chipField(_ title: String, _ chips: [ContextChip]) -> some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            PackWiseSectionHeader(title: title)
            PackWiseFlowLayout {
                ForEach(chips) { chip in
                    PackWiseChip(
                        title: chip.chipTitle,
                        symbol: chip.symbol,
                        tint: chip.tint,
                        isSelected: draft.chips.contains(chip)
                    ) {
                        if draft.chips.contains(chip) {
                            draft.chips.remove(chip)
                        } else {
                            draft.chips.insert(chip)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Review

    /// The last screen before the list is built.
    ///
    /// The destination leads visually; below it, one row per fact — dates,
    /// length, type, traveler, activities, bag, style, notes — so there is
    /// actually something to review.
    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.comfortable) {
            if let destination = draft.destination {
                ZStack(alignment: .bottomLeading) {
                    DestinationVisualView(
                        destination: destination,
                        purpose: .tripHero,
                        overlaysText: true
                    )
                    .frame(height: 168)

                    VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                        Text(destination.displayName)
                            .font(.title2.bold())
                        Text(dateSpan)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .foregroundStyle(.white)
                    .padding(PackWiseSpacing.comfortable)
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: PackWiseRadius.card, style: .continuous))

                // Grouped by what the user decided, not one row per form
                // field: the dates live on the hero, and the eight steps
                // collapse into a handful of named facts.
                PackWiseCard {
                    VStack(spacing: 0) {
                        reviewRow(
                            draft.tripType.symbol,
                            draft.tripType.tint,
                            "Your trip",
                            "\(draft.tripType.title) · \(draft.party.summary)"
                        )
                        PackWiseRowDivider()
                        reviewRow(
                            "figure.walk",
                            .green,
                            "Activities",
                            draft.activities.isEmpty ? "None chosen" : draft.activities.map(activityTitle).joined(separator: ", ")
                        )
                        PackWiseRowDivider()
                        reviewRow(
                            draft.bagType.symbol,
                            draft.bagType.tint,
                            "Packing",
                            draft.laundry == .none
                                ? "\(draft.bagType.title) · \(draft.packingStyle.title)"
                                : "\(draft.bagType.title) · \(draft.packingStyle.title) · \(draft.laundry.setupTitle)"
                        )
                        PackWiseRowDivider()
                        reviewRow(
                            "slider.horizontal.3",
                            PackWiseColor.accent,
                            "Preferences",
                            draft.chips.isEmpty
                                ? "None"
                                : ContextChip.allCases.filter { draft.chips.contains($0) }.map(\.chipTitle).joined(separator: ", ")
                        )
                        if !draft.notes.isEmpty {
                            PackWiseRowDivider()
                            reviewRow("note.text", PackWiseColor.info, "Notes", draft.notes)
                        }
                    }
                }
            }
        }
    }

    private func reviewRow(_ symbol: String, _ tint: Color, _ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: PackWiseSpacing.regular) {
            PackWiseIconBadge(symbol: symbol, tint: tint)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
            Text(label)
                .font(PackWiseFont.rowTitle)
                .foregroundStyle(PackWiseColor.textPrimary)
            Spacer(minLength: PackWiseSpacing.snug)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(PackWiseColor.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, PackWiseSpacing.regular)
        .accessibilityElement(children: .combine)
    }

    private var dateSpan: String {
        let start = draft.startDate.formatted(.dateTime.month(.abbreviated).day())
        let end = draft.endDate.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end) · \(draft.duration.days) days · \(draft.duration.nights) nights"
    }

    private var shortDateSpan: String {
        let start = draft.startDate.formatted(.dateTime.month(.abbreviated).day())
        let end = draft.endDate.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end)"
    }

    /// The moment between "build it" and the list: a loader over the trip
    /// summary, so the flow never jumps abruptly into a finished list.
    private var buildingOverlay: some View {
        VStack(spacing: PackWiseSpacing.loose) {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(PackWiseColor.accent)
            Text(isEditing ? "Updating your packing list" : "Building your packing list")
                .font(PackWiseFont.cardTitle)
                .foregroundStyle(PackWiseColor.textPrimary)
            Text("Weather, activities, and the way you travel — all considered.")
                .font(PackWiseFont.screenSubtitle)
                .foregroundStyle(PackWiseColor.textSecondary)
                .multilineTextAlignment(.center)

            if let destination = draft.destination {
                PackWiseCard {
                    HStack(spacing: PackWiseSpacing.regular) {
                        PackWiseIconBadge(symbol: "mappin.and.ellipse", tint: PackWiseColor.accent)
                        VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                            Text(destination.displayName)
                                .font(PackWiseFont.rowTitle)
                                .foregroundStyle(PackWiseColor.textPrimary)
                            Text("\(shortDateSpan) · \(draft.tripType.title)")
                                .font(PackWiseFont.rowSubtitle)
                                .foregroundStyle(PackWiseColor.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.top, PackWiseSpacing.snug)
            }
            Spacer()
            Spacer()
        }
        .padding(PackWiseSpacing.loose)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PackWiseColor.screen)
        .transition(.opacity)
    }

    @ViewBuilder
    private func footer(for step: SetupStep) -> some View {
        if step == .review {
            Button(reviewCTA) {
                Task { await advance(from: step) }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canAdvance(for: step) || isBuilding)
            .padding(PackWiseSpacing.comfortable)
            .background(PackWiseColor.screen)
        }
    }

    private var reviewCTA: String {
        if isBuilding {
            return isEditing ? "Updating your packing list" : "Building your packing list"
        }
        return isEditing ? "Update Packing List" : "Build My Packing List"
    }

    private func canAdvance(for step: SetupStep) -> Bool {
        switch step {
        case .destination: draft.destination != nil
        case .dates: TripDateMath.isStartAllowed(draft.startDate) && draft.endDate >= draft.startDate
        default: true
        }
    }

    private func goBack() {
        if !stepPath.isEmpty {
            stepPath.removeLast()
        }
    }

    private func advance(from step: SetupStep) async {
        if step == .dates && !TripDateMath.isStartAllowed(draft.startDate) {
            dateError = "Start date must be today or later."
            return
        }
        dateError = nil
        if step != .review {
            if let next = SetupStep(rawValue: step.rawValue + 1) {
                stepPath.append(next)
            }
            return
        }
        await saveTrip()
    }

    private func prefillIfNeeded() {
        guard !didPrefill else { return }
        didPrefill = true
        if initialStep != .destination {
            stepPath = SetupStep.allCases.filter {
                $0 != .destination && $0.rawValue <= initialStep.rawValue
            }
        }
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
                laundryAccess: draft.laundry,
                userNotes: notes,
                contextChips: Array(draft.chips),
                party: party,
                on: existing
            )
            var context = existing.context(preferences: prefs, weather: weather)
            context.party = party
            if let enrichment = await ContextIntelligenceGate.noteEnrichment(notes: notes, context: context, intelligence: dependencies.intelligence) {
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
            travelMode: party.travelMode,
            laundryAccess: draft.laundry
        )

        var context = trip.context(preferences: prefs, weather: weather)
        context.party = party
        if let enrichment = await ContextIntelligenceGate.noteEnrichment(notes: notes, context: context, intelligence: dependencies.intelligence) {
            activities.append(contentsOf: enrichment.inferredActivities.filter { !activities.contains($0) })
            trip.activitiesRaw = activities.joined(separator: ",")
            var chips = Set(trip.contextChips)
            enrichment.inferredChips.forEach { chips.insert($0) }
            trip.contextChipsRaw = chips.map(\.rawValue).joined(separator: ",")
            context.activities = activities
            context.contextChips = chips
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
        addingCustom = false
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

/// Terse subtitles for the bag step.
///
/// `BagType.implication` is domain copy — it explains to the engine's user
/// what choosing a bag does to the list, and it is kept intact for that. At
/// six options on one screen those full sentences make the rows twice the
/// height the board draws, so the setup step gets its own short labels. This
/// lives here rather than in `Domain/` because it is presentation only.
/// Presentation-only, like `BagType.setupSubtitle` below. The middle option
/// deliberately reads as availability ("there if I need it") and the last as
/// intent ("planning on it") — the engine treats them differently, so the
/// wording must establish which one the user meant.
private extension LaundryAccess {
    var setupTitle: String {
        switch self {
        case .none: "No laundry"
        case .possible: "Laundry if I need it"
        case .planned: "Planning to do laundry"
        }
    }

    var setupSubtitle: String {
        switch self {
        case .none: "Pack for the full trip"
        case .possible: "Available, but not counting on it"
        case .planned: "Pack fewer clothes and wash mid-trip"
        }
    }

    var setupSymbol: String {
        switch self {
        case .none: "xmark.circle"
        case .possible: "circle.dotted"
        case .planned: "washer"
        }
    }

    var setupTint: Color {
        switch self {
        case .none: PackWiseColor.textSecondary
        case .possible: PackWiseColor.info
        case .planned: PackWiseColor.accent
        }
    }
}

private extension BagType {
    var setupSubtitle: String {
        switch self {
        case .personalItem: "Smallest and most compact"
        case .carryOn: "Favor versatile items and fewer backups"
        case .checked: "More flexibility"
        case .backpack: "Great for flexible travel"
        case .roadTripLuggage: "Traveling by car"
        case .notSure: "Choose later"
        }
    }
}
