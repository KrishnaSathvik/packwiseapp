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

    /// The one true persistence/API/signature order for `Set<TripType>`,
    /// per the product-approved matrix in design Section 8.1
    /// (`docs/plans/2026-09-04-product-experience-v2-design.md`). Every
    /// stable-boundary serialization of a trip-type set must use this order
    /// instead of `Set` iteration order, which Swift does not guarantee.
    /// See `StableRawValueSetCodec` in `TripContextCollections.swift`.
    static let stableOrder: [TripType] = [
        .vacation, .cityBreak, .beach, .business, .outdoor, .roadTrip,
        .weddingEvent, .skiSnow, .festival, .visitingFamily, .other
    ]
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

    /// The four V2 physical bags, in the one true persistence/API/signature
    /// order. `.notSure` and `.roadTripLuggage` remain declared cases for
    /// existing non-V2 call sites (default preferences, legacy pickers) but
    /// are deliberately excluded here: "not sure yet" is represented by an
    /// empty `Set<BagType>`, not a case, and `roadTripLuggage` is retired in
    /// favor of Road Trip as a trip type. `stableOrder` is what excludes
    /// them from V2 stable encoding/decoding without touching those other
    /// call sites or removing the cases from this enum. See
    /// `StableRawValueSetCodec` and `BagTypeLegacyRawValue` in
    /// `TripContextCollections.swift`.
    static let stableOrder: [BagType] = [.personalItem, .carryOn, .checked, .backpack]
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
    /// Traveler-scoped device signals (Task 8), set in a companion's traveler
    /// details. Never trip context and never in the Intelligence API chip
    /// vocabulary: they live in `base.json` `traveler_device_chips`.
    case bringingPhone
    case bringingTablet
    case bringingHeadphones
    case bringingPowerBank
    case bringingCamera

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
        case .bringingPhone: "Bringing a phone"
        case .bringingTablet: "Bringing a tablet"
        case .bringingHeadphones: "Bringing headphones"
        case .bringingPowerBank: "Bringing a power bank"
        case .bringingCamera: "Bringing a camera"
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

    /// Device choices in a companion's traveler details, in display order
    /// (Tasks 8–8.1). Every device is explicit for everyone except the
    /// primary traveler's phone. Laptop reuses the existing `bringingLaptop`
    /// signal.
    static var travelerDevices: [ContextChip] {
        [.bringingPhone, .bringingLaptop, .bringingTablet, .bringingHeadphones, .bringingPowerBank, .bringingCamera]
    }

    /// The primary traveler's device choices in About you: everything but the
    /// phone, which is implicit because PackWise runs on it.
    static var primaryDevices: [ContextChip] {
        travelerDevices.filter { $0 != .bringingPhone }
    }

    /// Signals that only ever belong to one traveler's details — stored on
    /// that traveler, never as the trip's own chips, and never sent as trip
    /// context. (`bringingLaptop` predates them and remains a trip chip too.)
    static var travelerDeviceSignals: Set<ContextChip> {
        [.bringingPhone, .bringingTablet, .bringingHeadphones, .bringingPowerBank, .bringingCamera]
    }

    /// The About you choices for the primary traveler, in display order.
    static var aboutYou: [ContextChip] {
        [.dailyMedication, .wearContacts, .bringingLaptop, .usuallyWorkOut, .runWhileTraveling, .needFormalOutfit, .getColdEasily]
    }
}

/// A Me "Usually true for me" habit and the About you choice it prefills on
/// a new trip.
enum MeHabit: CaseIterable, Sendable {
    case workOut
    case laptop
    case contacts
    case medication

    var chip: ContextChip {
        switch self {
        case .workOut: .usuallyWorkOut
        case .laptop: .bringingLaptop
        case .contacts: .wearContacts
        case .medication: .dailyMedication
        }
    }

    func isOn(in preferences: TravelerPreferences) -> Bool {
        switch self {
        case .workOut: preferences.usuallyWorkOut
        case .laptop: preferences.usuallyBringLaptop
        case .contacts: preferences.wearContacts
        case .medication: preferences.alwaysBringMedication
        }
    }

    func set(_ on: Bool, in preferences: inout TravelerPreferences) {
        switch self {
        case .workOut: preferences.usuallyWorkOut = on
        case .laptop: preferences.usuallyBringLaptop = on
        case .contacts: preferences.wearContacts = on
        case .medication: preferences.alwaysBringMedication = on
        }
    }
}

/// The one mapping for prefill, the pre-9.1 backfill, and their tests.
enum MeDefaultChoices {
    static let habits = MeHabit.allCases

    static func chips(for preferences: TravelerPreferences) -> Set<ContextChip> {
        Set(habits.filter { $0.isOn(in: preferences) }.map(\.chip))
    }

    /// The reason code a habit-caused row carried when the engine still read
    /// Me directly — identical to the trip-choice code.
    static func reasonCode(_ chip: ContextChip) -> String { "preference.\(chip.rawValue)" }
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

/// The country a trip is taken from — the trip's own copy of the home
/// country that was true when it was created (Task 9.2). `Me.homeCountry`
/// seeds it for a *new* trip and is never consulted for that trip again, so
/// editing Me later changes the next fresh trip only. Conceptually it is the
/// trip's origin, not "home country at creation": a later release can let a
/// trip start from somewhere else without changing the model.
///
/// A device-suggested code is a guess, not a fact (implementation decision
/// "Home country"), so only a confirmed origin can make a trip international.
struct TripOrigin: Hashable, Codable, Sendable {
    var countryCode: String?
    var source: HomeCountrySource

    init(countryCode: String?, source: HomeCountrySource) {
        self.countryCode = countryCode?.isEmpty == true ? nil : countryCode
        self.source = source
    }

    /// The seed for a new trip: Me's home country as it is right now.
    init(seededFrom preferences: TravelerPreferences) {
        self.init(countryCode: preferences.homeCountryCode, source: preferences.homeCountrySource)
    }

    /// No origin on record. Never international on its own; a trip in this
    /// state is one the origin backfill has not reached yet.
    static let unknown = TripOrigin(countryCode: nil, source: .deviceSuggested)

    /// The one international decision (design: "international = destination
    /// ≠ home"), shared by the engine and every screen that orders by it.
    func isInternational(destinationCountryCode: String) -> Bool {
        guard source == .userConfirmed, let countryCode else { return false }
        return destinationCountryCode.uppercased() != countryCode.uppercased()
    }
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
    /// V4 multi-bag default-bag preference (design Section 6.2), replacing
    /// `preferredBag` as the authoritative persisted value.
    /// `preferredBag` remains for existing call sites (`MeView`, setup)
    /// until Task 8 rewires them to the multi-select.
    var preferredBagTypes: Set<BagType> = []
    var usesFahrenheit: Bool
    var usesImperial: Bool
    /// The four "Usually true for me" habits are defaults, never engine input
    /// (Tasks 8.2–9.1). Each seeds a *new* trip's About you choice through
    /// `MeDefaultChoices`; from then on that trip's own saved choice is its
    /// only authority, so changing Me never changes an existing trip. The
    /// stored names predate the boundary and stay for store compatibility.
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
    /// Every selected trip type — the authoritative V2 trip context (never
    /// empty for a real trip). Serialize only through `TripType.stableOrder`.
    var tripTypes: Set<TripType>
    var activities: [String]
    var datedActivities: [DatedActivity]
    /// Every selected physical bag. Empty means "Not sure yet": no luggage
    /// constraint. Serialize only through `BagType.stableOrder`.
    var bagTypes: Set<BagType>
    var packingStyle: PackingStyle
    var transportation: Transportation
    var laundryAccess: LaundryAccess
    var travelerCount: Int
    var userNotes: String
    var contextChips: Set<ContextChip>
    var weather: TripWeatherContext?
    /// Me at generation time. The engine reads no home-country value from
    /// here (Task 9.2) and no habit (Tasks 8.2–9.1); what remains in use is
    /// unit and style context.
    var preferences: TravelerPreferences
    var party: TripParty = .solo()
    /// The trip's own origin country; see `TripOrigin`. Defaults to unknown
    /// so a context built without one is never international by accident.
    var origin: TripOrigin = .unknown

    var effectiveParty: TripParty {
        party.travelers.isEmpty ? .solo() : party
    }

    var isInternationalConfirmed: Bool {
        contextChips.contains(.travelingInternationally)
            || origin.isInternational(destinationCountryCode: destination.countryCode)
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
