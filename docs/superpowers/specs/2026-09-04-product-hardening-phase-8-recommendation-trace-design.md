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

**Required guard: a closed key vocabulary, not an open one.** An unbounded
`[String: String]` would let three unrelated call sites each invent their
own key names over time — exactly the open-vocabulary drift
`PackingCapability`/`ActivityNeed`/`WeatherSignal` were each closed to
prevent. The key set below is not invented; it is read directly off what
each of the three real call sites already computes, and nothing else:

- `CareQuantityEngine.Result.arguments` (`CareQuantity.swift:44,64`) builds
  exactly `["quantity", "rate", "name", "days"]` for diapers and
  `["quantity", "name"]` for extra outfits — a subset of the same four
  keys, never a fifth.
- `WarmLayerQuantities.quantity`'s arguments (`ClothingQuantity.swift:265`)
  build exactly `["quantity", "days"]`.
- `ConstraintResolver.sharingResolution`'s call site
  (`PackingEngine.swift:901-921`) has `quantity` (the resolved shared
  count, `SharingResolution.shared(quantity:reason:)`) and, for the one
  `essentials.umbrella_compact` special case, `weather.rainDays`
  (`:905-906`) already in scope; `party.travelers.count` is available at
  the call site (already read as `party.travelers.count` at `:916` in
  today's code, there named `partySize`) for the `scaleByParty`/
  `scaleByDevices`/`scaleByDurationAndParty` policies where party size is
  the reason the number is what it is.

**The closed set — six keys, every one traced to a real call site above:**

```text
"quantity"      — every family; the resolved count itself
"days"          — care (both items), warm-layer rotation
"rate"          — care/diapers only (the per-day rate the count derives from)
"name"          — care only (the traveler's display name)
"travelerCount" — sharing only, when the policy is party-size-driven
"rainDays"      — sharing only, the umbrella special case
```

Two deliberate departures from the illustrative key names named when this
guard was requested, both because the real call sites don't back them:
`washCycleDays`/`requiredUses`/`packingStyle`/`bag` are not in this set —
those are `ClothingQuantityEvidence`'s facts (`ClothingQuantity.swift`), and
the clothing family is explicitly excluded from `quantityReasonArguments`
(above) precisely so its evidence has exactly one home, not two. And
`sharedQuantity` is not a separate key from plain `quantity` — care and
warm-layer both already self-reference their own resolved count as
`"quantity"`, and giving the sharing family a same-meaning key under a
different name would be the vocabulary drift this guard exists to prevent,
not a justified exception.

A test (or audit-script check, Task 6 below) enforces this list is closed:
any key written to `quantityReasonArguments` outside this set fails the
same way an unlisted `ActivityNeed`/`PackingCapability` raw string would.

**Verified live, not assumed stale:** `scripts/audit_recommendation_traces.py
--goldens ios/PackWiseTests/Goldens` at `eadc345` reports **0** rows missing
required quantity evidence (309/309, 100%) — the Phase 1 baseline's "25
missing" finding (P2-5) is **already resolved**; it predates Phase 3, which
landed the clothing evidence and populated `quantityReason` even at the
policy floor (`fixture 01`'s sleepwear: `quantity=1`, `quantityReason: "1
sleep set with repeat wear."`). The trace-coverage doc's own numbers
(`docs/engine-audits/2026-09-03-trace-coverage.md`) are from before Phase 3
and must not be cited as current in Phase 8's closure — Task 9's exit
report regenerates this file fresh.

### `signals` — `sourceSignals`, unchanged, already exposed in Item Detail

`ItemDetailView.reasons` (`PackingListView.swift:793-804`) already renders
`item.sourceSignals` as capsule chips via `.customerLabel`. Nothing to add;
Phase 8 reads this list, does not replace it.

### `needs`/`capabilities` and `coverage` — the survivor's side is missing, and how it's populated is a required amendment

`PackingCapability` (`CoverageResolver.swift:12-25`, 12 closed cases) and
`CoverageSuppression` (`:92-107`) are Phase 4's authority. `CoverageSuppression`
is recorded **per suppressed item** — `covered: [CapabilityCoverage]` names
which capability was covered and by which surviving item's canonical ID
(`coveringItemID`). There is **no inverse view**: nothing today answers "what
does this *surviving* item cover?" from the surviving item's own record —
that fact only exists by scanning every `CoverageSuppression.covered` entry
in the same `EngineGeneration` for a `coveringItemID` match, and
`EngineGeneration` is a transient return value, never persisted.
**Genuinely missing:** a field on `PackingItemDraft` naming what a
surviving item satisfies.

**Required amendment: this is not "invert the suppressions," because
inverting only sees a capability that some *other, suppressed* candidate
also wanted.** The counterexample that overrides the original design: a
rain jacket (`clothing.rain_jacket`, `itemCapabilities`:
`[.rainShell, .windShell]`, `CoverageResolver.swift:145`) genuinely
satisfies `windProtection` even on a trip where no windbreaker candidate
was ever generated in the first place — there is no
`CoverageSuppression` to invert, because nothing was suppressed, and the
original inversion design would silently omit `windShell` from the rain
jacket's trace even though the rain jacket is exactly why the trip's wind
need is met. The correct concept is not "what did this item make
redundant" (that is `CoverageSuppression`, unchanged, see below) but:

```text
kept candidate's own capabilities  ∩  active required needs
  = capabilities genuinely satisfied by this item
```

**Read `CoverageResolver.resolve(items:needs:)` closely
(`CoverageResolver.swift:222-290`): this intersection is already computed,
by name, inside the resolution loop itself, every single time.** For each
item in priority order, `let needed = capabilities.intersection(needs)`
(`:245`) is exactly `itemCapabilities[canonical] ∩ needs` — and every path
that keeps an item (the user-added/modified branch, `:246-252`; the
plain-pass-through branch for items outside the vocabulary, `:240-244`; the
"kept because it genuinely covers an uncovered need" branch, `:284-287`)
already has `needed` in scope at the moment it appends to `kept`. The
"suppressed because already covered" branch (`:266-283`) is the only one
that does *not* keep the item — correctly, since a suppressed item never
gets a trace to populate.

**The fix: attach `needed` to the item at the exact point `resolve` decides
to keep it, inside `CoverageResolver` itself — not a second pass in
`PackingEngine` over `coverageSuppressions` afterward.** This is the same
"capture as byproduct of the real decision" discipline Amendment 1 (below)
applies to constraints — `CoverageResolver.resolve` already computes the
fact; it should return it, not have `PackingEngine` re-derive a lossy
approximation of it from a different, structurally incomplete data source.
No second coverage evaluator, no change to `needs(context:)` or
`itemCapabilities` themselves — `resolve`'s signature and its per-item loop
are the only things that change (Architecture, below).

`suppressedAlternatives`-type evidence — "what this item made redundant,"
i.e. today's `CoverageSuppression.covered` read from the *suppressed* side
— stays a **distinct, still-valid** trace concept. The two questions ("what
does this item satisfy" vs. "what did this item make unnecessary") are
both real and both wanted; this amendment adds the first without touching
the second.

### `suppressions` — already fully recorded, just not surfaced in Item Detail

`CoverageSuppression` already carries `refutedCapabilities` (capabilities the
item claimed but were refuted, not just covered-elsewhere) and `coveredBy`.
This is unchanged, complete, Phase 4 evidence. It answers "why isn't item X
on the list" for **removed** items — which have no Item Detail row today,
since Item Detail only opens for items present on the list. Phase 8 does not
need to change this; it is cited, not extended. (A "what does this
survivor satisfy" view is the `satisfiedCapabilities` field above, not a
change to `CoverageSuppression` itself.)

### `constraints` — required amendment: captured at generation time, not re-derived live

The original design for this facet read `ConstraintDecision.items`
(`ConstraintResolver.swift:6-13`, the **removed** side only) and then
argued that for a *surviving* item, "did a bag/style/share constraint
affect it" could be answered by **re-calling**
`ConstraintResolver.optionalRuling(importance:tags:bag:style:)` and
`.sharingResolution(for:rules:context:party:)` live from presentation code
— on the reasoning that both functions are pure, so calling them twice
costs nothing and decides nothing new.

**The user overrides that reasoning, not merely refines it.** The house
rule this phase must follow: the engine makes the decision once; the trace
explains that exact decision; it does not re-derive it by calling the same
function again from a different layer. Purity is not the test — a pure
function re-called from Item Detail with the item's *current* stored
fields plus a *fresh* catalog/trip lookup can silently answer a different
question than the one the engine actually decided at generation time
(the catalog's tags could change between app versions; the trip's
`bagType`/`packingStyle` could be edited after generation without a
regeneration in between — Item Detail would then show a live re-ruling for
today's bag, not the ruling that actually produced this item). The
generation-time call is the *only* one whose answer this specific
`PackingItemDraft` is a consequence of; a second call several screens later
is not that answer, even when it happens to compute the same value most of
the time.

**Read `PackingEngine.generateDetailed` end to end (`:34-64`) to find where
each decision actually fires**, tracing into every place it calls
`ConstraintResolver`:

- `resolve(suggestions:context:existing:overrides:ownership:travelerID:assignedTravelerID:drops:)`
  (`:661-747`), called from both `generateSimple` (`:127-136`) and
  `generateForParty` (`:178-187`, `:190-199`), is where
  `ConstraintResolver.optionalRuling(...)` is actually called
  (`:715-720`) — but **only when a suggestion has no existing draft to
  merge into** (the `if let existingItem` branch at `:688-710` returns
  before ever reaching the ruling call; an item already on the list from a
  prior generation is never re-ruled by `resolve` itself). When
  `ruling.keep == false` the item is dropped and recorded in `drops`
  (`:721-726`) — it never becomes a draft, so it has no trace to capture.
  When `ruling.keep == true`, the draft is constructed immediately after
  (`:728-743`) — this is the byproduct-capture point: the same `ruling`
  value already computed at `:715` is in scope right where the
  `PackingItemDraft` it decided to keep is built.
  `ConstraintResolver.optionalRuling`'s own guard (`:54-57`) makes the
  ruling a no-op (`keep: true, conflictKey: nil`) whenever `importance !=
  .optional` or the bag/style combination doesn't constrain space at all —
  the overwhelming majority of items. Only when that guard is *false* (an
  optional item on a space-constrained bag) did the ruling do real work;
  that is the "materially affected" case worth capturing, not a
  trivially-true ruling for every item on every trip.
- `ConstraintResolver.sharingResolution(for:rules:context:party:)` is
  called from **two** places, and they decide different things: once in
  `generateForParty` (`:171`) to route a suggestion into the shared or
  personal collection *before* any draft exists, and once in
  `applyQuantities` (`:902`) to compute the *quantity* of an already-shared
  draft (`:901-921`, the byproduct-capture point for sharing — the
  `quantity`/`fallback` this exact call returns is what
  `copy.quantity`/`copy.quantityReason` are set from two lines later). The
  original design's own observation that "the shared-vs-personal fact is
  already fully captured by `ownershipType == .shared` plus (Task 1's)
  `quantityReasonArguments`" was correct and stays true — but the
  `RecommendationTrace.ConstraintFacet` code sample built in the same
  design *re-called* `sharingResolution` anyway (Architecture, original
  draft), contradicting its own analysis. That contradiction is the actual
  bug this amendment closes: `ConstraintFacet.sharing` must be
  reconstructed from `item.ownershipType`/`item.quantity`/
  `item.quantityReason`/`item.quantityReasonArguments` — fields already
  populated as a byproduct of the one real `sharingResolution` call at
  `:902` — never a second call.

**The redesign, concretely.** `PackingItemDraft` gains one new field for
the bag/style facet (the sharing facet needs no new field, per above):

```text
Generation (PackingEngine.resolve, :715-720)
    ↓
ConstraintResolver.optionalRuling(...) decides — real work only when
importance == .optional AND the bag/style combination is space-constrained
    ↓
capture: was this item's survival contingent on essentialOptionalTags
protection, or on a bag/style combination that doesn't trim optionals?
    ↓
PackingItemDraft.bagStyleConstraintFact (nil when the ruling never left
its no-op guard — the common case)
    ↓
persist (Task 2)
    ↓
Item Detail reads the stored fact — never calls optionalRuling again
```

```swift
/// Captured once, in PackingEngine.resolve, at the exact optionalRuling(...)
/// call (:715-720) that already decides whether this item survives a
/// space-constrained bag. Nil whenever the ruling never left its own
/// no-op guard (importance != .optional, or the bag/style combination
/// doesn't constrain space) — the common case, and correctly not "no
/// constraint was ever evaluated" trace noise for every item on every trip.
struct BagStyleConstraintFact: Hashable, Codable, Sendable {
    /// True when the item survived only because it carries an
    /// essentialOptionalTags tag (base/rain/cold/medication) — without
    /// that protection, this exact bag/style combination would have
    /// trimmed it (ConstraintResolver.swift:58-61).
    var survivedByEssentialTagProtection: Bool
    /// The conflictKey this bag/style combination would use for a
    /// non-protected optional item. Nil only when this bag/style
    /// combination doesn't trim optionals at all (a checked bag, or a
    /// non-light style on a carry-on/backpack) — "your bag/style doesn't
    /// trim, so this wasn't at risk" is itself a real, inspectable fact,
    /// distinct from "a tag protected you from a trim that was live."
    var wouldTrimUnderKey: String?
}
```

`optionalRuling` (`ConstraintResolver.swift:48-70`) returns *before*
computing which key would apply whenever the essential-tag check succeeds
(`:59-61`, `return OptionalRuling(keep: true, conflictKey: nil)` — the
`bag == .personalItem`/`style == .light` branches below it never run), so
today's `keep`/`conflictKey` pair alone cannot answer "would this have
trimmed the item absent tag protection." Closing that requires computing
the would-be key *before* the tag check, not after — a behavior-preserving
reorder, not a new decision (every `keep`/`conflictKey` output is
byte-identical to today for every input). `OptionalRuling` widens to carry
the two new facts alongside the two that already exist:

```swift
struct OptionalRuling {
    var keep: Bool
    var conflictKey: String?
    /// False whenever this call's own no-op guard short-circuited
    /// (importance != .optional, or the bag/style combination doesn't
    /// constrain space) — every other field is trivial in that case.
    var wasConstraintLive: Bool
    /// True when keep == true only because an essentialOptionalTags tag
    /// protected the item from a trim that was otherwise live.
    var essentialTagProtected: Bool
    /// The conflictKey this bag/style combination would use for a
    /// non-protected optional item; nil when this combination doesn't
    /// trim optionals at all.
    var wouldTrimUnderKey: String?
}

static func optionalRuling(
    importance: ItemImportance,
    tags: [String],
    bag: BagType,
    style: PackingStyle
) -> OptionalRuling {
    guard importance == .optional,
          bag.appliesBagConstraint, bag.isSpaceConstrained else {
        return OptionalRuling(keep: true, conflictKey: nil, wasConstraintLive: false, essentialTagProtected: false, wouldTrimUnderKey: nil)
    }
    let wouldBeKey: String? = {
        if bag == .personalItem {
            return style == .prepared ? "style.prepared_vs_personal_item" : "bag.personal_item"
        }
        if style == .light { return "bag.space_constrained" }
        return nil
    }()
    let isEssentialOptional = tags.contains { essentialOptionalTags.contains($0) }
    if isEssentialOptional {
        return OptionalRuling(keep: true, conflictKey: nil, wasConstraintLive: true, essentialTagProtected: true, wouldTrimUnderKey: wouldBeKey)
    }
    if let wouldBeKey {
        return OptionalRuling(keep: false, conflictKey: wouldBeKey, wasConstraintLive: true, essentialTagProtected: false, wouldTrimUnderKey: wouldBeKey)
    }
    return OptionalRuling(keep: true, conflictKey: nil, wasConstraintLive: true, essentialTagProtected: false, wouldTrimUnderKey: nil)
}
```

`PackingEngine.resolve` (`:715-743`) then reads `ruling.wasConstraintLive`
to decide whether to populate `bagStyleConstraintFact` at all, and
`ruling.essentialTagProtected`/`.wouldTrimUnderKey` directly for the
struct's two fields — no branching logic re-implemented a second time in
`PackingEngine`; every fact is a field read off the one call's now-richer
return value.

`ConstraintFacet` becomes a pure read, never a second call:

```swift
extension RecommendationTrace {
    struct ConstraintFacet: Hashable, Sendable {
        /// From PackingItemDraft.bagStyleConstraintFact — nil when the
        /// bag/style ruling never left its no-op guard for this item.
        var bagStyle: BagStyleConstraintFact?
        /// Reconstructed from stored fields already populated as a
        /// byproduct of PackingEngine.applyQuantities's one real
        /// sharingResolution call (:902) — never a second call.
        var sharing: ConstraintResolver.SharingResolution?

        static func read(from item: PackingItemDraft) -> ConstraintFacet {
            ConstraintFacet(
                bagStyle: item.bagStyleConstraintFact,
                sharing: item.ownershipType == .shared
                    ? .shared(quantity: item.quantity, reason: item.quantityReason)
                    : nil
            )
        }
    }
}
```

**No new persisted field for the sharing half of this facet** — only
`bagStyleConstraintFact` is new; sharing is a read of fields Task 1 already
persists.

### `authority` — already fully expressible, unchanged, and the boundary this amendment strengthens

`hasUserAuthority(_:)` (`ConstraintResolver.swift:193-195`) reads
`isUserAdded`/`isUserModified`, both already on `PackingItemDraft` and
`PackingItemRecord`. A `custom.*` canonical id (or nil canonical id) marks
an off-catalog item — `scripts/audit_recommendation_traces.py`'s own
`TraceItem.is_user_authority` property already encodes this exact test.
Nothing new; `RecommendationTrace.authority` is a direct field read, and
was never proposed to re-call anything — Amendment 1 leaves this facet
exactly as originally designed. What Amendment 1 changes is the standard
every other facet in this file must now meet: **Item Detail reads persisted
trace and never calls `PackingEngine`, `CoverageResolver`,
`ConstraintResolver`, or `WeatherSignalExtractor` directly, for any facet,
constraint or otherwise** — stated explicitly here because the original
`ConstraintFacet` design was the one place this boundary was actually
violated in code, not just under-stated in prose.

### Persistence — the real cross-cutting gap, and the precedent for closing it

`PackingItemRecord` (`ios/PackWise/Data/Persistence/Models.swift:187-232`)
persists `reasonCode`/`reasonArguments` (as `reasonArgumentsRaw`, a
`"k=v|k=v"`-joined string) and `quantityReason`, but **not**
`quantityEvidence` — confirmed by reading `PackingItemRecord.init(from:)`
end to end; no `quantityEvidence` line exists. The `Catalog.swift:377`
comment already names this as Phase 8's to close. The same gap will apply
to the three new fields above (`quantityReasonArguments`,
`satisfiedCapabilities`, `bagStyleConstraintFact`) unless Phase 8 adds
them. The existing
`reasonArgumentsRaw`/`sourceSignalsRaw` pattern (pipe-joined key=value
pairs; comma-joined raw values) is the precedent to follow — not a new
serialization scheme, and not a `Codable` conformance added to
`CoverageSuppression`/`ConstraintDecision`/`CapabilityCoverage` themselves
(which stay `Hashable, Sendable` only, exactly as Phase 4/Phase 7 left
them — they are not what gets persisted; their *derived, flattened* facts
are).

**A second, narrower gap in the same file — required amendment, and the
original framing of it was wrong, not just incomplete.** The original
design stated `PackingItemRecord.apply(_:)` (`:269-280`) "already refreshes
`reason`/`quantityReason` on every merge but not `reasonCode`/
`reasonArguments`/`sourceSignals`," and treated closing that specific
asymmetry for two new fields as out of scope. **Reproduced live, not
assumed: `grep -rn "\.apply(" ios/PackWise --include="*.swift"` finds
`PackingItemRecord.apply(_:)` has zero call sites anywhere in the app
target.** The only `.apply(` calls in `Repositories.swift` are
`TravelerRecord.apply` (`:75`) and `WeatherChangeProposalRecord.apply`
(`:301,311,319,353,357`) — unrelated types. `PackingItemRecord.apply(_:)`
is dead code: never invoked in production, never exercised by a test
(`grep -rn "\.apply(" ios/PackWiseTests` finds no `PackingItemRecord`
match either). The original design's premise — that this method is the
live regeneration-merge mechanism, just missing two fields from its
refresh set — does not describe the actual codebase. **The user overrides
the original scoping call, and this correction is what makes the override
necessary, not merely convenient:** Phase 8 must fix the real mechanism,
because the real mechanism has a materially worse gap than "two fields
non-refreshed" — for most kept items on a regeneration, *nothing* refreshes
at all.

**The real regeneration flow, traced end to end.** There are two paths a
`PackingItemDraft` can reach a persisted `PackingItemRecord` through, and
they behave completely differently:

1. **Brand-new trip** (`TripSetupView.saveTrip()`, the `existingTrip ==
   nil` branch, `:1104-1107`): `engine.generate(context:)` runs with no
   `existing` argument, and `TripRepository.replaceItems(on:with:)`
   (`Repositories.swift:49-62`) deletes every prior `PackingItemRecord` (if
   any — there are none, this is a first save) and constructs entirely
   fresh records from the drafts (`:54`). No staleness is possible here;
   every field is freshly written. `PackingItemRecord.apply(_:)` plays no
   role.
2. **Existing trip, user edits and re-saves** (`TripSetupView.saveTrip()`,
   the `existingTrip != nil` branch, `:1057-1071`) — the actual
   "regenerate" the roadmap and this amendment mean. This calls
   `engine.recommendationDiff(context:existing:overrides:)`
   (`PackingEngine.swift:66-89`), which internally calls
   `generate(context:existing:[],overrides:)` (`:71`) — **`existing: []`,
   not the trip's real existing drafts** — purely to get a from-scratch
   baseline to diff against, then compares that fresh baseline to the
   *actual* existing drafts by `recommendationKey`, producing
   `RecommendationDiff.add`/`.removeCandidates`/`.quantityChanges`
   (`Catalog.swift:445-454`). The diff is shown to the user
   (`RecommendationDiffSheet`), and only what the user approves is applied
   via `TripRepository.applyDiff(_:addIDs:removeIDs:quantityIDs:on:)`
   (`Repositories.swift:232-260`) — which **still never calls
   `PackingItemRecord.apply(_:)`**: `diff.add` becomes new records via
   `addItem` (`:243`); `diff.removeCandidates` become "Not Needed"
   overrides via `markNotNeeded` (`:256`); and `diff.quantityChanges`
   mutate `record.quantity` **directly**, inline, with a packed-quantity
   clamp (`:247-250`) but with **no update to `reason`, `reasonCode`,
   `reasonArguments`, `sourceSignals`, or `quantityReason` at all** — even
   though the quantity just changed for a reason, and that reason's
   structured facts were computed and then dropped on the floor a second
   time. Worse: an item whose **quantity is unchanged but whose cause
   changed** — the exact scenario this amendment must guard (Hiking
   removed, a different activity independently keeps the same boots) —
   isn't in *any* of the three diff buckets, because the diff loop's only
   comparison is `fresh.quantity != item.quantity`
   (`PackingEngine.swift:84,112`). That item's persisted record is never
   touched at all. Its `reasonCode`, `sourceSignals`, and (once this phase
   lands) `quantityReasonArguments`/`satisfiedCapabilities`/constraint
   trace facts stay exactly as they were computed under the *old* activity
   forever, or until the item happens to also get a quantity change for an
   unrelated reason.

**The fix has two parts, both grounded in machinery that already exists
and already gets this right when given the chance:**

1. **`recommendationDiff`'s internal baseline must be merge-aware, not
   from-scratch.** Change `generate(context: context, existing: [],
   overrides: overrides)` (`:71`) to `generate(context: context, existing:
   existing, overrides: overrides)` — passing the *real* existing drafts,
   not `[]`. This is not new decision logic: `resolve(...)`'s existing-item
   branch (`:688-710`) already does exactly the right thing when given real
   existing drafts — for a non-user-authority item, it refreshes `reason`/
   `reasonCode`/`reasonArguments`/`sourceSignals`/`ownershipType`/
   `travelerID` while preserving `id`/`packedQuantity` (neither field is
   touched by that branch) and preserving an already-set
   `assignedTravelerID` (`:702-704`, only defaulted when nil — the explicit
   owner/carrier protection this amendment's non-touch list requires,
   already built and already correct); for a user-authority item, the
   branch returns the existing draft completely untouched (`:689-694`).
   `applyQuantities` then recomputes quantity/quantityReason for every
   non-user-authority item exactly as it already does today, on this now
   correctly-merged draft instead of a from-scratch one. **This reuses
   Phase 7's own priority-hierarchy machinery for the diff's baseline
   instead of bypassing it** — the diff was the one place in the app that
   *wasn't* asking the engine to merge, despite the engine already knowing
   how.
2. **The diff's own comparison, and what `applyDiff` does with an approved
   item, must cover the full causal unit, not quantity alone.**
   `PackingEngine.recommendationDiff`'s per-item comparison
   (`:81-87`/`:108-114`) widens from `fresh.quantity != item.quantity` to
   flag an item whenever *any* of its causal facts differ: `reasonCode`,
   `reasonArguments`, `sourceSignals`, `quantity`, `quantityReason`,
   `quantityReasonArguments`, `satisfiedCapabilities`, or the constraint/
   authority trace facts (Amendment 1). `QuantityChangeSuggestion` widens
   from `{item, suggestedQuantity}` to carry the full merged draft
   (`{existing: PackingItemDraft, fresh: PackingItemDraft}` — the
   `fresh` value is the already-correctly-merged draft from fix #1, safe to
   apply wholesale because it already preserves `id`/`packedQuantity`/
   explicit `assignedTravelerID`). `TripRepository.applyDiff` replaces its
   ad hoc `record.quantity = change.suggestedQuantity` line with
   `record.apply(change.fresh)` — **finally giving `PackingItemRecord
   .apply(_:)` a real caller**, and closing the loop this amendment is
   named for.

**A second real caller of the same widened comparison, found by tracing
the chain further, not assumed absent.**
`WeatherChangeReconciler.prune(_:existing:overrides:)`
(`WeatherChangeReconciler.swift:166-190`) re-validates a *pending*
weather-triggered `RecommendationDiff` against the trip's current state
before showing it to the user — and its own quantity-change filter
(`:186-189`, `current.quantity != change.suggestedQuantity`) is exactly as
narrow as the bug fix #2 closes. Left unwidened, `prune` would silently
drop a causal-only (quantity-unchanged) refresh proposed through the
weather-change path, even after fix #2 makes the direct-edit path correct
— the same bug, reintroduced through a second entry point. `prune`'s
filter widens to the same `causallyDiffers(from:)` predicate fix #2 adds,
which is why that predicate is placed on `PackingItemDraft` itself
(`Catalog.swift`) rather than as a private helper inside
`PackingEngine.recommendationDiff` — two real call sites need the
identical comparison, and duplicating it would let them silently drift
apart the next time either one is edited.

**`PackingItemRecord.apply(_:)`'s corrected refresh contract**, now that it
has a real caller supplying a properly merge-aware draft:

```text
REFRESH TOGETHER (one coherent unit, every approved regeneration):
  reason, reasonCode, reasonArgumentsRaw, sourceSignalsRaw
  quantity, quantityReason, quantityReasonArgumentsRaw   (Task 1)
  satisfiedCapabilitiesRaw                                (Task 1, Amendment 2)
  bagStyleConstraintFact (raw)                             (Task 1, Amendment 1)
  ownershipTypeRaw, travelerID

NEVER TOUCHED BY THIS METHOD:
  packedQuantity  — explicit user state; carried forward via the merge-
                    aware draft's own preserved packedQuantity, but this
                    method does not additionally clamp or reset it — that
                    stays applyDiff's existing responsibility (:248-250),
                    unchanged, applied before apply(_:) is called
  isUserAdded      — never true for a re-merged existing item; unrelated
  assignedTravelerID — already correctly preserved-or-defaulted upstream,
                    by resolve()'s :702-704 guard, before the draft ever
                    reaches apply(_:); apply(_:) copies whatever the
                    already-correct merged draft says
  bagID            — copied through unchanged; no bag-reassignment logic
                    exists in this phase
```

The item never reaches `apply(_:)` at all when `hasUserAuthority` is true
(`resolve`'s `:689-694` branch returns the existing draft unmodified, so
its `recommendationKey`-matched entry in `generated` is byte-identical to
`existing`, and the widened per-item comparison in fix #2 finds no causal
fact differs — it is never flagged for the diff in the first place). This
is the existing Phase 7 priority-hierarchy guarantee, reused rather than
reimplemented, and is exactly how "explicit user authority always wins" is
already enforced upstream of persistence — Phase 8 adds no new authority
check.

**Required regression test** (concrete task in the plan): a trip generates
with Hiking selected (an item, e.g. `footwear.hiking_shoes`, carries
`activity.hiking` sourced evidence); the user edits the trip to remove
Hiking and add a different activity that independently keeps the same
canonical item on the list under a different cause; regenerate; assert the
persisted record's `reasonCode`/`sourceSignals`/`quantityReasonArguments`/
`satisfiedCapabilities` reflect the *new* cause, not the stale one — while,
in the same regeneration, a packed item's `packedQuantity`, a manually-set
quantity, a "Not Needed" override, and an explicitly-assigned
`assignedTravelerID` on *other* items are asserted byte-identical
before/after.

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

No second decision engine. Every fact this phase surfaces is captured at
the exact moment `PackingEngine`/`CoverageResolver`/`ConstraintResolver`
already decides it, as a byproduct of that one real call — never
re-derived by a second, later call from presentation code, and never
approximated by inverting a differently-shaped record after the fact. This
is the house rule Amendments 1–3 exist to enforce, made explicit here
because the original architecture violated it in two places
(`ConstraintFacet`'s live re-call; `coveredCapabilities`'s suppression
inversion) and left a third mechanism (regeneration persistence) entirely
disconnected from the fields it was meant to refresh.

### 1. New `PackingItemDraft` fields (Catalog.swift)

```swift
struct PackingItemDraft: Hashable, Identifiable, Codable, Sendable {
    // ... existing fields unchanged ...
    /// Structured arguments behind quantityReason for the non-clothing
    /// quantity families (care, warm-layer rotation, party sharing) — the
    /// same role reasonArguments already plays for the inclusion reason.
    /// Empty for fixed singletons and for the clothing family, which
    /// already has quantityEvidence. Closed key vocabulary — see "quantity"
    /// above: {"quantity","days","rate","name","travelerCount","rainDays"}.
    var quantityReasonArguments: [String: String] = [:]
    /// itemCapabilities[canonicalItemID] ∩ activeNeeds, computed once
    /// inside CoverageResolver.resolve's own resolution loop (Amendment 2)
    /// — NOT an inversion of coverageSuppressions. Empty when this item's
    /// own capabilities don't intersect any currently-active need (most
    /// items, and every item outside the closed capability vocabulary).
    var satisfiedCapabilities: [String] = []
    /// Captured once, in PackingEngine.resolve, at the one optionalRuling
    /// call that decides whether this item survives a space-constrained
    /// bag (Amendment 1). Nil whenever that ruling never left its own
    /// no-op guard for this item — the common case.
    var bagStyleConstraintFact: BagStyleConstraintFact? = nil
}

struct BagStyleConstraintFact: Hashable, Codable, Sendable {
    var survivedByEssentialTagProtection: Bool
    var wouldTrimUnderKey: String?
}
```

(`coveredCapabilities` from the original design is renamed
`satisfiedCapabilities` here — the name change tracks the concept change:
this is no longer "what a suppression said," it is "what this item's own
capabilities satisfy," which is a different, more general fact.)

### 2. Populate all three in `PackingEngine`/`CoverageResolver`, at the exact call that decides them

- `quantityReasonArguments`: set alongside `quantityReason` at each of the
  three non-clothing call sites in `applyQuantities`
  (`PackingEngine.swift:901-921` shared, `:929-931` care, `:937-944` warm
  layer) — the `arguments` dictionaries each family already builds for
  `render(...)` are assigned to the field, keyed only from the closed
  vocabulary above, instead of only feeding the render call. Unchanged
  from the original design; restated here because it is the one field of
  the three that was already correctly scoped as "populate where the real
  computation happens."
- `satisfiedCapabilities` (**Amendment 2 — redesigned**): populated inside
  `CoverageResolver.resolve(items:needs:)` itself
  (`CoverageResolver.swift:222-290`), not by `PackingEngine` inverting
  `coverageSuppressions` afterward. `resolve`'s signature changes to
  return the fact it already computes:

  ```swift
  static func resolve(
      items: [PackingItemDraft],
      needs: Set<PackingCapability>
  ) -> (kept: [PackingItemDraft], suppressions: [CoverageSuppression]) {
      // ... unchanged iteration/priority logic ...
      for item in ordered {
          guard let canonical = item.canonicalItemID,
                let capabilities = itemCapabilities[canonical] else {
              kept.append(item)   // outside the vocabulary — stays empty
              continue
          }
          let needed = capabilities.intersection(needs)   // :245, already computed
          if item.isUserAdded || item.isUserModified {
              var copy = item
              copy.satisfiedCapabilities = needed.map(\.rawValue).sorted()
              kept.append(copy)
              for capability in needed where covered[capability] == nil { covered[capability] = canonical }
              continue
          }
          if needed.isEmpty {
              // unchanged: suppress-as-refuted or kept-with-empty-satisfied
          }
          if needed.allSatisfy({ covered[$0] != nil }) {
              // unchanged: suppressed, no trace to populate
          }
          var copy = item
          copy.satisfiedCapabilities = needed.map(\.rawValue).sorted()
          kept.append(copy)
          for capability in needed where covered[capability] == nil { covered[capability] = canonical }
      }
      return (kept, suppressions)
  }
  ```

  `PackingEngine.applyCoverage` (`:826-864`) needs no inversion pass at
  all — it already receives `kept` from `CoverageResolver.resolve` and
  feeds it forward; `satisfiedCapabilities` simply arrives already set.
  `CoverageSuppression.covered`/`refutedCapabilities` are unchanged —
  they remain the distinct "what this item made redundant" concept, read
  from the suppressed side, exactly as before.
- `bagStyleConstraintFact` (**Amendment 1 — new**): populated in
  `PackingEngine.resolve` (`:661-747`), immediately after the
  `ConstraintResolver.optionalRuling(...)` call at `:715-720`, only when
  that call's own no-op guard (`importance == .optional &&
  bag.appliesBagConstraint && bag.isSpaceConstrained`) was live for this
  item — set on the `PackingItemDraft` constructed at `:728-743`. Requires
  `OptionalRuling` (`ConstraintResolver.swift:35-39`) to surface the
  `essentialOptionalTags` branch outcome it already computes internally
  (`:58-61`) rather than only its final `keep`/`conflictKey` collapse, so
  `PackingEngine` reads the fact off the one call instead of
  re-implementing `optionalRuling`'s branching a second time to
  reconstruct it.

All three are additive, zero-diff for every existing field: no item is
added, removed, requantified, or re-covered differently than today.
`report_engine_goldens.py` must show the three new keys appear in every
fixture output with zero change to any existing key — verified per-task,
not assumed.

### 3. `RecommendationTrace` — a read layer over generation-time facts, never a second call

```swift
/// Assembled entirely from an item's own stored, structured facts —
/// PackingItemDraft/PackingItemRecord fields populated once, at
/// generation time, by PackingEngine/ConstraintResolver/CoverageResolver
/// (see Architecture §1–2 above). No function in this type calls
/// PackingEngine, ConstraintResolver, CoverageResolver, or
/// WeatherSignalExtractor — every fact here is a field read, not a
/// re-derivation. This is the boundary Amendment 1 made explicit after
/// the original ConstraintFacet design violated it.
enum RecommendationTrace {
    enum InclusionFamily: String, Hashable, Sendable {
        case baseEssential, tripType, activity, weatherPrecise, weatherSeasonal
        case party, dependency, personalPreference, destination, documents
        case flight, substitution, userAuthority
    }

    /// Pure derivation over the closed reasonCode/signal vocabulary
    /// already read above — no new stored field. Unchanged by Amendments
    /// 1–3; inclusion was never the part of this design that re-called
    /// anything.
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

    /// A field read, never a second call — see §"constraints", above.
    struct ConstraintFacet: Hashable, Sendable {
        var bagStyle: BagStyleConstraintFact?
        var sharing: ConstraintResolver.SharingResolution?

        static func read(from item: PackingItemDraft) -> ConstraintFacet {
            ConstraintFacet(
                bagStyle: item.bagStyleConstraintFact,
                sharing: item.ownershipType == .shared
                    ? .shared(quantity: item.quantity, reason: item.quantityReason)
                    : nil
            )
        }
    }

    /// itemCapabilities ∩ activeNeeds, read directly off the stored field
    /// — see §"needs/capabilities and coverage", above.
    struct CoverageFacet: Hashable, Sendable {
        var satisfiedCapabilities: [String]
    }

    struct Authority: Hashable, Sendable {
        var isUserAdded: Bool
        var isUserModified: Bool
        var isCustomItem: Bool
    }
}
```

Item Detail reads all five facets directly from `item`'s already-persisted
fields — `PackingItemRecord.draft` (Task 2). No facet function takes a
`catalog`, `rules`, `context`, or `party` parameter; none of them need one,
because nothing here re-derives anything the engine didn't already decide.
This is a stronger, simpler contract than the original design's
`constraintFacet(for:catalog:rules:context:party:)` signature, not a
weaker one — it has fewer inputs because it does less (reads, not
recomputes).

### What does NOT change

- `PackingEngine`'s item selection, quantity arithmetic, coverage
  resolution, weather signal extraction, and `ConstraintResolver`'s
  decision functions are read, never altered in their decision logic —
  only their already-computed byproducts gain a wider audience and (Task 1
  amendment) a wider capture point.
- `CoverageSuppression`, `ConstraintDecision`, `CapabilityCoverage` stay
  `Hashable, Sendable`, not `Codable` — nothing persists them directly;
  only flattened, derived facts (`satisfiedCapabilities: [String]`,
  `bagStyleConstraintFact`) do.
- `RecommendationSignal` gains no new case. The finer vocabulary the
  roadmap wants already lives in `reasonCode`.
- Item Detail / `PackingRow`'s visual structure, spacing, and card layout
  are unchanged — new content fills existing sections
  (`ItemDetailView.reasons`) or adds one clearly-scoped subsection, never a
  new screen or navigation flow.
- **Strengthened, not loosened, by Amendments 1–3:** Item Detail reads
  persisted trace only. It never calls `PackingEngine`,
  `CoverageResolver`, `ConstraintResolver`, or `WeatherSignalExtractor`
  directly, for any facet. This was implicit in the original design and
  is now the explicit, checked contract `RecommendationTrace`'s function
  signatures enforce structurally (no facet function accepts `catalog`/
  `rules`/`context`/`party`).

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

1. **Metric refined, per required review: "generic-only generated
   explanations = 0" is replaced by "generated recommendations lacking
   causal structured provenance = 0."** The original roadmap wording
   conflated two different questions — "does this row have generic
   *prose*" and "does this row have a real *cause* behind it at all" — and
   Phase 1's own P2-4 finding already proved the first question's answer
   (68 `.generic`-suffixed rows) is the fallback ladder working
   *correctly*, not a defect. The refined metric asks only the second
   question, and is checked, not assumed, against the real script:
   `classify_inclusion` (`audit_recommendation_traces.py:227-238`) already
   computes exactly this split — a row fails `missing_reason_code` or
   `missing_signal` (empty `reasonCode` or empty `signals`, `:230-233`)
   only when the engine produced an item with **no structured causal fact
   behind it at all** (the "fabricated 'Suggested for your trip' with
   nothing backing it" case the refined metric names); a row that clears
   both checks — including every `trip_type.generic` row, which carries a
   real `reasonCode`, a real `signals` list, and (confirmed by reading
   `PackingEngine.swift:403-410`) a real `arguments: ["tripType": ...]`
   driving its generic prose — has causal structured provenance regardless
   of how generic its rendered copy reads. **The refined metric is
   therefore exactly today's existing `missing_reason_code ∪
   missing_signal` defect count** (`INCLUSION_DEFECT_BUCKETS`,
   `:222`) — already 0, already computed, already the pass/fail gate
   `classify_inclusion` enforces. No new script logic; the change is
   entirely in what the exit-metrics table calls this number and what it
   folds together. Run fresh, not cited stale:
   `python3 scripts/audit_recommendation_traces.py --goldens
   ios/PackWiseTests/Goldens` reports, live, at this amendment's HEAD:
   `DEFECTS — missing reason code: 0`, `DEFECTS — missing causal signal:
   0`, `generic-only (weak, informational): 68` — confirming the refined
   metric (0) and the informational bucket (68) are independent numbers
   today, exactly as the refined framing requires. The 68-row
   `trip_type.generic` bucket is reported by the script under its own
   label — **"generic rendered fallback copy," not folded into the
   pass/fail metric, not forced toward zero, not dropped from the audit
   output** — and Task 9's exit report must show both numbers side by
   side, not one in place of the other. Driving that 68-row bucket toward
   zero would still require authoring new rule content (new reasonCodes,
   new `signalAdds`/`ActivityContract` entries, new reasons.json
   templates), which stays recommendation-content authorship, out of this
   phase's golden boundary, unaffected by the metric rename.
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
plus the two already-zero gates from before Phase 8 — Task 9 wires it into
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

**Re-classification review, required by Amendments 1–2: none of the
eighteen citations above change.** Every "existing evidence" cell cites a
test or fixture that proves the underlying **engine decision** (that
hiking shoes cover walking, that ski gloves cover cold hands, that a
sharing resolution produced a given quantity, that a Not Needed override
survives regeneration) — none of them cite, or depend on, *how the trace
assembler reads that decision back*. Amendments 1–2 change the second
thing (`ConstraintFacet` stops live-recalling; `satisfiedCapabilities`
stops inverting suppressions) without touching the first (the decisions
themselves, and the tests that prove them, are Non-goals — untouched).
Scenarios 5 and 6 (footwear/hand-protection coverage) were the two most
likely candidates for re-classification, since Amendment 2 is exactly
about coverage — checked directly: both cite `substitution.*` reasonCodes
and `CoverageTests` assertions about which item survives, never
`coveredCapabilities`/`satisfiedCapabilities` itself, so neither citation
was built on the old inversion design and neither needs updating. No
scenario's original plan (Task 4/Task 7, pre-amendment) exercised the old
`ConstraintFacet.sharing`/`bagStyleTrimEligible` live-recall either — the
function was defined but never called by a named scenario test — so
Amendment 1 also requires no citation changes, only a redesign of the
facet function itself (Architecture, above).

## Non-goals

- Redesigning `PackingEngine`, `CoverageResolver`, `ConstraintResolver`, or
  `ActivityContracts` decision logic. Every function this phase calls
  already exists and is called for its existing, already-computed answer.
- Forcing the 68-row generic-only rendered-copy bucket to zero (see Exit
  metrics, above) — that bucket is informational, distinct from the
  refined pass/fail metric, and reducing it requires new rule content,
  which is recommendation-content authorship, not trace productization.
- A new `RecommendationSignal` case, a new `PackingCapability`, a new
  `ActivityNeed`, or any `shared/rules/*.json` change beyond the one
  `party.shared` template fix.
- **No longer a non-goal (required amendment):** fixing
  `PackingItemRecord.apply(_:)`'s refresh contract, and the regeneration
  flow that was never actually calling it, is now in scope — see
  "Persistence," above. The original framing of this as an out-of-scope
  pre-existing gap was itself based on a mistaken premise about how
  regeneration works; Phase 8 fixes the real mechanism.
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

- Zero-diff gate for the three new `PackingItemDraft` fields
  (`quantityReasonArguments`, `satisfiedCapabilities`,
  `bagStyleConstraintFact`): `report_engine_goldens.py --baseline-ref
  eadc345` must show the three new keys appended to every fixture's items
  with **zero** change to any existing key, before any field's
  behavior-adjacent test is trusted.
- The `party.shared` fix is the one **approved, reviewed** golden diff:
  fixture 37's two shared-item rows change `quantityReason` text only;
  `quantity` values, every other fixture, and every non-`party.shared` row
  in fixture 37 must be byte-identical to `eadc345`.
- The Amendment 3 regeneration-refresh fix is verified by its own named
  regression test (Hiking removed / a different activity independently
  keeps an overlapping item), asserting the persisted record's causal
  fields reflect the new cause while packed state, manual quantity, Not
  Needed, and explicit carrier assignment on other items in the same
  regeneration are byte-identical before/after — not a golden-fixture
  diff, since it exercises the persistence layer
  (`TripRepository`/`PackingItemRecord`), not `PackingEngine` output
  directly.
- `quantityReasonArguments`'s closed key vocabulary is enforced by a test
  (or audit-script check) that fails on any unlisted key, the same
  discipline `ActivityNeed`/`PackingCapability`/`WeatherSignal` already
  established.
- `scripts/run_engine_audit.sh` clean after every task, `--strict` clean by
  the phase's closing task.
- Full `xcodebuild test`, `python3 scripts/validate_shared.py`, `npm
  --prefix api run preflight` at close.
- All 18 required scenarios map to a named task and a named test (cited
  existing test/fixture, or new trace test) in the implementation plan —
  re-checked against Amendments 1–2's redesign; no citation changed (see
  "Re-classification review," above).

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
