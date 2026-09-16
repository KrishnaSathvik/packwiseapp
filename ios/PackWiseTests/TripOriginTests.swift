import Foundation
import SwiftData
import Testing
@testable import PackWise

/// Product Experience V2, Task 9.2 — the trip owns its origin country.
///
/// `Me.homeCountry` is a profile fact that seeds a *new* trip's
/// `originCountry`. From then on the trip's own value decides whether it is
/// international; changing Me later affects the next fresh trip only. Trips
/// saved before this boundary gain an origin once, from their own evidence
/// first and today's Me last, and are never consulted against Me again.
@MainActor
struct TripOriginTests {
    private static let rules: PackingRulesFile = try! SharedLibrary.rules()
    private static let engine = PackingEngine(catalog: try! SharedLibrary.catalog(), rules: rules)
    private static let international = "destination.international"

    private static func destination(_ city: String) throws -> Destination {
        try #require(try SharedLibrary.testDestinations().first { $0.city == city })
    }

    private static func me(_ code: String, confirmed: Bool = true) -> TravelerPreferences {
        var prefs = TravelerPreferences.deviceDefaults()
        prefs.homeCountryCode = code
        prefs.homeCountrySource = confirmed ? .userConfirmed : .deviceSuggested
        return prefs
    }

    private static func vacation(to city: String, me: TravelerPreferences) throws -> TripDraft {
        var draft = TripDraft.fresh(preferences: me)
        draft.destination = try destination(city)
        draft.startDate = Calendar.current.startOfDay(for: .now)
        draft.endDate = Calendar.current.date(byAdding: .day, value: 4, to: draft.startDate)!
        draft.toggleTripType(.vacation)
        return draft
    }

    /// Persists a draft exactly as `TripSetupView.saveTrip` does for a new trip.
    @discardableResult
    private static func save(_ draft: TripDraft, in context: ModelContext, status: TripStatus = .packing) throws -> TripRecord {
        let repo = TripRepository(context: context)
        let trip = TripRecord(
            destination: try #require(draft.destination),
            startDate: draft.startDate, endDate: draft.endDate,
            durationDays: draft.duration.days, durationNights: draft.duration.nights,
            tripType: TripType.stableOrder.first(where: draft.tripTypes.contains) ?? .other,
            activities: draft.activities, bagType: .notSure, packingStyle: draft.packingStyle,
            status: status,
            contextChips: ContextChip.allCases.filter(draft.tripChips.contains),
            travelMode: draft.travelMode, laundryAccess: draft.laundry,
            origin: draft.origin
        )
        context.insert(trip)
        try repo.applyTripTypes(draft.tripTypes, on: trip)
        repo.attach(party: draft.party, bagTypes: draft.bagTypes, on: trip)
        try context.save()
        return trip
    }

    private static func generate(_ trip: TripRecord, me: TravelerPreferences) -> [PackingItemDraft] {
        engine.generate(context: trip.context(preferences: me, weather: nil))
    }

    private static func ids(_ items: [PackingItemDraft]) -> Set<String> {
        Set(items.compactMap(\.canonicalItemID))
    }

    private static func container() throws -> ModelContext {
        ModelContext(try PackWisePersistence.container(inMemory: true))
    }

    // MARK: - New trips

    @Test func meHomeCountrySeedsAFreshTripsOrigin() throws {
        let context = try Self.container()
        let draft = try Self.vacation(to: "Chicago", me: Self.me("IN"))
        #expect(draft.origin == TripOrigin(countryCode: "IN", source: .userConfirmed))

        let trip = try Self.save(draft, in: context)
        #expect(trip.origin == TripOrigin(countryCode: "IN", source: .userConfirmed))
        #expect(trip.isInternational)
        #expect(Self.ids(Self.generate(trip, me: Self.me("IN"))).contains("documents.passport"))
    }

    @Test func aFreshTripAfterAMeChangePrefillsTheNewValue() throws {
        let before = try Self.vacation(to: "Chicago", me: Self.me("IN"))
        let after = try Self.vacation(to: "Chicago", me: Self.me("US"))
        #expect(before.origin == TripOrigin(countryCode: "IN", source: .userConfirmed))
        #expect(after.origin == TripOrigin(countryCode: "US", source: .userConfirmed))
        #expect(!after.origin.isInternational(destinationCountryCode: "US"))
    }

    @Test func anUnconfirmedMeHomeCountrySeedsAnUnconfirmedOrigin() throws {
        let draft = try Self.vacation(to: "Tokyo", me: Self.me("US", confirmed: false))
        #expect(draft.origin == TripOrigin(countryCode: "US", source: .deviceSuggested))
        #expect(!draft.origin.isInternational(destinationCountryCode: "JP"), "a device guess is not a fact")
    }

    // MARK: - Existing trips are isolated from Me

    @Test func anExistingInternationalTripStaysInternationalWhenMeChanges() throws {
        let context = try Self.container()
        let trip = try Self.save(try Self.vacation(to: "Chicago", me: Self.me("IN")), in: context)
        let original = Self.ids(Self.generate(trip, me: Self.me("IN")))
        #expect(original.contains("documents.passport"))

        let regenerated = Self.ids(Self.generate(trip, me: Self.me("US")))
        #expect(trip.origin == TripOrigin(countryCode: "IN", source: .userConfirmed))
        #expect(trip.isInternational)
        #expect(regenerated == original, "Me moving to the destination country changes nothing")
    }

    @Test func anExistingDomesticTripStaysDomesticWhenMeChanges() throws {
        let context = try Self.container()
        let trip = try Self.save(try Self.vacation(to: "Chicago", me: Self.me("US")), in: context)
        let original = Self.ids(Self.generate(trip, me: Self.me("US")))
        #expect(!original.contains("documents.passport"))

        let regenerated = Self.ids(Self.generate(trip, me: Self.me("IN")))
        #expect(trip.origin == TripOrigin(countryCode: "US", source: .userConfirmed))
        #expect(!trip.isInternational)
        #expect(regenerated == original, "Me moving abroad does not make an old trip international")
    }

    @Test func editingATripRestoresItsOwnOriginNeverMe() throws {
        let context = try Self.container()
        let trip = try Self.save(try Self.vacation(to: "Chicago", me: Self.me("IN")), in: context)
        let edit = TripDraft.from(trip: trip)
        #expect(edit.origin == TripOrigin(countryCode: "IN", source: .userConfirmed))
    }

    @Test func aCompletedTripIsNeverMutatedByALaterMeChange() throws {
        let context = try Self.container()
        let trip = try Self.save(try Self.vacation(to: "Chicago", me: Self.me("IN")), in: context, status: .completed)
        let repo = TripRepository(context: context)
        repo.replaceItems(on: trip, with: Self.generate(trip, me: Self.me("IN")))
        try context.save()
        let itemsBefore = trip.items.map { "\($0.canonicalItemID ?? ""):\($0.quantity):\($0.packedQuantity)" }.sorted()
        let chipsBefore = trip.contextChips

        context.insert(PackingPreferenceRecord(from: Self.me("US")))
        try context.save()
        #expect(try TripOriginBackfill.run(in: context) == 0)
        #expect(trip.origin == TripOrigin(countryCode: "IN", source: .userConfirmed))
        #expect(trip.isInternational)
        #expect(trip.contextChips == chipsBefore)
        #expect(trip.items.map { "\($0.canonicalItemID ?? ""):\($0.quantity):\($0.packedQuantity)" }.sorted() == itemsBefore)
    }

    // MARK: - The engine reads the trip, not Me

    @Test func theListIsDrivenByTheTripsOriginNotByMe() throws {
        let context = try Self.container()
        let trip = try Self.save(try Self.vacation(to: "Chicago", me: Self.me("IN")), in: context)

        var ownedByTrip = trip.context(preferences: Self.me("US"), weather: nil)
        #expect(ownedByTrip.origin == TripOrigin(countryCode: "IN", source: .userConfirmed))
        #expect(ownedByTrip.isInternationalConfirmed)
        #expect(Self.ids(Self.engine.generate(context: ownedByTrip)).contains("documents.passport"))

        // The same trip with only Me saying "abroad" is not international:
        // the engine has no live Me home-country dependency left.
        ownedByTrip.origin = .unknown
        #expect(!ownedByTrip.isInternationalConfirmed)
        #expect(!Self.ids(Self.engine.generate(context: ownedByTrip)).contains("documents.passport"))
        ownedByTrip.preferences = Self.me("IN")
        #expect(!Self.ids(Self.engine.generate(context: ownedByTrip)).contains("documents.passport"))
    }

    // MARK: - Legacy trips gain an origin once

    /// Trips saved before Task 9.2 have no origin. Their own evidence decides
    /// first: a chip or an international row keeps them international, a
    /// generated list without one keeps them domestic, and only a trip with
    /// nothing to say takes today's Me as its seed. A relaunch changes nothing.
    @Test func legacyTripsGainAnOriginOnceFromTheirOwnEvidenceThenMe() throws {
        let context = try Self.container()
        let repo = TripRepository(context: context)
        func legacy(to city: String, generatedWith me: TravelerPreferences?, chips: [ContextChip] = []) throws -> TripRecord {
            var draft = try Self.vacation(to: city, me: Self.me("US"))
            draft.origin = .unknown
            draft.chips.formUnion(chips)
            let trip = try Self.save(draft, in: context)
            trip.originCountryCode = ""
            trip.originCountrySourceRaw = ""
            if let me {
                var legacyContext = trip.context(preferences: me, weather: nil)
                legacyContext.origin = TripOrigin(seededFrom: me)
                repo.replaceItems(on: trip, with: Self.engine.generate(context: legacyContext))
            }
            try context.save()
            #expect(trip.origin == nil)
            return trip
        }
        func rows(_ trip: TripRecord) -> [String] {
            trip.items.map { "\($0.canonicalItemID ?? $0.displayName):\($0.quantity):\($0.packedQuantity)" }.sorted()
        }
        let empty = try legacy(to: "Chicago", generatedWith: nil)
        let internationalExplained = try legacy(to: "Tokyo", generatedWith: Self.me("US"))
        let internationalContradicted = try legacy(to: "Chicago", generatedWith: Self.me("IN"))
        let domesticNowAbroad = try legacy(to: "Tokyo", generatedWith: Self.me("JP"))
        let chipped = try legacy(to: "Chicago", generatedWith: Self.me("US"), chips: [.travelingInternationally])
        let all = [empty, internationalExplained, internationalContradicted, domesticNowAbroad, chipped]
        let before = all.map(rows)

        // Today's Me: United States, confirmed. It explains the Tokyo trip's
        // international rows and contradicts the Chicago trip's.
        context.insert(PackingPreferenceRecord(from: Self.me("US")))
        try context.save()

        #expect(try TripOriginBackfill.run(in: context) == 5)

        #expect(empty.origin == TripOrigin(countryCode: "US", source: .userConfirmed), "nothing to say: seeded from Me")
        #expect(internationalExplained.origin == TripOrigin(countryCode: "US", source: .userConfirmed))
        #expect(internationalExplained.isInternational)
        #expect(!internationalExplained.contextChips.contains(.travelingInternationally))

        #expect(internationalContradicted.origin == TripOrigin(countryCode: "US", source: .userConfirmed))
        #expect(internationalContradicted.contextChips.contains(.travelingInternationally), "its list says international; the trip now says so itself")
        #expect(internationalContradicted.isInternational)
        #expect(Self.ids(Self.generate(internationalContradicted, me: Self.me("US"))).contains("documents.passport"))

        #expect(domesticNowAbroad.origin == TripOrigin(countryCode: "US", source: .deviceSuggested), "generated without a confirmed origin, so it keeps none")
        #expect(!domesticNowAbroad.isInternational)
        #expect(!Self.ids(Self.generate(domesticNowAbroad, me: Self.me("US"))).contains("documents.passport"))

        #expect(chipped.origin == TripOrigin(countryCode: "US", source: .userConfirmed))
        #expect(chipped.isInternational)

        #expect(all.map(rows) == before, "the backfill never touches rows")

        // A relaunch with a different Me changes nothing.
        let prefs = try #require(try context.fetch(FetchDescriptor<PackingPreferenceRecord>()).first)
        prefs.apply(Self.me("IN"))
        try context.save()
        #expect(try TripOriginBackfill.run(in: context) == 0)
        #expect(empty.origin == TripOrigin(countryCode: "US", source: .userConfirmed))
        #expect(domesticNowAbroad.origin == TripOrigin(countryCode: "US", source: .deviceSuggested))
        #expect(internationalContradicted.contextChips.filter { $0 == .travelingInternationally }.count == 1)
        #expect(all.map(rows) == before)
    }

    @Test func aTripWithoutAnOriginIsNeverInternationalOnItsOwn() throws {
        let context = try Self.container()
        var draft = try Self.vacation(to: "Tokyo", me: Self.me("US"))
        draft.origin = .unknown
        let trip = try Self.save(draft, in: context)
        trip.originCountrySourceRaw = ""
        #expect(trip.origin == nil)
        #expect(!trip.isInternational)
        #expect(!trip.context(preferences: Self.me("US"), weather: nil).isInternationalConfirmed)
    }
}
