import SwiftData
import SwiftUI

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
    /// stack's root; the bottom action pushes, Back pops.
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
        // each of the nine steps is a real push, not swapped-in content.
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
        TripSetupShell(
            step: step,
            leading: step == .destination ? .cancel : .back,
            primaryTitle: primaryTitle(for: step),
            primaryEnabled: canAdvance(for: step) && !isBuilding,
            onLeading: { step == .destination ? dismiss() : goBack() },
            onPrimary: { Task { await advance(from: step) } },
            primaryHint: hint(for: step)
        ) {
            stepContent(for: step)
        }
    }

    private func primaryTitle(for step: SetupStep) -> String {
        guard step == .review else { return "Next" }
        if isBuilding {
            return isEditing ? "Updating your packing list" : "Building your packing list"
        }
        return isEditing ? "Update Packing List" : "Build My Packing List"
    }

    private func hint(for step: SetupStep) -> String? {
        switch step {
        case .destination: "Choose a destination to continue."
        case .tripTypes: "Choose at least one trip type."
        default: nil
        }
    }

    @ViewBuilder
    private func stepContent(for step: SetupStep) -> some View {
        switch step {
        case .destination: destinationStep
        case .dates: datesStep
        case .travelers: travelersStep
        case .tripTypes: tripTypesStep
        case .activities: activitiesStep
        case .bags: bagsStep
        case .styleAndLaundry: styleAndLaundryStep
        case .preferences: preferencesStep
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

    // MARK: - 1. Destination

    private var destinationStep: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.comfortable) {
            HStack(spacing: PackWiseSpacing.snug) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PackWiseColor.textSecondary)
                TextField("Search city or destination", text: $search)
                    .font(PackWiseFont.rowTitle)
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
                                        .font(PackWiseFont.selectionGlyph)
                                        .foregroundStyle(PackWiseColor.onAccent, PackWiseColor.accent)
                                }
                            }
                            .padding(.vertical, PackWiseSpacing.regular)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(draft.destination == destination ? .isSelected : [])
                    }
                }
            }

            // Destination photography, with the name and a location pin
            // below. The destination redesign itself is Task 9.
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
            }
        }
    }

    // MARK: - 2. Dates

    private var datesStep: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
            PackWiseCard {
                PackWiseDateRangePicker(
                    start: $draft.startDate,
                    end: $draft.endDate,
                    earliest: Calendar.current.startOfDay(for: .now)
                )
            }

            // The span and its length are one fact, so they read as one row.
            PackWiseCard {
                HStack(spacing: PackWiseSpacing.regular) {
                    PackWiseIconBadge(symbol: "calendar", tint: PackWiseColor.accent)
                    VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                        Text(shortDateSpan)
                            .font(PackWiseFont.cardTitle)
                            .foregroundStyle(PackWiseColor.textPrimary)
                        Text("\(draft.duration.days) days · \(draft.duration.nights) nights")
                            .font(PackWiseFont.rowSubtitle)
                            .foregroundStyle(PackWiseColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }

            if let dateError {
                Label(dateError, systemImage: "exclamationmark.triangle")
                    .font(PackWiseFont.rowSubtitle)
                    .foregroundStyle(PackWiseColor.danger)
            }
        }
    }

    // MARK: - 3. Travelers

    private var travelersStep: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.loose) {
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
                        draft.setTravelMode(mode)
                    }
                }
            }

            if draft.travelMode == .family || draft.travelMode == .group {
                PackWiseCard {
                    VStack(spacing: PackWiseSpacing.regular) {
                        countRow(
                            title: "Other adults",
                            detail: "Besides you",
                            value: Binding(get: { draft.otherAdultCount }, set: { draft.setOtherAdultCount($0) }),
                            range: TripDraft.otherAdultRange(for: draft.travelMode)
                        )
                        if draft.travelMode == .family {
                            PackWiseRowDivider(inset: 0)
                            countRow(
                                title: "Children",
                                detail: "Infants to teens",
                                value: Binding(get: { draft.childProfiles.count }, set: { draft.setChildCount($0) }),
                                range: TripDraft.childRange
                            )
                        }
                    }
                }
            }

            if draft.travelMode != .solo {
                let party = draft.party
                ForEach(Array(draft.otherAdults.prefix(draft.otherAdultCount))) { adult in
                    if let traveler = party.travelers.first(where: { $0.id == adult.id }) {
                        adultDetails(label: party.positionLabel(for: traveler), adult: adultBinding(adult.id))
                    }
                }
                if draft.travelMode == .family {
                    ForEach(draft.childProfiles) { child in
                        if let traveler = party.travelers.first(where: { $0.id == child.id }) {
                            childDetails(label: party.positionLabel(for: traveler), child: childBinding(child.id))
                        }
                    }
                }
            }
        }
    }

    /// Bindings by traveler ID, never by array index: a count stepper can
    /// shrink the array while a row is still rendering.
    private func adultBinding(_ id: UUID) -> Binding<AdultDraft> {
        Binding(
            get: { draft.otherAdults.first { $0.id == id } ?? AdultDraft(id: id) },
            set: { value in
                if let index = draft.otherAdults.firstIndex(where: { $0.id == id }) { draft.otherAdults[index] = value }
            }
        )
    }

    private func childBinding(_ id: UUID) -> Binding<ChildDraft> {
        Binding(
            get: { draft.childProfiles.first { $0.id == id } ?? ChildDraft(id: id) },
            set: { value in
                if let index = draft.childProfiles.firstIndex(where: { $0.id == id }) { draft.childProfiles[index] = value }
            }
        )
    }

    private func countRow(
        title: String,
        detail: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        Stepper(value: value, in: range) {
            VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                HStack(spacing: PackWiseSpacing.snug) {
                    Text(title)
                        .font(PackWiseFont.rowTitle)
                        .foregroundStyle(PackWiseColor.textPrimary)
                    Text("\(value.wrappedValue)")
                        .font(PackWiseFont.numeral)
                        .foregroundStyle(PackWiseColor.accent)
                        .monospacedDigit()
                }
                Text(detail)
                    .font(PackWiseFont.rowSubtitle)
                    .foregroundStyle(PackWiseColor.textSecondary)
            }
        }
        .accessibilityValue("\(value.wrappedValue)")
    }

    private func adultDetails(label: String, adult: Binding<AdultDraft>) -> some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            PackWiseSectionHeader(title: label)
            PackWiseCard {
                VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
                    nameField(adult.name)
                    PackWiseRowDivider(inset: 0)
                    chipGroup(
                        title: "Devices",
                        helper: "Only what they're bringing. PackWise won't assume.",
                        options: ContextChip.travelerDevices,
                        selection: adult.chips,
                        titleFor: \.chipTitle
                    )
                    PackWiseRowDivider(inset: 0)
                    chipGroup(
                        title: "Anything different?",
                        helper: nil,
                        options: ContextChip.partnerDifferences,
                        selection: adult.chips,
                        titleFor: \.differenceTitle
                    )
                    PackWiseRowDivider(inset: 0)
                    TextField("Add note", text: adult.notes, axis: .vertical)
                        .font(PackWiseFont.rowTitle)
                        .lineLimit(1...4)
                }
            }
        }
    }

    private func childDetails(label: String, child: Binding<ChildDraft>) -> some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            PackWiseSectionHeader(title: label)
            PackWiseCard {
                VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
                    nameField(child.name)
                    PackWiseRowDivider(inset: 0)
                    HStack {
                        Text("Age group")
                            .font(PackWiseFont.rowTitle)
                            .foregroundStyle(PackWiseColor.textPrimary)
                        Spacer()
                        Picker("Age group", selection: child.ageGroup) {
                            ForEach(AgeGroup.allCases.filter { $0 != .adult }) { group in
                                Text(group.title).tag(group)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    // Young children get no device choices by default; a teen
                    // can bring their own.
                    if ChildDraft.offersDevices(child.wrappedValue.ageGroup) {
                        PackWiseRowDivider(inset: 0)
                        chipGroup(
                            title: "Devices",
                            helper: "Only what they're bringing. PackWise won't assume.",
                            options: ContextChip.travelerDevices,
                            selection: child.chips,
                            titleFor: \.chipTitle
                        )
                    }
                    let needs = ChildNeed.suggested(for: child.wrappedValue.ageGroup)
                    if !needs.isEmpty {
                        PackWiseRowDivider(inset: 0)
                        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                            Text("What should PackWise plan for?")
                                .font(PackWiseFont.rowSubtitle.weight(.semibold))
                                .foregroundStyle(PackWiseColor.textSecondary)
                            PackWiseFlowLayout {
                                ForEach(needs) { need in
                                    PackWiseChip(
                                        title: need.title,
                                        isSelected: child.wrappedValue.needs.contains(need)
                                    ) {
                                        if child.wrappedValue.needs.contains(need) {
                                            child.wrappedValue.needs.remove(need)
                                        } else {
                                            child.wrappedValue.needs.insert(need)
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

    /// A labeled optional name. The card heading is the stable position
    /// (Adult 1, Child 1), so the typed name appears only here.
    private func nameField(_ name: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
            Text("Name")
                .font(PackWiseFont.rowSubtitle.weight(.semibold))
                .foregroundStyle(PackWiseColor.textSecondary)
            TextField("Optional", text: name)
                .font(PackWiseFont.rowTitle)
                .textInputAutocapitalization(.words)
        }
    }

    private func chipGroup(
        title: String,
        helper: String?,
        options: [ContextChip],
        selection: Binding<Set<ContextChip>>,
        titleFor: KeyPath<ContextChip, String>
    ) -> some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                Text(title)
                    .font(PackWiseFont.rowSubtitle.weight(.semibold))
                    .foregroundStyle(PackWiseColor.textSecondary)
                if let helper {
                    Text(helper)
                        .font(PackWiseFont.rowSubtitle)
                        .foregroundStyle(PackWiseColor.textTertiary)
                }
            }
            PackWiseFlowLayout {
                ForEach(options) { chip in
                    PackWiseChip(
                        title: chip[keyPath: titleFor],
                        symbol: chip.symbol,
                        tint: chip.tint,
                        isSelected: selection.wrappedValue.contains(chip)
                    ) {
                        if selection.wrappedValue.contains(chip) {
                            selection.wrappedValue.remove(chip)
                        } else {
                            selection.wrappedValue.insert(chip)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 4. Trip types

    private var tripTypesStep: some View {
        TripSetupSelectionGrid(items: TripType.stableOrder) { type, layout in
            MultiSelectionCard(
                symbol: type.symbol,
                tint: type.tint,
                title: type.title,
                isSelected: draft.tripTypes.contains(type),
                layout: layout
            ) {
                draft.toggleTripType(type)
            }
        }
    }

    // MARK: - 5. Activities

    private var activitiesStep: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.comfortable) {
            TripSetupSelectionGrid(items: draft.visibleActivities(contracts: dependencies.rules.tripTypeContracts)) { id, layout in
                MultiSelectionCard(
                    symbol: PackWiseActivityStyle.symbol(for: id),
                    tint: PackWiseActivityStyle.tint(for: id),
                    title: activityTitle(id),
                    isSelected: draft.activities.contains(id),
                    layout: layout
                ) {
                    draft.toggleActivity(id)
                }
            }

            if addingCustom {
                HStack(spacing: PackWiseSpacing.snug) {
                    Image(systemName: "plus")
                        .foregroundStyle(PackWiseColor.accent)
                    TextField("Add something", text: $customText)
                        .font(PackWiseFont.rowTitle)
                        .focused($customFieldFocused)
                        .onSubmit { addCustom() }
                    if !customText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button("Add") { addCustom() }
                            .font(PackWiseFont.rowTitle)
                            .foregroundStyle(PackWiseColor.accent)
                    }
                }
                .padding(PackWiseSpacing.regular)
                .background(PackWiseColor.surfaceAlt, in: RoundedRectangle(cornerRadius: PackWiseRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PackWiseRadius.control, style: .continuous)
                        .strokeBorder(PackWiseColor.border, lineWidth: 1)
                }
            } else {
                Button {
                    addingCustom = true
                    customFieldFocused = true
                } label: {
                    Label("Add something", systemImage: "plus")
                        .font(PackWiseFont.rowTitle)
                        .foregroundStyle(PackWiseColor.accent)
                        .frame(minHeight: PackWiseSize.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 6. Bags

    private var bagsStep: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
            TripSetupSelectionGrid(items: BagType.stableOrder, columns: 1) { bag, layout in
                MultiSelectionCard(
                    symbol: bag.symbol,
                    tint: bag.tint,
                    title: bag.title,
                    subtitle: bag.setupSubtitle,
                    isSelected: draft.bagTypes.contains(bag),
                    layout: layout
                ) {
                    draft.toggleBag(bag)
                }
            }
            if draft.bagTypes.isEmpty {
                Label("Not sure yet? Skip this — PackWise won't apply a bag limit.", systemImage: "info.circle")
                    .font(PackWiseFont.rowSubtitle)
                    .foregroundStyle(PackWiseColor.textSecondary)
            }
        }
    }

    // MARK: - 7. Style and laundry

    private var styleAndLaundryStep: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.loose) {
            VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                PackWiseSectionHeader(title: "Packing style")
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

            VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                PackWiseSectionHeader(title: "Laundry")
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

    // MARK: - 8. Preferences

    /// Grouped by what each fact is about (design Section 11). Laundry is on
    /// the style step; the boolean chip stays in the enum for old trips.
    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.loose) {
            devicesYouAreBringing
            ForEach(PreferenceGroup.allCases, id: \.self) { group in
                VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                    PackWiseSectionHeader(title: group.title)
                    PackWiseFlowLayout {
                        ForEach(group.chips) { chip in
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
        }
    }

    /// Task 8.1: one device model. Your phone is implicit — PackWise runs on
    /// it — so it is stated, not offered as a fake choice. Every other device
    /// is an explicit choice stored on your traveler, never on the trip.
    private var devicesYouAreBringing: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            PackWiseSectionHeader(title: "Devices you're bringing")
            HStack(spacing: PackWiseSpacing.regular) {
                PackWiseIconBadge(symbol: ContextChip.bringingPhone.symbol, tint: ContextChip.bringingPhone.tint)
                VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                    Text("Phone")
                        .font(PackWiseFont.rowTitle)
                        .foregroundStyle(PackWiseColor.textPrimary)
                    Text("Included automatically")
                        .font(PackWiseFont.rowSubtitle)
                        .foregroundStyle(PackWiseColor.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .font(PackWiseFont.rowTitle)
                    .foregroundStyle(PackWiseColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, PackWiseSpacing.regular)
            .padding(.vertical, PackWiseSpacing.snug + 2)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(PackWiseColor.surfaceAlt, in: RoundedRectangle(cornerRadius: PackWiseRadius.control, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Phone, included automatically")
            // Devices are attributes of you, like the chips below — the same
            // chip treatment companions' device choices use.
            PackWiseFlowLayout {
                ForEach(ContextChip.primaryDevices) { chip in
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

    // MARK: - 9. Review

    /// One wrapping summary per decision, so nothing is hidden behind a
    /// combined line.
    private var reviewStep: some View {
        let party = draft.party
        return VStack(alignment: .leading, spacing: PackWiseSpacing.comfortable) {
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
                            .font(PackWiseFont.screenTitle)
                        Text(dateSpan)
                            .font(PackWiseFont.screenSubtitle)
                            .opacity(0.92)
                    }
                    .foregroundStyle(PackWiseColor.onAccent)
                    .padding(PackWiseSpacing.comfortable)
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: PackWiseRadius.card, style: .continuous))
            }

            PackWiseCard {
                VStack(spacing: 0) {
                    ForEach(Array(TripReviewSummary.sections(draft: draft, party: party, activityTitle: activityTitle).enumerated()), id: \.element.title) { index, section in
                        if index > 0 { PackWiseRowDivider() }
                        reviewSummaryBlock(section)
                    }
                }
            }
        }
    }

    private func reviewSummaryBlock(_ section: TripReviewSummary.Section) -> some View {
        HStack(alignment: .top, spacing: PackWiseSpacing.regular) {
            PackWiseIconBadge(symbol: section.symbol, tint: section.tint)
            VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                Text(section.title)
                    .font(PackWiseFont.rowSubtitle.weight(.semibold))
                    .foregroundStyle(PackWiseColor.textSecondary)
                Text(section.value)
                    .font(PackWiseFont.rowTitle)
                    .foregroundStyle(PackWiseColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, PackWiseSpacing.snug)
        .accessibilityElement(children: .combine)
    }

    private var dateSpan: String {
        "\(shortDateSpan) · \(draft.duration.days) days · \(draft.duration.nights) nights"
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
                            Text(shortDateSpan)
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

    // MARK: - Flow

    private func canAdvance(for step: SetupStep) -> Bool {
        switch step {
        case .destination: draft.destination != nil
        case .dates: TripDateMath.isStartAllowed(draft.startDate) && draft.endDate >= draft.startDate
        case .tripTypes: draft.hasTripType
        case .review: draft.destination != nil && draft.hasTripType
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
        if let next = step.next {
            stepPath.append(next)
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
        guard let destination = draft.destination, draft.hasTripType else { return }
        isBuilding = true
        let prefs = preferenceRecords.first?.preferences ?? .deviceDefaults()
        let duration = draft.duration
        let notes = draft.notes
        // Only what the user tapped. Notes and trip types never add or remove
        // an activity at save time.
        var activities = draft.activities
        let party = draft.party
        let repository = TripRepository(context: modelContext)

        let resolved = await TripWeatherRefresh.resolveForSetup(
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
                tripTypes: draft.tripTypes,
                activities: activities,
                bagTypes: draft.bagTypes,
                packingStyle: draft.packingStyle,
                laundryAccess: draft.laundry,
                userNotes: notes,
                contextChips: ContextChip.allCases.filter(draft.tripChips.contains),
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
            let diff = dependencies.engine.recommendationDiff(
                context: context,
                existing: existing.items.map(\.draft),
                overrides: existing.overrides.map(\.draft)
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
            tripType: TripType.stableOrder.first(where: draft.tripTypes.contains) ?? .other,
            activities: activities,
            bagType: .notSure,
            packingStyle: draft.packingStyle,
            status: .packing,
            userNotes: notes,
            contextChips: ContextChip.allCases.filter(draft.tripChips.contains),
            travelerCount: party.travelers.count,
            travelMode: party.travelMode,
            laundryAccess: draft.laundry
        )
        modelContext.insert(trip)
        try? repository.applyTripTypes(draft.tripTypes, on: trip)
        repository.attach(party: party, bagTypes: draft.bagTypes, on: trip)

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

    /// A typed activity the user explicitly adds. Known keywords normalize to
    /// their activity; anything else stays a custom, inert entry.
    private func addCustom() {
        let text = customText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let interpreted = dependencies.engine.interpretFreeTextActivities(text, selected: [])
        if interpreted.isEmpty {
            if !draft.activities.contains(where: { $0.caseInsensitiveCompare(text) == .orderedSame }) {
                draft.activities.append(text)
            }
        } else {
            for id in interpreted where !draft.activities.contains(id) {
                draft.activities.append(id)
            }
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
        TripReviewSummary.activityTitle(id)
    }
}

/// The About you / trip preference groups (design Section 11). Only known,
/// relevant controls appear. Devices are their own section above these
/// groups (Task 8.1), so no device chip appears here.
enum PreferenceGroup: CaseIterable {
    case health, clothingAndComfort, trip

    var title: String {
        switch self {
        case .health: "Health"
        case .clothingAndComfort: "Clothing & comfort"
        case .trip: "This trip"
        }
    }

    var chips: [ContextChip] {
        switch self {
        case .health: [.dailyMedication, .wearContacts]
        case .clothingAndComfort: [.usuallyWorkOut, .runWhileTraveling, .needFormalOutfit, .getColdEasily]
        case .trip: [.travelingInternationally]
        }
    }
}

/// Review's summaries, one per decision, as plain values so they are
/// testable. Empty bags read "Not sure yet".
enum TripReviewSummary {
    struct Section: Hashable {
        var title: String
        var symbol: String
        var tint: Color
        var value: String
    }

    static func sections(draft: TripDraft, party: TripParty, activityTitle: (String) -> String = activityTitle) -> [Section] {
        let travelers = party.travelers.map(party.label(for:)).joined(separator: ", ")
        return [
            Section(
                title: "Trip types",
                symbol: TripType.stableOrder.first(where: draft.tripTypes.contains)?.symbol ?? "suitcase",
                tint: PackWiseColor.accent,
                value: draft.tripTypes.isEmpty ? "None chosen" : TripType.stableOrder.filter(draft.tripTypes.contains).map(\.title).joined(separator: ", ")
            ),
            Section(
                title: "Travelers",
                symbol: party.travelMode.symbol,
                tint: party.travelMode.tint,
                value: party.usesSimpleList ? "Just you" : "\(party.travelerCountSummary) · \(travelers)"
            ),
            Section(
                title: "Activities",
                symbol: "figure.walk",
                tint: PackWiseColor.success,
                value: draft.activities.isEmpty ? "None chosen" : draft.activities.map(activityTitle).joined(separator: ", ")
            ),
            Section(
                title: "Bags",
                symbol: "suitcase",
                tint: PackWiseColor.info,
                value: draft.bagTypes.isEmpty ? "Not sure yet" : BagType.stableOrder.filter(draft.bagTypes.contains).map(\.title).joined(separator: ", ")
            ),
            Section(
                title: "Packing style",
                symbol: draft.packingStyle.symbol,
                tint: draft.packingStyle.tint,
                value: draft.packingStyle.title
            ),
            Section(
                title: "Laundry",
                symbol: draft.laundry.setupSymbol,
                tint: draft.laundry.setupTint,
                value: draft.laundry.setupTitle
            ),
            Section(
                title: "Your devices",
                symbol: ContextChip.bringingPhone.symbol,
                tint: ContextChip.bringingPhone.tint,
                value: (["Phone"] + ContextChip.primaryDevices.filter(draft.chips.contains).map(\.chipTitle)).joined(separator: ", ")
            ),
            Section(
                title: "Preferences",
                symbol: "slider.horizontal.3",
                tint: PackWiseColor.accent,
                value: {
                    let chips = ContextChip.allCases.filter { draft.tripChips.contains($0) && !ContextChip.primaryDevices.contains($0) }
                    return chips.isEmpty ? "None" : chips.map(\.chipTitle).joined(separator: ", ")
                }()
            ),
        ]
    }

    static func activityTitle(_ id: String) -> String {
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
        case "camping": "Camping"
        case "skiing": "Skiing"
        default: id.prefix(1).uppercased() + id.dropFirst()
        }
    }
}

/// Presentation-only copy for the laundry control. The middle option reads as
/// availability ("there if I need it") and the last as intent ("planning on
/// it") — the engine treats them differently.
extension LaundryAccess {
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

/// Terse subtitles for the bag step; `BagType.implication` stays the fuller
/// domain copy.
extension BagType {
    var setupSubtitle: String {
        switch self {
        case .personalItem: "Fits under the seat"
        case .carryOn: "Overhead bin"
        case .checked: "More room for extras"
        case .backpack: "Carried on your back"
        case .roadTripLuggage: "Traveling by car"
        case .notSure: "Choose later"
        }
    }
}
