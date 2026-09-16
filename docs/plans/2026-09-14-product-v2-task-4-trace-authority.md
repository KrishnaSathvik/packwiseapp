# Product Experience V2, Task 4 — trace authority decision

Date: 2026-09-14 · Branch: `product-v2-stage-a` · Decided before any multi-trip-type behavior

## Audit of the two representations

| Representation | Origin | Writers before this change | Readers before this change |
| --- | --- | --- | --- |
| Phase 8 `RecommendationTrace` | hardening Phase 8 | `PackingEngine`, `ConstraintResolver`, `CoverageResolver` populate structured draft fields (`reasonCode`, `reasonArguments`, `sourceSignals`, `quantityEvidence`, `quantityReasonArguments`, `satisfiedCapabilities`, `bagStyleConstraintFact`), persisted as columns | `RecommendationTrace` facets → Item Detail and reason rendering |
| `PackingItemRecord.recommendationTraceRaw` | Task 2 (V4 column) | **none** | **none** |

`recommendationTraceRaw` was a reserved column that nothing wrote or read, so there was no divergence yet. The risk was that Task 4 would start writing multi-source provenance there as a second model.

## Decision

- **The Phase 8 `RecommendationTrace` is the single explanation authority.** It still reads only an item's own structured fields.
- **Multi-source provenance joins it as one more structured field:** `PackingItemDraft.provenance: [RecommendationProvenance]`, read through `RecommendationTrace.provenance(for:)`. Each fact carries `reasonCode`, `reasonArguments`, `sourceSignals`, and, when a trip type is the source, `tripType`.
- **`recommendationTraceRaw` is only that field's persisted encoding.** `RecommendationTrace.ProvenanceEncoding` writes a versioned JSON envelope; an empty set stores `nil`. `PackingItemRecord.init(from:)`, `apply(_:)`, and `draft` are its only writers and readers. It is not a second explanation system, and no schema change was needed because the column already exists in 5.0.0.
- **Every engine source records a fact where it adds a suggestion:** base essentials, trip type, activities and activity needs, preferences, destination/documents, weather (precise and seasonal), party, companions, and flight. A merge appends facts and never drops one. The row's single customer reason is still chosen by tier.
- **Facts are stored in canonical order** (signal vocabulary, reason code, trip-type stable order, arguments), so identical inputs persist identically.
- **Regeneration:** a stored provenance that disagrees with the fresh one is causal (`causallyDiffers`), like every other Phase 8 trace field. A pre-Task-4 record with no stored provenance is not a change to show the traveler; it is written on its next real causal refresh.
- **Old payloads:** a draft encoded before this field existed (inside a pending weather proposal) still decodes, because the backing store is optional.
- **Goldens:** the ledger now serializes `provenance`. `report_engine_goldens.py` compares it as a trace field and accepts `--ignore-trace-field provenance` for baselines recorded before it existed.

Presentation is unchanged. Item Detail still renders the same reason; showing several facts belongs to Task 13.

## Evidence

- `RecommendationProvenanceTests` (6):
  - an item from a trip type plus a selected activity carries both facts;
  - every engine item carries at least one fact;
  - canonical order is independent of activity order;
  - combined provenance persists, reloads, and refreshes through `recommendationTraceRaw` without divergence;
  - a pre-Task-4 draft still decodes;
  - causality works, and a legacy-empty record is exempt.
- Golden ledger: all 38 goldens are JSON-identical to `4f55101` once `provenance` is removed. `report_engine_goldens.py --baseline-ref 4f55101 --ignore-trace-field provenance` shows 1441 unchanged and zero changes of any kind. 1438 of the 1441 items carry facts; the other 3 are user-authority rows (manual quantity, existing rain shell, custom item) that keep their stored trace.
- iOS 415/415 · Python audits 115 · trace audit `--strict` CLEAN · `validate_shared.py` OK.
