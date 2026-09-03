# PackWise Product Hardening — Phase 1 and Next Phases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a deterministic, reviewable ledger of PackWise's current packing behavior, then harden context, needs, coverage, weather, constraints, explanations, traveler safety, and lifecycle behavior one bounded phase at a time.

**Architecture:** Phase 1 extends the existing 17-fixture golden harness; it does not replace `PackingEngine`, `ClothingQuantityEngine`, `CoverageResolver`, `ConstraintResolver`, or the provenance fields on `PackingItemDraft`. The ledger combines stable JSON, semantic diffs, property tests, a machine-readable surfaced-input contract, trace metrics, and ranked findings. Later phases change one behavior family at a time and require a reviewed golden diff before the next phase opens.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, SwiftData, JSON catalogs/rules under `shared/`, Python 3 audit scripts, `xcodebuild`, and Git.

## Global Constraints

- Never market or label PackWise as an AI app in customer-facing copy.
- The list remains local-first and usable offline.
- GPT never writes SwiftData or directly inserts packing items.
- Explicit decisions win; removed items do not return and manual quantities survive unrelated regeneration.
- Ambiguous traveler attribution resolves to **don't infer**.
- Weather changes create proposals and never silently rewrite a list.
- `BagType.notSure` applies no bag constraint.
- Run `python3 scripts/validate_shared.py` after catalog or rule edits.
- Phase 1 changes measurement only—no recommendation, quantity, coverage, weather, party, persistence, or GPT behavior.
- Presentation stays frozen during deterministic hardening.
- The user's sequencing decision defers physical-device verification for deterministic Phases 1–8. It does not mark that verification complete.
- M3B/M3C remain closed until the M3A exit gate is green and traveler-safe acceptance exists.
- Preserve the pre-existing signing diff in `ios/PackWise.xcodeproj/project.pbxproj`; do not stage it into hardening commits without separate authorization.

---

## Repository Baseline

- `shared/fixtures/golden/golden-fixtures.json` and `ios/PackWiseTests/Goldens/` contain 17 fixtures/outputs.
- `GoldenEngineTests.swift` captures identity, owner, category, quantity, importance, signals, reason code/copy, quantity copy, coverage suppressions, and constraint decisions.
- Current goldens contain 674 item rows, 13 coverage entries, and 7 constraint entries. One row has no reason code.
- The serializer does not capture `assignedTravelerID` or `reasonArguments`.
- There is no reusable semantic diff command, surfaced-input contract, or trace-coverage report.
- `LaundryAccess.none/possible/planned`, clothing policies, coverage, constraints, and memory events already exist and must be audited rather than recreated.
- `camping` has presentation styling but no deterministic activity rule. Phase 1 records that; Phase 5 changes it.

## Phase 1 File Map

- Modify `docs/plans/2026-09-02-product-hardening-program.md`, `docs/device-pass-checklist.md`, and `docs/implementation-decisions.md` for honest gate state.
- Modify `ios/PackWiseTests/GoldenEngineTests.swift`, `ReasonQualityTests.swift`, `ClothingQuantityTests.swift`, `ConstraintTests.swift`, `IntelligenceServiceTests.swift`, `ContextIntelligenceGateTests.swift`, and `WeatherChangeTests.swift`.
- Modify `shared/fixtures/golden/golden-fixtures.json`; add approved outputs under `ios/PackWiseTests/Goldens/`.
- Create `docs/engine-audits/surfaced-input-contracts.json`.
- Create `scripts/report_engine_goldens.py`, `scripts/audit_engine_inputs.py`, `scripts/audit_recommendation_traces.py`, and `scripts/run_engine_audit.sh`, with tests under `scripts/tests/`.
- Create `docs/engine-audits/2026-09-03-phase-1-baseline.md`, `2026-09-03-trace-coverage.md`, and `2026-09-03-engine-findings.md`.

---

### Task 0: Freeze presentation and record the sequencing decision

**Files:**
- Modify: `docs/plans/2026-09-02-product-hardening-program.md`
- Modify: `docs/device-pass-checklist.md`
- Modify: `docs/implementation-decisions.md`
- Preserve unstaged: `ios/PackWise.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: recorded simulator evidence and the user's explicit device-gate deferral.
- Produces: presentation implementation/simulator verification complete; device verification deferred; deterministic Phase 1 authorized; M3B/M3C still blocked.

- [ ] Review `git status --short` and `git diff --stat`. Stop if an unrecognized Domain, Data, API, or shared-rule change appears.
- [ ] Align the three documents to this exact state:

```text
Phase 0 implementation          complete
Phase 0 simulator verification  complete — 143 tests, 87-screen matrix
Phase 0 device verification     deferred by product decision, not verified
Presentation baseline           frozen for deterministic hardening
Phase 1                         authorized
M3B/M3C                         still blocked by the M3A device exit gate
```

- [ ] Run:

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: `** TEST SUCCEEDED **`. Record the fresh count rather than assuming it remains 143.

- [ ] Commit only reviewed presentation/governance files with message `feat: freeze simulator-verified UI baseline`. Do not create a device-verified tag and do not stage the signing diff.

---

### Task 1: Complete the stable golden schema

**Files:**
- Modify: `ios/PackWiseTests/GoldenEngineTests.swift`
- Modify: `ios/PackWiseTests/ReasonQualityTests.swift`
- Modify: `ios/PackWiseTests/Goldens/*.json`

**Interfaces:**
- Consumes: `PackingEngine.generateDetailed(context:existing:overrides:) -> EngineGeneration`.
- Produces: stable owner/carrier and structured reason evidence without inventing unavailable need data.

- [ ] Add a failing serializer test that decodes fixture 11 and requires stable `carrier` and `reasonArguments` fields.

```swift
@Test func goldenSchemaCapturesCarrierAndReasonArguments() throws {
    let output = try renderFixture(id: "11-couple-5d-rain")
    #expect(output.items.first { $0.owner != "shared" }?.carrier.isEmpty == false)
    #expect(output.items.contains { !$0.reasonArguments.isEmpty })
}
```

- [ ] Run `GoldenEngineTests`; expect failure because those fields are absent.
- [ ] Add `carrier: String` and `reasonArguments: [String: String]` to `GoldenItem`. Reuse stable traveler slugs; serialize no carrier as `unassigned`, never a UUID.
- [ ] Keep first-class `needsSatisfied` absent: the current engine does not expose it. Coverage remains in the top-level `coverage` ledger.
- [ ] Replace literal fixture-count assertions in both test files with manifest-ID versus golden-filename equality.
- [ ] Re-record, then inspect `git diff -- ios/PackWiseTests/Goldens`. Expected: schema-only additions; no item, quantity, reason, coverage, or constraint changes.
- [ ] Run focused tests and commit with `test: complete golden recommendation evidence`.

---

### Task 2: Add a semantic golden-diff command

**Files:**
- Create: `scripts/report_engine_goldens.py`
- Create: `scripts/tests/test_report_engine_goldens.py`

**Interfaces:**
- Consumes: a baseline Git ref/directory and candidate golden directory.
- Produces: `UNCHANGED`, `ADDED`, `REMOVED`, `QUANTITY CHANGES`, `TRACE CHANGES`, `COVERAGE CHANGES`, and `CONSTRAINT CHANGES`.

- [ ] Write failing tests for one unchanged item, addition, removal, quantity-only change, trace-only change, coverage change, and new fixture.

```python
def test_quantity_change_is_not_add_remove():
    report = compare(
        golden(items=[item("clothing.tshirt", 7)]),
        golden(items=[item("clothing.tshirt", 3)]),
    )
    assert report.quantity_changes == [("primary", "clothing.tshirt", 7, 3)]
    assert report.added == []
    assert report.removed == []
```

- [ ] Implement structural comparison keyed by `(owner, canonicalItemID)`. Treat signals, reason code/arguments/copy, and quantity reason as trace fields.
- [ ] Support:

```bash
python3 scripts/report_engine_goldens.py --baseline-ref HEAD --candidate ios/PackWiseTests/Goldens
python3 scripts/report_engine_goldens.py --baseline-dir /tmp/baseline --candidate /tmp/candidate --format markdown
```

- [ ] Run `python3 -m unittest scripts.tests.test_report_engine_goldens -v`; compare the repository to `HEAD`; expect 17 unchanged fixtures and zero changes.
- [ ] Commit with `test: add semantic engine golden diff`.

---

### Task 3: Expand the hardening fixture ledger without fixing behavior

**Files:**
- Modify: `shared/fixtures/golden/golden-fixtures.json`
- Modify only if needed: `shared/fixtures/weather/named-fixtures.json`
- Create: new JSON outputs under `ios/PackWiseTests/Goldens/`

**Interfaces:**
- Consumes: the existing fixture schema and named weather fixtures.
- Produces: deterministic current-output captures for realistic exceptional combinations.

- [ ] Add frozen scenarios:

| ID | Scenario | Measures |
| --- | --- | --- |
| 18 | Anchorage · 64d · road trip · hiking + camping · planned laundry · seasonal | plateau, unknown activity, seasonal layers |
| 19 | Phoenix · 5d · city · walking · carry-on · light · hot | inappropriate cold/rain gear |
| 20 | Seattle · 5d · vacation · walking+sightseeing · rain | rain sufficiency and duplication |
| 21 | Ski · 5d · checked · prepared · snow | cold-category completeness |
| 22 | Business + running · 5d | formal/fitness overlap |
| 23 | International beach · 7d · personal item · light | documents, beach identity, compactness |
| 24 | Family + infant, no infant needs | no diaper/formula/stroller inference |
| 25 | Unknown activity `cosplayConvention` | safe, inert fallback |
| 26 | User-added rain shell before wet weather | existing coverage |
| 27 | Custom user item survives regeneration | custom-item authority |

- [ ] Keep API outage and completed-trip behavior out of static goldens; test them at service/lifecycle boundaries.
- [ ] Run `python3 scripts/validate_shared.py`.
- [ ] Record with `PACKWISE_RECORD_GOLDENS=1 xcodebuild test ... -only-testing:PackWiseTests/GoldenEngineTests`. The recorder intentionally fails after writing.
- [ ] Run the semantic report. Existing fixtures must remain unchanged; new defects become findings, not fixes.
- [ ] Run the golden suite normally and commit fixtures/outputs only with `test: expand engine hardening ledger`.

---

### Task 4: Complete invariant, authority, and failure audits

**Files:**
- Modify: `ios/PackWiseTests/ClothingQuantityTests.swift`
- Modify: `ios/PackWiseTests/ConstraintTests.swift`
- Modify: `ios/PackWiseTests/IntelligenceServiceTests.swift`
- Modify: `ios/PackWiseTests/ContextIntelligenceGateTests.swift`
- Modify: `ios/PackWiseTests/WeatherChangeTests.swift`

**Interfaces:**
- Consumes: current policies and boundaries.
- Produces: passing measurement tests plus reproducible findings for desired properties that currently fail.

- [ ] For every `ClothingNeedPolicy`, inventory minimum, maximum, laundry ordering, style ordering, bag ordering, 15d/30d plateau, and formal-top offset.
- [ ] Add parameterized assertions driven by declared sensitivity:

```swift
if policy.laundrySensitivity != .none {
    #expect(planned <= possible)
    #expect(possible <= none)
}
#expect(result >= policy.minimum)
#expect(result <= resolvedMaximum)
```

- [ ] Add authority cases for removed canonical item, manual quantity, user-added canonical/custom item, packed state, owner, and carrier.
- [ ] Inject a throwing context-intelligence service; assert deterministic generation still succeeds and note enrichment remains off.
- [ ] Assert a family note about a daughter’s medication cannot become the primary traveler’s medication chip.
- [ ] Add weather lifecycle cases: no weather still generates; partial forecast does not cover a 30-day trip; existing user rain coverage prevents a duplicate proposal; completed trips do not refresh.
- [ ] Run the five focused suites. Do not change production behavior to make a desired-but-currently-failing property pass; route it to the findings document. Do not commit red tests.
- [ ] Commit passing audit coverage with `test: audit engine invariants and failure boundaries`.

---

### Task 5: Create the surfaced-input contract

**Files:**
- Create: `docs/engine-audits/surfaced-input-contracts.json`
- Create: `scripts/audit_engine_inputs.py`
- Create: `scripts/tests/test_audit_engine_inputs.py`
- Modify: `ios/PackWiseTests/PackingEngineTests.swift`

**Interfaces:**
- Consumes: trip/activity/bag/style/laundry/preference/traveler options and shared rules.
- Produces: one machine-readable record per surfaced input plus a dead/context-only/untested report.

- [ ] Use this record shape:

```json
{
  "kind": "activity",
  "id": "camping",
  "exposed": true,
  "engineContract": "missing",
  "fixtureIDs": ["18-anchorage-64d-road-hiking-camping"],
  "iconContract": "tent",
  "ownerScope": "trip"
}
```

Allowed contracts: `deterministic`, `contextOnly`, `missing`. Do not relabel a broken control as context-only to make the report green.

- [ ] Write script tests for duplicate IDs, missing icon, engine-recognized option with no fixture, illegal contract, and valid context-only option.
- [ ] Implement `python3 scripts/audit_engine_inputs.py --contracts docs/engine-audits/surfaced-input-contracts.json --format markdown`.
- [ ] In `PackingEngineTests.swift`, assert every `TripType`, `BagType`, `PackingStyle`, `LaundryAccess`, and suggested activity has an audit row.
- [ ] Run script/Swift tests. Expected: Camping is explicitly reported as missing deterministic behavior and points to fixture 18.
- [ ] Commit with `test: inventory surfaced packing inputs`.

---

### Task 6: Generate trace coverage and close Phase 1

**Files:**
- Create: `scripts/audit_recommendation_traces.py`
- Create: `scripts/tests/test_audit_recommendation_traces.py`
- Create: `scripts/run_engine_audit.sh`
- Create: `docs/engine-audits/2026-09-03-trace-coverage.md`
- Create: `docs/engine-audits/2026-09-03-phase-1-baseline.md`
- Create: `docs/engine-audits/2026-09-03-engine-findings.md`
- Modify: `docs/plans/2026-09-02-product-hardening-program.md`

**Interfaces:**
- Consumes: Tasks 1–5.
- Produces: one reproducible command, exact trace metrics, and ranked findings routed to later phases.

- [ ] Define inclusion completeness as non-empty reason code + causal signal + specific or approved base-essential explanation. Require quantity evidence only for policy-sensitive or quantity>1 rows; report fixed singletons separately.
- [ ] Test classification with passport, shirts, weather jacket, custom item, shared umbrella, missing reason, and generic-only reason.
- [ ] Make `scripts/run_engine_audit.sh` run shared validation, Python tests, focused Swift suites, semantic golden report, input audit, and trace audit with fail-fast behavior.
- [ ] Publish baseline sections for fixture manifest, schema gaps, two-run determinism, quantity properties, authority/fallback matrix, surface-input coverage, trace metrics, Miami/Chicago gate, and evidence paths.
- [ ] Rank findings:

```text
P0 — crash/data loss, unsafe attribution, explicit-decision violation, nonsense
P1 — missing normal-trip coverage, material duplication, advertised input with no effect
P2 — weak explanation, polish, non-critical trace gap
```

Each finding names fixture/item, observed output, desired property, command, and destination phase.

- [ ] Run:

```bash
scripts/run_engine_audit.sh
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
npm --prefix api run preflight
```

- [ ] Close Phase 1 only when the report answers what every fixture produces, what changed, which inputs matter/do nothing, which decisions survive, which failures degrade safely, and which findings route to Phases 2–8.
- [ ] Commit evidence with `docs: close engine hardening phase 1`.

---

## Follow-on Phase Sequence

Each phase gets a separate task-level implementation plan at entry.

### Phase 2 — Context Model Hardening

Introduce immutable `TripContextSnapshot` compiled once from `TripContext`. Normalize dates, activities, bag semantics, party, weather quality, and existing `LaundryAccess.none/possible/planned`; return explicit `valid`, `normalized`, or `unsupportedButSafe` diagnostics. Keep UI/repository boundaries on `TripContext` during migration.

**Exit:** all fixtures compile deterministically; unknown activity, unknown bag, missing weather, invalid dates, empty party, and legacy laundry signals have tested outcomes; goldens stay unchanged until a family opts into the snapshot.

### Phase 3 — Clothing Needs and Quantity Hardening

Route clothing through explicit need/use inputs. Fix only Phase 1 quantity findings: wash-cycle plateau, formal-top overlap, bounds, bag/style ordering, workout frequency, swim rotation, and age buffers.

**Exit:** Tokyo laundry variants visibly diverge, 30 days plateaus, manual quantities survive, and the reviewed diff contains clothing quantity/trace changes only.

### Phase 4 — Footwear and Outerwear Coverage

Harden the closed capability vocabulary for running/walking/hiking/formal/water/snow footwear and light/warm/wind/rain/snow/formal layers. User-added/modified multifunction items claim coverage without being suppressed.

**Exit:** overlap fixtures avoid redundancy and every suppression names capabilities and covering items.

### Phase 5 — Surfaced Activity Contracts

Resolve every `missing` contract. Camping adds personal travel needs only: headlamp, warm layer, suitable footwear, sleep clothing where needed, insect repellent, water bottle, sun protection, and weather-supported rain protection. Exclude tents, sleeping bags, stoves, fuel, cookware, and campsite logistics. Unknown custom activities remain preserved and inert.

**Exit:** every surfaced activity is deterministic or explicitly context-only; Camping/Hiking effects are distinct and non-duplicative.

### Phase 6 — Weather Need Hardening

Use existing WeatherKit normalization to map precise, partial, seasonal, cached, and failed weather into conservative needs. Combine precise covered dates with seasonal uncovered dates without inventing precision.

**Exit:** hot+rain, cold+rain, wind+mild, heat+sun, hot-day/cool-night, snow+business, rain+hiking, and rain+couple pass; Phoenix lacks cold bloat; Anchorage gains conservative seasonal layers.

### Phase 7 — Central Constraints and User Authority

Centralize bag/style conflicts, sharing, dependencies, manual quantities, Not Needed, user-added items, ownership, and carrier. Priority: explicit current-trip decision → manual/Not Needed/user-added → current constraints → memory → accepted enrichment → defaults.

**Exit:** prepared+personal-item resolves visibly, shared semantics hold, owner/carrier remain distinct, and unrelated refreshes never override users.

### Phase 8 — Recommendation Trace Productization

Promote current provenance into complete inclusion, quantity, signal, need/capability, coverage, suppression, and constraint evidence. Only then expose Item Detail and row subtitles.

**Exit:** every generated item answers why it exists, why that quantity, and which signals mattered; fixed singletons avoid fake math; missing generated trace is zero.

### Phase 9 — Accepted Context Intelligence / M3B

**Entry requires both:** deterministic product gates green and M3A physical-device App Attest/UI exit gate green.

Interpret notes into known structured trip-level signals, show acceptance, and merge only accepted signals. Traveler-scoped interpretation requires an explicit safe contract; ambiguous family context is dropped.

### Phase 10 — Family Hardening and Memory Audit

Harden adult/teen/child/toddler/infant clothing and ownership. Diapers, formula, stroller, car seat, and medication stay explicit-only. Audit existing immutable memory events rather than rebuilding them.

### Phase 11 — Weather-Change V2 Integration

Run V2 needs/coverage through `WeatherChangeReconciler`. Existing items may satisfy a new weather need and yield no proposal. Remaining consequences stay pending until accepted.

### Engine V2 Product Gate

1. Miami beach and Chicago business are recognizable without labels.
2. Tokyo planned laundry is materially smaller than no laundry; 30 days plateaus.
3. Running+walking does not duplicate footwear blindly.
4. Rain+hiking produces sufficient, non-duplicative protection.
5. Quantity, Not Needed, custom items, owner, and carrier survive refreshes.
6. OpenAI, WeatherKit, and network failure leave a usable local list.
7. Every generated item has useful inclusion and quantity evidence.

Use targeted pairwise coverage across duration, bag, style, laundry, party, climate, weather quality, trip type, activities, overrides, connectivity, and lifecycle state—not the Cartesian product.

### Phase 12 — Lifecycle Features

Order: domain events → notifications → Final Check → post-trip review → Packing Memory derivation/UI. Notifications consume domain state, never WeatherKit directly. Final Check shows critical remaining items, not the whole list. Memory derives habits from events and never outranks current-trip decisions.

---

## Self-Review

- Phase 1 covers audit, expansion, semantic diffs, invariants, overrides/fallback, surfaced inputs, trace metrics, findings, and a one-command exit.
- Phases 2–12 cover context, quantities, coverage, activities, weather, constraints, explanation UI, traveler-safe intelligence, family behavior, proposal integration, and lifecycle features.
- Deliberately excluded: trip segments, travel advisories, trip-type multi-select, full camping logistics, and premature Packing Memory UI.
- Existing Engine V2 components are reused; unavailable evidence is recorded honestly.
- Device verification stays deferred/unchecked and M3B stays blocked.
- Current type names are preserved: `LaundryAccess`, `TripContext`, `PackingItemDraft`, `EngineGeneration`, `CoverageSuppression`, `ConstraintDecision`, `RecommendationOverrideDraft`, and `WeatherChangeReconciler`.
- Every behavior phase ends with focused tests, semantic golden review, and a separate commit.

