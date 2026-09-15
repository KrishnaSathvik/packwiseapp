import SwiftUI

/// What the destination step shows (Task 9). One state at a time, so a
/// selected destination is never stated twice and an empty query is never
/// a bare field over blank space.
enum DestinationStepPhase: Equatable {
    /// No query: legitimate recents when the user has trips, else guidance.
    case empty(recents: [Destination])
    case searching
    case results([Destination])
    case noResults(query: String)
    case selected(Destination)

    static func resolve(
        selected: Destination?,
        query: String,
        isSearching: Bool,
        results: [Destination],
        recents: [Destination]
    ) -> DestinationStepPhase {
        if let selected { return .selected(selected) }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty(recents: recents) }
        if isSearching { return .searching }
        return results.isEmpty ? .noResults(query: trimmed) : .results(results)
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
    var search: any DestinationSearching
    /// Attaches test/weather fixtures to a live result (see `TripSetupView`).
    var prepare: (Destination) -> Destination

    @State private var results: [Destination] = []
    @State private var isSearching = false
    @FocusState private var fieldFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var phase: DestinationStepPhase {
        .resolve(selected: selected, query: query, isSearching: isSearching, results: results, recents: recents)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.loose) {
            if case .selected(let destination) = phase {
                confirmed(destination)
            } else {
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
                case .noResults(let text):
                    noResults(text)
                case .selected:
                    EmptyView()
                }
            }
        }
        // Re-runs on Change too, so an edited trip's prefilled name searches.
        .task(id: "\(query)|\(selected == nil)") {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard selected == nil else { return }
            guard !text.isEmpty else {
                results = []
                isSearching = false
                return
            }
            isSearching = true
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            let found = await search.search(query: text)
            guard !Task.isCancelled else { return }
            results = found.map(prepare)
            isSearching = false
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

    private func noResults(_ text: String) -> some View {
        HStack(alignment: .top, spacing: PackWiseSpacing.regular) {
            PackWiseIconBadge(symbol: "magnifyingglass", tint: .gray)
            VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                Text("No places found for “\(text)”")
                    .font(PackWiseFont.rowTitle)
                    .foregroundStyle(PackWiseColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Check the spelling, or try again when you're online.")
                    .font(PackWiseFont.rowSubtitle)
                    .foregroundStyle(PackWiseColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
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
                    selected = nil
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
        fieldFocused = false
        AccessibilityNotification.Announcement("\(destination.accessibilityName) selected").post()
    }
}
