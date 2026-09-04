# Product Hardening Phase 8 — Recommendation Trace Productization Design

**Date:** 2026-09-04
**Base:** `product-hardening-phase1` at `eadc345` (Phase 7's closing commit — the
semantic golden baseline for every diff this design and its plan specify)
**State:** approved design; implementation not started

## Objective

Turn PackWise's existing provenance — `PackingItemDraft`'s `reasonCode`/
`reasonArguments`/`sourceSignals`/`quantityReason`/`quantityEvidence`,
`EngineGeneration`'s `coverageSuppressions`/`constraintDecisions`, and Phase
7's `ConstraintResolver.SharingResolution`/`hasUserAuthority`/
`isExplicitlyRemoved` — into one complete, queryable recommendation trace
per item, and wire the already-frozen Item Detail sheet
(`ItemDetailView`/`PackingRow`, `ios/PackWise/Features/TripDetail/PackingListView.swift`)
to it. The recommendation engine still decides once; this phase only makes
that decision legible. No second explanation engine, no new decision logic.

## What already exists — read before designing anything new

Every field the roadmap's `RecommendationTrace` sketch names was checked
against the real code, not assumed. The result is a mixed picture, the same
shape every prior phase's design doc found: some of the sketch is already
fully expressible, one piece is a genuine, coded, waiting-to-be-picked-up
breadcrumb, and a few pieces are real gaps.

### `inclusion` — fully expressible today, no new stored field needed

`PackingItemDraft` (`Catalog.swift:362-438`) already carries `reasonCode:
String`, `reasonArguments: [String: String]`, `sourceSignals:
[RecommendationSignal]`, and `reason: String`. `RecommendationSignal`
(`TripTypes.swift:272-298`) is a **coarse** ten-case enum (`weather`,
`duration`, `activity`, `tripType`, `destination`, `baseEssential`,
`userPreference`, `history`, `gptReasoning`, `party`) — it does not by
itself distinguish `weatherPrecise` from `weatherSeasonal`, or
`personalPreference` from `dependency`. But `reasonCode` already is that
finer vocabulary: a live count across all 38 goldens
(`python3 -c "..."` over `ios/PackWiseTests/Goldens/*.json"`) finds real
prefixes `activity.*` (187 rows), `base.essential.*` (890), `destination.*`
(36), `documents.*` (9), `flight.*` (22), `party.*` (29), `substitution.*`
(17), `trip_type.*` (68), `weather.*` (180) — and within `weather.*`, the two
seasonal codes (`weather.seasonal_sun`, `weather.seasonal_layer`,
`PackingEngine.swift:637,649`) are a closed, disjoint pair from every other
`weather.*` code (`addWeather`, `PackingEngine.swift:563-613`, all precise-
forecast). `ReasonRenderer.tier(_:)` (`QuantityEngine.swift:161-167`) already
ranks specificity by this exact prefix structure (weather=4,
activity/party/substitution=3, preference/trip_type/destination/documents/
flight=2, else=1) and is the mechanism the engine itself uses to pick the
more specific reason when two signals compete for one item
(`addWeather`'s `add(...)`, `:545`). **The roadmap's `InclusionFamily` is a
pure derivation over an already-structured, already-closed string
vocabulary — not a new stored field, and not a new enum on
`PackingItemDraft`.** It is a new pure function (Architecture, below), the
same "derive presentation from structured facts" pattern
`PackingReasonPresentation.inclusionReason` (`PackingListView.swift:16-40`)
already establishes for cosmetic wording.

### `quantity` — a real, already-flagged gap, clothing-only today

`PackingItemDraft.quantityEvidence: ClothingQuantityEvidence?`
(`Catalog.swift:377`) already exists, with its own comment: *"Engine-only
structured facts behind a clothing quantity. Persistence and product
presentation are deliberately deferred to Phase 8."* This is Phase 3
handing Phase 8 exactly the field the roadmap wants — read, not
reinvented. It is populated in `applyQuantities`
(`PackingEngine.swift:962`) and **is already serialized into every golden
fixture** (`GoldenEngineTests.swift:506,583`) — confirmed directly:
fixture 01's `clothing.sleepwear` row carries a full
`quantityEvidence` object (`policyID`, `basis: "sleepRotation"`,
`requiredUses: 5`, `laundryPlan`, `styleBuffer`, …) today.

The real gap: **only the clothing family has a typed evidence struct.**
The three other quantity>1-capable families each compute structured
`reasonCode`/`arguments` pairs internally and then discard them, keeping
only the rendered string on the draft:

- `CareQuantityEngine.Result` (`CareQuantity.swift:14-18`): `value`,
  `reasonCode`, `arguments: [String: String]`, `fallback` — diapers/extra
  outfits. Only `quantityReason` (the rendered text) survives onto
  `PackingItemDraft` (`PackingEngine.swift:930-931`).
- `WarmLayerQuantities.quantity` (`ClothingQuantity.swift:236-266`):
  returns the same `(value, reasonCode, arguments, fallback)` shape for
  cold-weather layer rotation. Same fate (`PackingEngine.swift:943-944`).
- `ConstraintResolver.sharingResolution`'s `.shared(quantity, reason)`
  (`ConstraintResolver.swift:120-125`): `reason` is already a fully-rendered
  string (built by the private `sharedQuantityReason`,
  `ConstraintResolver.swift:173-185`); no structured arguments travel with
  it at all today.
- Legacy `QuantityEngine.quantity` (`QuantityEngine.swift:7-43`, the
  non-clothing fallback family): returns only `(value: Int, reason: String)`
  — no `reasonCode` even survives internally past the render call.

**Genuinely missing:** a `quantityReasonArguments: [String: String]` field
on `PackingItemDraft`, mirroring the pattern `reasonArguments` already
establishes for the *inclusion* reason, populated for these three families
the same way `reasonArguments` already is for `RuleSuggestion`. This is an
additive field capturing facts the engine already computes and currently
throws away — not a new computation.

**Verified live, not assumed stale:** `scripts/audit_recommendation_traces.py
--goldens ios/PackWiseTests/Goldens` at `eadc345` reports **0** rows missing
required quantity evidence (309/309, 100%) — the Phase 1 baseline's "25
missing" finding (P2-5) is **already resolved**; it predates Phase 3, which
landed the clothing evidence and populated `quantityReason` even at the
policy floor (`fixture 01`'s sleepwear: `quantity=1`, `quantityReason: "1
sleep set with repeat wear."`). The trace-coverage doc's own numbers
(`docs/engine-audits/2026-09-03-trace-coverage.md`) are from before Phase 3
and must not be cited as current in Phase 8's closure — Task 8's exit
report regenerates this file fresh.

### `signals` — `sourceSignals`, unchanged, already exposed in Item Detail

`ItemDetailView.reasons` (`PackingListView.swift:793-804`) already renders
`item.sourceSignals` as capsule chips via `.customerLabel`. Nothing to add;
Phase 8 reads this list, does not replace it.

### `needs`/`capabilities` and `coverage` — the survivor's side is missing

`PackingCapability` (`CoverageResolver.swift:12-25`, 12 closed cases) and
`CoverageSuppression` (`:92-107`) are Phase 4's authority. `CoverageSuppression`
is recorded **per suppressed item** — `covered: [CapabilityCoverage]` names
which capability was covered and by which surviving item's canonical ID
(`coveringItemID`). There is **no inverse view**: nothing today answers "what
does this *surviving* item cover?" from the surviving item's own record —
that fact only exists by scanning every `CoverageSuppression.covered` entry
in the same `EngineGeneration` for a `coveringItemID` match, and
`EngineGeneration` is a transient return value, never persisted.
**Genuinely missing:** a `coveredCapabilities: [String]` field (raw
`PackingCapability` values) on `PackingItemDraft`, populated once, after
coverage resolution, by inverting `coverageSuppressions` — a pure
derivation from data the engine already computed in the same call, not a
second coverage decision.

### `suppressions` — already fully recorded, just not surfaced in Item Detail

`CoverageSuppression` already carries `refutedCapabilities` (capabilities the
item claimed but were refuted, not just covered-elsewhere) and `coveredBy`.
This is unchanged, complete, Phase 4 evidence. It answers "why isn't item X
on the list" for **removed** items — which have no Item Detail row today,
since Item Detail only opens for items present on the list. Phase 8 does not
need to change this; it is cited, not extended. (A "what did this survivor
suppress" view is the `coveredCapabilities` field above, not a change to
`CoverageSuppression` itself.)

### `constraints` — answerable live, without a new persisted field

`ConstraintDecision.items` (`ConstraintResolver.swift:6-13`) lists the
canonical IDs a decision **removed** — again the removed side, not the
survivor's. For a *surviving* item, "did a bag/style/share/authority
constraint affect it" is answerable without any new persistence, because
the two functions that decide it are pure and already need only facts the
item and its trip already carry:

- `ConstraintResolver.optionalRuling(importance:tags:bag:style:)`
  (`:48-70`) — needs the item's `importance` (on the draft), the catalog's
  `tags` for its `canonicalItemID` (static lookup, `catalog.item(id:)`,
  `Catalog.swift:63`), and the trip's current `bagType`/`packingStyle`
  (already on `TripRecord`). Re-calling this is not re-deciding inclusion —
  it is the same one-line authority Phase 7 already made the single source
  of truth, invoked again for its own already-computed-once answer.
- `ConstraintResolver.sharingResolution(for:rules:context:party:)`
  (`:127-147`) — the shared-vs-personal fact for this item is already
  fully captured by whether `item.ownershipType == .shared` plus (once
  Task 1 lands) `quantityReasonArguments`; no live re-call is even needed
  for a stored item, only for a not-yet-generated preview.

**No new persisted field for constraints.** `authority` (below) already
covers the fourth named case (share is covered by `ownershipType` +
quantity evidence).

### `authority` — already fully expressible, unchanged

`hasUserAuthority(_:)` (`ConstraintResolver.swift:193-195`) reads
`isUserAdded`/`isUserModified`, both already on `PackingItemDraft` and
`PackingItemRecord`. A `custom.*` canonical id (or nil canonical id) marks
an off-catalog item — `scripts/audit_recommendation_traces.py`'s own
`TraceItem.is_user_authority` property already encodes this exact test.
Nothing new; `RecommendationTrace.authority` is a direct read.

### Persistence — the real cross-cutting gap, and the precedent for closing it

`PackingItemRecord` (`ios/PackWise/Data/Persistence/Models.swift:187-232`)
persists `reasonCode`/`reasonArguments` (as `reasonArgumentsRaw`, a
`"k=v|k=v"`-joined string) and `quantityReason`, but **not**
`quantityEvidence` — confirmed by reading `PackingItemRecord.init(from:)`
end to end; no `quantityEvidence` line exists. The `Catalog.swift:377`
comment already names this as Phase 8's to close. The same gap will apply
to the two new fields above (`quantityReasonArguments`,
`coveredCapabilities`) unless Phase 8 adds them. The existing
`reasonArgumentsRaw`/`sourceSignalsRaw` pattern (pipe-joined key=value
pairs; comma-joined raw values) is the precedent to follow — not a new
serialization scheme, and not a `Codable` conformance added to
`CoverageSuppression`/`ConstraintDecision`/`CapabilityCoverage` themselves
(which stay `Hashable, Sendable` only, exactly as Phase 4/Phase 7 left
them — they are not what gets persisted; their *derived, flattened* facts
are).

**A second, narrower gap in the same file:** `PackingItemRecord.apply(_:)`
(`:269-280`), called when a regenerated draft merges back into an existing
persisted row, already refreshes `reason`/`quantityReason` on every
merge but **not** `reasonCode`/`reasonArguments`/`sourceSignals` — a
pre-existing asymmetry, not caused by this phase. Any new trace field this
phase adds must be added to `apply(_:)`'s refresh set (peers of `reason`/
`quantityReason`, which the user-visible trace must stay in sync with on
regeneration) — named here explicitly so the implementing task does not
silently copy the `reasonCode` non-refresh instead. Fixing the pre-existing
`reasonCode`/`sourceSignals` staleness itself is out of scope — it predates
Phase 8 and is not one of the eight named trace facets.

**Schema versioning:** `PackWiseSchemaV1`→`V2`→`V3`
(`Models.swift:609-652`) exist and are bumped only for **new model types**
joining the schema (`WeatherChangeProposalRecord` in V2,
`PackingMemoryEventRecord` in V3) via `MigrationStage.lightweight`. Every
prior *field* addition to `PackingItemRecord` itself (e.g. `reasonCode:
String = ""`, `:197`) shipped with a default value and no schema version
bump — SwiftData's lightweight automatic migration already covers additive,
defaulted fields on an unchanged model type. The new fields below follow
that same precedent: defaulted `String = ""` properties, no `PackWiseSchemaV4`.

## Architecture

No second decision engine. Three additions, all pure derivations over data
the engine already computed in the same `generateDetailed` call, plus one
presentation-layer assembler that reads them.

### 1. Two new `PackingItemDraft` fields (Catalog.swift)

```swift
struct PackingItemDraft: Hashable, Identifiable, Codable, Sendable {
    // ... existing fields unchanged ...
    /// Structured arguments behind quantityReason for the non-clothing
    /// quantity families (care, warm-layer rotation, party sharing) — the
    /// same role reasonArguments already plays for the inclusion reason.
    /// Empty for fixed singletons and for the clothing family, which
    /// already has quantityEvidence.
    var quantityReasonArguments: [String: String] = [:]
    /// Raw PackingCapability values this item satisfies for another need —
    /// the inverse of CoverageSuppression.covered, computed once after
    /// coverage resolution. Empty when this item covers no capability
    /// another candidate also wanted (most items).
    var coveredCapabilities: [String] = []
}
```

### 2. Populate both in `PackingEngine`, from data already computed

- `quantityReasonArguments`: set alongside `quantityReason` at each of the
  three non-clothing call sites in `applyQuantities`
  (`PackingEngine.swift:908-919` shared, `:929-931` care, `:937-944` warm
  layer) — the `arguments`/`["quantity":…, "partySize":…]` dictionaries
  already being built for `render(...)` are assigned to the field instead
  of only feeding the render call.
- `coveredCapabilities`: one pass in `generateDetailed`
  (`PackingEngine.swift:34-64`), after `coverageSuppressions` is known,
  inverting it: `Dictionary(grouping: suppressions.flatMap(\.covered), by:
  \.coveringItemID)`, mapped to sorted raw capability values, applied to
  the matching item by `canonicalItemID` (and `travelerID` for personal
  items, mirroring `CoverageSuppression.travelerID`'s own scoping).

Both are additive, zero-diff for every existing field: no item is added,
removed, requantified, or re-covered. `report_engine_goldens.py` must show
the two new keys appear in every fixture output with zero change to any
existing key — verified per-task, not assumed.

### 3. `RecommendationTrace` — presentation-layer assembler, not a stored type

```swift
/// Assembled on demand from an item's own stored, structured facts plus
/// (for the constraint facet only) a live, pure re-call of the same
/// authority functions Phase 7 centralized. Never a second decision —
/// every fact here was already decided once by PackingEngine/
/// ConstraintResolver/CoverageResolver; this only reads it back.
enum RecommendationTrace {
    enum InclusionFamily: String, Hashable, Sendable {
        case baseEssential, tripType, activity, weatherPrecise, weatherSeasonal
        case party, dependency, personalPreference, destination, documents
        case flight, substitution, userAuthority
    }

    /// Pure derivation over the closed reasonCode/signal vocabulary
    /// already read above — no new stored field.
    static func inclusionFamily(reasonCode: String, signals: [RecommendationSignal]) -> InclusionFamily {
        if reasonCode.isEmpty { return .userAuthority }
        if reasonCode.hasPrefix("base.essential.") { return .baseEssential }
        if reasonCode.hasPrefix("weather.seasonal") { return .weatherSeasonal }
        if reasonCode.hasPrefix("weather.") { return .weatherPrecise }
        if reasonCode.hasPrefix("activity.") { return .activity }
        if reasonCode.hasPrefix("party.") { return .party }
        if reasonCode.hasPrefix("dependency.") { return .dependency }
        if reasonCode.hasPrefix("preference.") { return .personalPreference }
        if reasonCode.hasPrefix("trip_type.") { return .tripType }
        if reasonCode.hasPrefix("destination.") { return .destination }
        if reasonCode.hasPrefix("documents.") { return .documents }
        if reasonCode.hasPrefix("flight.") { return .flight }
        if reasonCode.hasPrefix("substitution.") { return .substitution }
        return .tripType // closed fallback; a test walks every reasons.json key to prove this branch is unreachable today
    }

    struct QuantityFacet: Hashable, Sendable {
        var value: Int
        var isFixedSingleton: Bool
        var clothingEvidence: ClothingQuantityEvidence?
        var reason: String
        var reasonArguments: [String: String]
    }

    struct ConstraintFacet: Hashable, Sendable {
        var bagStyleTrimEligible: Bool   // ConstraintResolver.optionalRuling(...).keep == false would apply if optional
        var sharing: ConstraintResolver.SharingResolution
    }

    struct Authority: Hashable, Sendable {
        var isUserAdded: Bool
        var isUserModified: Bool
        var isCustomItem: Bool
    }
}
```

Item Detail calls these directly from `item`'s already-loaded fields (plus,
for `ConstraintFacet`, one `catalog.item(id:)` lookup and the trip's stored
`bagType`/`packingStyle`/`effectiveParty` — all already available where
`ItemDetailView` is presented). No new domain type touches
`PackingEngine.generateDetailed`'s decision path.

### What does NOT change

- `PackingEngine`'s item selection, quantity arithmetic, coverage
  resolution, weather signal extraction, and `ConstraintResolver`'s
  decision functions are read, never altered in their decision logic —
  only their already-computed byproducts gain a wider audience.
- `CoverageSuppression`, `ConstraintDecision`, `CapabilityCoverage` stay
  `Hashable, Sendable`, not `Codable` — nothing persists them directly;
  only flattened, derived facts (`coveredCapabilities: [String]`) do.
- `RecommendationSignal` gains no new case. The finer vocabulary the
  roadmap wants already lives in `reasonCode`.
- Item Detail / `PackingRow`'s visual structure, spacing, and card layout
  are unchanged — new content fills existing sections
  (`ItemDetailView.reasons`) or adds one clearly-scoped subsection, never a
  new screen or navigation flow.

## Decision — the `party.shared` pluralization fix

**The routed finding, verbatim**
(`docs/plans/2026-09-02-product-hardening-program.md:308-315`): a shared
quantity greater than 1 still renders "One for the group" because
`shared/rules/reasons.json`'s `"party.shared"` template
(`"One for the group — not one per person."`) has no placeholder, unlike
`"party.shared_umbrella"`.

**Reproduced live, not assumed**, against `ios/PackWiseTests/Goldens/
37-family4-5d-hiking-camping-outdoor.json` at `eadc345`:

```json
{"canonicalItemID": "toiletries.sunscreen", "owner": "shared", "quantity": 2,
 "quantityReason": "One for the group — not one per person."}
```

A family of 4 sharing sunscreen (`scaleByParty`, `per: 3` →
`ceil(4/3) = 2`) genuinely gets `quantity: 2`, and the reason text says
"One" — the exact bug, live, in the current baseline.

**Root cause, read precisely.** `ConstraintResolver.sharingResolution`
already returns a correctly-computed `quantity` and a **correctly
pluralized** fallback string (`sharedQuantityReason`,
`ConstraintResolver.swift:182-184`: `quantity == 1 ? "One for the group…"
: "\(quantity) for the group…"`). `PackingEngine.applyQuantities`
(`:913-919`) passes `quantity`/`partySize` as `render(...)` arguments, but
`render` (`ReasonRenderer.render`, `QuantityEngine.swift:135-155`) checks
`templates[code]` **first** and only falls back to the caller's `fallback`
string when no template exists. `reasons.json` *does* have a `"party.shared"`
key — a static string with no `{…}` placeholder — so the template always
wins, the `quantity`/`partySize` arguments are silently discarded, and the
already-correct `ConstraintResolver`-built fallback never surfaces. Both
symptoms have the same one root cause: a template exists where it
shouldn't be static.

**The fix, matching `party.shared_umbrella`'s established pattern exactly**
(per the task's instruction — derive from `SharingResolution`'s quantity,
not a new hardcoded string in recommendation logic): `party.shared_umbrella`
already solves "templates can't pluralize" by pre-building a phrase
argument (`umbrellaPhrase = quantity == 1 ? "One umbrella" : "\(quantity)
umbrellas"`, `ConstraintResolver.swift:179`, mirrored again in
`PackingEngine.swift:907`) and putting `{umbrellaPhrase}` in the template.
`party.shared` gets the same treatment:

- `shared/rules/reasons.json`: `"party.shared": "{quantityPhrase} for the
  group — not one per person."`
- `PackingEngine.applyQuantities`'s non-umbrella branch
  (`:913-919`): build `let quantityPhrase = quantity == 1 ? "One" :
  "\(quantity)"` (same shape as `umbrellaPhrase`) and pass it as
  `"quantityPhrase"` instead of the currently-inert `"quantity"`/
  `"partySize"` pair (`partySize` was never consumed by the template
  either, confirmed by reading `reasons.json`; it is dropped, not kept as
  dead weight).

This is a template-and-argument fix only. No change to `sharedQuantity`'s
arithmetic, no change to `sharingPolicies`, no change to which items are
shared or their quantities — the golden boundary's "approved shared-
quantity wording correction," nothing more. Fixture 37's `toiletries.
sunscreen`/`toiletries.insect_repellent` rows are the only expected golden
diff, and only their `quantityReason` string; `quantity: 2`/`quantity: 1`
themselves must not move.

## Exit metrics — reuse and strengthen `audit_recommendation_traces.py`

Read in full (`scripts/audit_recommendation_traces.py`, 557 lines). Run
fresh against `eadc345` (not cited from the stale Phase 1 doc):

```text
Total item rows: 1441 (3 user-authority / exempt, 1438 engine-generated / scored)
Inclusion completeness: 1370/1438 (95.3%) — 0 missing reason code, 0 missing signal
Quantity evidence: 309/309 required rows have evidence (100%) — 0 missing
CLEAN
```

Two of the roadmap's five target metrics are **already zero today** —
"missing inclusion evidence" and "missing required quantity evidence" are
not gaps Phase 8 needs to close; they were closed by Phase 1's own
DEAD-bucket work and Phase 3's quantity evidence, respectively, and Phase
8's job is to *keep* them at zero (regression-guard via `--strict` in CI),
not re-derive them.

The other three need real script work:

1. **"generic-only generated explanations = 0" — the roadmap's framing
   conflicts with the codebase's own established finding, and that
   conflict is named here rather than silently resolved.** 68 rows
   currently carry `trip_type.generic`. Every one was already individually
   examined by Phase 1's P2-4 finding (`docs/engine-audits/
   2026-09-03-engine-findings.md`) and found to be the fallback ladder
   working *correctly* — `essentials.sunglasses` gets `trip_type.generic`
   only in fixtures with no `weather.hot`/`weather.uv` signal anywhere
   else; `electronics.headphones`/`travel_comfort.book` have no
   activity/weather rule that could ever give them a more specific code;
   `clothing.blazer`/`dress_shirt`/`footwear.dress_shoes` are business-
   trip-type items with no more specific rule; `activities.ski_gloves`/
   `ski_goggles` fall back because ski/snow has no dedicated
   `ActivityContract` (Phase 5 closed with only Hiking and Camping
   migrated); Camping's `activities.daypack`/`health.blister_pads`/
   `health.first_aid` fall back because `ActivityContracts["camping"]`
   deliberately does not declare `.dayCarry`/`.blisterCare` needs (those
   are Hiking's). **Driving this bucket to zero requires authoring new
   rule content — new reasonCodes, new `signalAdds`/`ActivityContract`
   entries, or new reasons.json templates for real items — which is
   recommendation-content authorship, not trace productization, and is
   explicitly out of this phase's golden boundary ("item inclusion/
   removal... coverage decisions... activity behavior" must not change).**
   Phase 8's call: report this bucket through the strengthened
   `InclusionFamily` classification (every row still gets a real family —
   `.tripType` — and a real, inspectable `reasonCode`, distinguishable from
   a defect), but do not force the count to zero. This is stated
   explicitly, per the task's own instruction to name a roadmap/reality
   conflict rather than reconcile it silently, the same call every prior
   phase's design doc had to make once.
2. **"invalid precise/seasonal provenance = 0" — new check, add it.**
   Structural, not text-matching: `weather.seasonal_sun`/
   `weather.seasonal_layer` rows must always carry empty
   `reasonArguments` (confirmed: both are rendered with `[:]`,
   `PackingEngine.swift:639,651` — only precise codes like
   `weather.rain_days` carry day-count arguments). A row with a seasonal
   reasonCode and any non-empty `reasonArguments` is a defect: it would
   mean seasonal fallback copy is claiming forecast-derived specifics it
   doesn't have. Currently **0** such rows (verified: every
   `weather.seasonal_*` row across all 38 goldens has `reasonArguments:
   {}`) — this is a regression guard for a currently-clean invariant, not
   a fix.
3. **"fabricated provenance on custom/user-added rows = 0" — new check,
   add it.** `TraceItem.is_user_authority` rows are currently *excluded*
   from scoring, not verified empty. Add the check: every user-authority
   row must have empty `reasonCode`/`reason`/`signals` — the engine must
   never invent inclusion provenance for the user's own decision.
   Currently **0** violations (verified directly:
   `14-manual-quantity-survives-refresh`'s t-shirt and
   `27-…-custom-item-…`'s custom item both have fully empty
   `reasonCode`/`reason`/`signals`/`reasonArguments` today) — again a
   regression guard on an already-correct invariant.

`--strict` (already a flag on the script, unused by any CI step today)
becomes the mechanism that turns "0 today" into "0 forever" for gates 2–3
plus the two already-zero gates from before Phase 8 — Task 8 wires it into
`scripts/run_engine_audit.sh`'s existing pass/fail semantics, the same
"reportable finding vs. build-breaking" convention `audit_engine_inputs.py`
already established.

## The 18 required scenarios — existing evidence vs. genuinely new

| # | Scenario | Existing evidence | New work |
| --- | --- | --- | --- |
| 1 | base essential singleton | Any fixture, e.g. 01 `toiletries.toothbrush` (`base.essential.toiletries`, fixed singleton) | Trace classification test only |
| 2 | Tokyo planned-laundry T-shirts | Fixtures 02/02b/03/05; `GoldenEngineTests.swift:139-158` already asserts `quantityEvidence.laundryPlan`/`laundryReduced` | None — cite |
| 3 | workout clothing | Fixture 08 (`clothing.workout_top`/`workout_bottom`) | None — cite |
| 4 | swimwear | Fixture 06; `GoldenEngineTests.swift:173` asserts `quantityEvidence.basis == "dryingRotation"` | None — cite |
| 5 | Hiking footwear covering walking | `substitution.hiking_covers_walking` (fixture 29), `substitution.running_covers_walking` (fixture 08) | None — cite |
| 6 | ski gloves covering ordinary gloves | `CoverageTests.skiGlovesCoverColdHandsWithoutAnIDPairRule` (`CoverageTests.swift:249`); fixtures 21/35 | None — cite |
| 7 | Camping item | Fixtures 28–32, 37 (flashlight, insect repellent, hydration, overnight warmth) | None — cite |
| 8 | precise rain item | Fixtures 09, 36 (`weather.rain_days`/`weather.rain_weekday`) | None — cite |
| 9 | seasonal sun/layer item | Fixture 18 (Reykjavik roadtrip, seasonal-only path), fixture 12 (far-future date, seasonal-only path); `weather.seasonal_sun`/`weather.seasonal_layer` reasonCodes | None — cite |
| 10 | partial forecast, precise + seasonal together | Fixture 33 (byte-stable pin, documented deviation); `WeatherNeedHardeningTests.partialForecastBlendsCoveredSignalsWithSeasonalRemainder`/`.seasonalRemainderNeverDowngradesAPreciseDayItem` (`WeatherNeedHardeningTests.swift:144,186`) | None — cite |
| 11 | shared umbrella | Fixture 11 ("shared umbrella ×1"), fixture 38 | None — cite |
| 12 | shared quantity > 1 reason (party.shared fix) | Fixture 37's `toiletries.sunscreen` (`quantity: 2`) reproduces the bug live today | **New**: fix + re-recorded fixture 37 + a focused unit test on the exact pluralization |
| 13 | dependency (laptop charger) | `companionNotDuplicatedWhenRulesAlreadyEmitIt` (`ConstraintTests.swift:308`), `userAddedChargerPreemptsTheAutomaticLaptopCompanion` (`:665`) — both assert `dependency.companion` | None — cite |
| 14 | manual quantity override | `manualQuantitySurvivesWeatherRefresh` (`ClothingQuantityTests.swift:485`); fixture 14 | None — cite |
| 15 | Not Needed | `removedBaseEssentialStaysRemovedAcrossRegeneration` (`ConstraintTests.swift:387`); fixture 13 | None — cite |
| 16 | user-added canonical item | `userAddedCanonicalAndCustomItemsSurviveRegeneration` (`ConstraintTests.swift:436`) | None — cite |
| 17 | custom item | Same test; fixture 27's `custom.lucky_travel_journal` | None — cite |
| 18 | party owner/carrier distinction | `ownerStaysWithTheSameTravelerAcrossRegeneration`, `manuallyReassignedCarrierSurvivesRegeneration` (`ConstraintTests.swift:497,519`); fixture 37 | None — cite |

Sixteen of eighteen scenarios already have a named, passing test or fixture
proving the underlying **decision**. Phase 8's job for those sixteen is a
**trace-classification test** — proving `RecommendationTrace` reads the
right facet correctly off the existing evidence, not re-proving the
decision. Only scenario 12 requires a production fix; scenario 10 needs no
new fixture (Phase 6 already documented why the golden schema can't express
a true partial-forecast fixture and routed that as its own follow-up,
unowned by Phase 8 — cited, not re-litigated).

## Non-goals

- Redesigning `PackingEngine`, `CoverageResolver`, `ConstraintResolver`, or
  `ActivityContracts` decision logic. Every function this phase calls
  already exists and is called for its existing, already-computed answer.
- Forcing the 68-row generic-only bucket to zero (see Exit metrics, above)
  — named as a roadmap/reality conflict, not silently done or silently
  skipped.
- A new `RecommendationSignal` case, a new `PackingCapability`, a new
  `ActivityNeed`, or any `shared/rules/*.json` change beyond the one
  `party.shared` template fix.
- Fixing `PackingItemRecord.apply(_:)`'s pre-existing
  `reasonCode`/`sourceSignals` non-refresh — named as a gap this phase's
  new fields must not repeat, not a defect this phase repairs generally.
- Redesigning Item Detail's layout, navigation, or `PackingRow`'s row
  chrome. New content fills existing sections.
- Persisting `CoverageSuppression`/`ConstraintDecision` themselves, or
  giving them `Codable` conformance — only their derived, flattened facts
  persist.
- Context intelligence (Phase 9+), family hardening (Phase 10), weather V2
  reconciler integration (Phase 11), lifecycle features (Phase 12).
- Physical-device verification, M3B/M3C — stay deferred/blocked exactly as
  every prior phase left them.

## Verification plan

- Zero-diff gate for the two new `PackingItemDraft` fields:
  `report_engine_goldens.py --baseline-ref eadc345` must show the two new
  keys appended to every fixture's items with **zero** change to any
  existing key, before either field's behavior-adjacent test is trusted.
- The `party.shared` fix is the one **approved, reviewed** golden diff:
  fixture 37's two shared-item rows change `quantityReason` text only;
  `quantity` values, every other fixture, and every non-`party.shared` row
  in fixture 37 must be byte-identical to `eadc345`.
- `scripts/run_engine_audit.sh` clean after every task, `--strict` clean by
  Task 8.
- Full `xcodebuild test`, `python3 scripts/validate_shared.py`, `npm
  --prefix api run preflight` at close.
- All 18 required scenarios map to a named task and a named test (cited
  existing test/fixture, or new trace test) in the implementation plan.

## Routed findings inherited, and their disposition

- **`reasons.json`'s `party.shared` pluralization (F-8-shared-copy)** —
  Phase 7 routed this explicitly to Phase 8. Decided and fixed here (see
  Decision, above).
- **`CoverageContext` double-construction** (Phase 6's design doc) — not
  Phase 8's; unaffected, carried forward unchanged.
- **Golden-fixture-schema gap for expressing a true partial forecast**
  (Phase 6's closure) — not Phase 8's; the partial-forecast trace scenario
  (#10) is proven at the unit level already, cited above, no golden schema
  change needed for Phase 8's purposes.
- **F-1 (golden-diff schema tolerance) and the context-chip/bag-type/
  trip-type UNTESTED tail** — pre-existing, outside Phase 8's scope,
  carried forward unchanged.
