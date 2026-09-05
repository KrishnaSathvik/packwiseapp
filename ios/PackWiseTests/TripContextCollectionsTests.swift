import Foundation
import Testing
@testable import PackWise

/// Stable multi-value trip context contracts — Product Experience V2, Task 1.
///
/// These tests pin two properties every later task depends on:
/// - `Set<TripType>`/`Set<BagType>` always serialize in one deterministic
///   order, regardless of insertion order or `Set` iteration order.
/// - Unknown and retired legacy raw values normalize predictably instead of
///   silently choosing an arbitrary primary value.
struct TripContextCollectionsTests {

    // MARK: - Stable order across insertion order

    @Test func tripTypeEncodingIsStableAcrossInsertionOrder() throws {
        let a: Set<TripType> = [.beach, .vacation, .cityBreak]
        let b: Set<TripType> = [.cityBreak, .beach, .vacation]
        #expect(try StableRawValueSetCodec.encode(a, order: TripType.stableOrder)
            == StableRawValueSetCodec.encode(b, order: TripType.stableOrder))
        #expect(try StableRawValueSetCodec.encode(a, order: TripType.stableOrder)
            == #"["vacation","cityBreak","beach"]"#)
    }

    @Test func tripTypeEncodingIsStableAcrossEveryPermutationOfThreeValues() throws {
        let values: [TripType] = [.business, .outdoor, .roadTrip]
        let expected = #"["business","outdoor","roadTrip"]"#
        for permutation in values.permutations() {
            let set = Set(permutation)
            #expect(try StableRawValueSetCodec.encode(set, order: TripType.stableOrder) == expected)
        }
    }

    @Test func bagTypeEncodingIsStableAcrossInsertionOrder() throws {
        let a: Set<BagType> = [.checked, .personalItem, .carryOn]
        let b: Set<BagType> = [.carryOn, .checked, .personalItem]
        #expect(try StableRawValueSetCodec.encode(a, order: BagType.stableOrder)
            == StableRawValueSetCodec.encode(b, order: BagType.stableOrder))
        #expect(try StableRawValueSetCodec.encode(a, order: BagType.stableOrder)
            == #"["personalItem","carryOn","checked"]"#)
    }

    @Test func encodingExcludesMembersOutsideTheStableOrderVocabulary() throws {
        // `.notSure` still exists as a `BagType` case for non-V2 call sites,
        // but it is not part of the V2 physical-bag vocabulary, so a stable
        // boundary must never persist it even if it somehow ends up in a set.
        let set: Set<BagType> = [.notSure, .carryOn]
        #expect(try StableRawValueSetCodec.encode(set, order: BagType.stableOrder)
            == #"["carryOn"]"#)
    }

    // MARK: - Stable order contracts

    @Test func tripTypeStableOrderMatchesTheApprovedMatrix() {
        #expect(TripType.stableOrder == [
            .vacation, .cityBreak, .beach, .business, .outdoor, .roadTrip,
            .weddingEvent, .skiSnow, .festival, .visitingFamily, .other
        ])
    }

    @Test func bagTypeStableOrderIsExactlyTheFourV2PhysicalBags() {
        #expect(BagType.stableOrder == [.personalItem, .carryOn, .checked, .backpack])
        #expect(!BagType.stableOrder.contains(.notSure))
        #expect(!BagType.stableOrder.contains(.roadTripLuggage))
    }

    // MARK: - Round trip

    @Test func decodingAnEncodedSetReturnsTheSameValuesWithNoDiagnostics() throws {
        let original: Set<TripType> = [.beach, .festival, .other]
        let json = try StableRawValueSetCodec.encode(original, order: TripType.stableOrder)
        let normalized = try StableRawValueSetCodec.decode(json, order: TripType.stableOrder)
        #expect(normalized.values == original)
        #expect(normalized.diagnostics.isEmpty)
    }

    // MARK: - Unknown value normalization

    @Test func unknownTripTypeRawValueIsDroppedAndFallsBackToOtherWhenNoneRemain() throws {
        let normalized = try TripType.normalizedSet(fromStableJSON: #"["madeUpTripType"]"#)
        #expect(normalized.values == [.other])
        #expect(normalized.diagnostics.contains(.droppedUnknownRawValues(["madeUpTripType"])))
        #expect(normalized.diagnostics.contains(.fallbackAppliedAfterEmptyResult))
    }

    @Test func mixedKnownAndUnknownTripTypesKeepTheKnownValueWithoutFallback() throws {
        let normalized = try TripType.normalizedSet(fromStableJSON: #"["beach","madeUpTripType"]"#)
        #expect(normalized.values == [.beach])
        #expect(normalized.diagnostics == [.droppedUnknownRawValues(["madeUpTripType"])])
    }

    @Test func emptyPersistedTripTypeArrayFallsBackToOther() throws {
        let normalized = try TripType.normalizedSet(fromStableJSON: "[]")
        #expect(normalized.values == [.other])
        #expect(normalized.diagnostics == [.fallbackAppliedAfterEmptyResult])
    }

    @Test func unknownBagRawValueDropsToNoBagConstraint() throws {
        let normalized = try BagType.normalizedSet(fromStableJSON: #"["madeUpBag"]"#)
        #expect(normalized.values.isEmpty)
        #expect(normalized.diagnostics == [.droppedUnknownRawValues(["madeUpBag"])])
    }

    @Test func emptyPersistedBagArrayStaysEmptyWithNoDiagnostic() throws {
        let normalized = try BagType.normalizedSet(fromStableJSON: "[]")
        #expect(normalized.values.isEmpty)
        #expect(normalized.diagnostics.isEmpty)
    }

    // MARK: - Legacy bag compatibility (never a selectable V2 case)

    @Test func legacyNotSureBagValueNormalizesToEmptySetNotASelectableCase() throws {
        let normalized = try BagType.normalizedSet(fromStableJSON: #"["notSure"]"#)
        #expect(normalized.values.isEmpty)
        #expect(normalized.diagnostics == [.droppedLegacyRawValues(["notSure"])])
    }

    @Test func legacyRoadTripLuggageBagValueNormalizesToEmptySetAndNeverInfersRoadTrip() throws {
        let normalized = try BagType.normalizedSet(fromStableJSON: #"["roadTripLuggage"]"#)
        #expect(normalized.values.isEmpty)
        #expect(normalized.diagnostics == [.droppedLegacyRawValues(["roadTripLuggage"])])
        // The legacy decoder is isolated to BagType; it has no access to
        // TripType and therefore structurally cannot add `.roadTrip`.
        #expect(BagTypeLegacyRawValue.allCases.map(\.rawValue).sorted() == ["notSure", "roadTripLuggage"])
    }

    @Test func legacyBagValuesMixedWithAKnownBagKeepOnlyTheKnownBag() throws {
        let normalized = try BagType.normalizedSet(fromStableJSON: #"["notSure","carryOn","roadTripLuggage"]"#)
        #expect(normalized.values == [.carryOn])
        #expect(normalized.diagnostics == [.droppedLegacyRawValues(["notSure", "roadTripLuggage"])])
    }

    // MARK: - Malformed input

    @Test func malformedJSONThrowsRatherThanSilentlyNormalizing() {
        #expect(throws: (any Error).self) {
            try TripType.normalizedSet(fromStableJSON: "not json")
        }
    }

    // MARK: - Draft validation

    @Test func emptyTripTypeSelectionIsInvalidForANewDraft() {
        #expect(throws: TripTypeSelectionError.emptySelection) {
            try TripTypeSelection.validateNonEmptyDraftSelection([])
        }
    }

    @Test func nonEmptyTripTypeSelectionIsValidForANewDraft() throws {
        try TripTypeSelection.validateNonEmptyDraftSelection([.beach])
    }

    @Test func emptyBagSelectionIsAlwaysValid() throws {
        // "Not sure yet" — an empty bag set is a legitimate end state, never
        // an error, unlike an empty trip-type selection.
        let normalized = try BagType.normalizedSet(fromStableJSON: "[]")
        #expect(normalized.values.isEmpty)
    }
}

private extension Array {
    /// Small permutation helper for exhaustive stable-order tests. Fine for
    /// the short arrays used here (3-4 elements); not intended for general use.
    func permutations() -> [[Element]] {
        guard count > 1 else { return [self] }
        var result: [[Element]] = []
        for (index, element) in enumerated() {
            var rest = self
            rest.remove(at: index)
            for permutation in rest.permutations() {
                result.append([element] + permutation)
            }
        }
        return result
    }
}
