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
    case packingList
    /// Sheets are rendered as plain screens — a capture cannot tap one open.
    case itemDetail
    case tripsHome
    case tripsHomeEmpty
    case setupDestination
    case setupDates
    case setupParty
    case setupPartyFamily
    case setupType
    case setupActivities
    case setupBagStyle
    case setupExtras
    case setupReview
    case reviewChanges
    case weatherChanged
    case me
    case onboarding
    case weatherDetail
    case tripDetailCompleted

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

    /// The later steps need a populated draft, so they open on the seeded trip.
    private func setup(_ step: SetupStep) -> some View {
        NavigationStack {
            TripSetupView(existingTrip: seed.trip, initialStep: step)
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch screen {
            case .tripDetail:
                NavigationStack { TripDetailView(trip: seed.trip) }
            case .packingList:
                NavigationStack { PackingListView(trip: seed.trip) }
            case .tripsHome, .tripsHomeEmpty:
                TripsHomeView()
            case .setupDestination:
                NavigationStack { TripSetupView() }
            case .setupDates:
                setup(.dates)
            case .setupParty:
                setup(.party)
            case .setupPartyFamily:
                NavigationStack {
                    TripSetupView(existingTrip: seed.familyTrip, initialStep: .party)
                }
            case .setupType:
                setup(.type)
            case .setupActivities:
                setup(.activities)
            case .setupBagStyle:
                setup(.bagAndStyle)
            case .setupExtras:
                setup(.extras)
            case .setupReview:
                setup(.review)
            case .reviewChanges:
                RecommendationDiffSheet(
                    diff: DebugTripSeed.sampleDiff,
                    trip: seed.trip,
                    title: "Review changes",
                    onFinished: {}
                )
            case .me:
                MeView()
            case .onboarding:
                OnboardingView {}
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
                    .background(Color(.systemGroupedBackground))
                    .navigationTitle("Chicago")
                    .navigationBarTitleDisplayMode(.inline)
                }
            case .itemDetail:
                if let item = seed.trip.items.first(where: { $0.displayName == "Rain jacket" }) {
                    ItemDetailSheet(
                        item: item,
                        travelers: seed.trip.party.travelers,
                        showsAssignment: false,
                        onNotNeeded: {}
                    )
                }
            }
        }
    }
}

/// Chicago, five days, part way packed — the trip the reference board draws.
@MainActor
@Observable
final class DebugTripSeed {
    let container: ModelContainer
    let trip: TripRecord
    /// Two adults and a toddler, so the family branch of the party step has
    /// something to draw.
    let familyTrip: TripRecord
    /// Finished and fully packed, for the past-trip treatment.
    let completedTrip: TripRecord

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
            activities: ["sightseeing", "walking"],
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

        // A generated list nobody has started, and a finished trip, so Trips
        // Home shows all three of its states at once.
        let tokyo = TripRecord(
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
        context.insert(tokyo)
        for item in Self.items().prefix(12) {
            repository.addItem(item.draft, to: tokyo, syncWeatherChange: false)
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
                adultCount: 2,
                childProfiles: [
                    ChildDraft(name: "Ada", ageGroup: .toddler, needs: Set(ChildNeed.suggested(for: .toddler).prefix(2)))
                ]
            ),
            bagType: .checked,
            on: familyTrip
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
            QuantityChangeSuggestion(
                item: item("clothing.tshirts", "T-shirts", .clothing, quantity: 4).draft,
                suggestedQuantity: 5
            )
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
    private static func items() -> [Seeded] {
        [
        item("essentials.passport", "Passport", .essentials, importance: .critical, packed: true),
        item("essentials.wallet", "Wallet", .essentials, importance: .critical, packed: true),
        item("essentials.phone", "Phone", .essentials, importance: .critical, packed: true),
        item("essentials.keys", "Keys", .essentials, packed: true),
        item("essentials.sunglasses", "Sunglasses", .essentials),
        item("essentials.travel_insurance", "Travel insurance card", .essentials, reason: "Required for travel"),

        item("clothing.tshirts", "T-shirts", .clothing, quantity: 4, reason: "Five-day trip", packed: true),
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
