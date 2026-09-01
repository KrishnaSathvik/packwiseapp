import Foundation
import Testing
@testable import PackWise

/// Constraint resolver tests — Engine V2 plan, Step 5: dependencies,
/// explicit conflicts, and the family sharing rules that must never drift.
struct ConstraintTests {
    private func makeEngine() throws -> PackingEngine {
        PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
    }

    private func destination(_ name: String) throws -> Destination {
        try SharedLibrary.testDestinations().first { $0.city == name }!
    }

    private func context(
        destination: Destination,
        days: Int = 5,
        type: TripType = .cityBreak,
        activities: [String] = ["sightseeing", "walking"],
        bag: BagType = .carryOn,
        style: PackingStyle = .balanced,
        chips: Set<ContextChip> = [],
        party: TripParty? = nil
    ) -> TripContext {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        let end = Calendar.current.date(byAdding: .day, value: days - 1, to: start)!
        let math = TripDateMath.daysAndNights(from: start, to: end)
        var prefs = TravelerPreferences.deviceDefaults()
        prefs.homeCountryCode = "US"
        prefs.homeCountrySource = .userConfirmed
        return TripContext(
            destination: destination,
            startDate: start,
            endDate: end,
            durationDays: math.days,
            durationNights: math.nights,
            tripType: type,
            activities: activities,
            datedActivities: [],
            bagType: bag,
            packingStyle: style,
            transportation: .unknown,
            laundryAccess: .none,
            travelerCount: party?.travelers.count ?? 1,
            userNotes: "",
            contextChips: chips,
            weather: nil,
            preferences: prefs,
            party: party ?? .solo()
        )
    }

    // MARK: - Dependencies

    /// Adding a camera by hand pulls in its charger — a different trust
    /// posture than the up-front list, so the add must name its trigger.
    @Test func userAddedCameraSurfacesChargerWithNamingReason() throws {
        let camera = PackingItemDraft(
            canonicalItemID: "electronics.camera",
            displayName: "Camera",
            category: .electronics,
            quantity: 1,
            importance: .normal,
            sourceSignals: [.userPreference],
            reason: "Added by you",
            isUserAdded: true
        )
        let items = try makeEngine().generate(
            context: context(destination: try destination("Chicago")),
            existing: [camera]
        )
        let charger = items.first { $0.canonicalItemID == "electronics.camera_charger" }
        #expect(charger != nil)
        #expect(charger?.reasonCode == "dependency.companion")
        #expect(charger?.reason.localizedCaseInsensitiveContains("camera") == true)
    }

    /// When the rules already emitted the companion, the dependency pass
    /// must not duplicate it.
    @Test func companionNotDuplicatedWhenRulesAlreadyEmitIt() throws {
        let items = try makeEngine().generate(
            context: context(destination: try destination("Chicago"), type: .business, activities: ["work"], bag: .checked, style: .prepared)
        )
        #expect(items.filter { $0.canonicalItemID == "electronics.laptop_charger" }.count == 1)
    }

    /// Explicit user decisions outrank dependencies: a removed companion
    /// stays removed.
    @Test func removedCompanionStaysRemoved() throws {
        let camera = PackingItemDraft(
            canonicalItemID: "electronics.camera",
            displayName: "Camera",
            category: .electronics,
            quantity: 1,
            importance: .normal,
            sourceSignals: [.userPreference],
            reason: "Added by you",
            isUserAdded: true
        )
        let overrides = [RecommendationOverrideDraft(canonicalItemID: "electronics.camera_charger", action: "removed")]
        let items = try makeEngine().generate(
            context: context(destination: try destination("Chicago")),
            existing: [camera],
            overrides: overrides
        )
        #expect(!items.contains { $0.canonicalItemID == "electronics.camera_charger" })
    }

    /// The chip adds contact solution; the solution's companion adds the case.
    @Test func contactsChainAddsCase() throws {
        let items = try makeEngine().generate(
            context: context(destination: try destination("Chicago"), chips: [.wearContacts])
        )
        let ids = Set(items.compactMap(\.canonicalItemID))
        #expect(ids.contains("toiletries.contacts_solution"))
        #expect(ids.contains("toiletries.contact_case"))
    }

    // MARK: - Explicit conflicts

    /// Prepared says bring extras; a personal item says there's no room. The
    /// bag wins for optional extras, and the decision is recorded with
    /// one-sentence user-terms copy — two rules never fight silently.
    @Test func preparedVersusPersonalItemResolvesExplicitly() throws {
        let engine = try makeEngine()
        let dest = try destination("Chicago")
        let roomy = engine.generateDetailed(context: context(destination: dest, type: .vacation, bag: .checked, style: .prepared))
        let tight = engine.generateDetailed(context: context(destination: dest, type: .vacation, bag: .personalItem, style: .prepared))

        let roomyIDs = Set(roomy.items.compactMap(\.canonicalItemID))
        let tightIDs = Set(tight.items.compactMap(\.canonicalItemID))
        let decision = tight.constraintDecisions.first { $0.constraint == "style.prepared_vs_personal_item" }
        #expect(decision != nil, "the conflict must be recorded, not resolved silently")
        for dropped in decision?.items ?? [] {
            #expect(roomyIDs.contains(dropped), "\(dropped) should exist when there's room")
            #expect(!tightIDs.contains(dropped), "\(dropped) should be trimmed for a personal item")
        }
        #expect(decision?.items.isEmpty == false)
        #expect(decision?.summary.hasPrefix("Trimmed to fit a personal item") == true)
        #expect(roomy.constraintDecisions.isEmpty, "a checked bag has no conflict to record")
    }

    /// Optional items that are small or safety-relevant survive the trim.
    @Test func essentialOptionalTagsSurvivePersonalItem() {
        let ruling = ConstraintResolver.optionalRuling(
            importance: .optional,
            tags: ["medication"],
            bag: .personalItem,
            style: .light
        )
        #expect(ruling.keep)
    }

    // MARK: - Family sharing (fixture 12 is the risk, not the gate)

    /// Sunscreen shared across the party is right; medication never is; a
    /// stroller belongs to the group. These must hold as the sharing rules
    /// evolve.
    @Test func familySharingKeepsMedicationPersonal() throws {
        let rules = try SharedLibrary.rules()
        let medicationIDs = ["health.daily_medication", "kids.medication", "health.prescription_copy"]
        for id in medicationIDs {
            #expect(!rules.party.sharedByDefault.contains(id), "\(id) must never be shared by default")
        }

        var partner = Traveler(name: "Sam", role: .partner, ageGroup: .adult)
        partner.chips = [.dailyMedication]
        let party = TripParty(
            travelMode: .family,
            travelers: [Traveler.primarySelf(), partner, Traveler(name: "Emma", role: .child, ageGroup: .toddler)]
        )
        let generation = try makeEngine().generateDetailed(
            context: context(destination: try destination("Chicago"), days: 7, bag: .checked, party: party)
        )
        let medication = generation.items.filter { $0.canonicalItemID == "health.daily_medication" }
        #expect(medication.count == 1)
        #expect(medication.first?.ownershipType == .personal)
        #expect(medication.first?.travelerID == partner.id, "the partner's medication belongs to the partner")
        // Its companion follows the trigger's owner, not the shared pile.
        let copy = generation.items.first { $0.canonicalItemID == "health.prescription_copy" }
        if let copy {
            #expect(copy.ownershipType == .personal)
            #expect(copy.travelerID == partner.id)
        }
        let shared = generation.items.filter { $0.ownershipType == .shared }.compactMap(\.canonicalItemID)
        #expect(!shared.contains("health.daily_medication"))
    }
}
