#if DEBUG
import SwiftData
import SwiftUI

/// Launches a single screen against a seeded in-memory trip, so the UI
/// conformance pass can be photographed against the reference board.
///
/// `ImageRenderer` cannot render `List`, `ScrollView`, or `NavigationStack` —
/// it produces SwiftUI's unavailable glyph — so screens have to be captured
/// from the running app. Reaching Trip Detail by hand means walking onboarding
/// and the whole of trip setup for every appearance and text size, which is
/// why this exists.
///
/// Compiled out of Release along with everything it touches, exactly like
/// `DeveloperToolsView`. Nothing here writes to the real store: the seed lives
/// in its own in-memory container.
///
///     xcrun simctl launch booted com.packwiseapp.app -PackWiseScreen tripDetail
enum DebugPreviewScreen: String {
    case tripDetail
    case tripDetailSeasonal
    case packingList
    case packingListScrolled
    /// The family trip's generated list, aggregated in the All scope (Task 11).
    case packingListFamily
    /// Task 11 list states: couple All; family per-person and Shared scopes;
    /// the family list scrolled; each Status; searches; and opened groups.
    case packingListCouple
    case packingListFamilyYou
    case packingListFamilyAdult1
    case packingListFamilyChild1
    case packingListFamilyShared
    case packingListFamilyMiddle
    case packingListFamilyBottom
    case packingListFamilyToPack
    case packingListFamilyPacked
    case packingListFamilyImportant
    case packingListFamilyHidePacked
    case packingListFamilySearchItem
    case packingListFamilySearchTraveler
    case packingListFamilySearchNone
    case packingListFamilyGroupTshirts
    case packingListFamilyGroupToothbrush
    /// Legacy full-screen item detail plus real-sheet states for comparison.
    case itemDetail
    case itemDetailSheet
    case itemDetailLarge
    case addItem
    case addItemCategory
    case tripsHome
    case tripsHomeEmpty
    case setupDestination
    case setupDestinationFallback
    /// Task 9 destination states: empty with no trips, recents, searching,
    /// compact results, confirmed places, a long name, and offline visuals.
    case setupDestinationEmpty
    case setupDestinationRecents
    case setupDestinationSearching
    case setupDestinationResults
    case setupDestinationChicago
    case setupDestinationKhammam
    case setupDestinationLong
    case setupDestinationOffline
    /// Task 9.1 search states: a successful search with no matches, a failed
    /// search, and a failed search while changing a selected destination.
    case setupDestinationNoMatch
    case setupDestinationUnavailable
    case setupDestinationUnavailableKept
    /// Review's destination hero on a map (Khammam) and offline (graphical).
    case setupReviewMap
    case setupReviewOffline
    /// Trip Detail's hero with the map provider failing.
    case tripDetailOffline
    /// Task 9.1 status bar: Trip Detail over a trusted photo and while the
    /// visual is still loading; then after popping back to, and pushing on
    /// to, light screens.
    case tripDetailTrusted
    case tripDetailLoading
    case statusBarAfterPop
    case statusBarAfterPush
    /// Task 9.1 weather line: a long destination with no forecast yet.
    case tripsHomeLong
    case setupDates
    case setupTravelers
    case setupTravelersFamily
    case setupTravelersFamilyDetails
    case setupTravelersGroup
    case setupTripTypes
    case setupActivities
    case setupBags
    case setupStyleLaundry
    case setupPreferences
    case setupReview
    case reviewChanges
    case weatherChanged
    case me
    case onboarding
    case onboardingTrip
    case onboardingPersonal
    case weatherDetail
    case weatherDetailSeasonal
    case tripDetailCompleted
    /// Task 10: Trip Detail with every one of the eleven categories non-empty,
    /// opened at the top and opened at the bottom (simctl cannot scroll).
    case tripDetailAllCategories
    case tripDetailAllCategoriesMiddle
    case tripDetailAllCategoriesScrolled

    /// Where the screen's page opens, when a capture needs more than its top.
    var initialScrollAnchor: UnitPoint? {
        switch self {
        case .tripDetailAllCategoriesMiddle: .center
        case .tripDetailAllCategoriesScrolled: .bottom
        default: nil
        }
    }

    /// The screen named by `-PackWiseScreen`, if the app was launched with one.
    static var requested: DebugPreviewScreen? {
        guard let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-PackWiseScreen"),
              index + 1 < ProcessInfo.processInfo.arguments.count else {
            return nil
        }
        return DebugPreviewScreen(rawValue: ProcessInfo.processInfo.arguments[index + 1])
    }
}

struct DebugPreviewScene: View {
    let screen: DebugPreviewScreen

    @State private var seed = DebugTripSeed()

    var body: some View {
        content
            .modelContainer(screen == .tripsHomeEmpty ? DebugTripSeed.emptyContainer : seed.container)
    }

    private func familyList(_ state: PackingListDebugState) -> some View {
        NavigationStack { PackingListView(trip: seed.familyTrip, debugPresentation: .list(state)) }
    }

    /// The later steps need a populated draft, so they open on the seeded trip.
    private func setup(_ step: SetupStep) -> some View {
        TripSetupView(existingTrip: seed.trip, initialStep: step)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch screen {
            case .tripDetail:
                NavigationStack { TripDetailView(trip: seed.trip) }
            case .tripDetailAllCategories, .tripDetailAllCategoriesMiddle, .tripDetailAllCategoriesScrolled:
                NavigationStack { TripDetailView(trip: seed.allCategoriesTrip) }
            case .tripDetailSeasonal:
                NavigationStack { TripDetailView(trip: seed.seasonalTrip) }
            case .packingList:
                NavigationStack { PackingListView(trip: seed.trip) }
            case .packingListScrolled:
                NavigationStack { PackingListView(trip: seed.trip, focusedCategory: .toiletries) }
            case .packingListFamily:
                NavigationStack { PackingListView(trip: seed.familyTrip) }
            case .packingListCouple:
                NavigationStack { PackingListView(trip: seed.coupleTrip) }
            case .packingListFamilyYou:
                familyList(PackingListDebugState(scope: .traveler(0)))
            case .packingListFamilyAdult1:
                familyList(PackingListDebugState(scope: .traveler(1)))
            case .packingListFamilyChild1:
                familyList(PackingListDebugState(scope: .traveler(2)))
            case .packingListFamilyShared:
                familyList(PackingListDebugState(scope: .shared))
            case .packingListFamilyMiddle:
                familyList(PackingListDebugState(scrollTo: .toiletries))
            case .packingListFamilyBottom:
                familyList(PackingListDebugState(scrollTo: .travelComfort))
            case .packingListFamilyToPack:
                familyList(PackingListDebugState(status: .toPack))
            case .packingListFamilyPacked:
                familyList(PackingListDebugState(status: .packed))
            case .packingListFamilyImportant:
                familyList(PackingListDebugState(status: .important))
            case .packingListFamilyHidePacked:
                familyList(PackingListDebugState(hidePacked: true, scrollTo: .toiletries))
            case .packingListFamilySearchItem:
                familyList(PackingListDebugState(search: "tooth"))
            case .packingListFamilySearchTraveler:
                familyList(PackingListDebugState(search: "Maya"))
            case .packingListFamilySearchNone:
                familyList(PackingListDebugState(search: "snorkel mask"))
            case .packingListFamilyGroupTshirts:
                familyList(PackingListDebugState(openGroup: "clothing.tshirt"))
            case .packingListFamilyGroupToothbrush:
                familyList(PackingListDebugState(openGroup: "toiletries.toothbrush"))
            case .tripsHome, .tripsHomeEmpty:
                TripsHomeView()
            case .setupDestination:
                setup(.destination)
            case .setupDestinationFallback:
                TripSetupView(existingTrip: seed.completedTrip, initialStep: .destination)
            case .setupDestinationEmpty:
                TripSetupView()
                    .modelContainer(DebugTripSeed.emptyContainer)
            case .setupDestinationRecents:
                TripSetupView()
            case .setupDestinationNoMatch:
                TripSetupView(captureSearch: DebugDestinationSearch(mode: .noMatches), captureQuery: "Zzqxv")
                    .modelContainer(DebugTripSeed.emptyContainer)
            case .setupDestinationUnavailable:
                TripSetupView(captureSearch: DebugDestinationSearch(mode: .fails), captureQuery: "Khammam")
                    .modelContainer(DebugTripSeed.emptyContainer)
            case .setupDestinationUnavailableKept:
                TripSetupView(captureSearch: DebugDestinationSearch(mode: .fails), captureQuery: "Khammam",
                              captureDestination: DebugDestinationSearch.chicago, captureChanging: true)
            case .setupDestinationSearching:
                TripSetupView(captureSearch: DebugDestinationSearch(mode: .suspends), captureQuery: "Kham")
                    .modelContainer(DebugTripSeed.emptyContainer)
            case .setupDestinationResults:
                TripSetupView(captureSearch: DebugDestinationSearch(), captureQuery: "Chi")
                    .modelContainer(DebugTripSeed.emptyContainer)
            case .setupDestinationChicago:
                TripSetupView(captureDestination: DebugDestinationSearch.chicago)
            case .setupDestinationKhammam:
                TripSetupView(captureDestination: DebugDestinationSearch.khammam)
            case .setupDestinationLong:
                TripSetupView(captureDestination: DebugDestinationSearch.longName)
            case .setupDestinationOffline:
                TripSetupView(captureDestination: DebugDestinationSearch.khammam)
                    .environment(\.destinationVisuals, DebugTripSeed.offlineVisuals)
            case .setupReviewMap:
                TripSetupView(existingTrip: seed.familyTrip, initialStep: .review, captureDestination: DebugDestinationSearch.khammam)
            case .setupReviewOffline:
                TripSetupView(existingTrip: seed.familyTrip, initialStep: .review, captureDestination: DebugDestinationSearch.longName)
                    .environment(\.destinationVisuals, DebugTripSeed.offlineVisuals)
            case .tripDetailOffline:
                NavigationStack { TripDetailView(trip: seed.trip) }
                    .environment(\.destinationVisuals, DebugTripSeed.offlineVisuals)
            case .tripDetailTrusted:
                NavigationStack { TripDetailView(trip: seed.trip) }
                    .environment(\.destinationVisuals, DebugTripSeed.trustedVisuals)
            case .tripDetailLoading:
                NavigationStack { TripDetailView(trip: seed.trip) }
                    .environment(\.destinationVisuals, DebugTripSeed.loadingVisuals)
            case .statusBarAfterPop:
                DebugStatusBarNavigation(trip: seed.trip, pushesOnward: false)
            case .statusBarAfterPush:
                DebugStatusBarNavigation(trip: seed.trip, pushesOnward: true)
            case .tripsHomeLong:
                TripsHomeView()
                    .modelContainer(DebugTripSeed.longDestinationContainer)
            case .setupDates:
                setup(.dates)
            case .setupTravelers:
                setup(.travelers)
            case .setupTravelersFamily:
                TripSetupView(existingTrip: seed.familyTrip, initialStep: .travelers)
            case .setupTravelersFamilyDetails:
                TripSetupView(existingTrip: seed.familyTrip, initialStep: .travelers)
                    .environment(\.setupCaptureScrollAnchor, UnitPoint(x: 0.5, y: 0.28))
            case .setupTravelersGroup:
                TripSetupView(existingTrip: seed.groupTrip, initialStep: .travelers)
                    .environment(\.setupCaptureScrollAnchor, UnitPoint(x: 0.5, y: 0.3))
            case .setupTripTypes:
                setup(.tripTypes)
            case .setupActivities:
                setup(.activities)
            case .setupBags:
                setup(.bags)
            case .setupStyleLaundry:
                setup(.styleAndLaundry)
            case .setupPreferences:
                setup(.preferences)
            case .setupReview:
                TripSetupView(existingTrip: seed.familyTrip, initialStep: .review)
            case .reviewChanges:
                NavigationStack {
                    RecommendationDiffScreen(
                        diff: DebugTripSeed.sampleDiff,
                        trip: seed.trip,
                        onFinished: {}
                    )
                }
            case .me:
                MeView()
            case .onboarding:
                OnboardingView {}
            case .onboardingTrip:
                OnboardingView(onFinished: {}, initialPage: 1)
            case .onboardingPersonal:
                OnboardingView(onFinished: {}, initialPage: 2)
            case .weatherDetail:
                NavigationStack {
                    WeatherDetailView(
                        destinationName: "Chicago",
                        dateLine: "Sep 12 – Sep 16",
                        weather: seed.trip.weatherSnapshots.first?.weatherContext
                            ?? DebugTripSeed.sampleForecast,
                        impacts: [],
                        usesFahrenheit: true,
                        rainThreshold: 0.35,
                        uvThreshold: 6,
                        windThreshold: 15
                    )
                }
            case .weatherDetailSeasonal:
                NavigationStack {
                    WeatherDetailView(
                        destinationName: seed.seasonalTrip.destinationDisplayName,
                        dateLine: "Nov 4 – Nov 11",
                        weather: .seasonal(),
                        impacts: [],
                        usesFahrenheit: true,
                        rainThreshold: 0.35,
                        uvThreshold: 6,
                        windThreshold: 15
                    )
                }
            case .tripDetailCompleted:
                NavigationStack { TripDetailView(trip: seed.completedTrip) }
            case .weatherChanged:
                NavigationStack {
                    ScrollView {
                        PackWiseCard {
                            WeatherChangedCard(proposal: DebugTripSeed.sampleProposal(tripID: seed.trip.id)) {}
                        }
                        .padding(PackWiseSpacing.comfortable)
                    }
                    .background(PackWiseColor.screen)
                    .navigationTitle("Chicago")
                    .navigationBarTitleDisplayMode(.inline)
                }
            case .itemDetail:
                if let item = seed.trip.items.first(where: { $0.displayName == "Rain jacket" }) {
                    NavigationStack {
                        ItemDetailView(
                            item: item,
                            travelers: seed.trip.party.travelers,
                            showsAssignment: false,
                            onNotNeeded: {}
                        )
                    }
                }
            case .itemDetailSheet:
                NavigationStack {
                    PackingListView(trip: seed.trip, debugPresentation: .itemDetailMedium)
                }
            case .itemDetailLarge:
                NavigationStack {
                    PackingListView(trip: seed.trip, debugPresentation: .itemDetailLarge)
                }
            case .addItem:
                NavigationStack {
                    PackingListView(trip: seed.trip, debugPresentation: .addItem)
                }
            case .addItemCategory:
                NavigationStack {
                    PackingListView(trip: seed.trip, debugPresentation: .addItemCategory)
                }
            }
        }
    }
}

/// Capture-only destination search: real places with their real
/// coordinates, returned without the network, or never (to hold the
/// searching state on screen).
struct DebugDestinationSearch: DestinationSearching {
    enum Mode: Sendable { case results, suspends, noMatches, fails }
    var mode: Mode = .results

    static let chicago = Destination(
        displayName: "Chicago", city: "Chicago", region: "IL", country: "United States", countryCode: "US",
        latitude: 41.8781, longitude: -87.6298, timeZone: "America/Chicago", mapKitIdentifier: nil, fixtureID: nil
    )
    static let khammam = Destination(
        displayName: "Khammam", city: "Khammam", region: "Telangana", country: "India", countryCode: "IN",
        latitude: 17.2473, longitude: 80.1514, timeZone: "Asia/Kolkata", mapKitIdentifier: nil, fixtureID: nil
    )
    static let longName = Destination(
        displayName: "Saint-Rémy-de-Provence", city: "Saint-Rémy-de-Provence", region: "Provence-Alpes-Côte d'Azur",
        country: "France", countryCode: "FR", latitude: 43.7888, longitude: 4.8317, timeZone: "Europe/Paris",
        mapKitIdentifier: nil, fixtureID: nil
    )

    func search(query: String) async throws -> [Destination] {
        switch mode {
        case .suspends:
            try await Task.sleep(for: .seconds(3600))
            return []
        case .noMatches:
            return []
        case .fails:
            throw DestinationSearchError.unavailable
        case .results:
            break
        }
        return [
            Self.chicago,
            Destination(displayName: "Chicago Heights", city: "Chicago Heights", region: "IL", country: "United States", countryCode: "US",
                        latitude: 41.5061, longitude: -87.6356, timeZone: "America/Chicago", mapKitIdentifier: nil, fixtureID: nil),
            Destination(displayName: "Chico", city: "Chico", region: "CA", country: "United States", countryCode: "US",
                        latitude: 39.7285, longitude: -121.8375, timeZone: "America/Los_Angeles", mapKitIdentifier: nil, fixtureID: nil),
            Destination(displayName: "Chiang Mai", city: "Chiang Mai", region: "Chiang Mai", country: "Thailand", countryCode: "TH",
                        latitude: 18.7883, longitude: 98.9853, timeZone: "Asia/Bangkok", mapKitIdentifier: nil, fixtureID: nil),
        ]
    }
}

/// Walks a navigation stack for the status-bar check: Trip Detail opens on a
/// light root, then pops back to it, or pushes on to a light screen.
struct DebugStatusBarNavigation: View {
    let trip: TripRecord
    var pushesOnward: Bool
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            List { Text(pushesOnward ? "Root" : "Root after popping Trip Detail") }
                .navigationTitle("Trips")
                .navigationDestination(for: String.self) { step in
                    if step == "detail" {
                        TripDetailView(trip: trip)
                    } else {
                        Text("A light screen pushed after Trip Detail")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(PackWiseColor.screen)
                            .navigationTitle("Light")
                    }
                }
        }
        .task {
            path = ["detail"]
            try? await Task.sleep(for: .seconds(1.5))
            if pushesOnward { path.append("light") } else { path.removeAll() }
        }
    }
}

/// A map provider that never answers, holding the loading state.
struct DebugSuspendedMapSnapshots: DestinationMapSnapshotting {
    func snapshot(for request: DestinationMapRequest) async throws -> UIImage {
        try await Task.sleep(for: .seconds(3600))
        throw CancellationError()
    }
}

/// A map provider that always fails, as offline.
struct DebugOfflineMapSnapshots: DestinationMapSnapshotting {
    func snapshot(for request: DestinationMapRequest) async throws -> UIImage {
        throw URLError(.notConnectedToInternet)
    }
}

/// Chicago, five days, part way packed — the trip the reference board draws.
@MainActor
@Observable
final class DebugTripSeed {
    let container: ModelContainer
    let trip: TripRecord
    /// Far-future trip with no precise forecast, for seasonal presentation.
    let seasonalTrip: TripRecord
    /// Two adults and a toddler, so the family branch of the party step has
    /// something to draw.
    let familyTrip: TripRecord
    /// Finished and fully packed, for the past-trip treatment.
    let completedTrip: TripRecord
    /// You plus three other adults, one named with device choices, for the
    /// expanded group branch of the travelers step.
    let groupTrip: TripRecord
    /// The Chicago trip with an item in every category, so Trip Detail's
    /// Packing block can be checked with all eleven rows (Task 10).
    let allCategoriesTrip: TripRecord
    /// You and Alex, with a generated list, for the couple list states (Task 11).
    let coupleTrip: TripRecord

    /// Visuals with no trusted imagery and a failing map: the offline state.
    static let offlineVisuals = MapKitDestinationVisualService(
        directory: nil,
        trusted: { _ in nil },
        mapSnapshots: DebugOfflineMapSnapshots()
    )

    /// A trusted photo for every destination, to check the hero over a bright
    /// image (the onboarding photograph has a pale sky at its top).
    static let trustedVisuals = MapKitDestinationVisualService(
        directory: nil,
        trusted: { _ in UIImage(named: PackWiseImageSlot.welcome) },
        mapSnapshots: DebugOfflineMapSnapshots()
    )

    static let loadingVisuals = MapKitDestinationVisualService(
        directory: nil,
        trusted: { _ in nil },
        mapSnapshots: DebugSuspendedMapSnapshots()
    )

    /// One upcoming trip with a long destination name and no forecast yet.
    static let longDestinationContainer: ModelContainer = {
        let container = try! PackWisePersistence.container(inMemory: true)
        let context = ModelContext(container)
        context.insert(PackingPreferenceRecord(from: .deviceDefaults()))
        let start = Calendar.current.date(byAdding: .day, value: 5, to: Calendar.current.startOfDay(for: .now))!
        let trip = TripRecord(
            destination: DebugDestinationSearch.longName,
            startDate: start,
            endDate: Calendar.current.date(byAdding: .day, value: 6, to: start)!,
            durationDays: 7,
            durationNights: 6,
            tripType: .vacation,
            activities: ["sightseeing"],
            bagType: .carryOn,
            packingStyle: .balanced,
            status: .planning
        )
        context.insert(trip)
        let repository = TripRepository(context: context)
        for item in items().prefix(10) {
            repository.addItem(item.draft, to: trip, syncWeatherChange: false)
        }
        try? context.save()
        return container
    }()

    /// For the empty Trips Home. Trips Home reads its own @Query, so an empty
    /// state needs a store with nothing in it.
    static let emptyContainer: ModelContainer = {
        let container = try! PackWisePersistence.container(inMemory: true)
        let context = ModelContext(container)
        context.insert(PackingPreferenceRecord(from: .deviceDefaults()))
        try? context.save()
        return container
    }()

    init() {
        container = try! PackWisePersistence.container(inMemory: true)
        let context = ModelContext(container)
        context.insert(PackingPreferenceRecord(from: .deviceDefaults()))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .gmt
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!

        let destination = (try? SharedLibrary.testDestinations())?.first { $0.city == "Chicago" }
            ?? Destination(
                displayName: "Chicago",
                city: "Chicago",
                region: "Illinois",
                country: "United States",
                countryCode: "US",
                latitude: 41.8781,
                longitude: -87.6298,
                timeZone: "America/Chicago",
                mapKitIdentifier: nil,
                fixtureID: nil
            )

        trip = TripRecord(
            destination: destination,
            startDate: start,
            endDate: calendar.date(byAdding: .day, value: 4, to: start)!,
            durationDays: 5,
            durationNights: 4,
            tripType: .cityBreak,
            activities: ["sightseeing", "walking", "museum sketching"],
            bagType: .carryOn,
            packingStyle: .balanced,
            status: .packing
        )
        context.insert(trip)

        let repository = TripRepository(context: context)
        let seeded = Self.items()
        for item in seeded {
            repository.addItem(item.draft, to: trip, syncWeatherChange: false)
        }
        // SwiftData does not promise relationship order, so packed state is
        // matched by name rather than by position.
        let packedNames = Set(seeded.filter(\.packed).map(\.draft.displayName))
        for record in trip.items where packedNames.contains(record.displayName) {
            record.packedQuantity = record.quantity
        }
        repository.storeWeather(Self.forecast(start: start, calendar: calendar), on: trip)

        allCategoriesTrip = TripRecord(
            destination: destination,
            startDate: calendar.date(byAdding: .day, value: 20, to: start)!,
            endDate: calendar.date(byAdding: .day, value: 24, to: start)!,
            durationDays: 5,
            durationNights: 4,
            tripType: .cityBreak,
            activities: ["sightseeing", "walking"],
            bagType: .carryOn,
            packingStyle: .balanced,
            status: .packing,
            travelerCount: 2,
            travelMode: .family
        )
        context.insert(allCategoriesTrip)
        // Fresh drafts, not `seeded`: item IDs are unique across the store,
        // so reusing the main trip's drafts would move its rows here.
        let allCategoryItems = Self.items() + Self.remainingCategoryItems()
        for item in allCategoryItems {
            repository.addItem(item.draft, to: allCategoriesTrip, syncWeatherChange: false)
        }
        let allPackedNames = Set(allCategoryItems.filter(\.packed).map(\.draft.displayName))
        for record in allCategoriesTrip.items where allPackedNames.contains(record.displayName) {
            record.packedQuantity = record.quantity
        }

        // A generated list nobody has started, and a finished trip, so Trips
        // Home shows all three of its states at once.
        seasonalTrip = TripRecord(
            destination: Destination(
                displayName: "Tokyo",
                city: "Tokyo",
                region: "Tokyo",
                country: "Japan",
                countryCode: "JP",
                latitude: 35.6762,
                longitude: 139.6503,
                timeZone: "Asia/Tokyo",
                mapKitIdentifier: nil,
                fixtureID: nil
            ),
            startDate: calendar.date(byAdding: .day, value: 53, to: start)!,
            endDate: calendar.date(byAdding: .day, value: 61, to: start)!,
            durationDays: 8,
            durationNights: 7,
            tripType: .vacation,
            activities: ["sightseeing", "walking"],
            bagType: .carryOn,
            packingStyle: .light,
            status: .planning
        )
        context.insert(seasonalTrip)
        for item in Self.items().filter({ !$0.draft.sourceSignals.contains(.weather) }).prefix(12) {
            repository.addItem(item.draft, to: seasonalTrip, syncWeatherChange: false)
        }

        let maui = TripRecord(
            destination: Destination(
                displayName: "Maui",
                city: "Maui",
                region: "Hawaii",
                country: "United States",
                countryCode: "US",
                latitude: 20.7984,
                longitude: -156.3319,
                timeZone: "Pacific/Honolulu",
                mapKitIdentifier: nil,
                fixtureID: nil
            ),
            startDate: calendar.date(byAdding: .day, value: -29, to: start)!,
            endDate: calendar.date(byAdding: .day, value: -23, to: start)!,
            durationDays: 7,
            durationNights: 6,
            tripType: .beach,
            activities: ["beachDays"],
            bagType: .checked,
            packingStyle: .balanced,
            status: .completed
        )
        context.insert(maui)

        familyTrip = TripRecord(
            destination: destination,
            startDate: calendar.date(byAdding: .day, value: 90, to: start)!,
            endDate: calendar.date(byAdding: .day, value: 96, to: start)!,
            durationDays: 7,
            durationNights: 6,
            tripType: .vacation,
            activities: ["sightseeing"],
            bagType: .checked,
            packingStyle: .prepared,
            status: .planning
        )
        context.insert(familyTrip)
        repository.attach(
            party: TripPartyBuilder.make(
                mode: .family,
                selfChips: [],
                otherAdults: [AdultDraft(name: "Maya", chips: [.bringingPhone, .bringingLaptop])],
                children: [
                    ChildDraft(name: "Ada", ageGroup: .toddler, needs: Set(ChildNeed.suggested(for: .toddler).prefix(2))),
                    ChildDraft(ageGroup: .teen, chips: [.bringingPhone])
                ]
            ),
            bagTypes: [.carryOn, .checked],
            on: familyTrip
        )
        // A V2 reference state: two trip types, two bags.
        try? repository.applyTripTypes([.vacation, .beach], on: familyTrip)
        familyTrip.activitiesRaw = "beachDays,sightseeing"
        // A real generated list, so the family Packing List shows its current state.
        if let catalog = try? SharedLibrary.catalog(), let rules = try? SharedLibrary.rules() {
            let familyContext = familyTrip.context(preferences: .deviceDefaults(), weather: nil)
            repository.replaceItems(on: familyTrip, with: PackingEngine(catalog: catalog, rules: rules).generate(context: familyContext))
        }
        // Part way packed, unevenly, so the All scope shows partial groups:
        // You have done your toiletries and footwear, Maya her toothbrush.
        let familyYou = familyTrip.party.primary.id
        let maya = familyTrip.party.travelers.first { $0.name == "Maya" }?.id
        for record in familyTrip.items {
            let mine = record.travelerID == familyYou && (record.category == .toiletries || record.category == .footwear)
            let hers = record.travelerID == maya && record.canonicalItemID == "toiletries.toothbrush"
            if mine || hers { record.packedQuantity = record.quantity }
        }

        coupleTrip = TripRecord(
            destination: destination,
            startDate: calendar.date(byAdding: .day, value: 40, to: start)!,
            endDate: calendar.date(byAdding: .day, value: 44, to: start)!,
            durationDays: 5,
            durationNights: 4,
            tripType: .cityBreak,
            activities: ["sightseeing"],
            bagType: .carryOn,
            packingStyle: .balanced,
            status: .packing,
            travelerCount: 2,
            travelMode: .couple
        )
        context.insert(coupleTrip)
        repository.attach(
            party: TripPartyBuilder.make(mode: .couple, selfChips: [], otherAdults: [AdultDraft(name: "Alex")], children: []),
            bagTypes: [.carryOn],
            on: coupleTrip
        )
        if let catalog = try? SharedLibrary.catalog(), let rules = try? SharedLibrary.rules() {
            let coupleContext = coupleTrip.context(preferences: .deviceDefaults(), weather: nil)
            repository.replaceItems(on: coupleTrip, with: PackingEngine(catalog: catalog, rules: rules).generate(context: coupleContext))
        }
        for record in coupleTrip.items where record.travelerID == coupleTrip.party.primary.id && record.category == .toiletries {
            record.packedQuantity = record.quantity
        }

        groupTrip = TripRecord(
            destination: destination,
            startDate: calendar.date(byAdding: .day, value: 120, to: start)!,
            endDate: calendar.date(byAdding: .day, value: 124, to: start)!,
            durationDays: 5,
            durationNights: 4,
            tripType: .business,
            activities: ["work"],
            bagType: .carryOn,
            packingStyle: .light,
            status: .planning
        )
        context.insert(groupTrip)
        repository.attach(
            party: TripPartyBuilder.make(
                mode: .group,
                selfChips: [.bringingHeadphones],
                otherAdults: [AdultDraft(name: "Jordan", chips: [.bringingPhone, .bringingLaptop]), AdultDraft(), AdultDraft()],
                children: []
            ),
            bagTypes: [.carryOn],
            on: groupTrip
        )

        completedTrip = TripRecord(
            destination: Destination(
                displayName: "Maui",
                city: "Maui",
                region: "Hawaii",
                country: "United States",
                countryCode: "US",
                latitude: 20.7984,
                longitude: -156.3319,
                timeZone: "Pacific/Honolulu",
                mapKitIdentifier: nil,
                fixtureID: nil
            ),
            startDate: calendar.date(byAdding: .day, value: -29, to: start)!,
            endDate: calendar.date(byAdding: .day, value: -23, to: start)!,
            durationDays: 7,
            durationNights: 6,
            tripType: .beach,
            activities: ["beachDays"],
            bagType: .checked,
            packingStyle: .balanced,
            status: .completed
        )
        context.insert(completedTrip)
        for item in Self.items().prefix(10) {
            repository.addItem(item.draft, to: completedTrip, syncWeatherChange: false)
        }
        for record in completedTrip.items {
            record.packedQuantity = record.quantity
        }

        try? context.save()
    }

    static let sampleForecast: TripWeatherContext = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .gmt
        return forecast(start: calendar.startOfDay(for: .now), calendar: calendar)
    }()

    /// A change set covering all three kinds, so the diff sheet can be checked.
    static let sampleDiff = RecommendationDiff(
        add: [
            item("clothing.umbrella", "Compact umbrella", .clothing, reason: "Rain expected Sunday", signals: [.weather]).draft,
            item("footwear.waterproof", "Waterproof shoes", .footwear, reason: "Two rainy days", signals: [.weather]).draft
        ],
        removeCandidates: [
            item("essentials.sunglasses", "Sunglasses", .essentials, reason: "Little sun expected", signals: [.weather]).draft
        ],
        quantityChanges: [
            {
                let existing = item("clothing.tshirts", "T-shirts", .clothing, quantity: 4).draft
                var fresh = existing
                fresh.quantity = 5
                return QuantityChangeSuggestion(existing: existing, fresh: fresh)
            }()
        ]
    )

    static func sampleProposal(tripID: UUID) -> WeatherChangeProposal {
        WeatherChangeProposal(
            id: UUID(),
            tripID: tripID,
            oldSnapshotID: UUID(),
            newSnapshotID: UUID(),
            createdAt: .now,
            status: .pending,
            signalChanges: [],
            headline: "Rain is now expected on Sunday and Monday.",
            diff: sampleDiff,
            tripContextSignature: ""
        )
    }

    private struct Seeded {
        var draft: PackingItemDraft
        var packed: Bool
    }

    private static func item(
        _ id: String,
        _ name: String,
        _ category: PackingCategory,
        quantity: Int = 1,
        reason: String = "",
        quantityReason: String = "",
        importance: ItemImportance = .normal,
        signals: [RecommendationSignal] = [.baseEssential],
        packed: Bool = false
    ) -> Seeded {
        Seeded(
            draft: PackingItemDraft(
                canonicalItemID: id,
                displayName: name,
                category: category,
                quantity: quantity,
                importance: importance,
                sourceSignals: signals,
                reason: reason,
                quantityReason: quantityReason,
                isUserAdded: false,
                ownershipType: .personal,
                travelerID: nil
            ),
            packed: packed
        )
    }

    /// Rebuilt per call. `PackingItemRecord.id` is unique and copied from the
    /// draft, so reusing one draft across two trips makes SwiftData upsert and
    /// silently migrate the item from one trip to the other.
    /// One or two rows for each category `items()` leaves empty, so a trip
    /// seeded with both has all eleven.
    private static func remainingCategoryItems() -> [Seeded] {
        [
        item("documents.id", "Government ID", .documents, importance: .critical, packed: true),
        item("documents.tickets", "Tickets and reservations", .documents, importance: .important),
        item("kids.snacks", "Snacks for the kids", .kids, quantity: 4),
        item("kids.extra_outfits", "Extra outfits", .kids, quantity: 2, packed: true),
        item("health.pain_reliever", "Pain reliever", .health),
        item("health.band_aids", "Band-aids", .health, packed: true),
        item("activities.daypack", "Daypack", .activities, packed: true),
        item("travel_comfort.neck_pillow", "Neck pillow", .travelComfort),
        item("travel_comfort.book", "Book", .travelComfort, packed: true),
        item("misc.laundry_bag", "Laundry bag", .miscellaneous),
        ]
    }

    private static func items() -> [Seeded] {
        [
        item("essentials.passport", "Passport", .essentials, importance: .critical, packed: true),
        item("essentials.wallet", "Wallet", .essentials, importance: .critical, packed: true),
        item("essentials.phone", "Phone", .essentials, importance: .critical, packed: true),
        item("essentials.keys", "Keys", .essentials, packed: true),
        item("essentials.sunglasses", "Sunglasses", .essentials),
        item("essentials.travel_insurance", "Travel insurance card", .essentials, reason: "Required for travel"),

        item(
            "clothing.tshirts",
            "T-shirts",
            .clothing,
            quantity: 4,
            reason: "A versatile everyday layer for this trip.",
            quantityReason: "Four tops cover this five-day trip with normal reuse.",
            signals: [.duration],
            packed: true
        ),
        item("clothing.pants", "Pants", .clothing, quantity: 2, reason: "Five-day trip", packed: true),
        item("clothing.sweater", "Light sweater", .clothing, reason: "Cool evenings", signals: [.weather], packed: true),
        item("clothing.rain_jacket", "Rain jacket", .clothing, reason: "Rain expected Sunday", signals: [.weather]),
        item("clothing.underwear", "Underwear", .clothing, quantity: 5, packed: true),
        item("clothing.socks", "Socks", .clothing, quantity: 5, packed: true),
        item("clothing.sleepwear", "Sleepwear", .clothing, packed: true),
        item("clothing.jeans", "Jeans", .clothing),

        item("footwear.walking_shoes", "Walking shoes", .footwear, reason: "Sightseeing planned", packed: true),
        item("footwear.dress_shoes", "Dress shoes", .footwear),
        item("footwear.sandals", "Sandals", .footwear),

        item("toiletries.toothbrush", "Toothbrush", .toiletries, packed: true),
        item("toiletries.toothpaste", "Toothpaste", .toiletries, packed: true),
        item("toiletries.deodorant", "Deodorant", .toiletries),
        item("toiletries.shampoo", "Shampoo", .toiletries),

        item("electronics.charger", "Phone charger", .electronics, importance: .important, packed: true),
        item("electronics.power_bank", "Portable charger", .electronics),
        item("electronics.adapter", "Travel adapter", .electronics)
        ]
    }

    private static func forecast(start: Date, calendar: Calendar) -> TripWeatherContext {
        let daily: [DailyForecast] = (0..<5).map { index in
            let day = calendar.date(byAdding: .day, value: index, to: start)!
            let raining = index == 1 || index == 2
            return DailyForecast(
                date: calendar.startOfDay(for: day),
                symbol: raining ? "cloud.rain" : "sun.max",
                highF: raining ? 71 : 78,
                lowF: raining ? 61 : 65,
                rainProbability: raining ? 0.7 : 0.1,
                uvIndex: raining ? 3 : 6,
                windMph: 9,
                snowExpected: false,
                summary: raining ? "Rain" : "Sunny"
            )
        }
        return TripWeatherContext(
            minTemperatureF: 61,
            maxTemperatureF: 78,
            dailyForecast: daily,
            rainDays: 2,
            heavyRainDays: 0,
            snowDays: 0,
            outdoorRainOverlapDays: 2,
            maxDailyTemperatureSwing: 17,
            uvRange: 6,
            windRange: 9,
            weatherSummary: "Mild with rain midweek",
            fetchedAt: start,
            providerFetchedAt: start,
            providerExpiresAt: calendar.date(byAdding: .day, value: 1, to: start),
            coverageStart: start,
            coverageEnd: calendar.date(byAdding: .day, value: 4, to: start),
            forecastAvailableForWholeTrip: true,
            forecastAvailableForPartialTrip: false,
            isPreciseForecast: true,
            source: .fixture,
            fixtureID: nil,
            alerts: [],
            attribution: nil
        )
    }
}
#endif
