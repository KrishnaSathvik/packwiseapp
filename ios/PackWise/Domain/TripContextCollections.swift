import Foundation

// Product Experience V2, Task 1 — stable multi-value trip context contracts.
//
// Domain code may hold `TripType`/`BagType` as a `Set`, but every
// persistence, API, fixture, signature, and diff boundary must serialize
// them in one deterministic order. Swift's `Set` makes no ordering
// guarantee, so "just encode the Set" would make two logically-identical
// selections produce different bytes depending on insertion history. This
// file makes stable ordering and unknown/legacy-value normalization an
// explicit, testable property instead of an accident that later
// engine/persistence code has to work around case by case.
//
// See docs/plans/2026-09-04-product-experience-v2-design.md Sections 4-6.

/// One diagnostic fact recorded while normalizing a persisted/raw-value set.
///
/// Diagnostics never throw and never block normalization; they exist so a
/// caller can log or surface a legacy/corrupted value instead of silently
/// pretending nothing happened.
enum TripContextNormalizationDiagnostic: Equatable, Sendable {
    /// Raw values that are not part of the type's stable/known vocabulary —
    /// for example corrupted data, or a value from a build that no longer
    /// exists.
    case droppedUnknownRawValues([String])

    /// Raw values that are recognized but deliberately excluded from V2
    /// domain selection — `BagType`'s retired `notSure`/`roadTripLuggage`
    /// values. They normalize away rather than mapping to a selectable V2
    /// case.
    case droppedLegacyRawValues([String])

    /// The decoded set was empty after dropping unknown/legacy values, so
    /// the caller-supplied fallback was substituted. Used for `TripType`,
    /// which must never normalize to "no trip type."
    case fallbackAppliedAfterEmptyResult
}

/// The result of normalizing a persisted/raw-value array into a domain set.
struct NormalizedSet<Value: Hashable & Sendable>: Equatable, Sendable {
    let values: Set<Value>
    let diagnostics: [TripContextNormalizationDiagnostic]

    var isEmpty: Bool { values.isEmpty }
}

/// Encodes/decodes `Set<Value>` at stable boundaries (persistence, API DTOs,
/// fixtures, signatures, goldens) using a fixed reference order, so two
/// logically-equal sets always produce byte-identical output regardless of
/// insertion or `Set` iteration order.
enum StableRawValueSetCodec {
    /// Encodes `values` as a JSON array of raw strings, ordered by position
    /// in `order`. A member of `values` that does not appear in `order` is
    /// silently excluded: `order` is the definition of what is valid at
    /// this boundary, not merely a sort key. This is how a value can remain
    /// a declared enum case (for non-V2 call sites) while never being
    /// persisted/serialized as a V2 selection.
    static func encode<Value: RawRepresentable & Hashable>(
        _ values: Set<Value>,
        order: [Value]
    ) throws -> String where Value.RawValue == String {
        let orderedRawValues = order.filter(values.contains).map(\.rawValue)
        let data = try JSONEncoder().encode(orderedRawValues)
        return String(decoding: data, as: UTF8.self)
    }

    /// Decodes a JSON array of raw strings into a normalized set.
    ///
    /// - `order` is both the stable output order and the closed vocabulary:
    ///   a raw value that does not match any element of `order` is dropped
    ///   as unknown, even if `Value(rawValue:)` would otherwise succeed.
    ///   This is how retired-but-still-declared cases (like
    ///   `BagType.notSure`) are excluded from V2 decoding without removing
    ///   them from the enum.
    /// - `legacyRawValues` names raw values that are recognized as
    ///   deliberately retired rather than merely unknown, so callers and
    ///   migration diagnostics can tell the two apart.
    /// - `emptyResultFallback` is substituted, with a diagnostic, only when
    ///   the decoded set would otherwise be empty.
    static func decode<Value: RawRepresentable & Hashable>(
        _ json: String,
        order: [Value],
        legacyRawValues: Set<String> = [],
        emptyResultFallback: Set<Value> = []
    ) throws -> NormalizedSet<Value> where Value.RawValue == String {
        let rawValues = try JSONDecoder().decode([String].self, from: Data(json.utf8))
        let knownRawValues = Set(order.map(\.rawValue))

        var decoded: Set<Value> = []
        var droppedUnknown: [String] = []
        var droppedLegacy: [String] = []

        for raw in rawValues {
            if knownRawValues.contains(raw), let value = Value(rawValue: raw) {
                decoded.insert(value)
            } else if legacyRawValues.contains(raw) {
                droppedLegacy.append(raw)
            } else {
                droppedUnknown.append(raw)
            }
        }

        var diagnostics: [TripContextNormalizationDiagnostic] = []
        if !droppedUnknown.isEmpty {
            diagnostics.append(.droppedUnknownRawValues(droppedUnknown))
        }
        if !droppedLegacy.isEmpty {
            diagnostics.append(.droppedLegacyRawValues(droppedLegacy))
        }
        if decoded.isEmpty, !emptyResultFallback.isEmpty {
            decoded = emptyResultFallback
            diagnostics.append(.fallbackAppliedAfterEmptyResult)
        }

        return NormalizedSet(values: decoded, diagnostics: diagnostics)
    }
}

extension TripType {
    /// Normalizes a persisted/raw trip-type JSON array. An unknown raw
    /// value is dropped with a diagnostic; if that leaves no known trip
    /// type, the safe normalized value is `[.other]` — a trip must always
    /// have at least one known trip type once normalized.
    static func normalizedSet(fromStableJSON json: String) throws -> NormalizedSet<TripType> {
        try StableRawValueSetCodec.decode(json, order: stableOrder, emptyResultFallback: [.other])
    }
}

/// Raw `BagType` values that were removed from V2 selectable/domain
/// semantics but can still appear in legacy persisted data.
///
/// Deliberately declared apart from `BagType.allCases`/`BagType.stableOrder`
/// so no V2 code path can iterate, select, or persist them as a bag — the
/// only place these strings are meaningful again is decoding old data,
/// where they normalize to "no bag" rather than a selectable case. In
/// particular, a legacy `roadTripLuggage` bag never implies the trip is a
/// Road Trip: this decoder has no access to `TripType` and cannot infer one
/// (see design Section 6.2).
enum BagTypeLegacyRawValue: String, CaseIterable, Sendable {
    case notSure
    case roadTripLuggage
}

extension BagType {
    /// Normalizes a persisted/raw bag JSON array to the V2 physical bag
    /// set. Unknown values and the retired `notSure`/`roadTripLuggage`
    /// legacy values both drop to no bag constraint — "not sure yet" is
    /// represented by an empty set, never a case.
    static func normalizedSet(fromStableJSON json: String) throws -> NormalizedSet<BagType> {
        try StableRawValueSetCodec.decode(
            json,
            order: stableOrder,
            legacyRawValues: Set(BagTypeLegacyRawValue.allCases.map(\.rawValue))
        )
    }
}

/// Multi-select trip-type validation shared by every draft/editor surface.
enum TripTypeSelectionError: Error, Equatable, Sendable {
    /// A trip must carry at least one trip type; empty selection is only
    /// ever valid transiently while the user is still choosing.
    case emptySelection
}

enum TripTypeSelection {
    /// Validates a trip-type selection for a new/edited draft. Empty bags
    /// are a valid "not sure yet" state; empty trip types are not.
    static func validateNonEmptyDraftSelection(_ tripTypes: Set<TripType>) throws {
        guard !tripTypes.isEmpty else { throw TripTypeSelectionError.emptySelection }
    }
}
