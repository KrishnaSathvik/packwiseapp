import SwiftUI

/// What the destination step shows (Task 9). One state at a time, so a
/// selected destination is never stated twice and an empty query is never
/// a bare field over blank space.
enum DestinationStepPhase: Equatable {
    /// No query: legitimate recents when the user has trips, else guidance.
    case empty(recents: [Destination])
    case searching
    case results([Destination])
    /// The search ran and nothing matched.
    case noMatches(query: String)
    /// The search could not run. Any selected destination is untouched.
    case unavailable(query: String)
    case selected(Destination)

    /// - Parameter isChanging: the user tapped Change. The selected
    ///   destination stays selected until another result is chosen, so a
    ///   failed search never loses it.
    static func resolve(
        selected: Destination?,
        isChanging: Bool = false,
        query: String,
        outcome: DestinationSearchOutcome,
        recents: [Destination]
    ) -> DestinationStepPhase {
        if let selected, !isChanging { return .selected(selected) }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty(recents: recents) }
        switch outcome {
        case .results(let destinations): return .results(destinations)
        case .noMatches: return .noMatches(query: trimmed)
        case .unavailable: return .unavailable(query: trimmed)
        case .idle, .searching: return .searching
        }
    }
}

/// The outcome of the latest destination search.
enum DestinationSearchOutcome: Equatable {
    case idle
    case searching
    case results([Destination])
    case noMatches(query: String)
    case unavailable(query: String)
}

/// Runs destination searches for the step and records a truthful outcome.
/// It never reads or writes the selected destination.
@MainActor
@Observable
final class DestinationSearchModel {
    private(set) var outcome: DestinationSearchOutcome = .idle
    private let provider: any DestinationSearching
    private let prepare: (Destination) -> Destination

    init(provider: any DestinationSearching, prepare: @escaping (Destination) -> Destination = { $0 }) {
        self.provider = provider
        self.prepare = prepare
    }

    /// Debounces, then searches. A cancelled search (the query changed)
    /// records nothing.
    func search(_ query: String, debounce: Duration = .zero) async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            outcome = .idle
            return
        }
        outcome = .searching
        if debounce > .zero {
            try? await Task.sleep(for: debounce)
        }
        guard !Task.isCancelled else { return }
        do {
            let found = try await provider.search(query: text)
            guard !Task.isCancelled else { return }
            outcome = found.isEmpty ? .noMatches(query: text) : .results(found.map(prepare))
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            outcome = .unavailable(query: text)
        }
    }
}

/// Recent destinations come only from the user's own trips: newest first,
/// one row per place, at most `limit`. Never a fabricated "popular" list.
enum DestinationRecents {
    static let limit = 3

    static func recents(from trips: [(destination: Destination, createdAt: Date)], limit: Int = limit) -> [Destination] {
        var seen: Set<String> = []
        return trips
            .sorted { $0.createdAt > $1.createdAt }
            .map(\.destination)
            .filter { seen.insert(identity($0)).inserted }
            .prefix(limit)
            .map { $0 }
    }

    private static func identity(_ destination: Destination) -> String {
        let name = destination.city.isEmpty ? destination.displayName : destination.city
        return "\(name.lowercased())|\(destination.region.lowercased())|\(destination.countryCode.lowercased())"
    }
}

extension Destination {
    /// The place name as a result title and hero title.
    var presentationTitle: String {
        displayName.isEmpty ? city : displayName
    }

    /// "Illinois, United States" — the geographic context under a place name.
    /// MapKit returns postal abbreviations for some countries' regions; they
    /// expand here, at display time, so the stored destination is untouched.
    var presentationSubtitle: String {
        let expandedRegion = DestinationRegionNames.expand(region, countryCode: countryCode)
        return [expandedRegion, country]
            .filter { !$0.isEmpty && $0.caseInsensitiveCompare(presentationTitle) != .orderedSame }
            .joined(separator: ", ")
    }

    /// One phrase for VoiceOver: "Khammam, Telangana, India".
    var accessibilityName: String {
        [presentationTitle, presentationSubtitle].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

enum DestinationRegionNames {
    static func expand(_ region: String, countryCode: String) -> String {
        let key = region.trimmingCharacters(in: .whitespaces).uppercased()
        switch countryCode.uppercased() {
        case "US": return unitedStates[key] ?? region
        case "CA": return canada[key] ?? region
        default: return region
        }
    }

    private static let unitedStates: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California",
        "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware", "DC": "District of Columbia", "FL": "Florida",
        "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa",
        "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland",
        "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi", "MO": "Missouri",
        "MT": "Montana", "NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey",
        "NM": "New Mexico", "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio",
        "OK": "Oklahoma", "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina",
        "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont",
        "VA": "Virginia", "WA": "Washington", "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming",
        "PR": "Puerto Rico",
    ]

    private static let canada: [String: String] = [
        "AB": "Alberta", "BC": "British Columbia", "MB": "Manitoba", "NB": "New Brunswick",
        "NL": "Newfoundland and Labrador", "NS": "Nova Scotia", "NT": "Northwest Territories", "NU": "Nunavut",
        "ON": "Ontario", "PE": "Prince Edward Island", "QC": "Quebec", "SK": "Saskatchewan", "YT": "Yukon",
    ]
}

/// Step 1's content inside the shared setup shell.
struct DestinationStepContent: View {
    @Binding var selected: Destination?
    @Binding var query: String
    var recents: [Destination]
    @State private var model: DestinationSearchModel
    @State private var isChanging = false
    @State private var retryToken = 0
    @FocusState private var fieldFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// - Parameter prepare: attaches test/weather fixtures to a live result
    ///   (see `TripSetupView`).
    init(
        selected: Binding<Destination?>,
        query: Binding<String>,
        recents: [Destination],
        search: any DestinationSearching,
        prepare: @escaping (Destination) -> Destination,
        startsChanging: Bool = false
    ) {
        _selected = selected
        _query = query
        self.recents = recents
        _model = State(initialValue: DestinationSearchModel(provider: search, prepare: prepare))
        _isChanging = State(initialValue: startsChanging)
    }

    private var phase: DestinationStepPhase {
        .resolve(selected: selected, isChanging: isChanging, query: query, outcome: model.outcome, recents: recents)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.loose) {
            if case .selected(let destination) = phase {
                confirmed(destination)
            } else {
                if isChanging, let kept = selected {
                    keepRow(kept)
                }
                searchField
                switch phase {
                case .empty(let recents) where !recents.isEmpty:
                    rowGroup(title: "Recent destinations", destinations: recents, symbol: "clock.arrow.circlepath")
                case .empty:
                    guidance
                case .searching:
                    searchingRow
                case .results(let destinations):
                    rowGroup(title: nil, destinations: destinations, symbol: "mappin.and.ellipse")
                case .noMatches:
                    message(symbol: "magnifyingglass", title: "No matches",
                            detail: "We couldn't find that destination. Try another city, region, or country.")
                case .unavailable:
                    message(symbol: "wifi.exclamationmark", title: "Can't search right now",
                            detail: "Check your connection and try again.", retry: true)
                case .selected:
                    EmptyView()
                }
            }
        }
        // Re-runs on Change and Try Again too, so an edited trip's
        // prefilled name searches.
        .task(id: "\(query)|\(selected == nil || isChanging)|\(retryToken)") {
            guard selected == nil || isChanging else { return }
            await model.search(query, debounce: .milliseconds(280))
        }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: PackWiseSpacing.snug) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(PackWiseColor.textSecondary)
                .accessibilityHidden(true)
            TextField("Search destination", text: $query)
                .font(PackWiseFont.rowTitle)
                .foregroundStyle(PackWiseColor.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .focused($fieldFocused)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(PackWiseColor.textTertiary)
                        .frame(minWidth: PackWiseSize.tapTarget, minHeight: PackWiseSize.tapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, PackWiseSpacing.regular)
        .frame(minHeight: PackWiseSize.tapTarget + PackWiseSpacing.tight)
        .background(PackWiseColor.surfaceAlt, in: RoundedRectangle(cornerRadius: PackWiseRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PackWiseRadius.control, style: .continuous)
                .strokeBorder(PackWiseColor.border, lineWidth: 1)
        }
    }

    private func rowGroup(title: String?, destinations: [Destination], symbol: String) -> some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            if let title {
                PackWiseSectionHeader(title: title)
            }
            PackWiseCard {
                VStack(spacing: 0) {
                    ForEach(Array(destinations.enumerated()), id: \.element.id) { index, destination in
                        if index > 0 { PackWiseRowDivider() }
                        resultRow(destination, symbol: symbol)
                    }
                }
            }
        }
    }

    private func resultRow(_ destination: Destination, symbol: String) -> some View {
        Button {
            choose(destination)
        } label: {
            HStack(spacing: PackWiseSpacing.regular) {
                Image(systemName: symbol)
                    .font(PackWiseFont.rowTitle)
                    .foregroundStyle(PackWiseColor.textTertiary)
                    .frame(width: PackWiseSize.badge * 0.7)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                    Text(destination.presentationTitle)
                        .font(PackWiseFont.rowTitle)
                        .foregroundStyle(PackWiseColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !destination.presentationSubtitle.isEmpty {
                        Text(destination.presentationSubtitle)
                            .font(PackWiseFont.rowSubtitle)
                            .foregroundStyle(PackWiseColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, PackWiseSpacing.snug)
            .frame(minHeight: PackWiseSize.tapTarget + PackWiseSpacing.snug)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(destination.accessibilityName)
        .accessibilityHint("Selects this destination.")
        .accessibilityAddTraits(.isButton)
    }

    private var searchingRow: some View {
        HStack(spacing: PackWiseSpacing.regular) {
            ProgressView()
                .tint(PackWiseColor.textSecondary)
            Text("Searching…")
                .font(PackWiseFont.rowSubtitle)
                .foregroundStyle(PackWiseColor.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PackWiseSpacing.tight)
        .frame(minHeight: PackWiseSize.tapTarget)
        .accessibilityElement(children: .combine)
    }

    private func message(symbol: String, title: String, detail: String, retry: Bool = false) -> some View {
        HStack(alignment: .top, spacing: PackWiseSpacing.regular) {
            PackWiseIconBadge(symbol: symbol, tint: .gray)
            VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                Text(title)
                    .font(PackWiseFont.rowTitle)
                    .foregroundStyle(PackWiseColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(PackWiseFont.rowSubtitle)
                    .foregroundStyle(PackWiseColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if retry {
                    Button("Try Again") { retryToken += 1 }
                        .font(PackWiseFont.rowTitle)
                        .foregroundStyle(PackWiseColor.accent)
                        .frame(minHeight: PackWiseSize.tapTarget)
                        .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
    }

    /// While changing, the current destination stays selected and one tap
    /// keeps it.
    private func keepRow(_ destination: Destination) -> some View {
        HStack(spacing: PackWiseSpacing.snug) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(PackWiseColor.accent)
                .accessibilityHidden(true)
            Text("Selected: \(destination.presentationTitle)")
                .font(PackWiseFont.rowSubtitle)
                .foregroundStyle(PackWiseColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: PackWiseSpacing.snug)
            Button("Keep") {
                isChanging = false
                fieldFocused = false
            }
            .font(PackWiseFont.rowTitle)
            .foregroundStyle(PackWiseColor.accent)
            .frame(minWidth: PackWiseSize.tapTarget, minHeight: PackWiseSize.tapTarget)
            .buttonStyle(.plain)
            .accessibilityLabel("Keep \(destination.presentationTitle)")
        }
    }

    /// No recents yet: what the destination is used for, in three quiet
    /// rows. Every line describes current behavior.
    private var guidance: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
            PackWiseSectionHeader(title: "How PackWise uses it")
            guidanceRow("building.2", tint: PackWiseColor.accent, "A city works best", "A region or country works too.")
            guidanceRow("cloud.sun", tint: .orange, "Weather for your dates", "Your destination and dates shape the forecast your list plans for.")
            guidanceRow("globe", tint: .teal, "Trips abroad", "Outside your home country, PackWise adds the travel documents to check.")
        }
    }

    private func guidanceRow(_ symbol: String, tint: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: PackWiseSpacing.regular) {
            PackWiseIconBadge(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                Text(title)
                    .font(PackWiseFont.rowTitle)
                    .foregroundStyle(PackWiseColor.textPrimary)
                Text(detail)
                    .font(PackWiseFont.rowSubtitle)
                    .foregroundStyle(PackWiseColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Confirmed

    /// The destination, stated once: a small map of the place, its name and
    /// context, a selected mark that is not color alone, and Change.
    private func confirmed(_ destination: Destination) -> some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: PackWiseSpacing.regular))
            : AnyLayout(HStackLayout(alignment: .center, spacing: PackWiseSpacing.regular))
        return PackWiseCard {
            layout {
                HStack(alignment: .center, spacing: PackWiseSpacing.regular) {
                    DestinationVisualView(
                        destination: destination,
                        purpose: .tripThumbnail,
                        accessibilityLabel: "Map of \(destination.presentationTitle)"
                    )
                    .frame(width: PackWiseSize.destinationThumbnail, height: PackWiseSize.destinationThumbnail)
                    .clipShape(RoundedRectangle(cornerRadius: PackWiseRadius.control, style: .continuous))
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                        Label("Selected", systemImage: "checkmark.circle.fill")
                            .font(PackWiseFont.microLabel)
                            .foregroundStyle(PackWiseColor.accent)
                        Text(destination.presentationTitle)
                            .font(PackWiseFont.cardTitle)
                            .foregroundStyle(PackWiseColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !destination.presentationSubtitle.isEmpty {
                            Text(destination.presentationSubtitle)
                                .font(PackWiseFont.rowSubtitle)
                                .foregroundStyle(PackWiseColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Selected destination: \(destination.accessibilityName)")
                    .accessibilityAddTraits(.isSelected)
                }
                if !stacked { Spacer(minLength: 0) }
                Button("Change") {
                    isChanging = true
                    fieldFocused = true
                }
                .font(PackWiseFont.rowTitle)
                .foregroundStyle(PackWiseColor.accent)
                .frame(minWidth: PackWiseSize.tapTarget, minHeight: PackWiseSize.tapTarget)
                .buttonStyle(.plain)
                .accessibilityLabel("Change destination")
            }
        }
    }

    private func choose(_ destination: Destination) {
        selected = destination
        isChanging = false
        fieldFocused = false
        AccessibilityNotification.Announcement("\(destination.accessibilityName) selected").post()
    }
}
