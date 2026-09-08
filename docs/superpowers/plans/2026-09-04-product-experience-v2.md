# PackWise Product Experience V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make trip types and bags true multi-value inputs, compose their needs through the existing deterministic engine, harden party eligibility/sharing, redesign the affected product surfaces, and close the simulator and physical-device V2 gate without weakening user authority or App Attest.

**Architecture:** Stable set-valued context is persisted in SwiftData V4 and normalized into typed trip-type needs plus a derived `LuggageContext`. The existing candidate, coverage, quantity, constraint, reconciliation, and structured-trace layers remain authoritative; V2 inserts explicit traveler eligibility and adds presentation-only family aggregation. UX work composes from the existing design system and one shared setup shell.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Testing, iOS 18+, MapKit, WeatherKit, JSON shared rules/schemas, Python shared validators/generators, TypeScript API contract tests, Xcode/xcodebuild.

**Design specification:** `docs/plans/2026-09-04-product-experience-v2-design.md`

## Mandatory amended execution order

Task headings retain their original identifiers so review comments remain stable, but implementation executes in this order:

```text
Task 1  Stable collection contracts
Task 2  Safe SwiftData V4 groundwork
Task 14 WeatherKit diagnostics → current-device reproduction → evidence-only fix → device recheck
Task 15 Cross-boundary array contract/fixture migration with explicit compatibility bridge
Task 3  Product-approved TripTypeContract table and typed contracts
Task 4  Multi-trip-type engine composition
Task 5  Multi-bag luggage semantics
Task 6  Traveler eligibility, including documents
Task 7  Catalog-wide sharing audit
Checkpoint V  One contact sheet for all major V2 reference states
Tasks 8–13 Production UX wiring and recommendation naming
Tasks 16–18 Authority, full automation, and physical-device exit gate
```

The order above is authoritative. In particular, Task 14 is not deferred until after UX work, and Tasks 3–5 do not start before Task 15 leaves all request/fixture boundaries green.

### Green-commit rule

Every task ends with a coherent repository. Before each commit run the focused iOS tests for that task and `python3 scripts/validate_shared.py`. If the task touches `shared/contracts`, request/fixture schemas, generated API artifacts, Swift DTOs, or TypeScript validation/model input, also run `npm --prefix api test` and `npm --prefix api run preflight`. A temporary adapter is allowed only when it is explicit, rejects unsupported multi-value behavior rather than choosing a primary value, has a removal test/task, and keeps production behavior unchanged until the consuming engine stage lands.

## Global Constraints

- Never label or market PackWise as AI in customer-facing UI or copy.
- Local-first list generation must work offline; the iPhone never calls OpenAI.
- GPT never writes SwiftData or final packing decisions.
- Explicit user decisions always win; Not Needed items do not silently return.
- Keep exactly two tabs: Trips and Me.
- Use `PackWiseColor`, `PackWiseFont`, `PackWiseSpacing`, and design-system primitives; no raw visual constants in feature screens.
- Keep dark mode intentionally disabled until a complete dark reference exists.
- Keep party mode, packing style, and laundry single-select.
- Treat unknown/ambiguous traveler attribution as no signal.
- Do not start M3B, M3C, memory lifecycle, notifications, or later roadmap work.
- Preserve the existing App Attest development path and its evidence.
- Do not delete existing user data to recover from a persistence or migration error.
- Do not regenerate golden files without reviewing and recording the semantic diff.
- The pre-existing modification to `ios/PackWise.xcodeproj/project.pbxproj` belongs to the user; inspect and preserve it before any project-file generation or source registration.

## Planned file map

### New focused files

- `ios/PackWise/Domain/TripContextCollections.swift` — stable enum-set ordering/encoding and normalized set diagnostics.
- `ios/PackWise/Domain/Packing/TripTypeContracts.swift` — typed `PackingNeed`, provenance, and trip-type contract resolution.
- `ios/PackWise/Domain/Packing/LuggageContext.swift` — bag-set normalization and capacity precedence.
- `ios/PackWise/Domain/Packing/TravelerEligibilityResolver.swift` — one age/device/explicit-need eligibility decision point.
- `ios/PackWise/Features/TripSetup/TripSetupShell.swift` — common setup chrome and sticky action.
- `ios/PackWise/Features/TripSetup/TripSetupSelectionGrid.swift` — shared trip-type/activity/bag multi-select surface.
- `ios/PackWise/Features/TripDetail/PackingListAggregation.swift` — pure All-scope presentation grouping.
- `ios/PackWise/Features/TripDetail/CategorySelectionView.swift` — shared Add/Edit category selector.
- `ios/PackWise/Data/Weather/WeatherRequestDiagnostics.swift` — Debug-safe live weather evidence envelope.
- `ios/PackWiseTests/TripContextCollectionsTests.swift`
- `ios/PackWiseTests/PersistenceMigrationV4Tests.swift`
- `ios/PackWiseTests/TripTypeCompositionTests.swift`
- `ios/PackWiseTests/LuggageContextTests.swift`
- `ios/PackWiseTests/TravelerEligibilityTests.swift`
- `ios/PackWiseTests/PackingListAggregationTests.swift`
- `ios/PackWiseTests/ProductV2AuthorityTests.swift`
- `ios/PackWiseTests/WeatherKitRequestTests.swift`

### Existing files with deliberate changes

- Domain/persistence: `ios/PackWise/Domain/TripTypes.swift`, `ios/PackWise/Domain/Party.swift`, `ios/PackWise/Domain/Packing/{Catalog,PackingEngine,CoverageResolver,ConstraintResolver,ClothingQuantity,PackingMemory}.swift`, `ios/PackWise/Data/Persistence/Models.swift`, `ios/PackWise/Data/Repositories/Repositories.swift`.
- Shared/API: `shared/rules/{trip-types,activity-rules,party,reasons}.json`, `shared/schemas/trip-eval.schema.json`, `shared/contracts/intelligence-api.yaml`, `shared/fixtures/**`, `ios/PackWise/Data/{SharedResources.swift,Intelligence/IntelligenceDTO.swift}`, `api/src/**`, generated API artifacts via existing generators.
- Setup/design: `ios/PackWise/Features/TripSetup/TripSetupView.swift`, `ios/PackWise/DesignSystem/{PackWisePrimitives,DestinationVisualService,DestinationVisualView}.swift`.
- Product surfaces: `ios/PackWise/Features/{Onboarding/OnboardingView,Trips/TripsHomeView,TripDetail/TripDetailView,TripDetail/PackingListView}.swift`.
- Weather: `ios/PackWise/Data/WeatherKit/{WeatherKitClient,WeatherKitWeatherService}.swift`, `ios/PackWise/Domain/Weather/WeatherNormalization.swift`, `ios/PackWise/Data/Weather/TripWeatherRefresh.swift`, `ios/PackWise/Features/Developer/DebugWeatherInjection.swift`.
- Tests/goldens: current `ios/PackWiseTests/*.swift`, `shared/fixtures/golden/golden-fixtures.json`, and reviewed `ios/PackWiseTests/Goldens/*.json`.
- Canonical docs/rules: the Product V2 source-of-truth updates named in Task 15.

---

## Stage A — Domain and schema migration

### Task 1: Stable collection contracts

**Files:**

- Create: `ios/PackWise/Domain/TripContextCollections.swift`
- Create: `ios/PackWiseTests/TripContextCollectionsTests.swift`
- Modify: `ios/PackWise/Domain/TripTypes.swift`
- Modify: `ios/PackWise.xcodeproj/project.pbxproj` only through a reviewed source-registration diff

**Interfaces:**

- Produces: `TripType.stableOrder`, `BagType.stableOrder`, `StableRawValueSetCodec`, `NormalizedSet<Value>`, V2-only physical `BagType` cases.
- Consumed by: persistence, DTOs, fixtures, signatures, review copy, and all later tasks.

- [ ] **Step 1: Write failing stable-order and compatibility tests.** Cover every permutation encoding identically; unknown trip types falling back to `.other`; unknown bags dropping to empty; `.notSure` and `.roadTripLuggage` legacy bag values normalizing to empty; empty trip types being invalid for a new draft.

```swift
@Test func tripTypeEncodingIsStableAcrossInsertionOrder() throws {
    let a: Set<TripType> = [.beach, .vacation, .cityBreak]
    let b: Set<TripType> = [.cityBreak, .beach, .vacation]
    #expect(try StableRawValueSetCodec.encode(a, order: TripType.stableOrder)
        == StableRawValueSetCodec.encode(b, order: TripType.stableOrder))
    #expect(try StableRawValueSetCodec.encode(a, order: TripType.stableOrder)
        == #"["vacation","cityBreak","beach"]"#)
}
```

- [ ] **Step 2: Run the focused tests and confirm they fail because the collection contracts do not exist.**

```bash
xcodebuild -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/TripContextCollectionsTests test
```

- [ ] **Step 3: Implement stable encoding/normalization and remove selectable V2 semantics from `.notSure`/`.roadTripLuggage`.** Keep a legacy raw-value decoder isolated from the V2 `BagType.allCases`; do not infer Road Trip.

- [ ] **Step 4: Re-run focused tests, inspect the source-registration diff, and commit.**

```bash
git add ios/PackWise/Domain/TripContextCollections.swift ios/PackWise/Domain/TripTypes.swift \
  ios/PackWiseTests/TripContextCollectionsTests.swift ios/PackWise.xcodeproj/project.pbxproj
git commit -m "feat: add stable multi-value trip context contracts"
```

### Task 2: SwiftData V4 migration without destructive recovery

**Files:**

- Modify: `ios/PackWise/Data/Persistence/Models.swift`
- Modify: `ios/PackWise/Domain/Packing/PackingMemory.swift`
- Modify: `ios/PackWise/Data/Repositories/Repositories.swift`
- Create: `ios/PackWiseTests/PersistenceMigrationV4Tests.swift`

**Interfaces:**

- Consumes: stable codecs from Task 1.
- Produces: `PackWiseSchemaV4`, `TripRecord.tripTypes`, `TripRecord.bagTypes` derived from `BagRecord`, `TravelerPreferences.preferredBagTypes`, persisted `PackingItemRecord.recommendationTrace`, set-valued repository create/apply methods, V4 `ContextFingerprint` values, non-destructive container failure behavior.

- [ ] **Step 1: Write a file-backed V3→V4 migration test.** Seed a V3 store with singular Beach/Carry-on plus travelers, personal/shared items, manual quantity, packed quantity, Not Needed override, custom item, owner/carrier, and category edit. Reopen through V4 and assert `[.beach]`, `[.carryOn]`, all IDs/relationships/state unchanged, and a second relaunch succeeds.

- [ ] **Step 2: Add migration rows for `notSure`, `roadTripLuggage`, and unknown values in both trips and preferences.** Assert both legacy bag values become an empty set and neither adds `.roadTrip`; physical preferred bags become singleton `preferredBagTypes`; unknown trip type becomes `.other` with a recorded normalization diagnostic.

- [ ] **Step 3: Run the focused migration suite and verify it fails on missing V4 fields.**

```bash
xcodebuild -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/PersistenceMigrationV4Tests test
```

- [ ] **Step 4: Add defaulted trip-type, preferred-bag-set, memory-fingerprint arrays and optional `recommendationTraceRaw`, then implement the explicit V4 migration/backfill.** Preserve legacy scalar columns as migration inputs only. Migrate the legacy trip bag scalar into the existing to-many `BagRecord` relationship, preserving a matching record’s ID/owner; derive `TripRecord.bagTypes` from that relationship instead of adding a second raw field. Update repository and preference persistence to accept sets. Until Tasks 3 and 5 land, existing engine adapters must require a singleton set and fail safely for a multi-value set; they must never select an arbitrary primary value.

- [ ] **Step 5: Remove `resetUnknownStore` and make container-open failure non-destructive.** Add a test that supplies an invalid/incompatible store, asserts the error is surfaced, and verifies the store/WAL/SHM bytes still exist unchanged.

- [ ] **Step 6: Run migration tests twice, inspect a dumped migrated store, and commit.**

```bash
git add ios/PackWise/Data/Persistence/Models.swift ios/PackWise/Data/Repositories/Repositories.swift \
  ios/PackWise/Domain/Packing/PackingMemory.swift ios/PackWiseTests/PersistenceMigrationV4Tests.swift
git commit -m "feat: migrate trips to multi-value context safely"
```

## Stage B — Multi-trip-type engine

### Task 3: Typed trip-type need contracts

**Files:**

- Create: `ios/PackWise/Domain/Packing/TripTypeContracts.swift`
- Modify: `ios/PackWise/Domain/Packing/Catalog.swift`
- Modify: `ios/PackWise/Data/SharedResources.swift`
- Replace content shape: `shared/rules/trip-types.json`
- Modify: `scripts/validate_shared.py`
- Create: `ios/PackWiseTests/TripTypeCompositionTests.swift`

**Interfaces:**

- Produces: `PackingNeed`, `RecommendationProvenance`, `PackingNeedContribution`, `TripTypeContract`, `TripTypeContractResolver.contributions(for:)`.
- Contract rule: trip-type JSON contains closed need IDs and suggested activity IDs, never canonical item IDs.

- [ ] **Step 1: Re-read and pin the approved table in design Section 8.1 before production code.** Encode a table-driven test for the exact needs, unselected suggested activities, and non-implications of Vacation, City Break, Beach, Business, Outdoor, Road Trip, Wedding/Event, Ski/Snow, Festival, Visiting Family, and Other. If an implementation concern would change a row, stop for product approval and commit that spec change first.

- [ ] **Step 2: Write validator and decoder tests.** Reject unknown need IDs, duplicate stable values, and canonical-looking item IDs in a trip-type contract. Assert `.other` has no deterministic need contribution.

- [ ] **Step 3: Write combination tests for all ten required trip-type sets.** Assert normalized needs and provenance, not only final item counts. Include insertion-order determinism.

```swift
@Test func businessAndCityBreakComposeNeedsWithoutPrimaryType() throws {
    let facts = TripTypeContractResolver(contracts: try TestRules.tripTypes)
        .contributions(for: [.business, .cityBreak])
    #expect(facts.map(\.need).contains(.formalWork))
    #expect(facts.map(\.need).contains(.urbanWalking))
    #expect(Set(facts.map(\.provenance.tripType)) == [.business, .cityBreak])
}
```

- [ ] **Step 4: Write suggestion-vs-selection tests.** Selecting City Break may order Walking/Museums/Nice Dinner as suggestions, but `TripContext.activities` stays empty until an explicit selection action. Changing trip types preserves the exact selected activity set and never adds/removes activities.

- [ ] **Step 5: Run shared validation and the focused Swift tests; confirm both fail on the old direct-item contract.**

```bash
python3 scripts/validate_shared.py
xcodebuild -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/TripTypeCompositionTests test
```

- [ ] **Step 6: Implement the typed contract decoder and convert every trip type exactly as approved.** Preserve current legitimate semantics through central need→candidate/capability mappings; do not copy each old list into Swift. Suggested activity IDs feed display ordering only and cannot write `TripContext.activities`.

- [ ] **Step 7: Run validation/tests and commit the contract layer.**

```bash
git add shared/rules/trip-types.json scripts/validate_shared.py \
  ios/PackWise/Domain/Packing/TripTypeContracts.swift ios/PackWise/Domain/Packing/Catalog.swift \
  ios/PackWise/Data/SharedResources.swift ios/PackWiseTests/TripTypeCompositionTests.swift
git commit -m "feat: model trip types as typed packing needs"
```

### Task 4: Compose all selected trip types through the existing engine

**Files:**

- Modify: `ios/PackWise/Domain/Packing/PackingEngine.swift`
- Modify: `ios/PackWise/Domain/Packing/CoverageResolver.swift`
- Modify: `ios/PackWise/Domain/Weather/WeatherChangeReconciler.swift`
- Modify: `ios/PackWiseTests/{PackingEngineTests,CoverageTests,GoldenEngineTests,ReasonQualityTests}.swift`
- Modify: `shared/fixtures/golden/golden-fixtures.json`
- Add reviewed V2 combination fixtures under `shared/fixtures/trips/` and goldens under `ios/PackWiseTests/Goldens/`

**Interfaces:**

- Consumes: `TripContext.tripTypes` and Task 3 contributions.
- Produces: one candidate collection, combined structured provenance, stable context signatures, and coverage based on the full need set.

- [ ] **Step 1: Add failing final-output tests for Vacation+Beach, Vacation+City Break+Beach, Business+City Break, Road Trip+Outdoor, Wedding/Event+Vacation, Festival+City Break, Visiting Family+Vacation, and Outdoor+Ski/Snow.** Assert no duplicate recommendation keys, baseline clothing is not multiplied, and expected capabilities remain covered.

- [ ] **Step 2: Add trace assertions.** Walking shoes must retain City Break/Sightseeing/Walking facts when present; no trace may expose an invented primary trip type.

- [ ] **Step 3: Replace the singular trip-type branch with contribution collection before candidate generation.** Merge provenance on an existing recommendation key instead of adding another row. Extend `CoverageResolver.needs` to consume normalized needs while retaining one greedy coverage pass.

- [ ] **Step 4: Update weather/context signatures to sort trip types, run focused tests, and generate a semantic golden diff.** Record for every changed golden: added IDs, removed IDs, quantity changes, coverage suppressions, constraint decisions, and reason/provenance changes.

- [ ] **Step 5: Commit only after the semantic diff matches the contract intent.**

```bash
git add ios/PackWise/Domain/Packing/PackingEngine.swift ios/PackWise/Domain/Packing/CoverageResolver.swift \
  ios/PackWise/Domain/Weather/WeatherChangeReconciler.swift ios/PackWiseTests shared/fixtures
git commit -m "feat: compose multiple trip types in one packing plan"
```

## Stage C — Multi-bag engine

### Task 5: Normalize luggage sets and centralize bag constraints

**Files:**

- Create: `ios/PackWise/Domain/Packing/LuggageContext.swift`
- Create: `ios/PackWiseTests/LuggageContextTests.swift`
- Modify: `ios/PackWise/Domain/Packing/{PackingEngine,ConstraintResolver,ClothingQuantity}.swift`
- Modify: `ios/PackWiseTests/{ConstraintTests,ClothingQuantityTests,PackingEngineTests}.swift`

**Interfaces:**

- Produces: `LuggageContext.resolve(_:)`, `LuggageContext.Capacity`, luggage-aware quantity/optional-item constraint inputs.
- Rule: `.checkedAvailable` always defeats carry-on-only/personal-item-only trimming; style remains independent.

- [ ] **Step 1: Write the complete luggage truth-table tests.** Cover empty, each single bag, Personal+Carry-on, Carry-on+Checked, Personal+Carry-on+Checked, Backpack+Checked, Backpack+Carry-on, and set-order determinism.

- [ ] **Step 2: Add behavioral tests.** The same prepared trip with Carry-on only may trim optional items; Carry-on+Checked must not emit a carry-on trim decision; Light+Checked may still reduce style-sensitive quantities.

- [ ] **Step 3: Run focused tests and verify failures on singular `BagType` APIs.**

- [ ] **Step 4: Implement luggage derivation and change quantity/constraint APIs from `BagType` to `LuggageContext`.** Remove all branches where the mere presence of carry-on wins over checked. Keep transportation separate.

- [ ] **Step 5: Update goldens/fixtures to `bagTypes`, record semantic diffs, run focused tests, and commit.**

```bash
git add ios/PackWise/Domain/Packing/LuggageContext.swift ios/PackWise/Domain/Packing/PackingEngine.swift \
  ios/PackWise/Domain/Packing/ConstraintResolver.swift ios/PackWise/Domain/Packing/ClothingQuantity.swift \
  ios/PackWiseTests shared/fixtures
git commit -m "feat: apply deterministic multi-bag capacity semantics"
```

## Stage D — Family eligibility and sharing

### Task 6: Add one traveler eligibility authority

**Files:**

- Create: `ios/PackWise/Domain/Packing/TravelerEligibilityResolver.swift`
- Create: `ios/PackWiseTests/TravelerEligibilityTests.swift`
- Modify: `ios/PackWise/Domain/Packing/{Catalog,PackingEngine}.swift`
- Modify: `shared/rules/party.json`
- Modify: `scripts/validate_shared.py`

**Interfaces:**

- Produces: `TravelerEligibilityResolver.evaluate(...) -> EligibilityDecision` and closed eligibility metadata.
- Replaces: distributed `shouldSkip` decisions as the final eligibility authority; temporary adapters may feed the resolver during migration.

- [ ] **Step 1: Write failing toddler tests.** With no explicit signal, exclude phone, phone charger, headphones, deodorant, medication, laptop, and Photo ID while retaining tops, sleepwear, socks, and suitable shoes. With explicit diapers/stroller/car-seat/medication/comfort needs, include only the selected need families. Never implement a category-wide Documents exclusion.

- [ ] **Step 2: Write attribution tests.** A primary traveler’s medication/laptop chip cannot make the child eligible; an unassigned note/chip cannot claim coverage for anyone.

- [ ] **Step 3: Write the approved travel-document matrix tests from design Section 9.3.** On a confirmed international family trip, every traveler including a toddler receives a personal passport and traveler-specific Visa/entry docs; Photo ID follows adult/teen eligibility and is not blindly assigned to the toddler; Travel insurance info resolves once as shared/single-per-party.

- [ ] **Step 4: Add closed eligibility metadata and validator coverage.** Missing metadata for sensitive families and each canonical document family fails validation rather than defaulting permissively.

- [ ] **Step 5: Insert eligibility before quantity/sharing, record suppressions in the audit ledger, delete redundant skip branching, and run focused tests.**

- [ ] **Step 6: Commit the eligibility layer.**

```bash
git add ios/PackWise/Domain/Packing/TravelerEligibilityResolver.swift ios/PackWise/Domain/Packing/Catalog.swift \
  ios/PackWise/Domain/Packing/PackingEngine.swift ios/PackWiseTests/TravelerEligibilityTests.swift \
  shared/rules/party.json scripts/validate_shared.py
git commit -m "feat: enforce traveler eligibility before recommendation"
```

### Task 7: Complete the sharing-policy catalog audit

**Files:**

- Modify: `shared/rules/party.json`
- Modify when naming/metadata requires it: `shared/catalog/*.json`
- Modify: `ios/PackWiseTests/{PackingEngineTests,CoverageTests}.swift`
- Add: `docs/plans/2026-09-04-product-experience-v2-sharing-audit.md`

**Interfaces:**

- Produces: reviewed eligibility/sharing classification table for every relevant canonical ID and executable rule coverage.

- [ ] **Step 1: Inventory every canonical item and write the audit table.** Explicitly adjudicate Passport, Photo ID, Visa/entry docs, Travel insurance info, toothpaste, shampoo, body wash, pain reliever, laundry bag, packing cubes, toiletry bag, chargers, adapters, sunscreen, umbrellas, medicines, books, and electronics across eligibility and sharing axes.

- [ ] **Step 2: Add failing tests for shared toiletries, personal clothing, personal footwear, shared umbrella, device-scaled adapters/chargers, and party/duration-scaled consumables.** Include solo, couple, family with two other adults+toddler, and group with three additional adults.

- [ ] **Step 3: Update rules and central shared-quantity semantics.** Do not store policy on generated item records; preserve owner/carrier invariants.

- [ ] **Step 4: Run shared validation, party invariants, engine tests, and commit the audit plus rule changes.**

```bash
python3 scripts/validate_shared.py
git add shared/rules/party.json shared/catalog ios/PackWiseTests \
  docs/plans/2026-09-04-product-experience-v2-sharing-audit.md
git commit -m "fix: align family eligibility and sharing across catalog"
```

## Checkpoint V — Whole-product visual reference before production wiring

### Visual reference contact sheet

**Files:**

- Modify: `ios/PackWise/Features/Developer/DebugPreviewScene.swift`
- Modify: `scripts/capture_ios_screens.sh`
- Modify: `ios/PackWiseTests/M1LoopTests.swift`
- Add evidence: `docs/device-evidence/product-v2/visual-reference-checkpoint.md`

**Produces:** deterministic, non-production reference states for 3 onboarding pages, all 9 setup steps, Trip Detail, solo Packing List, family grouped Packing List, traveler-filtered Packing List, Add Item, Choose Category, and Item Detail, rendered into one contact sheet.

- [ ] **Step 1: Add a failing inventory test for every required reference-state identifier.** The test pins the complete set so no major surface silently drops from the checkpoint.

- [ ] **Step 2: Add deterministic Debug preview models and reference compositions using the existing PackWise tokens/primitives.** These are visual targets, not wired production screens; they contain no network calls, persistence writes, or new product behavior.

- [ ] **Step 3: Extend the existing capture script to render every reference state at the standard device size, then build one contact sheet.** Record the commit, simulator/runtime, capture command, and artifact paths in the evidence document.

- [ ] **Step 4: Review the contact sheet with screen titles covered.** Typography hierarchy, margins, card/row restraint, icon containers, selected states, navigation treatment, CTA position, sheets, and empty states must still read as one app.

- [ ] **Step 5: Fix systemic discrepancies only in shared tokens, primitives, preview shell, or reference compositions; rerender until the contact sheet passes.** Do not wire feature behavior in this checkpoint.

- [ ] **Step 6: Run focused tests, shared validation, a Debug build, and commit the reference checkpoint.**

```bash
xcodebuild -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/M1LoopTests test
python3 scripts/validate_shared.py
xcodebuild -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
git add ios/PackWise/Features/Developer/DebugPreviewScene.swift scripts/capture_ios_screens.sh \
  ios/PackWiseTests/M1LoopTests.swift docs/device-evidence/product-v2/visual-reference-checkpoint.md
git commit -m "test: establish product v2 visual reference"
```

## Stage E — Setup flow redesign

### Task 8: Split setup state from the shared shell

**Files:**

- Create: `ios/PackWise/Features/TripSetup/TripSetupShell.swift`
- Create: `ios/PackWise/Features/TripSetup/TripSetupSelectionGrid.swift`
- Modify: `ios/PackWise/Features/TripSetup/TripSetupView.swift`
- Modify: `ios/PackWise/DesignSystem/PackWisePrimitives.swift`
- Modify: `ios/PackWise/Features/Developer/DebugPreviewScene.swift`
- Modify: `ios/PackWise/Features/Settings/MeView.swift`
- Add UI/state tests in: `ios/PackWiseTests/M1LoopTests.swift`

**Interfaces:**

- Produces: nine-step `SetupStep`, set-valued `TripDraft`, reusable `TripSetupShell`, reusable `MultiSelectionCard`/grid.
- Consumes: repository set APIs and stable ordering.

- [ ] **Step 1: Add state tests for fresh/edit drafts.** Assert multi-bag preference prefill, legacy-empty bags, multi-type round trip, family ID reuse, and review summaries. Assert suggested activities remain absent from `TripContext.activities` until tapped and selected activities remain byte-for-byte stable when trip types change.

- [ ] **Step 2: Change `TripDraft` to `tripTypes`/`bagTypes` and split the nine logical steps.** Require at least one trip type; allow empty bags.

- [ ] **Step 3: Implement the shared shell with bottom safe-area action.** Remove confirmation-action Next from the toolbar; retain native Back/cancel and accessible “Step n of 9.” Verify keyboard avoidance and Dynamic Type.

- [ ] **Step 4: Implement related multi-select surfaces for trip types, activities, and bags.** Suggested activities are the stable union from selected trip types and affect display/order only. Only a user tap changes `draft.activities`; changing trip types never auto-adds or removes an activity.

- [ ] **Step 5: Implement unambiguous traveler counts/labels, the combined style/laundry screen, and the matching Me default-bags multi-select.** Family and Group both count Other adults because You is implicit; Family separately counts Children. Review renders one interpretation (`You + 3 adults` or `4 adults`). Derived labels are stable and distinct.

- [ ] **Step 6: Update Review with separate wrapping sections for all context values and run focused tests/build.**

- [ ] **Step 7: Capture all nine setup screens on the simulator, compare as one flow, fix only systemic shell/primitive issues, and commit.**

```bash
git add ios/PackWise/Features/TripSetup ios/PackWise/Features/Settings/MeView.swift ios/PackWise/DesignSystem/PackWisePrimitives.swift \
  ios/PackWise/Features/Developer/DebugPreviewScene.swift ios/PackWiseTests/M1LoopTests.swift \
  ios/PackWise.xcodeproj/project.pbxproj
git commit -m "feat: redesign trip setup for composable context"
```

## Stage F — Onboarding and destination redesign

### Task 9: Unify onboarding and destination visuals

**Files:**

- Modify: `ios/PackWise/Features/Onboarding/OnboardingView.swift`
- Modify: `ios/PackWise/Features/TripSetup/TripSetupView.swift`
- Modify: `ios/PackWise/Features/Trips/TripsHomeView.swift`
- Modify: `ios/PackWise/DesignSystem/{DestinationVisualService,DestinationVisualView}.swift`
- Add tests in: `ios/PackWiseTests/M1LoopTests.swift`

**Interfaces:**

- Produces: shared onboarding shell, truthful copy, `MKMapSnapshotter` fallback/caching, safe overlay layout.

- [ ] **Step 1: Add presentation tests for the three approved onboarding messages and for destination result title/subtitle formatting.** Assert no shipped-memory or AI claim appears.

- [ ] **Step 2: Add a destination visual policy test with injected Look Around/map providers.** Assert destination preview uses map before graphical fallback and trip hero/thumbnail follows trusted image → map → graphical.

- [ ] **Step 3: Build one onboarding shell and apply it to all pages.** Keep consistent logo/wordmark, margins, type, CTA, pagination, and image/card frame.

- [ ] **Step 4: Redesign destination empty/results/selected states.** Never render a result row and a duplicate large confirmation simultaneously.

- [ ] **Step 5: Add MapKit snapshot fallback and cache derived images.** Reserve a protected text region/scrim so symbols or imagery cannot overlap destination/date copy. Verify Khammam specifically and at least one Look Around-covered city.

- [ ] **Step 6: Capture onboarding, destination empty/search/selected, Trips Home current/upcoming, and offline graphical fallback states; run focused tests; commit.**

```bash
git add ios/PackWise/Features/Onboarding ios/PackWise/Features/TripSetup/TripSetupView.swift \
  ios/PackWise/Features/Trips/TripsHomeView.swift ios/PackWise/DesignSystem/DestinationVisual* \
  ios/PackWiseTests/M1LoopTests.swift
git commit -m "feat: unify onboarding and destination experience"
```

## Stage G — Trip Detail categories

### Task 10: Show every non-empty category

**Files:**

- Modify: `ios/PackWise/Features/TripDetail/TripDetailView.swift`
- Modify: `ios/PackWiseTests/M1LoopTests.swift`

**Interfaces:**

- Produces: complete ordered non-empty category summaries; no hidden count.

- [ ] **Step 1: Add a failing pure/presentation test with all 11 categories non-empty.** Assert all 11 appear in `PackingCategory.displayOrder` and zero empty categories appear.

- [ ] **Step 2: Remove `prefix(5)` and “more categories,” preserving category navigation and See All.** Derive outdoor ordering from `trip.tripTypes.contains(.outdoor)`.

- [ ] **Step 3: Capture a full-category scrolling Trip Detail at standard and accessibility Dynamic Type, run focused tests, and commit.**

```bash
git add ios/PackWise/Features/TripDetail/TripDetailView.swift ios/PackWiseTests/M1LoopTests.swift
git commit -m "fix: show all packing categories on trip detail"
```

## Stage H — Family Packing List aggregation and filters

### Task 11: Aggregate family All scope without collapsing ownership

**Files:**

- Create: `ios/PackWise/Features/TripDetail/PackingListAggregation.swift`
- Create: `ios/PackWiseTests/PackingListAggregationTests.swift`
- Modify: `ios/PackWise/Features/TripDetail/PackingListView.swift`
- Modify: `ios/PackWise/Domain/Party.swift`

**Interfaces:**

- Produces: `PackingListPresentationRow`, `PersonalItemGroup`, `PackingListAggregator.rows(items:party:status:search:)`, stable traveler labels, compact People/Status scopes.
- Rule: aggregation is read-only presentation; mutations target underlying `PackingItemRecord` IDs.

- [ ] **Step 1: Write pure aggregation tests.** Four traveler toothbrush rows become one group; T-shirts expose per-traveler quantities; shared umbrella remains one row; different categories/canonical IDs do not merge; unrelated custom names do not merge.

- [ ] **Step 2: Add status/search tests.** A group is visible if a child record matches, completion uses matching records, search matches canonical/display/traveler label, and traveler scope returns raw records.

- [ ] **Step 3: Add stable label tests.** Empty names render You, Adult 1, Adult 2, Child 1, Child 2, Shared in stable party order; supplied names replace fallbacks without changing identity.

- [ ] **Step 4: Implement pure aggregation and refactor All scope.** Group row tap opens an expansion containing real records and real per-record controls. Never mutate group totals directly.

- [ ] **Step 5: Replace redundant filters with labelled People and Status scopes; hide People entirely for solo.** Give the floating add button and final row explicit safe-area clearance.

- [ ] **Step 6: Capture solo, couple, family All, each traveler, Shared, search, To pack, Packed, and Important states; run tests; commit.**

```bash
git add ios/PackWise/Features/TripDetail/PackingListAggregation.swift \
  ios/PackWise/Features/TripDetail/PackingListView.swift ios/PackWise/Domain/Party.swift \
  ios/PackWiseTests/PackingListAggregationTests.swift ios/PackWise.xcodeproj/project.pbxproj
git commit -m "feat: aggregate family packing list presentation"
```

## Stage I — Add/Edit category selection

### Task 12: Use one dedicated category selector

**Files:**

- Create: `ios/PackWise/Features/TripDetail/CategorySelectionView.swift`
- Modify: `ios/PackWise/Features/TripDetail/PackingListView.swift`
- Modify: `ios/PackWise/Features/Developer/DebugPreviewScene.swift`
- Add tests in: `ios/PackWiseTests/M1LoopTests.swift`

**Interfaces:**

- Produces: `CategorySelectionView(selection:onSelect:)` shared by Add and Edit.

- [ ] **Step 1: Add tests that Add and Edit expose the same ordered category model and selection callback.** Assert selecting a category updates exactly one draft/record and returns automatically.

- [ ] **Step 2: Replace Item Detail’s `Picker` and Add Item’s separate route content with the shared dedicated selector.** Use category tokens/icons/checkmark and no `.menu` presentation.

- [ ] **Step 3: Give Add Item content-sized native detents and verify keyboard/category navigation.** Preserve manual category edits across regeneration.

- [ ] **Step 4: Capture Add Item, Choose Category, Edit Item, and returned selection states; run focused tests; commit.**

```bash
git add ios/PackWise/Features/TripDetail/CategorySelectionView.swift \
  ios/PackWise/Features/TripDetail/PackingListView.swift \
  ios/PackWise/Features/Developer/DebugPreviewScene.swift ios/PackWiseTests/M1LoopTests.swift \
  ios/PackWise.xcodeproj/project.pbxproj
git commit -m "feat: add a shared category selection flow"
```

## Stage J — Recommendation naming and trace audit

### Task 13: Align causal needs, names, and the single RecommendationTrace

**Files:**

- Modify as adjudicated: `shared/rules/{activity-rules,trip-types,reasons}.json`
- Modify as adjudicated: `shared/catalog/*.json`
- Modify: `ios/PackWise/Domain/Packing/PackingEngine.swift`
- Modify: `ios/PackWise/Features/TripDetail/PackingListView.swift`
- Modify: `ios/PackWiseTests/{ReasonQualityTests,CopyWarmthTests,GoldenEngineTests}.swift`
- Add: `docs/plans/2026-09-04-product-experience-v2-naming-audit.md`

**Interfaces:**

- Produces: one reviewed mapping from causal need → candidate display name → `RecommendationTrace`, consumed by every customer-facing explanation surface.

- [ ] **Step 1: Generate the audit inventory from all trip-type/activity contracts.** Manually adjudicate every mismatch, beginning with Nightlife/Nice dinner outfit; record keep/rename/remap decisions in the audit doc.

- [ ] **Step 2: Add failing reason-quality tests for each adjudicated mismatch and multi-source trace.** Assert customer text is specific, truthful, and contains no internal/AI vocabulary. Assert Item Detail, row subtitle, and reason rendering all consume the same `RecommendationTrace` value.

- [ ] **Step 3: Apply catalog/rule/reason changes and merge compatible multi-cause facts into the existing Phase 8 trace structure:** `provenance[]`, quantity evidence, satisfied capabilities, suppressions, constraints, and authority. `recommendationTraceRaw` is its persistence encoding. Legacy source/reason fields feed only one migration adapter and never independently decide UI copy. Keep Phase 8 sections and quantity behavior unchanged.

- [ ] **Step 4: Run shared validation and reason/golden tests; review semantic diffs; commit.**

```bash
python3 scripts/validate_shared.py
git add shared/rules shared/catalog ios/PackWise/Domain/Packing/PackingEngine.swift \
  ios/PackWise/Features/TripDetail/PackingListView.swift ios/PackWiseTests \
  docs/plans/2026-09-04-product-experience-v2-naming-audit.md
git commit -m "fix: align recommendation names with causal context"
```

## Stage K — WeatherKit physical-device repair

### Task 14: Make the live WeatherKit path observable and date-correct

**Files:**

- Create: `ios/PackWise/Data/Weather/WeatherRequestDiagnostics.swift`
- Create: `ios/PackWiseTests/WeatherKitRequestTests.swift`
- Modify: `ios/PackWise/Data/WeatherKit/{WeatherKitClient,WeatherKitWeatherService}.swift`
- Modify: `ios/PackWise/Domain/Weather/WeatherNormalization.swift`
- Modify: `ios/PackWise/Data/Weather/TripWeatherRefresh.swift`
- Modify: `ios/PackWise/Features/Developer/{DeveloperToolsView,DebugWeatherInjection}.swift`
- Modify: `ios/PackWiseTests/{WeatherNormalizationTests,WeatherChangeTests}.swift`

**Interfaces:**

- Produces: destination-timezone query bounds, typed diagnostic envelope, deterministic fixture rebasing, unchanged `WeatherAvailability`/reconciliation authority.

- [x] **Step 1: Add diagnostic-envelope tests before changing live behavior.** Assert request coordinates/dates/timezones, provider-returned day bounds, normalization inclusions/exclusions, cache decision, typed error, and final `WeatherQuality` are captured; assert notes/custom text are absent.

- [x] **Step 2: Implement diagnostics only and run the focused tests.** Wire the envelope through `WeatherKitClient` → `WeatherKitWeatherService` → `TripWeatherResolver` → cache/result selection without changing query bounds, normalization, fallback, or UI behavior.

- [x] **Step 3: Reproduce the current Chicago failure on physical hardware before any behavioral fix.** (2026-09-08 — device symptom plus entitled-simulator reproduction recorded in `docs/device-evidence/product-v2/weatherkit.md`; provider throws `WDSJWTAuthenticatorServiceListener.Errors` code 2.) Use a trip beginning on the device’s current day. Save raw requested coordinates/dates, destination/device timezones, provider coverage, normalization result, cache result, typed error, and final quality in `docs/device-evidence/product-v2/weatherkit.md`.

- [x] **Step 4: Write the smallest failing regression test proved by Step 3.** (`currentDayTripInAnotherTimezoneRecordsProviderAuthFailure`; the evidence shows a provider authorization failure, so no timezone fix was added.) If the evidence shows a destination-timezone boundary defect, cover the exact device/destination timezone and current-date range. If it shows entitlement, provider, cache, or normalization failure instead, test that exact boundary and do not add an unrelated timezone fix.

- [x] **Step 5: Apply the smallest source fix supported by evidence and verify red→green.** (Setup-path diagnostics commit and honest unavailable copy. The root cause is Apple-side WeatherKit App Service authorization for `com.packwiseapp.app`, which no source change can repair — see the evidence file §4.) Preserve precise/partial/seasonal semantics and Apple attribution. Do not turn an error into fake seasonal weather.

- [x] **Step 6: Add a failing fixture-rebase test, then implement Debug-only rebasing.** A named fixture rebases local day components to any target trip range and passes through real normalization/reconciliation; hardcoded fixture dates cannot make injection fail.

- [ ] **Step 7: Run focused and full weather tests, then re-prove the same Chicago trip on hardware.** (Tests green 2026-09-08. Hardware re-proof is blocked on the portal action in the evidence file §4 and must be run from the `product-v2-stage-a` worktree.) Append before/after evidence and final quality to the evidence file. Stop if the live symptom remains.

- [ ] **Step 8: Run the green-commit checks and commit diagnostics, evidence-supported repair, Debug injection, and evidence.**

```bash
git add ios/PackWise/Data/Weather ios/PackWise/Data/WeatherKit ios/PackWise/Domain/Weather \
  ios/PackWise/Features/Developer ios/PackWiseTests docs/device-evidence/product-v2 \
  ios/PackWise.xcodeproj/project.pbxproj
git commit -m "fix: repair and instrument current-trip WeatherKit"
```

## Cross-cutting contracts and documentation

### Task 15: Update fixtures, API vocabulary, and canonical product documentation

**Files:**

- Modify: `shared/contracts/intelligence-api.yaml`
- Modify: `shared/schemas/trip-eval.schema.json`
- Modify: `shared/fixtures/trips/*.json`, `shared/fixtures/golden/golden-fixtures.json`
- Modify: `ios/PackWise/Data/{SharedResources.swift,Intelligence/IntelligenceDTO.swift}`
- Modify: `api/src/{types,validation,canonical}.ts`, `api/src/model/inputs.ts`, affected tests
- Regenerate: `api/generated/**` only through `scripts/build_intelligence_schemas.py` and `scripts/build_shared.py`
- Modify: `AGENTS.md`, `.cursor/rules/{packwise-architecture,packwise-intelligence,packwise-scope,packwise-ux}.mdc`
- Modify: `docs/{README,trip-creation,travelers-and-parties,packing-experience,navigation-and-onboarding,architecture,packing-engine,design-system,roadmap,implementation-decisions,device-pass-checklist,m3a2-verification-runbook}.md`

**Interfaces:**

- Produces: array-valued `tripTypes`/`bagTypes` DTOs in stable order and aligned source-of-truth documentation.
- Constraint: interpretation remains gated off; this changes contract shape, not M3B behavior.
- Compatibility: until Tasks 3–5 consume multi-value context, boundary adapters accept singleton arrays and empty bags but explicitly return `unsupportedButSafe` for multiple values. They never select a first/primary value. Tasks 4 and 5 remove those guards as their engine semantics land.

- [ ] **Step 1: Add failing schema/API tests.** Require one-or-more known `tripTypes`, zero-or-more known physical `bagTypes`, reject legacy singular fields in new requests, reject unknown values, and verify canonical stable ordering.

- [ ] **Step 2: Convert existing request/eval fixtures to singleton `tripTypes` arrays and zero/singleton `bagTypes` arrays.** Keep legacy-store migration fixtures separate. Add multi-value contract fixtures only where the temporary adapter can validate/round-trip them without invoking unfinished engine behavior.

- [ ] **Step 3: Update Swift DTO and TypeScript validation/model input shapes in the same change.** Add explicit temporary singleton/empty compatibility guards at unfinished engine call sites; multiple values return `unsupportedButSafe` and never choose a primary. Do not enable note enrichment or gap wiring.

- [ ] **Step 4: Regenerate artifacts using only the generators, then run validation/preflight/tests.**

```bash
python3 scripts/build_intelligence_schemas.py
python3 scripts/build_shared.py
python3 scripts/validate_shared.py
npm --prefix api test
npm --prefix api run preflight
```

- [ ] **Step 5: Align canonical docs and rules with the approved V2 decisions and freeze Phase 9/M3B behind the V2 exit gate.** Remove stale singular, top-Next, fake road-trip-bag, truncated-category, and shipped-memory claims.

- [ ] **Step 6: Commit contracts, generated artifacts, fixtures, and aligned documentation.**

```bash
git add shared api ios/PackWise/Data/SharedResources.swift ios/PackWise/Data/Intelligence/IntelligenceDTO.swift \
  AGENTS.md .cursor/rules docs
git commit -m "feat: migrate product v2 contracts to array context"
```

## Stage L — Authority, simulator, and physical-device verification

### Task 16: Prove explicit user authority across V2 context changes

**Files:**

- Create: `ios/PackWiseTests/ProductV2AuthorityTests.swift`
- Modify only if a defect is exposed: `ios/PackWise/Data/Repositories/Repositories.swift`, `ios/PackWise/Domain/Packing/PackingEngine.swift`, `ios/PackWise/Domain/Weather/WeatherChangeReconciler.swift`

**Interfaces:**

- Proves: manual quantity, packed count/state, Not Needed, user-added/custom item, owner, carrier, and category edit survive type/bag/party/weather edits and relaunch.

- [ ] **Step 1: Write one file-backed end-to-end authority scenario.** Create a family trip, modify every protected field, add/remove trip types and bags, regenerate through `RecommendationDiff`, apply accepted additions/quantities but not removals, relaunch, and assert every protected decision.

- [ ] **Step 2: Add scoped Not Needed tests.** A rejected child/personal/shared canonical item stays suppressed only for its correct recommendation identity and never resurrects because another trip type contributes the same need.

- [ ] **Step 3: Run focused tests; fix only genuine reconciliation defects; commit.**

```bash
xcodebuild -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/ProductV2AuthorityTests test
git add ios/PackWiseTests/ProductV2AuthorityTests.swift ios/PackWise/Data/Repositories/Repositories.swift \
  ios/PackWise/Domain/Packing/PackingEngine.swift ios/PackWise/Domain/Weather/WeatherChangeReconciler.swift
git commit -m "test: prove user authority across product v2 changes"
```

### Task 17: Full automated verification and semantic audit

**Files:**

- Modify only for defects: files owned by Tasks 1–16
- Add evidence: `docs/device-evidence/product-v2/simulator-verification.md`

- [ ] **Step 1: Run shared validation and API checks from a clean working tree.**

```bash
python3 scripts/validate_shared.py
npm --prefix api test
npm --prefix api run preflight
```

- [ ] **Step 2: Run the full iOS simulator suite.** Record test count, failures, simulator/runtime, commit, and duration.

```bash
xcodebuild -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

- [ ] **Step 3: Run a clean Release build and prove Debug tools are absent.**

```bash
xcodebuild -project ios/PackWise.xcodeproj -scheme PackWise \
  -configuration Release -destination 'generic/platform=iOS' build
```

- [ ] **Step 4: Review the complete engine semantic diff.** For every required fixture, record final IDs/quantities, duplicate-key count, coverage suppressions, constraints, eligibility suppressions, and structured provenance. Zero unexplained changes are permitted.

- [ ] **Step 5: Run the complete simulator screen matrix with `scripts/capture_ios_screens.sh`.** Review clipping, Dynamic Type, safe areas, consistent selection states, solo/party conditional UI, and all non-empty categories.

- [ ] **Step 6: Commit verification evidence or defect fixes in isolated commits.**

```bash
git add docs/device-evidence/product-v2/simulator-verification.md
git commit -m "test: record product v2 simulator verification"
```

### Task 18: Physical-device V2 acceptance and gate decision

**Files:**

- Add evidence: `docs/device-evidence/product-v2/device-pass.md`
- Add screenshots under the existing ignored/evidence policy; do not commit secrets or raw personal notes.
- Modify: `docs/device-pass-checklist.md`, `docs/m3a2-verification-runbook.md`, `docs/roadmap.md`, `docs/implementation-decisions.md` only after evidence exists.

- [ ] **Step 1: Install a development-signed Debug build on a physical iPhone and record exact build/commit/device/iOS/API environment.** Confirm light mode, no signup/location/notification/paywall, and offline list usability.

- [ ] **Step 2: Run and capture the complete required interaction matrix.** Onboarding; MapKit destination; trip-type/activity/bag multi-select; solo/couple/family/group; grouped All; traveler and Shared; add/edit/category/detail; quantity; Not Needed; custom item; relaunch; trip edit/regeneration.

- [ ] **Step 3: Run live WeatherKit on a current trip and capture raw diagnostics plus UI.** Confirm requested and provider dates/coordinates/timezones, precise coverage, final quality, Packing Impact agreement, and Apple attribution.

- [ ] **Step 4: Re-run the App Attest development chain.** Confirm support, key/challenge/attestation, two advancing assertions, replay rejection, tampered-body rejection, and real interpret 200. Do not conflate fixture crypto with Apple-service verification.

- [ ] **Step 5: Record raw observations before diagnosing or fixing.** Any defect gets a focused reproduction, test, implementation, verification, semantic diff, and separate commit; rerun the affected matrix afterward.

- [ ] **Step 6: Evaluate every V2 exit criterion with evidence links.** If any criterion is unproven, leave the gate red and M3B/M3C frozen. If all are green, update the gate documents precisely; TestFlight production App Attest remains deferred to distribution.

- [ ] **Step 7: Commit the evidence/gate record and stop for product review.**

```bash
git add docs/device-evidence/product-v2 docs/device-pass-checklist.md \
  docs/m3a2-verification-runbook.md docs/roadmap.md docs/implementation-decisions.md
git commit -m "docs: record product v2 physical-device gate"
```

## Final review checklist

- [ ] No production path reads a singular trip type or singular bag as authority.
- [ ] No selected trip type maps directly to an independent checklist.
- [ ] Every context set serializes stably at persistence/API/signature/golden boundaries.
- [ ] Empty bags are unconstrained; any checked bag disables carry-on-only trimming.
- [ ] Toddler/device/medication/equipment eligibility is explicit and conservative.
- [ ] Sharing policies have a catalog-wide evidence table and executable coverage.
- [ ] Family All aggregation changes presentation only.
- [ ] Every setup screen uses the same shell; multi- and single-select semantics are visually distinct.
- [ ] Destination confirmation is not duplicated and MapKit fallback is intentional.
- [ ] Onboarding makes only shipped, truthful promises.
- [ ] Trip Detail shows every non-empty category.
- [ ] Add/Edit share one dedicated category selector.
- [ ] Recommendation names, reasons, and provenance agree.
- [ ] Live current-trip WeatherKit and App Attest are proven independently on hardware.
- [ ] Manual, packed, Not Needed, custom, owner/carrier, and category decisions survive.
- [ ] Full iOS, engine/golden, shared, API, Release, simulator visual, offline, and physical-device gates are green.
- [ ] Phase 9/M3B/M3C remains frozen until all evidence is green.
