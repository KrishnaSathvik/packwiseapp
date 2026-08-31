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
        NavigationStack {
            switch screen {
            case .tripDetail:
                TripDetailView(trip: seed.trip)
            case .packingList:
                PackingListView(trip: seed.trip)
            }
        }
        .modelContainer(seed.container)
    }
}

/// Chicago, five days, part way packed — the trip the reference board draws.
@MainActor
@Observable
final class DebugTripSeed {
    let container: ModelContainer
    let trip: TripRecord

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
        for item in Self.items {
            repository.addItem(item.draft, to: trip, syncWeatherChange: false)
        }
        for (record, packed) in zip(trip.items, Self.items.map(\.packed)) where packed {
            record.packedQuantity = record.quantity
        }
        repository.storeWeather(Self.forecast(start: start, calendar: calendar), on: trip)
        try? context.save()
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

    private static let items: [Seeded] = [
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
