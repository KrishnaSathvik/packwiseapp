import Foundation

/// Customer language over the single RecommendationTrace authority. No trip,
/// catalog, weather service or resolver input: only this record's accepted facts.
/// Complete templates make grammar independent of raw taxonomy and set order.
enum RecommendationReasonRenderer {
    struct CustomerReason: Equatable, Sendable {
        var text: String
        var showsInList: Bool = true
    }

    struct PresentationContext: Sendable {
        var ownerName: String? = nil
        var isPrimaryTraveler = true
    }

    static func reason(for item: PackingItemDraft, context: PresentationContext = .init()) -> CustomerReason? {
        let authority = RecommendationTrace.authority(for: item)
        guard !authority.isUserAdded, !authority.isCustomItem else { return nil }
        let facts = RecommendationTrace.provenance(for: item)
        guard !facts.isEmpty else { return nil } // old stores never invent missing evidence
        let codes = Set(facts.map(\.reasonCode))
        let types = Set(facts.compactMap(\.tripType))
        func result(_ text: String) -> CustomerReason {
            // Names label the owner, never contribute a recommendation signal.
            let otherOwnerTemplates = [
                "For the camera you're bringing.": "For the camera they're bringing.",
                "For the laptop you're bringing.": "For the laptop they're bringing.",
                "For the tablet you're bringing.": "For the tablet they're bringing.",
                "For your phone.": "For their phone.",
                "For storing your contact lenses.": "For storing their contact lenses.",
                "An extra layer if you get cold easily.": "An extra layer if they get cold easily."
            ]
            let rendered = context.isPrimaryTraveler ? text : (otherOwnerTemplates[text] ?? text)
            return CustomerReason(text: rendered)
        }

        // Display priority only: owned need/device, activity, weather, trip,
        // other specific evidence, then a quiet generic fallback. Engine tiers
        // and the complete persisted facts are deliberately untouched.
        if item.ownershipType == .personal, item.travelerID != nil {
            let names = Set(facts.filter { $0.reasonCode == "party.age_group" && $0.sourceSignals.contains(.userPreference) }
                .compactMap { $0.reasonArguments["name"] }.filter { !$0.isEmpty })
            if names.count == 1, let storedName = names.first {
                let name = context.ownerName ?? storedName
                return result(item.canonicalItemID == "kids.stroller"
                    ? "For \(name) while getting around." : "For \(name).")
            }
        }
        for (code, text) in ownedTemplates where codes.contains(code) { return result(text) }
        if codes.contains("dependency.companion") {
            // The companion fact is generated inside the owner's resolution
            // group. Never look up a different traveler's device or live chips.
            let companions = Set(facts.filter { $0.reasonCode == "dependency.companion" }
                .compactMap { $0.reasonArguments["item"] })
            for (name, text) in companionTemplates where companions.contains(name) { return result(text) }
            return result("Goes with another item on this list.")
        }
        if codes.contains("activity.sightseeing"), types.contains(.cityBreak) {
            return result("Useful for sightseeing and days around the city.")
        }
        for (code, text) in activityTemplates where codes.contains(code) { return result(text) }
        if codes.contains("weather.hot"), codes.contains("weather.uv") {
            return result("For hot, sunny weather.")
        }
        for (code, text) in weatherTemplates where codes.contains(code) { return result(text) }
        if types.contains(.beach), types.contains(.festival) {
            return result("Useful for beach and festival days.")
        }
        if types.contains(.business), types.contains(.weddingEvent) {
            return result("For work and the event.")
        }
        // Specific types precede general Vacation/Other. Never recite all
        // selected metadata: these are only the types that contributed this item.
        for (type, text) in tripTemplates where types.contains(type) {
            return CustomerReason(text: text, showsInList: type != .vacation && type != .other)
        }
        for (code, text) in otherTemplates where codes.contains(code) { return result(text) }
        if codes.contains("base.essential.clothing") {
            return CustomerReason(text: "Everyday clothing for the trip.", showsInList: false)
        }
        return CustomerReason(text: "Useful for this trip.", showsInList: false)
    }

    /// Quantity is a separate trace facet, never a replacement inclusion cause.
    static func quantityExplanation(for item: PackingItemDraft) -> String? {
        let facet = RecommendationTrace.quantityFacet(for: item)
        if item.isUserModified { return nil } // old computed quantity may no longer apply
        if let evidence = facet.clothingEvidence, evidence.bagCapApplied {
            // Evidence records the applied cap, not the selected bag's identity.
            // Do not infer a personal-item bag from a numeric cap.
            return "Packed lighter to fit your luggage."
        }
        if item.ownershipType == .shared, !facet.reasonArguments.isEmpty {
            return "\(facet.value) for the group."
        }
        return facet.reason.isEmpty ? nil : facet.reason
    }

    private static let ownedTemplates: [(String, String)] = [
        ("preference.dailyMedication", "For daily medication."),
        ("preference.wearContacts", "For wearing contact lenses."),
        ("preference.bringingCamera", "For the camera you're bringing."),
        ("preference.bringingLaptop", "For the laptop you're bringing."),
        ("preference.bringingTablet", "For the tablet you're bringing."),
        ("preference.bringingPhone", "For your phone."),
        ("preference.bringingHeadphones", "For listening on the go."),
        ("preference.bringingPowerBank", "For charging on the go."),
        ("preference.getColdEasily", "An extra layer if you get cold easily."),
        ("preference.needFormalOutfit", "For dressing up."),
        ("preference.runWhileTraveling", "For running."),
        ("preference.usuallyWorkOut", "For working out."),
        ("preference.laundryAvailable", "For doing laundry during the trip.")
    ]
    private static let companionTemplates: [(String, String)] = [
        ("camera", "For the camera you're bringing."),
        ("laptop", "For the laptop you're bringing."),
        ("tablet", "For the tablet you're bringing."),
        ("phone", "For your phone."),
        ("contact solution", "For storing your contact lenses.")
    ]
    private static let activityTemplates: [(String, String)] = [
        ("activity.hiking", "For hiking."), ("activity.camping", "For camping."),
        ("activity.swimming", "For swimming."), ("activity.snorkeling", "For snorkeling."),
        ("activity.running", "For running."), ("activity.yoga", "For yoga."),
        ("activity.boatTrip", "For the boat trip."), ("activity.niceDinner", "For a nicer dinner."),
        ("activity.nightlife", "For nights out."), ("activity.work", "For work."),
        ("activity.sightseeing", "Useful for sightseeing."), ("activity.walking", "For walking days."),
        ("activity.beachDays", "Useful for beach days."), ("activity.museums", "For museum visits."),
        ("activity.shopping", "For shopping."), ("activity.wildlife", "For wildlife watching.")
        // Photography is context-only; it cannot manufacture equipment evidence.
    ]
    private static let weatherTemplates: [(String, String)] = [
        ("weather.rain_days", "Rain is expected during your trip."),
        ("weather.rain_weekday", "Rain is expected during your trip."),
        ("weather.snow", "Snow is expected during your trip."),
        ("weather.freezing", "For freezing weather."),
        ("weather.sustained_cold", "For cold weather throughout the trip."),
        ("weather.cold", "For colder parts of the trip."),
        ("weather.uv", "Useful for strong sun."), ("weather.hot", "For hot weather."),
        ("weather.cool_evenings", "For cooler evenings."),
        ("weather.temperature_swing", "For changing temperatures during the day."),
        ("weather.wind", "For windy conditions."),
        ("weather.seasonal_layer", "A layer for typically cooler conditions this time of year."),
        ("weather.seasonal_sun", "Sun protection for typical conditions this time of year.")
    ]
    private static let tripTemplates: [(TripType, String)] = [
        (.beach, "Useful for the beach."), (.business, "For work."),
        (.weddingEvent, "For the event."), (.skiSnow, "For snow activities."),
        (.outdoor, "For outdoor activities."), (.cityBreak, "Useful for city days."),
        (.roadTrip, "For the road trip."), (.festival, "For the festival."),
        (.visitingFamily, "Useful while visiting family."),
        (.vacation, "Useful for this trip."), (.other, "Useful for this trip.")
    ]
    private static let otherTemplates: [(String, String)] = [
        ("documents.visa_check", "Check the entry requirements that apply to you."),
        ("destination.international", "For international travel."),
        ("preference.travelingInternationally", "For international travel."),
        ("flight.empty_bottle", "Fill it after airport security."),
        ("substitution.hiking_covers_walking", "For hiking and walking days."),
        ("substitution.running_covers_walking", "For running and walking days.")
    ]
}
