# Product Hardening Phase 4 — Footwear and Outerwear Coverage Design

**Date:** 2026-09-03
**Base:** `product-hardening-phase1` at `0b52ae6`
**State:** approved design; implementation not started

## Objective

When one item legitimately satisfies multiple footwear, outerwear, or hand-
protection needs, PackWise keeps the smallest deterministic non-duplicative
set. Every suppressed candidate records structured evidence pairing each
covered capability with the item that covered it.

## Architecture

`CoverageResolver` remains the single coverage authority. Its capability
vocabulary stays closed and typed in Swift; Phase 4 does not migrate policy to
shared JSON and does not add ID-pair exceptions.

`PackingEngine` continues to compile one `TripContextSnapshot`. A new narrow
`CoverageContext` projects the snapshot fields required by coverage: trip
type, known activities, context chips, normalized duration/date/destination,
normalized party, and the existing weather input. The projection invokes the
existing `WeatherSignalExtractor` with the existing thresholds; it does not
create or reinterpret weather semantics. `CoverageResolver.needs` consumes
only this projection. Other engine families keep their current inputs.

The snapshot gains pass-through fields only where the coverage projection
cannot otherwise be complete (`contextChips` and the existing optional weather
context). These are closed typed inputs, not new inference.

## Capability and resolution model

The current ten footwear/outerwear capabilities remain. Phase 4 adds only two
hand-protection capabilities:

- everyday cold hand protection;
- snow-sport hand protection.

`activities.ski_gloves` covers both; `clothing.gloves` covers everyday cold
only. Ski gloves have deterministic priority over ordinary gloves. Ski/snow
trip intent creates the snow-sport need, while existing cold/snow weather
signals create the cold-hand need. Therefore the Aspen overlap resolves
through general capability coverage: ski gloves stay, ordinary gloves are
suppressed, and the evidence names the cold-hand capability and ski gloves as
its coverer.

The resolver retains its deterministic priority pass. It never suppresses a
user-added or user-modified item, but such an item may claim relevant coverage
and suppress an engine candidate in the same unambiguous owner group. In a
party list, an unassigned item claims coverage for nobody; no traveler is
guessed. Items outside the typed capability vocabulary pass through unchanged.

## Evidence

`CoverageSuppression` replaces parallel capability/coverer arrays as the
source of truth with stable per-capability facts:

```swift
struct CapabilityCoverage: Hashable, Sendable {
    var capability: PackingCapability
    var coveringItemID: String
}

struct CoverageSuppression: Hashable, Sendable {
    var travelerID: UUID?
    var canonicalItemID: String
    var covered: [CapabilityCoverage]
    var refutedCapabilities: [PackingCapability]
}
```

`covered` is sorted by capability raw value. `refutedCapabilities` is used
when an engine candidate is suppressed because its need is absent, such as a
rain shell in hot rain; it is also sorted. Compatibility accessors may expose
the old flattened arrays during migration, but golden serialization records
the exact capability-to-coverer mapping. The semantic reporter treats changes
to that mapping as coverage changes.

## Required behavior

- Running shoes cover everyday walking but do not erase a distinct hiking
  need when running and hiking are both selected.
- Hiking shoes cover everyday walking when running is absent.
- Formal footwear stays beside a walking-capable pair because the needs are
  distinct.
- A rain shell may cover wind; light and heavy warmth remain distinct layers;
  a winter coat does not erase an indoor/light layer.
- Ski gloves cover both snow-sport and ordinary cold-hand needs; ordinary
  gloves are suppressed when redundant.
- User-owned multifunction footwear/outerwear remains and may satisfy the
  corresponding need for its owner only.
- Repeated generation from identical inputs produces identical kept items and
  sorted suppression evidence.

## Golden boundary

Phase 4 may change footwear, outerwear, and hand-protection inclusion,
suppression, coverage evidence, and the reason of an item that absorbed a
capability. Clothing quantities, Camping behavior, weather-generated needs,
seasonal behavior, shared constraints, ownership/carrier assignment,
persistence, and presentation are reject conditions.

## Non-goals

- Footwear or clothing quantities.
- Camping/activity rule work.
- New weather signals or changed weather thresholds/interpretation.
- Seasonal-weather hardening.
- Shared-party constraints.
- UI, persistence, GPT, or context intelligence.
- Moving capability definitions into shared JSON.
- Pairwise ski-glove exceptions.

## Verification

Focused tests cover running+walking, hiking+walking, formal+business,
rain/wind/light/heavy outerwear, ski/cold hand protection, user-added
multifunction items, explicit owner-scoped coverage, ambiguous unassigned
party items, and repeated-run determinism. The Phase 1 ledger remains the
regression authority; semantic golden review must separate expected coverage
changes from unexpected behavior. Closure also requires the engine audit,
full iOS tests, shared validation if shared data changes, and API preflight.
