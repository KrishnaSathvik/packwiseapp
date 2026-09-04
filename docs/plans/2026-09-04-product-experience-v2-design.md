# PackWise Product Experience V2 — Design Specification

**Status:** Proposed for review. Documentation only; implementation has not started.

**Date:** 2026-09-04

**Decision owner:** Product

## 1. Decision and objective

Product Experience V2 replaces two false single-value assumptions and repairs the physical-device experience before M3B/M3C:

- A trip has one or more `TripType` values.
- A trip has zero or more physical `BagType` values. An empty set means “not sure yet” and applies no luggage constraint.
- Party mode, packing style, and laundry remain single-choice policies.
- Multiple signals compose into one packing plan through the existing recommendation pipeline. They never concatenate independent checklists.

The intended experience is:

> Tell PackWise what this trip actually looks like, and it composes one realistic packing plan for the whole trip.

The normalized flow is:

```text
destination + dates + party + trip types + activities + bags
+ packing style + laundry + preferences + weather + explicit decisions
                              ↓
                    normalized trip context
                              ↓
                    normalized packing needs
                              ↓
                 candidates + capability coverage
                              ↓
          quantities + luggage/style constraints + eligibility
                              ↓
                  sharing + authority reconciliation
                              ↓
                    one final packing list
```

Product Experience V2 is a prerequisite gate. Phase 9, M3B, M3C, memory product work, notifications, and lifecycle work remain frozen until the V2 exit gate is green.

## 2. Repository baseline

This design is based on the repository at `fe7aca0` plus an unrelated, pre-existing modification to `ios/PackWise.xcodeproj/project.pbxproj`, which this documentation pass does not touch.

The current implementation has these relevant seams:

- `TripContext`, `TripDraft`, `TripRecord`, `ContextFingerprint`, evaluation fixtures, and the Intelligence API contract carry singular `tripType` and `bagType` values.
- `shared/rules/trip-types.json` maps a trip type directly to canonical item IDs. `PackingEngine.collectRuleSuggestions` applies one rule.
- `CoverageResolver` already performs deterministic need/capability coverage for footwear and outerwear. It must remain the single coverage authority and grow only where V2 needs it.
- `ConstraintResolver`, `RecommendationDiff`, scoped `RecommendationOverrideRecord`, and repository reconciliation preserve explicit user authority. V2 must reuse them.
- Party persistence, owner/carrier semantics, age groups, child needs, and sharing policies already exist. Eligibility is currently spread across skip lists and age rules and needs one explicit decision layer.
- `PackingListView` displays traveler-specific records directly in All scope. Its filter model is reusable; its All-scope presentation is not.
- `TripSetupView` is one 1,229-line feature with eight navigation pushes and a top-right Next action. It should be decomposed around a shared shell without changing the two-tab app structure.
- Destination rendering supports bundled imagery, Look Around, then a graphical fallback. It does not currently produce the required MapKit snapshot fallback.
- `TripDetailView` intentionally truncates category summaries with `prefix(5)`.
- Add Item already has a pushed category list, but Item Detail still uses a `Picker`; both should use one dedicated selector component.
- WeatherKit requests daily weather for the supplied range, but the live path does not retain a diagnostic envelope containing requested coordinates/dates/timezone, provider coverage, normalization, cache, and error state. Debug injection uses fixed fixture dates.
- SwiftData is currently at `PackWiseSchemaV3`. `PackWisePersistence.container` deletes the store and retries after any open error. That behavior is incompatible with the V2 no-data-loss requirement and must be removed before the V4 migration ships.

## 3. Alternatives considered

### A. Keep primary values and add secondary tags

This minimizes schema work but creates a hidden priority system. Coverage, quantities, traces, and API serialization could still collapse to the primary value. It contradicts the product decision and is rejected.

### B. Generate and merge one checklist per selected context

This is easy to visualize but produces duplicate essentials, inflated quantities, competing reasons, and a second deduplication engine. It is rejected.

### C. Normalize sets into typed needs and reuse the existing pipeline — selected

Each selected trip type contributes typed needs and provenance. Activities, weather, traveler needs, and preferences contribute to the same normalized need set. Candidate generation happens once, capability coverage happens once, quantities happen once, and constraints/sharing/authority remain centralized. This is the only approach that fits the product promise and preserves the Phase 4/7/8 architecture.

## 4. Selection semantics

| Input | Domain representation | UI rule | Empty state |
| --- | --- | --- | --- |
| Destination | `Destination` | single | blocks review/build |
| Dates | closed date range | single range | defaults to valid range |
| Party | `TripParty` / `TravelMode` | single mode | defaults to solo |
| Trip types | `Set<TripType>` | multi-select | at least one required |
| Activities | stable unique `[String]` | multi-select | allowed |
| Bags | `Set<BagType>` | multi-select | “Not sure yet”; no constraint |
| Packing style | `PackingStyle` | single | preference or Balanced |
| Laundry | `LaundryAccess` | single | No laundry |
| Preferences | `Set<ContextChip>` | multi-select | allowed |
| Child needs | `Set<ChildNeed>` per child | multi-select | allowed |

`TripType.other` remains a known, inert type unless a deterministic contract is later approved. Arbitrary custom trip-type text does not create needs. Custom activities remain stored and displayed but do not affect recommendations unless normalized to a known activity contract.

`BagType` contains only physical bags in the V2 context: `.personalItem`, `.carryOn`, `.checked`, and `.backpack`. “Not sure yet” is represented by an empty set, not a bag. `roadTripLuggage` is removed from selectable/domain V2 values; Road Trip remains a trip type.

## 5. Stable set semantics and serialization

Domain code may use `Set`, but every boundary uses a stable order:

```swift
extension TripType {
    static let stableOrder: [TripType] = [
        .vacation, .cityBreak, .beach, .business, .outdoor, .roadTrip,
        .weddingEvent, .skiSnow, .festival, .visitingFamily, .other
    ]
}

extension BagType {
    static let stableOrder: [BagType] = [.personalItem, .carryOn, .checked, .backpack]
}
```

Persistence stores sorted raw values in versioned JSON arrays. API DTOs and fixtures use arrays in the same stable order. Signatures, cache keys, traces, golden files, and diffs must never depend on `Set` iteration order.

Unknown persisted values are dropped with a normalization diagnostic. If all trip types are unknown, the safe normalized value is `[.other]`; unknown bags normalize to no bag constraint. Request validation remains closed-vocabulary and rejects unknown values at the API boundary.

## 6. Schema and migration design

### 6.1 V4 stored model

`PackWiseSchemaV4` adds CloudKit-compatible, defaulted scalar storage:

```text
TripRecord.tripTypesRaw     JSON string array, default "[]"
PackingItemRecord.provenanceRaw  JSON string array, default "[]"
PackingPreferenceRecord.preferredBagTypesRaw  JSON string array, default "[]"
PackingMemoryEventRecord.tripTypesRaw  JSON string array, default "[]"
PackingMemoryEventRecord.bagTypesRaw   JSON string array, default "[]"
```

Legacy `tripTypeRaw` and `bagTypeRaw` remain in V4 as migration source/compatibility fields. New code never treats either as a primary value. They may be retired only in a later, separately tested schema version.

The domain accessors are:

```swift
var tripTypes: Set<TripType>
var bagTypes: Set<BagType>  // derived from the existing BagRecord relationship
```

`TripRecord.bags` is the persisted bag source of truth; adding a parallel `bagTypesRaw` field would create drift. V2 maintains at most one setup-created `BagRecord` per selected physical type, preserves the ID/owner of a matching existing record, and derives a sorted set at context boundaries. Future bag assignment may add concrete instances, but `TripContext` still consumes the de-duplicated type set. Every trip-type write sets the new stable array. During the compatibility window it may also write the first stable trip type to `tripTypeRaw`, solely so older diagnostics can read the record. No engine or UI decision reads legacy `tripTypeRaw` or `bagTypeRaw`.

`PackingItemRecord.provenanceRaw` persists the stable structured trip-type/activity/weather facts needed by multi-context trace. Existing `sourceSignalsRaw`, reason code/arguments, quantities, and authority fields remain intact.

### 6.2 Migration rules

V3 → V4 is an explicit migration with fixture-backed store tests:

| V3 value | V4 value |
| --- | --- |
| `tripTypeRaw = beach` | `tripTypesRaw = ["beach"]` |
| unknown trip type | `tripTypesRaw = ["other"]` plus diagnostic |
| `bagTypeRaw = carryOn` | preserve or create one Carry-on `BagRecord` |
| `bagTypeRaw = checked` | preserve or create one Checked bag `BagRecord` |
| `bagTypeRaw = notSure` | no setup-created bag records |
| `bagTypeRaw = roadTripLuggage` | no setup-created bag records |
| unknown bag type | no setup-created bag records plus diagnostic |

Migrating `roadTripLuggage` does **not** add `.roadTrip` to `tripTypes`; doing so would infer transportation intent from an obsolete bag label.

The same one-to-one conversion applies to immutable `ContextFingerprint` memory events using stable arrays. If an existing matching `BagRecord` exists, migration keeps its identity and owner; it does not discard assignment metadata. Existing item, override, owner, carrier, packed, category, and quantity fields are untouched. Existing packing items begin with empty structured provenance and continue to render their Phase 8 source-signal/reason fallback until the next accepted regeneration supplies facts.

`TravelerPreferences.preferredBagTypes` and `PackingPreferenceRecord.preferredBagTypesRaw` replace the singular default-bag preference. Legacy physical defaults migrate to singleton sets; `notSure`, `roadTripLuggage`, and unknown values migrate to empty. Me edits the same four-bag multi-select used by setup, and fresh setup drafts copy that set without making it mandatory.

### 6.3 Failure behavior

V2 removes `resetUnknownStore`. A persistent-store open or migration error is surfaced as a controlled startup failure with an actionable diagnostic in Debug and a recoverable customer-safe failure surface in Release. PackWise never deletes `packwise.store`, its WAL, or SHM merely because migration failed.

Migration verification must create an actual V3 file-backed store, populate solo and family trips plus user-authority state, open it through the V4 container, and assert values and relationships after relaunch.

## 7. Normalized context and luggage contract

`TripContext` and the repository-facing snapshot carry sets:

```swift
var tripTypes: Set<TripType>
var bagTypes: Set<BagType>
var luggage: LuggageContext
```

`LuggageContext` is derived, never separately persisted:

```swift
struct LuggageContext: Hashable, Sendable {
    enum Capacity: String, Codable, Sendable {
        case unspecified, veryConstrained, compact, carryOnConstrained, moderate, checkedAvailable
    }

    let bagTypes: Set<BagType>
    let capacity: Capacity
    let appliesCapacityConstraint: Bool
}
```

Precedence is deterministic:

| Selected bags | Capacity |
| --- | --- |
| none | `unspecified` |
| personal item only | `veryConstrained` |
| backpack, with or without personal item | `compact` |
| carry-on, with or without personal item | `carryOnConstrained` |
| carry-on + backpack, no checked bag | `moderate` |
| any set containing checked bag | `checkedAvailable` |

`checkedAvailable` disables carry-on-only trimming even if a carry-on or personal item is also selected. Packing style remains independent and may still reduce optional items or quantities. Transportation never masquerades as bag capacity. No bin-packing or per-bag allocation is introduced.

## 8. Typed need composition

### 8.1 Contracts

The new contract layer is:

```text
TripType → TripTypeContract → PackingNeedContribution
Activity → existing known rule adapter → PackingNeedContribution/candidates
Weather → WeatherSignal → PackingNeedContribution/candidates
Traveler/child need → eligibility-scoped contribution
Preference → preference-scoped contribution
```

Each contribution includes a closed typed need, provenance, and optional traveler scope:

```swift
struct PackingNeedContribution: Hashable, Sendable {
    let need: PackingNeed
    let provenance: RecommendationProvenance
    let travelerID: UUID?
}
```

The initial `PackingNeed` vocabulary is deliberately product-sized: everyday mobility, urban walking, leisure downtime, beach/swim, formal/work, outdoor day use, road comfort, snow/cold activity, festival attendance, host gift, rain shell, wind shell, light warmth, heavy warmth, device work, and child-explicit needs. It is closed and validated across Swift/shared rules.

Trip-type contracts live in a generated/validated shared rule file and contain need IDs, not canonical item IDs. A central need-candidate mapping may identify canonical candidates, but no trip type directly owns an item checklist. Existing catalog capability metadata and `CoverageResolver` decide overlaps. Candidate IDs still pass through canonical validation.

### 8.2 Composition

All selected known types contribute. The engine unions identical needs and retains all distinct provenance. Candidate identity remains the existing recommendation key (`ownership + traveler + canonical ID`), so a beach and city need cannot produce duplicate sunscreen or walking-shoe rows.

The order is fixed:

1. Normalize context and validate closed vocabularies.
2. Collect trip-wide and traveler-scoped needs with provenance.
3. Produce canonical candidates once.
4. Apply traveler eligibility.
5. Apply capability coverage and substitution once.
6. Compute quantities once.
7. Apply luggage and packing-style constraints once.
8. Resolve sharing/ownership/carrier.
9. Reconcile explicit user state and overrides.
10. Emit structured trace and stable output order.

The implementation must not create a second deduper, quantity engine, constraint engine, or trace architecture.

### 8.3 Combination expectations

- Vacation + Beach + City Break contributes leisure, swim/beach, and urban walking needs. Everyday essentials and clothing quantities are computed once.
- Business + City Break contributes work/formal and urban walking needs. A versatile walking shoe may cover city use; dress shoes remain only when formal capability is needed.
- Road Trip + Outdoor contributes road comfort and outdoor day-use needs. Road context does not alter bag capacity.
- Outdoor + Ski/Snow contributes outdoor and cold/snow needs. Coverage keeps necessary layers and suppresses redundant shells/footwear only when the needed capability remains covered.
- Vacation + Wedding/Event contributes leisure and formal/event needs. It does not create two clothing baselines.
- Festival + City Break and Visiting Family + Vacation preserve both provenance sources while deduplicating shared capabilities.

## 9. Traveler eligibility and sharing

### 9.1 Eligibility layer

Eligibility becomes one explicit domain decision before quantity and sharing:

```swift
TravelerEligibilityResolver.evaluate(
    candidate: Candidate,
    traveler: Traveler,
    explicitNeeds: Set<ChildNeed>,
    catalog: PackingCatalog,
    rules: EligibilityRules
) -> EligibilityDecision
```

The decision is `.eligible(reason)`, `.requiresExplicitSignal(signal)`, or `.ineligible(reason)`. Ineligible candidates are recorded in the audit ledger. Missing metadata resolves conservatively: a personal adult-only/device/medication candidate does not attach to a young child.

Age may justify ordinary clothing, sleepwear, socks, and suitable shoes. It never alone justifies phone, charger, headphones, deodorant, medication, or child equipment. Child equipment and medication require the corresponding explicit child need. No note or preference for one traveler is attributed to another.

### 9.2 Catalog audit

The V2 audit classifies every canonical item relevant to parties along two independent axes:

- eligibility: universal, adult/teen, age-specific, explicit-signal-only, device-signal-only;
- sharing: `personalOnly`, `singlePerParty`, `scaleByParty`, `scaleByDevices`, or `scaleByDurationAndParty`.

The audit must explicitly cover toothpaste, shampoo, body wash, pain reliever, laundry bag, packing cubes, toiletry bag, chargers, adapters, sunscreen, umbrellas, medicines, books, and electronics. Defaults are conservative: absent an approved sharing rule, personal clothing/footwear stay personal; ambiguous consumables do not multiply blindly; devices and their chargers require device ownership/context.

Underlying personal records remain one per traveler where appropriate. Sharing changes neither owner nor carrier semantics.

## 10. Recommendation trace

`RecommendationSignal` remains the broad customer-facing grouping, but each draft also carries stable structured provenance facts for the selected trip type/activity/weather signal that contributed. Multiple facts may coexist:

```text
Walking shoes
Based on
City Break · Sightseeing · Walking
```

```text
Rain jacket
Why it's on your list
Rain is expected and you'll be spending time outdoors.
Based on
Weather · Outdoor
```

Reason selection is deterministic and may synthesize one sentence from compatible facts. It never chooses a fake primary type. Phase 8’s structured trace sections and user-authority behavior remain unchanged.

## 11. Setup experience

The setup becomes nine logical steps:

1. Destination
2. Dates
3. Travelers
4. Trip types
5. Activities
6. Bags
7. Packing style + laundry
8. About you / trip preferences
9. Review

Every step uses one shared `TripSetupShell`: native Back/cancel, a compact progress indicator, 28pt bold title, gray helper, scrollable content, and a safe-area sticky bottom primary action. `Next` is not a top-right action. The shell uses `PackWiseColor`, `PackWiseFont`, `PackWiseSpacing`, existing primitives, native focus/keyboard behavior, Dynamic Type, VoiceOver, and 44pt targets.

### Destination

The empty state has a title, concise helper, search field, and recent destinations or useful guidance. Results are one lightweight row each (`Khammam` / `Telangana, India`). Selecting a result replaces the results with one compact confirmation rather than duplicating it in a second hero card.

`DestinationVisualService` policy becomes trusted bundled/Look Around image where appropriate, then `MKMapSnapshotter`, then a restrained graphical state. Search confirmation deliberately favors a map. Text overlays reserve space and use a contrast scrim; decorative symbols never overlap destination/date text.

### Travelers

Party mode remains single-select. Family input labels the count as “Other adults,” because the current user is implicit. Review produces unambiguous totals. Empty optional names are formatted by stable party order as You, Adult 1, Adult 2, Child 1, Child 2, Shared. Stable labels are presentation-derived from stable traveler IDs/order and do not overwrite optional names.

### Trip types and activities

Both use the same multi-selection primitive: clear checkmark, accent selected surface, icon, text, and color-independent accessibility state. Trip types require at least one selection. Suggested activities are the stable union of suggestions from all selected trip types; explicit activity selections are never removed when trip types change. Custom activity text stays inert unless it normalizes to a known contract.

### Bags

Copy is “What bags are you bringing?” / “Choose all that apply.” The four physical bags are independently selectable. The screen permits no selection and describes it as not sure yet/no bag constraint. It never asks “How are you traveling?”

### Style, laundry, preferences, review

Style and laundry share one screen but remain separate single-select groups. Preferences remain multi-select and are grouped by health, devices/work, clothing/comfort, and trip context; only relevant known controls appear. Review lists trip types, travelers, activities, bags, packing style, laundry, and preferences as separate wrapping summaries. Empty bags render “Not sure yet.”

## 12. Onboarding, home, detail, and list

### Onboarding

All three pages share a logo/wordmark position, typography, margins, content frame, CTA, and pagination. Copy is truthful to the shipped product:

1. Pack for the trip you’re actually taking. Destination, dates, weather and plans shape your list.
2. One trip can be many things. Beach, city, business, activities and luggage work together.
3. Your choices stay yours. Change quantities, skip items and add your own without losing your decisions.

No customer-facing AI language and no claim that Packing Memory is already personalizing future trips.

### Trips Home and Trip Detail

Trips Home keeps Current/Upcoming semantics and an obvious add-trip control. Destination imagery follows the shared image/map/graphical policy with safe text regions.

Trip Detail keeps hero, progress, weather, Packing Impact, and category overview. It renders every non-empty category in `PackingCategory.displayOrder`; `prefix(5)` and “more categories” are removed. The page scrolls and See All remains.

### Packing List

Solo hides people scope. Party trips show two compact, labelled scopes:

```text
People: All | You | Adult 1 | Adult 2 | Child 1 | Shared
Status: To pack 81 | Packed 0 | Important
```

The All scope aggregates personal records by canonical item ID and category. Each grouped row reports completion across travelers and a compact quantity breakdown. Tapping opens an expansion/detail surface containing the real per-traveler records. Shared items remain distinct shared rows. Traveler and Shared filters render real records, not aggregates. Custom personal items aggregate only when they share a canonical ID; unrelated custom strings are never guessed equivalent.

Search applies before aggregation to canonical/display names and traveler labels. Status applies to underlying records; a grouped row appears when at least one child record matches and its progress reflects the matching scope. The floating add button respects the bottom safe area and list content receives sufficient inset.

## 13. Add/Edit Item and naming audit

One `CategorySelectionView` is used by Add Item and Item Detail/Edit Item. It is a dedicated sheet or navigation page with category icons, titles, checkmark, and automatic return on selection. No `.menu` or compact `Picker` presentation is used. Add Item uses an appropriately sized native sheet with detents based on content.

The naming audit compares every trip-type/activity trigger, need, canonical display name, and rendered reason. `nightlife → Nice dinner outfit` is not accepted unless the need and customer language genuinely align; either Nice Dinner owns that item or Nightlife uses a general evening/going-out item approved in the canonical catalog. Changes remain catalog/rule changes and pass shared validation and golden semantic review.

## 14. WeatherKit repair and diagnostics

The physical-device failure is treated as an unknown until evidence identifies it. Debug diagnostics capture, with no sensitive user text:

```text
destination coordinates and destination timezone
requested start/end and normalized start/end-exclusive
device timezone and calendar
provider-returned daily dates/coverage
normalization included/excluded dates and quality
cache hit, age, coverage, and selected result
typed error domain/code
final TripWeatherState and WeatherQuality
```

Dates are normalized in the destination timezone before the WeatherKit query and again when matching returned days. Current-date, partial-window, and future-seasonal tests pin the boundary behavior. The UI never diagnoses from absence alone.

Debug injection rebases a named fixture’s local day components onto the target trip’s date range, preserving the fixture’s weather pattern and passing through the real normalization/reconciliation path. It remains compiled only in Debug.

Apple Weather attribution remains visible on every Apple-weather surface.

## 15. User authority and regeneration

V2 context changes generate a `RecommendationDiff` against current records. They do not replace the list wholesale. The following survive creation/edit, weather refresh, relaunch, and regeneration:

- manual quantity and packed quantity/state;
- Not Needed overrides, scoped by canonical ID + owner/shared identity;
- user-added/custom items;
- explicit owner and carrier;
- category edits;
- explicit trip-type, activity, bag, style, laundry, preference, and child-need choices.

A selected context may propose a previously unseen item, but an existing matching Not Needed override suppresses it. Removing a context may propose removal; removal remains off by default in the review diff.

## 16. Verification and evidence

Each implementation stage follows test-first → implementation → focused verification → semantic diff → commit. The minimum automated matrix includes every combination and authority case in the product brief, plus stable serialization permutations and V3→V4 file-store migration/relaunch.

Shared changes run `python3 scripts/validate_shared.py`. iOS work runs focused Swift Testing filters, then the full simulator suite and build. Golden changes require a human-readable semantic diff, not blind regeneration. API contract changes regenerate artifacts and run API tests/preflight. Debug-only symbols are checked absent from Release.

The final device pass records screenshots and raw observations for onboarding, setup, solo/couple/family/group, grouped and filtered lists, Add/Edit/Item Detail, authority survival, relaunch/edit, live WeatherKit, App Attest, and offline/local use. App Attest development verification must remain green.

## 17. Exit gate

Product Experience V2 closes only when every exit criterion from the approved brief is evidenced. In particular, singular compatibility fields must not influence product behavior, checked-bag presence must defeat carry-on-only trimming, toddler/device ambiguity must drop the signal, All-scope aggregation must remain presentation-only, current-trip WeatherKit must be proven on a physical iPhone, and no migration path may delete existing user data.

Only then may Phase 9/M3B be reconsidered.

## 18. Explicit non-goals

V2 does not add accounts, cross-device collaboration, GPT-driven final decisions, trip segments, route planning, a general solver, per-bag item allocation, airline limits, packing-memory lifecycle UI, notifications, post-trip intelligence, M3B, or M3C.
