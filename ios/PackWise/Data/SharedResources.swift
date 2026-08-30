import Foundation

enum ResourceError: Error {
    case missing(String)
}

enum SharedLibrary {
    private static let catalogFiles = [
        "essentials", "documents", "clothing", "footwear", "toiletries",
        "electronics", "health", "activities", "travel-comfort", "kids", "miscellaneous"
    ]

    static func catalog(bundle: Bundle = .main) throws -> PackingCatalog {
        var items: [CatalogItem] = []
        for name in catalogFiles {
            let data = try data(named: name, in: bundle)
            items.append(contentsOf: try JSONDecoder().decode(PackingCatalogFile.self, from: data).items)
        }
        return PackingCatalog(items: items)
    }

    static func rules(bundle: Bundle = .main) throws -> PackingRulesFile {
        let decoder = JSONDecoder()
        return PackingRulesFile(
            base: try decoder.decode(BaseRulesFile.self, from: try data(named: "base", in: bundle)),
            tripTypes: try decoder.decode(TripTypesRulesFile.self, from: try data(named: "trip-types", in: bundle)).tripTypes,
            activities: try decoder.decode(ActivityRulesFile.self, from: try data(named: "activity-rules", in: bundle)).activities,
            weather: try decoder.decode(WeatherRulesFile.self, from: try data(named: "weather", in: bundle)),
            quantities: try decoder.decode(QuantityPolicyFile.self, from: try data(named: "quantities", in: bundle)),
            substitutions: try decoder.decode(SubstitutionRulesFile.self, from: try data(named: "substitutions", in: bundle)),
            reasons: try decoder.decode(ReasonTemplatesFile.self, from: try data(named: "reasons", in: bundle)),
            party: try decoder.decode(PartyRulesFile.self, from: try data(named: "party", in: bundle))
        )
    }

    static func testDestinations(bundle: Bundle = .main) throws -> [Destination] {
        struct File: Codable { var destinations: [Destination] }
        return try JSONDecoder().decode(File.self, from: try data(named: "test-destinations", in: bundle)).destinations
    }

    static func weatherFixtures(bundle: Bundle = .main) throws -> [String: WeatherFixture] {
        try JSONDecoder().decode(WeatherFixtureFile.self, from: try data(named: "named-fixtures", in: bundle)).fixtures
    }

    static func tripEvals(bundle: Bundle = .main) throws -> [TripEvalFixture] {
        let names = [
            "BusinessTrip3Day", "ChicagoCityRainy5Day", "DenverOutdoorCold",
            "FamilyToddlerThemePark", "LongHaulInternationalFlight", "MiamiBeachCarryOn",
            "OneDayNoWeather", "OverrideKeepsRainJacketDeleted", "PreserveManualQuantity",
            "ReykjavikPhotography", "TokyoInternationalWalking", "WeddingWeekend"
        ]
        return try names.compactMap { name in
            guard let url = bundle.url(forResource: name, withExtension: "json") else { return nil }
            return try JSONDecoder().decode(TripEvalFixture.self, from: Data(contentsOf: url))
        }
    }

    static func data(named name: String, in bundle: Bundle) throws -> Data {
        if let url = bundle.url(forResource: name, withExtension: "json") {
            return try Data(contentsOf: url)
        }
        throw ResourceError.missing(name)
    }
}

struct TripEvalFixture: Codable, Sendable {
    var id: String
    var destinationFixture: String
    var weatherFixture: String?
    var days: Int
    var tripType: String
    var activities: [String]
    var bag: String
    var style: String
    var chips: [String]?
    var homeCountryCode: String
    var homeCountrySource: String
    var overrides: [OverrideEval]?
    var existing: [ExistingEval]?
    var mustInclude: [String]
    var mustNotInclude: [String]?
    var expectedQuantityRanges: [String: [Int]]?
    var expectedExactQuantities: [String: Int]?
    var travelerCount: Int?
    var party: PartyEval?
    /// Free-form trip note. The input to trip-note interpretation.
    var note: String?
    /// Chips and activities interpretation must produce from `note`.
    var mustInfer: [String]?
    /// Chips and activities interpretation must not produce. Guards against
    /// over-reading the note.
    var mustNotInfer: [String]?
    /// Canonical IDs that are legitimate contextual gap suggestions here.
    var allowedSuggestions: [String]?
}

struct PartyEval: Codable, Sendable {
    var travelMode: String
    var travelers: [TravelerEval]
}

struct TravelerEval: Codable, Sendable {
    var role: String
    var ageGroup: String
    var needs: [String]?
    var chips: [String]?
}

struct OverrideEval: Codable, Sendable {
    var canonicalItemID: String
    var action: String
}

struct ExistingEval: Codable, Sendable {
    var canonicalItemID: String
    var displayName: String
    var category: String
    var quantity: Int
    var isUserModified: Bool
}
