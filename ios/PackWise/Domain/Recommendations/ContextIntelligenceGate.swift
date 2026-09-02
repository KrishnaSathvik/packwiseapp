import Foundation

/// Gate between `interpretTripNote` and anything persisted. AGENTS.md:
/// GPT never writes SwiftData — suggestions go through validation, the
/// Recommendation Resolver, and user acceptance. The acceptance step is
/// M3B and does not exist yet, and the interpret prompt has no
/// traveler-attribution guard ("my daughter needs medication" must not
/// become a primary-traveler chip), so the enrichment path stays off.
enum ContextIntelligenceGate {
    /// Flip only when M3B lands the acceptance step and attribution guard.
    static let isNoteEnrichmentEnabled = false

    /// The single entry point trip setup may use for note enrichment.
    /// Returns nil while the gate is closed or the note is empty; never throws,
    /// because generation must not depend on the model being reachable.
    static func noteEnrichment(
        notes: String,
        context: TripContext,
        intelligence: any ContextIntelligenceService
    ) async -> TripContextEnrichment? {
        guard isNoteEnrichmentEnabled, !notes.isEmpty else { return nil }
        return try? await intelligence.interpretTripNote(notes, context: context)
    }
}
