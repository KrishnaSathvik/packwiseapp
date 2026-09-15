import Foundation
import SwiftData
import Testing
@testable import PackWise

/// Product Experience V2, Task 8 — setup state. Selection rules live on
/// `TripDraft`, so these run without UI: set-valued trip types and bags,
/// non-causal activity suggestions, stable traveler identity and labels, and
/// companion device choices that reach the engine only as traveler-scoped
/// signals.
@MainActor
struct TripSetupDraftTests {
    private static let rules: PackingRulesFile = try! SharedLibrary.rules()
    private static let engine = PackingEngine(catalog: try! SharedLibrary.catalog(), rules: rules)

    private static func destination(_ city: String = "Chicago") throws -> Destination {
        try #require(try SharedLibrary.testDestinations().first { $0.city == city })
    }

    private static func preferences(bags: Set<BagType> = []) -> TravelerPreferences {
        var prefs = TravelerPreferences.deviceDefaults()
        prefs.homeCountryCode = "US"
        prefs.homeCountrySource = .userConfirmed
        prefs.preferredBagTypes = bags
        return prefs
    }

    /// Persists a draft exactly as `TripSetupView.saveTrip` does for a new trip.
    private static func save(_ draft: TripDraft, in context: ModelContext) throws -> TripRecord {
        let repo = TripRepository(context: context)
        let trip = TripRecord(
            destination: try #require(draft.destination),
            startDate: draft.startDate, endDate: draft.endDate,
            durationDays: draft.duration.days, durationNights: draft.duration.nights,
            tripType: TripType.stableOrder.first(where: draft.tripTypes.contains) ?? .other,
            activities: draft.activities, bagType: .notSure, packingStyle: draft.packingStyle,
            contextChips: ContextChip.allCases.filter(draft.tripChips.contains),
            travelMode: draft.travelMode, laundryAccess: draft.laundry
        )
        context.insert(trip)
        try repo.applyTripTypes(draft.tripTypes, on: trip)
        repo.attach(party: draft.party, bagTypes: draft.bagTypes, on: trip)
        try context.save()
        return trip
    }

    // MARK: - Steps

    @Test func setupHasNineStepsInTheDesignedOrder() {
        #expect(SetupStep.allCases == [.destination, .dates, .travelers, .tripTypes, .activities, .bags, .styleAndLaundry, .preferences, .review])
        #expect(SetupStep.count == 9)
        #expect(SetupStep.bags.title == "What bags are you bringing?")
        #expect(SetupStep.bags.subtitle == "Choose all that apply.")
        #expect(SetupStep.allCases.allSatisfy { !$0.title.localizedCaseInsensitiveContains("how are you traveling") })
    }

    // MARK: - Fresh and edit drafts

    @Test func freshDraftPrefillsEveryDefaultBagAndRequiresATripType() {
        let multi = TripDraft.fresh(preferences: Self.preferences(bags: [.carryOn, .personalItem]))
        #expect(multi.bagTypes == [.carryOn, .personalItem])
        #expect(TripDraft.fresh(preferences: Self.preferences(bags: [])).bagTypes.isEmpty, "no default bags stays not sure yet")
        #expect(!multi.hasTripType, "no trip type is chosen for the user")
    }

    @Test func bagsAreIndependentAndOnlyPhysical() {
        var draft = TripDraft()
        draft.toggleBag(.carryOn)
        draft.toggleBag(.checked)
        draft.toggleBag(.notSure)
        draft.toggleBag(.roadTripLuggage)
        #expect(draft.bagTypes == [.carryOn, .checked])
        draft.toggleBag(.carryOn)
        draft.toggleBag(.checked)
        #expect(draft.bagTypes.isEmpty, "empty is valid: not sure yet")
    }

    @Test func multiTypeMultiBagTripRoundTripsThroughEdit() throws {
        let context = ModelContext(try PackWisePersistence.container(inMemory: true))
        var draft = TripDraft.fresh(preferences: Self.preferences())
        draft.destination = try Self.destination()
        draft.toggleTripType(.beach)
        draft.toggleTripType(.vacation)
        draft.toggleTripType(.business)
        draft.toggleBag(.backpack)
        draft.toggleBag(.checked)
        draft.toggleActivity("work")
        draft.chips = [.dailyMedication, .travelingInternationally]
        let trip = try Self.save(draft, in: context)

        #expect(trip.tripTypesRaw == #"["vacation","beach","business"]"#)
        #expect(trip.bagTypes == [.backpack, .checked])
        let edited = TripDraft.from(trip: trip)
        #expect(edited.tripTypes == [.vacation, .beach, .business])
        #expect(edited.bagTypes == [.backpack, .checked])
        #expect(edited.activities == ["work"])
        #expect(edited.chips == [.dailyMedication, .travelingInternationally])

        // A legacy trip with no bag record edits as not sure yet.
        let legacy = TripRecord(
            destination: try Self.destination(), startDate: .now, endDate: .now,
            durationDays: 1, durationNights: 0, tripType: .cityBreak, activities: [], bagType: .notSure, packingStyle: .balanced
        )
        context.insert(legacy)
        #expect(TripDraft.from(trip: legacy).bagTypes.isEmpty)
        #expect(TripDraft.from(trip: legacy).tripTypes == [.cityBreak])
    }

    @Test func editingFamilyCountsReusesEverySurvivingTravelerID() throws {
        let context = ModelContext(try PackWisePersistence.container(inMemory: true))
        var draft = TripDraft.fresh(preferences: Self.preferences())
        draft.destination = try Self.destination()
        draft.toggleTripType(.vacation)
        draft.setTravelMode(.family)
        draft.setOtherAdultCount(2)
        draft.setChildCount(2)
        draft.otherAdults[0].name = "Maya"
        draft.childProfiles[1].ageGroup = .toddler
        let trip = try Self.save(draft, in: context)
        let originalIDs = trip.party.travelers.map(\.id)
        let primaryID = trip.party.primary.id

        var edit = TripDraft.from(trip: trip)
        #expect(edit.otherAdultCount == 2 && edit.childProfiles.count == 2)
        edit.setChildCount(3)
        edit.setOtherAdultCount(1)
        let party = edit.party
        #expect(party.primary.id == primaryID, "You keep your ID")
        #expect(party.travelers.contains { $0.id == originalIDs[1] && $0.name == "Maya" }, "Maya keeps her ID and name")
        #expect(!party.travelers.contains { $0.id == originalIDs[2] }, "the removed adult is gone")
        let children = party.travelers.filter { $0.role == .child }
        #expect(children.count == 3)
        #expect(Array(children.prefix(2).map(\.id)) == Array(originalIDs.suffix(2)), "existing children keep their IDs, in order")
        #expect(children[1].ageGroup == .toddler)
    }

    // MARK: - Activities

    @Test func suggestionsAreNotSelectionsAndTripTypesNeverChangeActivities() throws {
        var draft = TripDraft()
        draft.toggleTripType(.beach)
        let beachSuggestions = draft.visibleActivities(contracts: Self.rules.tripTypeContracts)
        #expect(!beachSuggestions.isEmpty)
        #expect(draft.activities.isEmpty, "showing suggestions selects nothing")

        draft.toggleActivity("snorkeling")
        draft.toggleActivity("custom kite surfing")
        let selected = draft.activities

        draft.toggleTripType(.business)
        draft.toggleTripType(.beach)
        draft.toggleTripType(.outdoor)
        #expect(draft.activities == selected, "byte-for-byte stable across trip-type changes")

        let visible = draft.visibleActivities(contracts: Self.rules.tripTypeContracts)
        let union = TripTypeContractResolver(contracts: Self.rules.tripTypeContracts).suggestedActivityIDs(for: [.business, .outdoor])
        #expect(Array(visible.prefix(union.count)) == union, "suggestions are the stable union of the selected types")
        #expect(visible.contains("snorkeling") && visible.contains("custom kite surfing"), "a selection never disappears from view")

        // Unselected suggestions are non-causal: the saved context carries only taps.
        let context = ModelContext(try PackWisePersistence.container(inMemory: true))
        draft.destination = try Self.destination()
        let trip = try Self.save(draft, in: context)
        let tripContext = trip.context(preferences: Self.preferences(), weather: nil)
        #expect(tripContext.activities == ["snorkeling", "custom kite surfing"],
                "only taps enter context — custom text is kept but matches no contract: \(tripContext.activities)")
        #expect(Self.rules.activities["custom kite surfing"] == nil)
    }

    // MARK: - Travelers

    @Test func travelerCountsAndLabelsAreUnambiguous() {
        var draft = TripDraft()
        draft.setTravelMode(.group)
        draft.setOtherAdultCount(3)
        #expect(draft.party.travelerCountSummary == "You + 3 adults")
        #expect(draft.party.travelers.map(draft.party.label(for:)) == ["You", "Adult 1", "Adult 2", "Adult 3"])
        draft.setOtherAdultCount(0)
        #expect(draft.otherAdultCount == 1, "a group always has another adult")

        draft.setTravelMode(.family)
        draft.setOtherAdultCount(1)
        draft.setChildCount(2)
        draft.otherAdults[0].name = "Maya"
        let party = draft.party
        #expect(party.travelerCountSummary == "You + 1 adult, 2 children")
        #expect(party.travelers.map(party.label(for:)) == ["You", "Maya", "Child 1", "Child 2"])
        #expect(Set(party.travelers.map(party.label(for:))).count == party.travelers.count, "labels are distinct")
        #expect(party.travelers.allSatisfy { $0.name != "Child 1" && $0.name != "Adult 1" }, "labels never overwrite names")

        draft.setTravelMode(.couple)
        #expect(draft.party.travelers.count == 2 && draft.party.travelers[1].name == "Maya", "switching modes keeps the details")
        draft.setTravelMode(.solo)
        #expect(draft.party.travelerCountSummary == "Just you")
    }

    /// Adult 1's and a teen's device choices become their own engine signals
    /// — never You's, never trip context, never inferred for anyone else.
    @Test func companionDeviceChoicesBecomeTravelerScopedEngineSignals() throws {
        var draft = TripDraft.fresh(preferences: Self.preferences())
        draft.destination = try Self.destination("Tokyo")
        draft.toggleTripType(.vacation)
        draft.setTravelMode(.family)
        draft.setOtherAdultCount(2)
        draft.setChildCount(2)
        draft.otherAdults[0].chips = [.bringingPhone, .bringingTablet]
        draft.childProfiles[0].ageGroup = .teen
        draft.childProfiles[0].chips = [.bringingPhone]
        draft.childProfiles[1].ageGroup = .child
        draft.childProfiles[1].chips = [.bringingPhone]  // not offered below teen; dropped
        draft.chips = [.bringingPhone, .dailyMedication]  // a device signal can never be trip context

        #expect(draft.tripChips == [.dailyMedication])
        let party = draft.party
        let context = ModelContext(try PackWisePersistence.container(inMemory: true))
        let trip = try Self.save(draft, in: context)
        #expect(!trip.contextChips.contains(.bringingPhone), "device signals are never stored as trip chips")
        #expect(trip.party.travelers.first { $0.id == party.travelers[1].id }?.chips == [.bringingPhone, .bringingTablet], "persisted per traveler")

        var tripContext = trip.context(preferences: Self.preferences(), weather: nil)
        tripContext.party = trip.party
        let items = Self.engine.generate(context: tripContext)
        func ids(_ traveler: Traveler) -> Set<String> {
            Set(items.filter { $0.ownershipType == .personal && $0.travelerID == traveler.id }.compactMap(\.canonicalItemID))
        }
        let travelers = trip.party.travelers
        let you = travelers[0], adult1 = travelers[1], adult2 = travelers[2], teen = travelers[3], child = travelers[4]
        #expect(ids(you).isSuperset(of: ["essentials.phone", "electronics.phone_charger"]), "You: implicit phone")
        #expect(ids(adult1).isSuperset(of: ["essentials.phone", "electronics.phone_charger", "electronics.tablet"]), "Adult 1: chosen devices")
        #expect(ids(adult2).isDisjoint(with: ["essentials.phone", "electronics.phone_charger", "electronics.tablet"]), "Adult 2 chose nothing")
        #expect(ids(teen).isSuperset(of: ["essentials.phone", "electronics.phone_charger"]) && !ids(teen).contains("electronics.tablet"))
        #expect(ids(child).isDisjoint(with: ["essentials.phone", "electronics.phone_charger"]), "no device choice below teen")
        #expect(!ids(you).contains("electronics.tablet"), "Adult 1's tablet never becomes You's")

        let adapter = try #require(items.first { $0.canonicalItemID == "electronics.travel_adapter" })
        #expect(adapter.quantityReasonArguments["deviceCount"] == "4", "You's phone, Adult 1's phone and tablet, the teen's phone")
    }

    // MARK: - Review

    @Test func reviewSummarizesEveryDecisionSeparately() {
        var draft = TripDraft()
        draft.toggleTripType(.beach)
        draft.toggleTripType(.vacation)
        draft.setTravelMode(.group)
        draft.setOtherAdultCount(3)
        draft.toggleActivity("snorkeling")
        draft.packingStyle = .light
        draft.laundry = .planned
        draft.chips = [.wearContacts]

        let sections = TripReviewSummary.sections(draft: draft, party: draft.party)
        let values = Dictionary(uniqueKeysWithValues: sections.map { ($0.title, $0.value) })
        #expect(sections.map(\.title) == ["Trip types", "Travelers", "Activities", "Bags", "Packing style", "Laundry", "Your devices", "Preferences"])
        #expect(values["Your devices"] == "Phone", "the implicit phone is always stated")
        #expect(values["Trip types"] == "Vacation, Beach", "stable order, every type")
        #expect(values["Travelers"] == "You + 3 adults · You, Adult 1, Adult 2, Adult 3")
        #expect(values["Activities"] == "Snorkeling")
        #expect(values["Bags"] == "Not sure yet")
        #expect(values["Packing style"] == PackingStyle.light.title)
        #expect(values["Laundry"] == "Planning to do laundry")
        #expect(values["Preferences"] == ContextChip.wearContacts.chipTitle)

        draft.toggleBag(.checked)
        draft.toggleBag(.personalItem)
        #expect(TripReviewSummary.sections(draft: draft, party: draft.party).first { $0.title == "Bags" }?.value == "Personal item only, Checked bag")
    }

    /// Task 8.1: You's phone is implicit; every other device You bring is an
    /// explicit About you choice stored on your traveler — never trip context,
    /// never API chips, never another traveler's.
    @Test func primaryDeviceChoicesStayOnYouAndNeverBecomeTripContext() throws {
        let catalog = try SharedLibrary.catalog()
        let engine = PackingEngine(catalog: catalog, rules: Self.rules)
        func items(_ draft: TripDraft) throws -> (TripRecord, [PackingItemDraft]) {
            let context = ModelContext(try PackWisePersistence.container(inMemory: true))
            let trip = try Self.save(draft, in: context)
            return (trip, engine.generate(context: trip.context(preferences: Self.preferences(), weather: nil)))
        }
        let devices: Set<String> = ["electronics.laptop", "electronics.laptop_charger", "electronics.tablet", "electronics.headphones",
                                    "electronics.power_bank", "electronics.camera", "electronics.camera_charger", "electronics.memory_card"]

        // Solo, a trip whose rules used to add headphones, a power bank, and a camera.
        var solo = TripDraft.fresh(preferences: Self.preferences())
        solo.destination = try Self.destination()
        solo.toggleTripType(.vacation)
        solo.toggleActivity("sightseeing")
        solo.toggleActivity("photography")
        let (_, none) = try items(solo)
        let noneIDs = Set(none.compactMap(\.canonicalItemID))
        #expect(noneIDs.isSuperset(of: ["essentials.phone", "electronics.phone_charger"]), "implicit phone")
        #expect(noneIDs.isDisjoint(with: devices), "no device without a choice: \(noneIDs.intersection(devices))")

        let expected: [(ContextChip, Set<String>)] = [
            (.bringingLaptop, ["electronics.laptop", "electronics.laptop_charger"]),
            (.bringingHeadphones, ["electronics.headphones"]),
            (.bringingPowerBank, ["electronics.power_bank"]),
            (.bringingCamera, ["electronics.camera", "electronics.camera_charger", "electronics.memory_card"]),
            (.bringingTablet, ["electronics.tablet"]),
        ]
        for (chip, ids) in expected {
            var draft = solo
            draft.chips = [chip]
            let (trip, generated) = try items(draft)
            let got = Set(generated.compactMap(\.canonicalItemID)).intersection(devices)
            #expect(got == ids, "\(chip): \(got)")
            if chip != .bringingLaptop {
                #expect(!trip.contextChips.contains(chip), "\(chip) is never a trip chip")
                #expect(trip.party.primary.chips.contains(chip), "\(chip) lives on You's traveler record")
                #expect(TripDraft.from(trip: trip).chips.contains(chip), "\(chip) round-trips through edit")
            }
        }

        // A party: You's choices stay yours; Adult 1's stay theirs.
        var party = solo
        party.chips = [.bringingHeadphones, .bringingPowerBank]
        party.setTravelMode(.group)
        party.setOtherAdultCount(2)
        party.otherAdults[0].chips = [.bringingCamera, .bringingHeadphones]
        let (trip, generated) = try items(party)
        let travelers = trip.party.travelers
        func ids(_ traveler: Traveler) -> Set<String> {
            Set(generated.filter { $0.travelerID == traveler.id }.compactMap(\.canonicalItemID)).intersection(devices)
        }
        #expect(ids(travelers[0]) == ["electronics.headphones", "electronics.power_bank"])
        #expect(ids(travelers[1]) == ["electronics.headphones"], "Adult 1's own headphones; the camera is shared")
        #expect(ids(travelers[2]).isEmpty, "Adult 2 chose nothing and inherits nothing")
        #expect(generated.filter { $0.ownershipType == .shared }.compactMap(\.canonicalItemID).contains("electronics.camera"))
        #expect(trip.contextChips.allSatisfy { !ContextChip.travelerDeviceSignals.contains($0) })
    }

    // MARK: - Me laptop default (Task 8.2)

    private static let laptopRows: Set<String> = ["electronics.laptop", "electronics.laptop_charger"]

    private static func meLaptop(_ on: Bool) -> TravelerPreferences {
        var prefs = Self.preferences()
        prefs.usuallyBringLaptop = on
        return prefs
    }

    private static func soloVacation(_ prefs: TravelerPreferences) throws -> TripDraft {
        var draft = TripDraft.fresh(preferences: prefs)
        draft.destination = try Self.destination()
        draft.toggleTripType(.vacation)
        draft.toggleActivity("sightseeing")
        return draft
    }

    /// Saves the draft and generates its list with `prefs` as the Me state at
    /// generation time — which may differ from the Me state that seeded it.
    private static func saveAndGenerate(_ draft: TripDraft, prefs: TravelerPreferences) throws -> (TripRecord, [PackingItemDraft], ModelContext) {
        let context = ModelContext(try PackWisePersistence.container(inMemory: true))
        let trip = try Self.save(draft, in: context)
        return (trip, Self.engine.generate(context: trip.context(preferences: prefs, weather: nil)), context)
    }

    @Test func meLaptopDefaultPrefillsYouOnAFreshTrip() throws {
        #expect(TripDraft.fresh(preferences: Self.meLaptop(true)).chips == [.bringingLaptop])
        #expect(TripDraft.fresh(preferences: Self.meLaptop(false)).chips.isEmpty)

        let (trip, items, _) = try Self.saveAndGenerate(try Self.soloVacation(Self.meLaptop(true)), prefs: Self.meLaptop(true))
        #expect(trip.party.primary.chips.contains(.bringingLaptop), "the prefill is saved as You's own choice")
        #expect(Set(items.compactMap(\.canonicalItemID)).isSuperset(of: Self.laptopRows))
    }

    @Test func deselectingThePrefilledLaptopSavesATripWithNoLaptop() throws {
        let me = Self.meLaptop(true)
        var draft = try Self.soloVacation(me)
        #expect(draft.chips.contains(.bringingLaptop))
        draft.chips.remove(.bringingLaptop)

        let (trip, items, _) = try Self.saveAndGenerate(draft, prefs: me)
        #expect(Set(items.compactMap(\.canonicalItemID)).isDisjoint(with: Self.laptopRows),
                "Me still says laptop; this trip's choice wins")
        #expect(!trip.contextChips.contains(.bringingLaptop) && !trip.party.primary.chips.contains(.bringingLaptop))
        #expect(me.usuallyBringLaptop, "deselecting on a trip never edits Me")
        #expect(TripDraft.fresh(preferences: me).chips.contains(.bringingLaptop), "the next new trip is prefilled again")
    }

    @Test func meLaptopDefaultPrefillsOnlyYouOnAPartyTrip() throws {
        let me = Self.meLaptop(true)
        var draft = try Self.soloVacation(me)
        draft.setTravelMode(.group)
        draft.setOtherAdultCount(2)
        #expect(draft.otherAdults.allSatisfy { $0.chips.isEmpty })

        let (trip, items, _) = try Self.saveAndGenerate(draft, prefs: me)
        let travelers = trip.party.travelers
        #expect(travelers.count == 3)
        func laptop(_ traveler: Traveler) -> Set<String> {
            Set(items.filter { $0.travelerID == traveler.id }.compactMap(\.canonicalItemID)).intersection(Self.laptopRows)
        }
        #expect(travelers[0].role == .self && laptop(travelers[0]) == Self.laptopRows)
        #expect(laptop(travelers[1]).isEmpty && laptop(travelers[2]).isEmpty, "Adult 1 and Adult 2 receive nothing")
        #expect(travelers[1].chips.isEmpty && travelers[2].chips.isEmpty)
        #expect(!items.contains { $0.ownershipType == .shared && Self.laptopRows.contains($0.canonicalItemID ?? "") })
    }

    @Test func changingMeNeverChangesAnExistingTripsLaptop() throws {
        // Saved with Laptop off; Me later turns it on.
        let (offTrip, _, _) = try Self.saveAndGenerate(try Self.soloVacation(Self.meLaptop(false)), prefs: Self.meLaptop(false))
        #expect(!TripDraft.from(trip: offTrip).chips.contains(.bringingLaptop), "edit restores the trip's own off state")
        let offLater = Self.engine.generate(context: offTrip.context(preferences: Self.meLaptop(true), weather: nil))
        #expect(Set(offLater.compactMap(\.canonicalItemID)).isDisjoint(with: Self.laptopRows))

        // Saved with Laptop on; Me later turns it off.
        let (onTrip, _, _) = try Self.saveAndGenerate(try Self.soloVacation(Self.meLaptop(true)), prefs: Self.meLaptop(true))
        #expect(TripDraft.from(trip: onTrip).chips.contains(.bringingLaptop), "edit restores the trip's own on state")
        let onLater = Self.engine.generate(context: onTrip.context(preferences: Self.meLaptop(false), weather: nil))
        #expect(Set(onLater.compactMap(\.canonicalItemID)).isSuperset(of: Self.laptopRows))
    }

    @Test func laptopHasOneCauseAndThePreferenceIsNotEngineInput() throws {
        let me = Self.meLaptop(true)
        let (_, items, _) = try Self.saveAndGenerate(try Self.soloVacation(me), prefs: me)
        for id in Self.laptopRows {
            let row = try #require(items.first { $0.canonicalItemID == id })
            let laptopFacts = RecommendationTrace.provenance(for: row).filter { $0.reasonCode.localizedCaseInsensitiveContains("laptop") }
            #expect(laptopFacts.count == 1, "\(id): \(laptopFacts)")
        }

        // The preference alone, with no trip choice, is not a cause.
        var context = try Self.soloVacation(me)
        context.chips.remove(.bringingLaptop)
        let (_, withoutChoice, _) = try Self.saveAndGenerate(context, prefs: me)
        #expect(Set(withoutChoice.compactMap(\.canonicalItemID)).isDisjoint(with: Self.laptopRows))
    }

    /// Trips saved before Task 8.2 may owe their laptop to the preference
    /// alone. Their own saved list, not today's Me value, decides.
    @Test func legacyPreferenceLaptopBecomesTheTripsOwnChoiceOnce() throws {
        let context = ModelContext(try PackWisePersistence.container(inMemory: true))
        let repo = TripRepository(context: context)
        func legacyTrip(laptopReason: String?, userAdded: Bool = false) throws -> TripRecord {
            let trip = try Self.save(try Self.soloVacation(Self.meLaptop(false)), in: context)
            var rows = Self.engine.generate(context: trip.context(preferences: Self.preferences(), weather: nil))
            if let laptopReason {
                rows.append(PackingItemDraft(
                    canonicalItemID: "electronics.laptop", displayName: "Laptop", category: .electronics, quantity: 1,
                    importance: .important, sourceSignals: [.userPreference], reason: "", reasonCode: laptopReason,
                    isUserAdded: userAdded, ownershipType: .personal, travelerID: trip.party.primary.id
                ))
            }
            repo.replaceItems(on: trip, with: rows)
            try context.save()
            return trip
        }
        let owed = try legacyTrip(laptopReason: LaptopChoiceBackfill.preferenceReasonCode)
        let noLaptop = try legacyTrip(laptopReason: nil)
        let typedByUser = try legacyTrip(laptopReason: "user.added", userAdded: true)

        #expect(try LaptopChoiceBackfill.run(in: context) == 1)
        #expect(owed.party.primary.chips.contains(.bringingLaptop) && TripDraft.from(trip: owed).chips.contains(.bringingLaptop))
        let regenerated = Self.engine.generate(context: owed.context(preferences: Self.meLaptop(false), weather: nil))
        #expect(Set(regenerated.compactMap(\.canonicalItemID)).isSuperset(of: Self.laptopRows), "Me off later cannot drop it")
        #expect(!noLaptop.party.primary.chips.contains(.bringingLaptop))
        #expect(!typedByUser.party.primary.chips.contains(.bringingLaptop), "a user-added row is not a preference cause")
        #expect(try LaptopChoiceBackfill.run(in: context) == 0, "idempotent")
    }

    @Test func travelerEditorHeadingsAreStructuralWhileNamesIdentifyEverywhereElse() {
        var draft = TripDraft()
        draft.setTravelMode(.family)
        draft.setOtherAdultCount(2)
        draft.setChildCount(1)
        draft.otherAdults[0].name = "Alex"
        let party = draft.party
        #expect(party.travelers.map(party.positionLabel(for:)) == ["You", "Adult 1", "Adult 2", "Child 1"])
        #expect(party.travelers.map(party.label(for:)) == ["You", "Alex", "Adult 2", "Child 1"])
    }

    @Test func preferenceGroupsNeverOfferDeviceSignalsOrLaundry() {
        let offered = PreferenceGroup.allCases.flatMap(\.chips)
        #expect(Set(offered).isDisjoint(with: ContextChip.travelerDevices), "devices are their own About you section")
        #expect(!offered.contains(.laundryAvailable), "laundry is the style step's control")
        #expect(Set(offered).count == offered.count)
    }
}
