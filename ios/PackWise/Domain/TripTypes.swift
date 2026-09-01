import Foundation

enum TripStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case planning
    case packing
    case traveling
    case completed
    case archived
}

enum TripType: String, Codable, CaseIterable, Identifiable, Sendable {
    case vacation
    case cityBreak
    case beach
    case business
    case outdoor
    case roadTrip
    case weddingEvent
    case skiSnow
    case festival
    case visitingFamily
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vacation: "Vacation"
        case .cityBreak: "City Break"
        case .beach: "Beach"
        case .business: "Business"
        case .outdoor: "Outdoor"
        case .roadTrip: "Road Trip"
        case .weddingEvent: "Wedding / Event"
        case .skiSnow: "Ski / Snow"
        case .festival: "Festival"
        case .visitingFamily: "Visiting Family"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .vacation: "sun.horizon"
        case .cityBreak: "building.2"
        case .beach: "beach.umbrella"
        case .business: "briefcase"
        case .outdoor: "mountain.2"
        case .roadTrip: "car"
        case .weddingEvent: "heart"
        case .skiSnow: "snowflake"
        case .festival: "music.note"
        case .visitingFamily: "house"
        case .other: "ellipsis.circle"
        }
    }

    var suggestedActivityIDs: [String] {
        switch self {
        case .beach:
            ["swimming", "beachDays", "snorkeling", "niceDinner", "running", "sightseeing", "boatTrip"]
        case .cityBreak, .vacation:
            ["sightseeing", "walking", "niceDinner", "nightlife", "running", "shopping", "museums", "work"]
        case .business:
            ["work", "niceDinner", "walking"]
        case .outdoor:
            ["hiking", "sightseeing", "running", "wildlife"]
        case .roadTrip:
            ["sightseeing", "walking", "hiking"]
        case .weddingEvent:
            ["niceDinner", "sightseeing"]
        case .skiSnow:
            ["sightseeing"]
        case .festival:
            ["nightlife", "sightseeing"]
        case .visitingFamily:
            ["sightseeing", "walking", "niceDinner"]
        case .other:
            ["sightseeing", "walking"]
        }
    }
}

enum BagType: String, Codable, CaseIterable, Identifiable, Sendable {
    case personalItem
    case carryOn
    case checked
    case backpack
    case roadTripLuggage
    case notSure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personalItem: "Personal item only"
        case .carryOn: "Carry-on"
        case .checked: "Checked bag"
        case .backpack: "Backpack"
        case .roadTripLuggage: "Road-trip luggage"
        case .notSure: "Not sure yet"
        }
    }

    var implication: String {
        switch self {
        case .personalItem: "PackWise will keep the list very small and favor items that do more than one job."
        case .carryOn: "PackWise will favor versatile items and fewer backups."
        case .checked: "You have more room for extras if they earn a place on the list."
        case .backpack: "PackWise will lean compact and avoid bulky backups."
        case .roadTripLuggage: "Space is more flexible, but the list still stays trip-specific."
        case .notSure: "No bag constraint yet. Choose a bag later to tighten the list."
        }
    }

    var appliesBagConstraint: Bool { self != .notSure }

    var isSpaceConstrained: Bool {
        switch self {
        case .personalItem, .carryOn, .backpack: true
        case .checked, .roadTripLuggage, .notSure: false
        }
    }
}

enum PackingStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case light
    case balanced
    case prepared

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .balanced: "Balanced"
        case .prepared: "Prepared"
        }
    }

    var subtitle: String {
        switch self {
        case .light: "Keep it minimal. Reuse items where practical."
        case .balanced: "Enough for the trip with sensible backups."
        case .prepared: "Bring a little extra for the unexpected."
        }
    }
}

/// Activity IDs that have been merged away, mapped to their replacement.
///
/// Trips created before a merge still hold the old value in SwiftData, and an
/// unrecognized activity would silently drop its packing rule and be rejected by
/// the intelligence API's closed vocabulary. Normalizing on read heals those
/// rows without a store migration.
enum ActivityVocabulary {
    /// `fineDining` and `niceDinner` mapped to the same item, so the duplicate
    /// was removed rather than given a distinction the engine never made.
    static let renames: [String: String] = ["fineDining": "niceDinner"]

    static func normalize(_ activityID: String) -> String {
        renames[activityID] ?? activityID
    }

    static func normalize(_ activityIDs: [String]) -> [String] {
        var seen: Set<String> = []
        return activityIDs.map(normalize).filter { seen.insert($0).inserted }
    }
}

enum ContextChip: String, Codable, CaseIterable, Identifiable, Sendable {
    case dailyMedication
    case wearContacts
    case bringingLaptop
    case usuallyWorkOut
    case runWhileTraveling
    case needFormalOutfit
    case travelingInternationally
    case getColdEasily
    case laundryAvailable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dailyMedication: "I take daily medication"
        case .wearContacts: "I wear contacts"
        case .bringingLaptop: "I'm bringing a laptop"
        case .usuallyWorkOut: "I usually work out"
        case .runWhileTraveling: "I run while traveling"
        case .needFormalOutfit: "I need a formal outfit"
        case .travelingInternationally: "I'm traveling internationally"
        case .getColdEasily: "I get cold easily"
        case .laundryAvailable: "I'll have laundry"
        }
    }

    var differenceTitle: String {
        switch self {
        case .dailyMedication: "Medication"
        case .wearContacts: "Contacts / glasses"
        case .usuallyWorkOut: "Workout clothes"
        case .needFormalOutfit: "Formal outfit"
        case .getColdEasily: "Gets cold easily"
        default: title
        }
    }

    static var tripLevel: Set<ContextChip> {
        [.travelingInternationally, .laundryAvailable]
    }

    static var partnerDifferences: [ContextChip] {
        [.dailyMedication, .wearContacts, .usuallyWorkOut, .needFormalOutfit, .getColdEasily]
    }
}

enum ItemImportance: String, Codable, CaseIterable, Sendable {
    case critical
    case important
    case normal
    case optional
}

enum PackingCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case essentials
    case documents
    case clothing
    case kids
    case footwear
    case toiletries
    case electronics
    case health
    case activities
    case travelComfort = "travel_comfort"
    case miscellaneous

    var id: String { rawValue }

    var title: String {
        switch self {
        case .essentials: "Essentials"
        case .documents: "Documents"
        case .clothing: "Clothing"
        case .kids: "Kids"
        case .footwear: "Footwear"
        case .toiletries: "Toiletries"
        case .electronics: "Electronics"
        case .health: "Health"
        case .activities: "Activities"
        case .travelComfort: "Travel Comfort"
        case .miscellaneous: "Miscellaneous"
        }
    }

    static func displayOrder(international: Bool, outdoor: Bool) -> [PackingCategory] {
        var order = PackingCategory.allCases
        if international {
            order.removeAll { $0 == .documents }
            order.insert(.documents, at: 1)
        }
        if outdoor {
            order.removeAll { $0 == .activities }
            let insertAt = min(order.count, international ? 3 : 2)
            order.insert(.activities, at: insertAt)
        }
        return order
    }
}

enum RecommendationSignal: String, Codable, CaseIterable, Sendable {
    case weather
    case duration
    case activity
    case tripType
    case destination
    case baseEssential
    case userPreference
    case history
    case gptReasoning
    case party

    var customerLabel: String {
        switch self {
        case .weather: "Forecast"
        case .duration: "Trip length"
        case .activity: "Your activities"
        case .tripType: "Your trip"
        case .destination: "Your destination"
        case .baseEssential: "Essentials"
        case .userPreference: "Your preferences"
        case .history: "Your packing habits"
        case .gptReasoning: "Your trip"
        case .party: "Who's traveling"
        }
    }
}

struct Destination: Codable, Hashable, Sendable, Identifiable {
    var displayName: String
    var city: String
    var region: String
    var country: String
    var countryCode: String
    var latitude: Double
    var longitude: Double
    var timeZone: String
    var mapKitIdentifier: String?
    var fixtureID: String?

    var id: String { "\(city)-\(countryCode)-\(latitude)" }

    var subtitle: String {
        [region, country].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

enum HomeCountrySource: String, Codable, Sendable {
    case deviceSuggested
    case userConfirmed
}

enum Transportation: String, Codable, CaseIterable, Sendable {
    case flight
    case drive
    case train
    case cruise
    case other
    case unknown
}

enum LaundryAccess: String, Codable, CaseIterable, Sendable {
    case none
    case possible
    case planned
}

struct DatedActivity: Hashable, Sendable {
    var activityID: String
    var date: Date?
}

struct TravelerPreferences: Codable, Hashable, Sendable {
    var homeCountryCode: String?
    var homeCountrySource: HomeCountrySource
    var packingStyle: PackingStyle
    var preferredBag: BagType
    var usesFahrenheit: Bool
    var usesImperial: Bool
    var usuallyWorkOut: Bool
    var usuallyBringLaptop: Bool
    var wearContacts: Bool
    var alwaysBringMedication: Bool

    static func deviceDefaults(locale: Locale = .current) -> TravelerPreferences {
        let region = locale.region?.identifier
        let usesUS = locale.measurementSystem == .us
        return TravelerPreferences(
            homeCountryCode: region,
            homeCountrySource: .deviceSuggested,
            packingStyle: .balanced,
            preferredBag: .notSure,
            usesFahrenheit: usesUS,
            usesImperial: usesUS,
            usuallyWorkOut: false,
            usuallyBringLaptop: false,
            wearContacts: false,
            alwaysBringMedication: false
        )
    }
}

struct TripContext: Hashable, Sendable {
    var destination: Destination
    var startDate: Date
    var endDate: Date
    var durationDays: Int
    var durationNights: Int
    var tripType: TripType
    var activities: [String]
    var datedActivities: [DatedActivity]
    var bagType: BagType
    var packingStyle: PackingStyle
    var transportation: Transportation
    var laundryAccess: LaundryAccess
    var travelerCount: Int
    var userNotes: String
    var contextChips: Set<ContextChip>
    var weather: TripWeatherContext?
    var preferences: TravelerPreferences
    var party: TripParty = .solo()

    var effectiveParty: TripParty {
        party.travelers.isEmpty ? .solo() : party
    }

    var isInternationalConfirmed: Bool {
        if contextChips.contains(.travelingInternationally) { return true }
        guard preferences.homeCountrySource == .userConfirmed,
              let home = preferences.homeCountryCode, !home.isEmpty else { return false }
        return destination.countryCode.uppercased() != home.uppercased()
    }

    var hasLaundry: Bool {
        laundryAccess != .none
            || contextChips.contains(.laundryAvailable)
            || userNotes.localizedCaseInsensitiveContains("laundry")
    }

    /// The three-way laundry state with the legacy signals folded in: an
    /// explicit `laundryAccess` wins; the old boolean chip and a laundry
    /// mention in the notes state availability, not intent, so they resolve
    /// to `.possible`.
    var laundryPlan: LaundryAccess {
        if laundryAccess != .none { return laundryAccess }
        if contextChips.contains(.laundryAvailable)
            || userNotes.localizedCaseInsensitiveContains("laundry") {
            return .possible
        }
        return .none
    }

    var outdoorActivities: Bool {
        activities.contains(where: { ["hiking", "sightseeing", "walking", "running", "beachDays"].contains($0) })
    }
}

enum TripDateMath {
    static func daysAndNights(from start: Date, to end: Date, calendar: Calendar = .current) -> (days: Int, nights: Int) {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let days = max(1, (calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1)
        return (days, max(0, days - 1))
    }

    static func isStartAllowed(_ start: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: start) >= calendar.startOfDay(for: now)
    }
}
