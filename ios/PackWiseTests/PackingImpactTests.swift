import Foundation
import Testing
@testable import PackWise

struct PackingImpactTests {
    private func rules() throws -> PackingRulesFile {
        try SharedLibrary.rules()
    }

    private func build(_ items: [PackingItemDraft], party: TripParty = .solo()) throws -> [PackingImpact] {
        let rules = try rules()
        return PackingImpactBuilder.build(
            items: items,
            party: party,
            signalAdds: rules.weather.signalAdds,
            templates: rules.reasons.templates
        )
    }

    private func weatherItem(
        canonicalID: String,
        name: String,
        category: PackingCategory = .clothing,
        importance: ItemImportance = .normal,
        code: String,
        arguments: [String: String] = [:],
        signals: [RecommendationSignal] = [.weather],
        ownership: PackingOwnership = .personal,
        travelerID: UUID? = nil,
        quantity: Int = 1,
        isUserAdded: Bool = false
    ) -> PackingItemDraft {
        PackingItemDraft(
            canonicalItemID: canonicalID,
            displayName: name,
            category: category,
            quantity: quantity,
            importance: importance,
            sourceSignals: signals,
            reason: "",
            reasonCode: code,
            reasonArguments: arguments,
            isUserAdded: isUserAdded,
            ownershipType: ownership,
            travelerID: travelerID
        )
    }

    @Test func rainSignalGroupsRainJacketAndUmbrella() throws {
        let items = [
            weatherItem(
                canonicalID: "clothing.rain_jacket",
                name: "Rain jacket",
                code: "weather.rain_weekday",
                arguments: ["weekday": "Saturday"]
            ),
            weatherItem(
                canonicalID: "essentials.umbrella_compact",
                name: "Compact umbrella",
                category: .essentials,
                code: "weather.rain_weekday",
                arguments: ["weekday": "Saturday"]
            )
        ]
        let impacts = try build(items)
        #expect(impacts.count == 1)
        #expect(impacts[0].signal == .meaningfulRain)
        #expect(impacts[0].title == "Rain expected Saturday")
        #expect(Set(impacts[0].affectedItems.compactMap(\.canonicalItemID)) == [
            "clothing.rain_jacket",
            "essentials.umbrella_compact"
        ])
        #expect(impacts[0].summary.contains("added"))
    }

    @Test func coldEveningsGroupsLightLayers() throws {
        let items = [
            weatherItem(
                canonicalID: "clothing.light_sweater",
                name: "Light sweater",
                code: "weather.cool_evenings"
            )
        ]
        let impacts = try build(items)
        #expect(impacts.count == 1)
        #expect(impacts[0].signal == .coldEvenings)
        #expect(impacts[0].title == "Cool evenings")
        #expect(impacts[0].summary == "Light sweater added")
    }

    @Test func highUVGroupsSunscreenAsRecommended() throws {
        let items = [
            weatherItem(
                canonicalID: "toiletries.sunscreen",
                name: "Sunscreen",
                category: .toiletries,
                importance: .important,
                code: "weather.uv"
            )
        ]
        let impacts = try build(items)
        #expect(impacts.count == 1)
        #expect(impacts[0].signal == .highUVExposure)
        #expect(impacts[0].title == "High UV")
        #expect(impacts[0].affectedItems[0].effect == .recommended)
        #expect(impacts[0].summary == "Sunscreen recommended")
    }

    @Test func multipleTravelersCollapseIntoOneImpact() throws {
        let krishna = Traveler.primarySelf(name: "Krishna")
        let maya = Traveler(name: "Maya", role: .partner, ageGroup: .adult)
        let arjun = Traveler(name: "Arjun", role: .child, ageGroup: .child)
        let party = TripParty(travelMode: .family, travelers: [krishna, maya, arjun])
        let rainArgs = ["rainDays": "2", "tripDays": "5"]
        let items = [
            weatherItem(
                canonicalID: "clothing.rain_jacket",
                name: "Rain jacket",
                code: "weather.rain_days",
                arguments: rainArgs,
                travelerID: krishna.id
            ),
            weatherItem(
                canonicalID: "clothing.rain_jacket",
                name: "Rain jacket",
                code: "weather.rain_days",
                arguments: rainArgs,
                travelerID: maya.id
            ),
            weatherItem(
                canonicalID: "clothing.rain_jacket",
                name: "Rain jacket",
                code: "weather.rain_days",
                arguments: rainArgs,
                travelerID: arjun.id
            ),
            weatherItem(
                canonicalID: "essentials.umbrella_compact",
                name: "Compact umbrella",
                category: .essentials,
                code: "weather.rain_days",
                arguments: rainArgs,
                ownership: .shared,
                quantity: 2
            )
        ]
        let impacts = try build(items, party: party)
        #expect(impacts.count == 1)
        #expect(impacts[0].signal == .persistentRain)
        #expect(impacts[0].affectedItems.count == 4)
        #expect(impacts[0].summary == "Rain layers and 2 shared umbrellas added")
        #expect(impacts[0].affectedItems.contains { $0.ownerLabel == "Krishna" })
        #expect(impacts[0].affectedItems.contains { $0.ownerLabel == "Shared" })
    }

    @Test func sharedAndPersonalEffectsCoexist() throws {
        let krishna = Traveler.primarySelf(name: "Krishna")
        let maya = Traveler(name: "Maya", role: .partner, ageGroup: .adult)
        let party = TripParty(travelMode: .couple, travelers: [krishna, maya])
        let items = [
            weatherItem(
                canonicalID: "clothing.rain_jacket",
                name: "Rain jacket",
                code: "weather.rain_weekday",
                arguments: ["weekday": "Saturday"],
                travelerID: krishna.id
            ),
            weatherItem(
                canonicalID: "essentials.umbrella_compact",
                name: "Compact umbrella",
                category: .essentials,
                code: "weather.rain_weekday",
                arguments: ["weekday": "Saturday"],
                ownership: .shared
            )
        ]
        let impacts = try build(items, party: party)
        #expect(impacts.count == 1)
        let owners = Set(impacts[0].affectedItems.compactMap(\.ownerLabel))
        #expect(owners.contains("Krishna"))
        #expect(owners.contains("Shared"))
        #expect(!owners.contains("Maya"))
    }

    @Test func weatherPlusActivitySourceStillAppears() throws {
        let sweater = weatherItem(
            canonicalID: "clothing.light_sweater",
            name: "Light sweater",
            code: "weather.cool_evenings",
            signals: [.activity, .weather]
        )
        let hiking = PackingItemDraft(
            canonicalItemID: "footwear.hiking_shoes",
            displayName: "Hiking shoes",
            category: .footwear,
            quantity: 1,
            importance: .important,
            sourceSignals: [.activity],
            reason: "Hiking is on your plans.",
            reasonCode: "activity.hiking"
        )
        let impacts = try build([sweater, hiking])
        #expect(impacts.count == 1)
        #expect(impacts[0].signal == .coldEvenings)
        #expect(impacts[0].affectedItems.map(\.canonicalItemID) == ["clothing.light_sweater"])
    }

    @Test func nonWeatherRecommendationIsExcluded() throws {
        let hiking = PackingItemDraft(
            canonicalItemID: "footwear.hiking_shoes",
            displayName: "Hiking shoes",
            category: .footwear,
            quantity: 1,
            importance: .important,
            sourceSignals: [.activity],
            reason: "Hiking is on your plans.",
            reasonCode: "activity.hiking"
        )
        #expect(try build([hiking]).isEmpty)
    }

    @Test func noWeatherRecommendationsMeansNoPackingImpact() throws {
        #expect(try build([]).isEmpty)
        let wallet = PackingItemDraft(
            canonicalItemID: "essentials.wallet",
            displayName: "Wallet",
            category: .essentials,
            quantity: 1,
            importance: .critical,
            sourceSignals: [.baseEssential],
            reason: "A core item for almost every trip.",
            reasonCode: "base.essential"
        )
        #expect(try build([wallet]).isEmpty)
    }

    @Test func userAddedItemsAreNotImpacts() throws {
        let custom = weatherItem(
            canonicalID: "clothing.rain_jacket",
            name: "Rain jacket",
            code: "weather.rain_weekday",
            arguments: ["weekday": "Saturday"],
            isUserAdded: true
        )
        #expect(try build([custom]).isEmpty)
    }

    @Test func partialForecastDoesNotClaimUncoveredDays() throws {
        let items = [
            weatherItem(
                canonicalID: "clothing.rain_jacket",
                name: "Rain jacket",
                code: "weather.rain_days",
                arguments: ["rainDays": "1", "tripDays": "3"]
            )
        ]
        let impacts = try build(items)
        #expect(impacts.count == 1)
        #expect(impacts[0].title == "Rain expected on 1 days")
        #expect(!impacts[0].title.contains("7"))
        #expect(!impacts[0].title.contains("uncovered"))
    }

    @Test func reverseLookupUsesCatalogSignalAddsNotLiveWeather() throws {
        let jacket = weatherItem(
            canonicalID: "clothing.rain_jacket",
            name: "Rain jacket",
            code: ""
        )
        let impacts = try build([jacket])
        #expect(impacts.count == 1)
        #expect(impacts[0].signal == .persistentRain || impacts[0].signal == .meaningfulRain)
    }

    @Test func fixtureWeatherDoesNotShowAppleAttribution() async throws {
        let destination = try SharedLibrary.testDestinations().first { $0.city == "Chicago" }!
        let weather = try await MockWeatherService.bundled().weather(
            for: destination,
            start: Date.now,
            end: Calendar.current.date(byAdding: .day, value: 4, to: Date.now)!
        )
        guard case .forecast(let context) = weather else {
            Issue.record("Expected fixture forecast")
            return
        }
        #expect(context.source == .fixture)
        #expect(!context.showsAppleWeatherAttribution)
    }

    @Test func appleWeatherDoesShowAttribution() {
        let start = Date.now
        var context = TripWeatherContext.seasonal(fetchedAt: start)
        context.source = .weatherKit
        context.isPreciseForecast = true
        context.forecastAvailableForWholeTrip = true
        context.attribution = .applePlaceholder
        #expect(context.showsAppleWeatherAttribution)
        context.source = .fixture
        context.attribution = nil
        #expect(!context.showsAppleWeatherAttribution)
    }

    @Test func whyThisProvenanceMatchesImpactProvenance() async throws {
        let destination = try SharedLibrary.testDestinations().first { $0.city == "Chicago" }!
        let weather = try await MockWeatherService.bundled().weather(
            for: destination,
            start: Date.now,
            end: Calendar.current.date(byAdding: .day, value: 4, to: Date.now)!
        )
        guard case .forecast(let tripWeather) = weather else {
            Issue.record("Expected fixture forecast")
            return
        }
        let engine = PackingEngine(catalog: try SharedLibrary.catalog(), rules: try rules())
        var prefs = TravelerPreferences.deviceDefaults()
        prefs.homeCountryCode = "US"
        prefs.homeCountrySource = .userConfirmed
        let start = Calendar.current.startOfDay(for: Date.now)
        let end = Calendar.current.date(byAdding: .day, value: 4, to: start)!
        let math = TripDateMath.daysAndNights(from: start, to: end)
        let context = TripContext(
            destination: destination,
            startDate: start,
            endDate: end,
            durationDays: math.days,
            durationNights: math.nights,
            tripType: .cityBreak,
            activities: ["sightseeing", "walking"],
            datedActivities: ["sightseeing", "walking"].map { DatedActivity(activityID: $0, date: nil) },
            bagType: .carryOn,
            packingStyle: .light,
            transportation: .unknown,
            laundryAccess: .planned,
            travelerCount: 1,
            userNotes: "",
            contextChips: [.laundryAvailable],
            weather: tripWeather,
            preferences: prefs
        )
        let items = engine.generate(context: context)
        let jacket = try #require(items.first { $0.canonicalItemID == "clothing.rain_jacket" })
        #expect(jacket.sourceSignals.contains(.weather))
        #expect(!jacket.reasonCode.isEmpty)
        let impacts = try build(items)
        let rain = try #require(impacts.first { $0.signal == .meaningfulRain || $0.signal == .persistentRain })
        #expect(rain.reasonCodes.contains(jacket.reasonCode))
        #expect(rain.affectedItems.contains { $0.canonicalItemID == "clothing.rain_jacket" })
        #expect(jacket.reason.localizedCaseInsensitiveContains("rain"))
        #expect(rain.title.localizedCaseInsensitiveContains("rain"))
    }

    @Test func engineDoesNotInventItemsPackingImpactDidNotReceive() throws {
        let sweater = weatherItem(
            canonicalID: "clothing.light_sweater",
            name: "Light sweater",
            code: "weather.cool_evenings"
        )
        let impacts = try build([sweater])
        let ids = Set(impacts.flatMap { $0.affectedItems.compactMap(\.canonicalItemID) })
        #expect(ids == ["clothing.light_sweater"])
        #expect(!ids.contains("toiletries.sunscreen"))
    }
}
