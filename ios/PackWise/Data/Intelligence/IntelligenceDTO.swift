import Foundation

/// Wire types for the PackWise Intelligence API. Mirrors
/// `shared/schemas/intelligence/api.schema.json`; the server validates both
/// directions, and these decode what survived that.
enum IntelligenceDTO {
    struct Destination: Encodable, Sendable {
        var displayName: String
        var countryCode: String
        var latitude: Double?
        var longitude: Double?
    }

    struct TripContextPayload: Encodable, Sendable {
        var destination: Destination
        var startDate: String
        var endDate: String
        var durationDays: Int
        var tripType: String
        var activities: [String]
        var contextChips: [String]
        var bagType: String
        var packingStyle: String
        var transportation: String?
        var laundryAccess: String?
        var travelerCount: Int
        var weatherSummary: String?
        var currentItemIDs: [String]?
    }

    struct Item: Encodable, Sendable {
        var canonicalItemID: String?
        var displayName: String
        var quantity: Int?
        var category: String?
    }

    struct InterpretRequest: Encodable, Sendable {
        var note: String
        var context: TripContextPayload
        var safetyIdentifier: String
    }

    struct ItemsRequest: Encodable, Sendable {
        var context: TripContextPayload
        var items: [Item]
        var safetyIdentifier: String
    }

    struct Meta: Decodable, Sendable {
        var requestID: String
        var generatedAt: String
        var model: String?
        var promptVersion: String
        var schemaVersion: String
        var cached: Bool?
    }

    struct InterpretResponse: Decodable, Sendable {
        var meta: Meta
        var inferredActivities: [String]
        var inferredChips: [String]
        var noteSummary: String?
    }

    struct Suggestion: Decodable, Sendable {
        var canonicalItemID: String
        var action: String
        var confidence: Double?
        var signals: [String]?
        var reason: String?
        var reasonCode: String
        var reasonArguments: [String: String]?
    }

    struct GapResponse: Decodable, Sendable {
        var meta: Meta
        var suggestions: [Suggestion]
    }

    struct Optimization: Decodable, Sendable {
        var canonicalItemID: String
        var reason: String?
        var reasonCode: String
        var reasonArguments: [String: String]?
        var suggestedQuantity: Int?
        var confidence: Double?
    }

    struct OptimizationResponse: Decodable, Sendable {
        var meta: Meta
        var optimizations: [Optimization]
    }

    struct APIError: Decodable, Sendable {
        var error: String
        var message: String?
        var requestID: String
    }
}

extension IntelligenceDTO {
    /// Calendar dates, not instants: the trip's dates are local days, so they
    /// are formatted in the device time zone rather than shifted into UTC.
    private static let dateStyle = Date.ISO8601FormatStyle(timeZone: .current)
        .year()
        .month()
        .day()

    /// The packing-relevant shape of a trip. Free-form notes are deliberately
    /// excluded: only `interpretTripNote` sends note text, because that is the
    /// whole input to that capability.
    static func payload(for context: TripContext, currentItemIDs: [String]? = nil) -> TripContextPayload {
        TripContextPayload(
            destination: Destination(
                displayName: context.destination.displayName,
                countryCode: context.destination.countryCode,
                latitude: context.destination.latitude,
                longitude: context.destination.longitude
            ),
            startDate: dateStyle.format(context.startDate),
            endDate: dateStyle.format(context.endDate),
            durationDays: max(1, context.durationDays),
            tripType: context.tripType.rawValue,
            activities: context.activities,
            contextChips: context.contextChips.map(\.rawValue).sorted(),
            bagType: context.bagType.rawValue,
            packingStyle: context.packingStyle.rawValue,
            transportation: context.transportation.rawValue,
            laundryAccess: context.laundryAccess.rawValue,
            travelerCount: max(1, context.travelerCount),
            weatherSummary: context.weather?.weatherSummary,
            currentItemIDs: currentItemIDs
        )
    }

    static func items(from drafts: [PackingItemDraft]) -> [Item] {
        drafts.map { draft in
            Item(
                canonicalItemID: draft.canonicalItemID,
                displayName: draft.displayName,
                quantity: draft.quantity,
                category: draft.category.rawValue
            )
        }
    }
}
