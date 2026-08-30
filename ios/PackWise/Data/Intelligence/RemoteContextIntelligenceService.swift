import Foundation

/// Talks to the PackWise Intelligence API.
///
/// The server already validates every canonical item ID and reason code, but
/// this validates again against the on-device catalog and enums. The two run
/// from the same `shared/` source, so a mismatch means a version skew between
/// app and API — exactly the case where the app should drop the suggestion
/// rather than trust it.
struct RemoteContextIntelligenceService: ContextIntelligenceService {
    let client: IntelligenceHTTPClient
    let catalog: PackingCatalog
    let safetyIdentifier: String

    init(
        client: IntelligenceHTTPClient,
        catalog: PackingCatalog,
        safetyIdentifier: String = InstallIdentity.shared.identifier
    ) {
        self.client = client
        self.catalog = catalog
        self.safetyIdentifier = safetyIdentifier
    }

    func interpretTripNote(_ note: String, context: TripContext) async throws -> TripContextEnrichment {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return TripContextEnrichment(inferredActivities: [], inferredChips: [], noteSummary: "")
        }

        let response = try await client.send(
            path: "/v1/trip/interpret",
            body: IntelligenceDTO.InterpretRequest(
                note: trimmed,
                context: IntelligenceDTO.payload(for: context),
                safetyIdentifier: safetyIdentifier
            ),
            as: IntelligenceDTO.InterpretResponse.self
        )

        return TripContextEnrichment(
            inferredActivities: response.inferredActivities,
            // An unknown chip means the API knows a vocabulary this build does not.
            inferredChips: response.inferredChips.compactMap(ContextChip.init(rawValue:)),
            noteSummary: response.noteSummary ?? ""
        )
    }

    func findPackingGaps(context: TripContext, items: [PackingItemDraft]) async throws -> [PackingSuggestion] {
        let response = try await client.send(
            path: "/v1/packing/gaps",
            body: IntelligenceDTO.ItemsRequest(
                context: IntelligenceDTO.payload(for: context, currentItemIDs: canonicalIDs(of: items)),
                items: IntelligenceDTO.items(from: items),
                safetyIdentifier: safetyIdentifier
            ),
            as: IntelligenceDTO.GapResponse.self
        )

        return response.suggestions.compactMap { suggestion in
            guard catalog.item(id: suggestion.canonicalItemID) != nil,
                  let action = PackingSuggestionAction(rawValue: suggestion.action)
            else { return nil }
            return PackingSuggestion(
                canonicalItemID: suggestion.canonicalItemID,
                action: action,
                reasonCode: suggestion.reasonCode,
                reasonArguments: suggestion.reasonArguments ?? [:],
                reason: suggestion.reason,
                confidence: Self.confidence(suggestion.confidence),
                signals: suggestion.signals?.compactMap(RecommendationSignal.init(rawValue:)) ?? [.gptReasoning]
            )
        }
    }

    func optimizePacking(context: TripContext, items: [PackingItemDraft]) async throws -> [PackingOptimization] {
        let response = try await client.send(
            path: "/v1/packing/optimize",
            body: IntelligenceDTO.ItemsRequest(
                context: IntelligenceDTO.payload(for: context, currentItemIDs: canonicalIDs(of: items)),
                items: IntelligenceDTO.items(from: items),
                safetyIdentifier: safetyIdentifier
            ),
            as: IntelligenceDTO.OptimizationResponse.self
        )

        return response.optimizations.compactMap { optimization in
            guard catalog.item(id: optimization.canonicalItemID) != nil else { return nil }
            return PackingOptimization(
                canonicalItemID: optimization.canonicalItemID,
                reasonCode: optimization.reasonCode,
                reasonArguments: optimization.reasonArguments ?? [:],
                reason: optimization.reason,
                confidence: Self.confidence(optimization.confidence),
                suggestedQuantity: optimization.suggestedQuantity
            )
        }
    }

    private func canonicalIDs(of items: [PackingItemDraft]) -> [String] {
        Array(Set(items.compactMap(\.canonicalItemID))).sorted()
    }

    /// Confidence carries no meaning outside 0...1, so it is dropped rather
    /// than clamped into something the ranking would believe.
    private static func confidence(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0...1).contains(value) else { return nil }
        return value
    }
}
