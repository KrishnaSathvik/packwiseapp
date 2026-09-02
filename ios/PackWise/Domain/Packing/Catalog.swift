import Foundation

struct CatalogItem: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var localizationKey: String
    var displayName: String
    var category: PackingCategory
    var importance: ItemImportance
    var symbol: String
    var keywords: [String]
    var quantityKind: String
    var tags: [String]
    var capabilities: [String]
    var companions: [String]
    var travelRestrictionReviewRequired: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case localizationKey
        case displayName = "display_name"
        case category
        case importance
        case symbol
        case keywords
        case quantityKind = "quantity_kind"
        case tags
        case capabilities
        case companions
        case travelRestrictionReviewRequired
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        localizationKey = try container.decodeIfPresent(String.self, forKey: .localizationKey) ?? "packing.\(id)"
        displayName = try container.decode(String.self, forKey: .displayName)
        category = try container.decode(PackingCategory.self, forKey: .category)
        importance = try container.decode(ItemImportance.self, forKey: .importance)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "suitcase"
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        quantityKind = try container.decodeIfPresent(String.self, forKey: .quantityKind) ?? "one"
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
        companions = try container.decodeIfPresent([String].self, forKey: .companions) ?? []
        travelRestrictionReviewRequired = try container.decodeIfPresent(Bool.self, forKey: .travelRestrictionReviewRequired) ?? false
    }
}

struct PackingCatalogFile: Codable, Sendable {
    var version: Int
    var items: [CatalogItem]
}

struct PackingCatalog: Sendable {
    var items: [CatalogItem]
    private var byID: [String: CatalogItem]

    init(items: [CatalogItem]) {
        self.items = items
        self.byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    func item(id: String) -> CatalogItem? { byID[id] }

    func search(_ query: String) -> [CatalogItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return items.filter { item in
            item.displayName.lowercased().contains(q)
                || item.id.lowercased().contains(q)
                || item.keywords.contains { $0.lowercased().contains(q) }
        }
    }
}

struct ShortTripSkips: Codable, Sendable {
    /// Skip `ids` on trips of at most this many days: an organizer that
    /// claims to be core to almost every trip has to actually be one.
    var maxDays: Int
    var ids: [String]

    enum CodingKeys: String, CodingKey {
        case maxDays = "max_days"
        case ids
    }
}

struct BaseRulesFile: Codable, Sendable {
    var baseEssentials: [String]
    var internationalAdds: [String]
    var contextChips: [String: [String]]
    var freeTextKeywords: [String: String]
    var shortTripSkips: ShortTripSkips?

    enum CodingKeys: String, CodingKey {
        case baseEssentials = "base_essentials"
        case internationalAdds = "international_adds"
        case contextChips = "context_chips"
        case freeTextKeywords = "free_text_keywords"
        case shortTripSkips = "short_trip_skips"
    }
}

struct TripTypesRulesFile: Codable, Sendable {
    var tripTypes: [String: TripTypeRule]
    enum CodingKeys: String, CodingKey { case tripTypes = "trip_types" }
}

struct TripTypeRule: Codable, Sendable {
    var add: [String]
    var preferActivities: [String]?
    enum CodingKeys: String, CodingKey {
        case add
        case preferActivities = "prefer_activities"
    }
}

struct ActivityRulesFile: Codable, Sendable {
    var activities: [String: [String]]
}

struct WeatherRulesFile: Codable, Sendable {
    var thresholds: WeatherThresholds
    var signalAdds: [String: [String]]
}

struct WeatherThresholds: Codable, Sendable {
    var rainProbabilityAdd: Double
    var coolEveningMaxF: Double
    var coldMaxF: Double
    var hotMinF: Double
    var uvAdd: Double
    var windMphAdd: Double
    var temperatureSwingAdd: Double
    var heavyRainProbability: Double
    /// At or below this high, precipitation is winter precipitation and the
    /// trip counts as freezing for warm-layer purposes.
    var freezingMaxF: Double
    /// Rain on at least this fraction of trip days upgrades meaningfulRain
    /// to persistentRain.
    var persistentRainRatio: Double

    enum CodingKeys: String, CodingKey {
        case rainProbabilityAdd = "rain_probability_add"
        case coolEveningMaxF = "cool_evening_max_f"
        case coldMaxF = "cold_max_f"
        case hotMinF = "hot_min_f"
        case uvAdd = "uv_add"
        case windMphAdd = "wind_mph_add"
        case temperatureSwingAdd = "temperature_swing_add"
        case heavyRainProbability = "heavy_rain_probability"
        case freezingMaxF = "freezing_max_f"
        case persistentRainRatio = "persistent_rain_ratio"
    }

    init(
        rainProbabilityAdd: Double,
        coolEveningMaxF: Double,
        coldMaxF: Double,
        hotMinF: Double,
        uvAdd: Double,
        windMphAdd: Double,
        temperatureSwingAdd: Double,
        heavyRainProbability: Double,
        freezingMaxF: Double = 32,
        persistentRainRatio: Double = 0.5
    ) {
        self.rainProbabilityAdd = rainProbabilityAdd
        self.coolEveningMaxF = coolEveningMaxF
        self.coldMaxF = coldMaxF
        self.hotMinF = hotMinF
        self.uvAdd = uvAdd
        self.windMphAdd = windMphAdd
        self.temperatureSwingAdd = temperatureSwingAdd
        self.heavyRainProbability = heavyRainProbability
        self.freezingMaxF = freezingMaxF
        self.persistentRainRatio = persistentRainRatio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rainProbabilityAdd = try container.decode(Double.self, forKey: .rainProbabilityAdd)
        coolEveningMaxF = try container.decode(Double.self, forKey: .coolEveningMaxF)
        coldMaxF = try container.decode(Double.self, forKey: .coldMaxF)
        hotMinF = try container.decode(Double.self, forKey: .hotMinF)
        uvAdd = try container.decode(Double.self, forKey: .uvAdd)
        windMphAdd = try container.decode(Double.self, forKey: .windMphAdd)
        temperatureSwingAdd = try container.decode(Double.self, forKey: .temperatureSwingAdd)
        heavyRainProbability = try container.decode(Double.self, forKey: .heavyRainProbability)
        freezingMaxF = try container.decodeIfPresent(Double.self, forKey: .freezingMaxF) ?? 32
        persistentRainRatio = try container.decodeIfPresent(Double.self, forKey: .persistentRainRatio) ?? 0.5
    }
}

struct QuantityPolicyFile: Decodable, Sendable {
    var policies: [String: QuantityPolicy]
}

struct QuantityPolicy: Decodable, Sendable {
    var kind: String
    var value: Int?
    var alias: String?
    var light: QuantityStyleSpec?
    var balanced: QuantityStyleSpec?
    var prepared: QuantityStyleSpec?
    var thresholdDays: Int?
    var lightDivisor: Int?
    var balancedDivisor: Int?
    var min: Int?

    enum CodingKeys: String, CodingKey {
        case kind, value, alias, light, balanced, prepared, min
        case thresholdDays = "threshold_days"
        case lightDivisor = "light_divisor"
        case balancedDivisor = "balanced_divisor"
    }
}

struct QuantityStyleSpec: Decodable, Sendable {
    var factor: Double?
    var min: Int?
    var plus: Int?
    var laundryPlus: Int?
    var noLaundryMinus: Int?
    var noLaundryPlus: Int?
    var laundryMinus: Int?
    var noLaundryUseDays: Bool?
    var laundryUse: String?
    var noLaundryUse: String?

    enum CodingKeys: String, CodingKey {
        case factor, min, plus
        case laundryPlus = "laundry_plus"
        case noLaundryMinus = "no_laundry_minus"
        case noLaundryPlus = "no_laundry_plus"
        case laundryMinus = "laundry_minus"
        case noLaundryUseDays = "no_laundry_use_days"
        case laundryUse = "laundry_use"
        case noLaundryUse = "no_laundry_use"
    }

    init(from decoder: Decoder) throws {
        if let reuse = try? decoder.singleValueContainer().decode(Double.self) {
            factor = reuse
            min = nil
            plus = nil
            laundryPlus = nil
            noLaundryMinus = nil
            noLaundryPlus = nil
            laundryMinus = nil
            noLaundryUseDays = nil
            laundryUse = nil
            noLaundryUse = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        factor = try container.decodeIfPresent(Double.self, forKey: .factor)
        min = try container.decodeIfPresent(Int.self, forKey: .min)
        plus = try container.decodeIfPresent(Int.self, forKey: .plus)
        laundryPlus = try container.decodeIfPresent(Int.self, forKey: .laundryPlus)
        noLaundryMinus = try container.decodeIfPresent(Int.self, forKey: .noLaundryMinus)
        noLaundryPlus = try container.decodeIfPresent(Int.self, forKey: .noLaundryPlus)
        laundryMinus = try container.decodeIfPresent(Int.self, forKey: .laundryMinus)
        noLaundryUseDays = try container.decodeIfPresent(Bool.self, forKey: .noLaundryUseDays)
        laundryUse = try container.decodeIfPresent(String.self, forKey: .laundryUse)
        noLaundryUse = try container.decodeIfPresent(String.self, forKey: .noLaundryUse)
    }
}

struct SubstitutionRulesFile: Codable, Sendable {
    var needs: [String: [String]]
    var preferSingleWhen: [String: SubstitutionPreference]
}

struct SubstitutionPreference: Codable, Sendable {
    var ifActivity: String?
    var unlessActivity: String?
    var keep: String?
    var drop: String?
    var reasonCode: String?
}

struct ReasonTemplatesFile: Codable, Sendable {
    var templates: [String: String]
}

struct PartyRulesFile: Codable, Sendable {
    var sharedByDefault: [String]
    /// Skipped for infants, toddlers, and school-age children.
    var skipForYoungChildren: [String]
    /// Skipped only below school age: items a school-age child plausibly
    /// carries (headphones, a book, their own organizers) that a toddler
    /// does not.
    var skipForInfantsAndToddlers: [String]
    var ageGroups: [String: AgeGroupRule]
    var activityAdds: [String: [String]]
    var sharingPolicies: [String: SharingPolicyRule]

    enum CodingKeys: String, CodingKey {
        case sharedByDefault, skipForYoungChildren, skipForInfantsAndToddlers, ageGroups, activityAdds, sharingPolicies
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sharedByDefault = try container.decode([String].self, forKey: .sharedByDefault)
        skipForYoungChildren = try container.decode([String].self, forKey: .skipForYoungChildren)
        skipForInfantsAndToddlers = try container.decodeIfPresent([String].self, forKey: .skipForInfantsAndToddlers) ?? []
        ageGroups = try container.decode([String: AgeGroupRule].self, forKey: .ageGroups)
        activityAdds = try container.decode([String: [String]].self, forKey: .activityAdds)
        sharingPolicies = try container.decode([String: SharingPolicyRule].self, forKey: .sharingPolicies)
    }
}

struct AgeGroupRule: Codable, Sendable {
    var add: [String]
    var candidates: [String: [String]]
    var skipAdultClothing: Bool
    var quantityMultipliers: [String: Double]

    enum CodingKeys: String, CodingKey {
        case add, candidates, skipAdultClothing, quantityMultipliers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        add = try container.decodeIfPresent([String].self, forKey: .add) ?? []
        candidates = try container.decodeIfPresent([String: [String]].self, forKey: .candidates) ?? [:]
        skipAdultClothing = try container.decodeIfPresent(Bool.self, forKey: .skipAdultClothing) ?? false
        quantityMultipliers = try container.decodeIfPresent([String: Double].self, forKey: .quantityMultipliers) ?? [:]
    }
}

struct SharingPolicyRule: Codable, Sendable {
    var policy: SharingPolicy
    var per: Int?
    var min: Int?
    var value: Int?
}

struct PackingRulesFile: Sendable {
    var base: BaseRulesFile
    var tripTypes: [String: TripTypeRule]
    var activities: [String: [String]]
    var weather: WeatherRulesFile
    var quantities: QuantityPolicyFile
    var substitutions: SubstitutionRulesFile
    var reasons: ReasonTemplatesFile
    var party: PartyRulesFile

    var baseEssentials: [String] { base.baseEssentials }
    var internationalAdds: [String] { base.internationalAdds }
    var contextChips: [String: [String]] { base.contextChips }
    var freeTextKeywords: [String: String] { base.freeTextKeywords }
}

struct RecommendationProvenance: Hashable, Sendable {
    var reasonCode: String
    var reasonArguments: [String: String]
    var sourceSignals: [RecommendationSignal]
}

struct PackingItemDraft: Hashable, Identifiable, Codable, Sendable {
    var id: UUID
    var canonicalItemID: String?
    var displayName: String
    var category: PackingCategory
    var quantity: Int
    var packedQuantity: Int
    var importance: ItemImportance
    var sourceSignals: [RecommendationSignal]
    var reason: String
    var reasonCode: String
    var reasonArguments: [String: String]
    var quantityReason: String
    var isUserAdded: Bool
    var isUserModified: Bool
    var ownershipType: PackingOwnership
    /// Whose item this is. Nil when `ownershipType` is shared.
    var travelerID: UUID?
    /// Who is responsible for bringing it. Distinct from the owner.
    var assignedTravelerID: UUID?
    var bagID: UUID?

    var isPacked: Bool { packedQuantity >= max(1, quantity) }

    var recommendationKey: String {
        guard let canonical = canonicalItemID else { return id.uuidString }
        switch ownershipType {
        case .shared: return "shared:\(canonical)"
        case .personal: return "personal:\(travelerID?.uuidString ?? "none"):\(canonical)"
        }
    }

    init(
        id: UUID = UUID(),
        canonicalItemID: String?,
        displayName: String,
        category: PackingCategory,
        quantity: Int,
        packedQuantity: Int = 0,
        importance: ItemImportance,
        sourceSignals: [RecommendationSignal],
        reason: String,
        reasonCode: String = "",
        reasonArguments: [String: String] = [:],
        quantityReason: String = "",
        isUserAdded: Bool = false,
        isUserModified: Bool = false,
        ownershipType: PackingOwnership = .personal,
        travelerID: UUID? = nil,
        assignedTravelerID: UUID? = nil,
        bagID: UUID? = nil
    ) {
        self.id = id
        self.canonicalItemID = canonicalItemID
        self.displayName = displayName
        self.category = category
        self.quantity = quantity
        self.packedQuantity = packedQuantity
        self.importance = importance
        self.sourceSignals = sourceSignals
        self.reason = reason
        self.reasonCode = reasonCode
        self.reasonArguments = reasonArguments
        self.quantityReason = quantityReason
        self.isUserAdded = isUserAdded
        self.isUserModified = isUserModified
        self.ownershipType = ownershipType
        self.travelerID = travelerID
        self.assignedTravelerID = assignedTravelerID
        self.bagID = bagID
    }
}

struct QuantityChangeSuggestion: Hashable, Codable, Sendable {
    var item: PackingItemDraft
    var suggestedQuantity: Int
}

struct RecommendationDiff: Hashable, Identifiable, Codable, Sendable {
    var id: UUID = UUID()
    var add: [PackingItemDraft]
    var removeCandidates: [PackingItemDraft]
    var quantityChanges: [QuantityChangeSuggestion]

    var isEmpty: Bool {
        add.isEmpty && removeCandidates.isEmpty && quantityChanges.isEmpty
    }
}

struct RecommendationOverrideDraft: Hashable, Sendable {
    var canonicalItemID: String
    var action: String
    var travelerID: UUID? = nil
    var ownershipType: PackingOwnership? = nil
}

struct RuleSuggestion: Hashable, Sendable {
    var canonicalItemID: String
    var signals: [RecommendationSignal]
    var reasonCode: String
    var reasonArguments: [String: String]
    var reason: String
}
