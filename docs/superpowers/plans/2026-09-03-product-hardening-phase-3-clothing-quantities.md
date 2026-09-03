# PackWise Product Hardening Phase 3 — Clothing Needs and Quantity Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate clothing quantity decisions to normalized trip context and make each clothing family produce sensible, bounded, explainable quantities across short, long, laundry, activity, style, bag, and supported age contexts.

**Architecture:** `PackingEngine.generateDetailed` continues to compile one `TripContextSnapshot`, but only the clothing quantity path receives a clothing-specific projection of it; weather, footwear, coverage, constraints, shared quantities, care items, and all other families remain on `TripContext`. `ClothingQuantityEngine` returns a value, rendered reason, and structured `ClothingQuantityEvidence` from explicit per-family policies. The evidence lives on `PackingItemDraft` and in the test golden schema for now; Phase 3 does not add UI or SwiftData schema work.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI domain models, JSON catalog fixtures, Python semantic-golden audit scripts, Xcode 18/iOS 18 simulator tests.

## Global Constraints

- Work on `product-hardening-phase1` from `a73f4cf68016d3704a7f74e79fe49fa9afde13d3` and preserve the unrelated signing change in the main checkout.
- Phase 3 owns clothing needs and quantities only. Do not change footwear substitution, outerwear capability coverage, Camping rules, weather need generation, shared-item constraints, GPT/context intelligence, notifications, lifecycle, or presentation.
- Use `TripContextSnapshot` only for clothing quantity inputs; do not migrate unrelated engine families for consistency.
- Explicit user quantities, Not Needed overrides, user-added items, packed quantities, owner, and carrier always win.
- Ambiguous traveler attribution resolves to don't infer. Age buffers apply only from the explicitly resolved traveler and existing `party.json` multipliers.
- `LaundryAccess.planned <= .possible <= .none` for policies declaring laundry sensitivity. Packing-style and bag ordering apply only when declared by that policy.
- Planned-laundry 30-day quantities stay within each policy's documented tolerance of the 15-day result once its wash cycle dominates.
- Golden changes may include clothing quantities and clothing quantity evidence only. Added/removed items, non-clothing quantity changes, coverage changes, constraint changes, ownership/carrier changes, unrelated reasons, and user-authority changes are regressions.
- The Phase 1 F-1 legacy-schema diff gap remains P2 unless it blocks comparing Phase 3 against `a73f4cf`; do not fix it preemptively.
- Run `python3 scripts/validate_shared.py` after catalog edits. Presentation remains frozen, physical-device verification remains deferred, and M3B/M3C remain blocked.
- Stop at the Phase 3 exit gate. Do not begin Phase 4.

## File Map

- Modify `ios/PackWise/Domain/TripContextSnapshot.swift`: normalize explicit dated activity occurrences without inventing uses for undated selections.
- Modify `ios/PackWise/Domain/Packing/ClothingQuantity.swift`: define clothing-only inputs, explicit family policies, quantity resolution, and structured evidence.
- Modify `ios/PackWise/Domain/Packing/Catalog.swift`: add optional domain-only structured quantity evidence to `PackingItemDraft`; do not change SwiftData schema or UI.
- Modify `ios/PackWise/Domain/Packing/PackingEngine.swift`: thread the one compiled snapshot only to clothing quantity resolution and preserve user-modified rows before policy evaluation.
- Modify `shared/catalog/clothing.json`: route `clothing.swimsuit` through its own clothing quantity kind so drying rotation is explicit.
- Modify `ios/PackWiseTests/TripContextSnapshotTests.swift`: prove dated-use normalization and unknown/undated fail-safe behavior.
- Modify `ios/PackWiseTests/ClothingQuantityTests.swift`: prove family behavior, ordering, plateaus, overlap, age buffers, snapshot use, and user authority.
- Modify `ios/PackWiseTests/GoldenEngineTests.swift`: serialize structured clothing quantity evidence and add required-fixture semantic assertions.
- Modify `scripts/report_engine_goldens.py` and `scripts/tests/test_report_engine_goldens.py` only as needed to classify the new current-schema `quantityEvidence` field as a trace change; do not add backward compatibility for F-1.
- Regenerate only `ios/PackWiseTests/Goldens/*.json` rows whose clothing quantity or clothing quantity evidence intentionally changes.
- Create `docs/engine-audits/2026-09-03-phase-3-clothing-quantities.md`: reviewed semantic diff, invariant results, routed findings, commands, counts, and exit-gate state.
- Update `docs/plans/2026-09-02-product-hardening-program.md`: mark Phase 3 closed only after every gate passes and name Phase 4 as next but unopened.

---

### Task 1: Normalize Clothing Activity Uses and Define the Clothing Input Boundary

**Files:**
- Modify: `ios/PackWise/Domain/TripContextSnapshot.swift`
- Modify: `ios/PackWise/Domain/Packing/ClothingQuantity.swift`
- Modify: `ios/PackWiseTests/TripContextSnapshotTests.swift`
- Modify: `ios/PackWiseTests/ClothingQuantityTests.swift`

**Interfaces:**
- Consumes: `TripContextCompiler.compile(_:rules:) -> TripContextSnapshot`, `TripContext.datedActivities`, `TripContextSnapshot.knownActivityIDs`, and normalized `party`, `durationDays`, `bagType`, `packingStyle`, `laundryPlan`.
- Produces: `TripContextSnapshot.knownDatedActivityUses: [String: Int]` and `ClothingQuantityContext(snapshot:)` containing only `days`, `style`, `bag`, `laundry`, known selected activity IDs, explicit dated-use counts, and normalized party.

- [ ] **Step 1: Write failing snapshot tests for exact activity-use semantics.** Add tests that provide repeated dated `running` entries and expect their distinct trip dates to count, provide only an undated `running` selection and expect no manufactured dated count, and provide dated `cosplayConvention` entries and expect them to remain unknown rather than entering known-use counts.

```swift
@Test func knownDatedActivitiesCountDistinctUseDatesWithoutInventingUndatedUses() throws {
    var context = baseContext()
    context.activities = ["running"]
    context.datedActivities = [
        DatedActivity(activityID: "running", date: context.startDate),
        DatedActivity(activityID: "running", date: context.startDate),
        DatedActivity(activityID: "running", date: Calendar.current.date(byAdding: .day, value: 2, to: context.startDate))
    ]
    let snapshot = TripContextCompiler.compile(context, rules: try rules())
    #expect(snapshot.knownDatedActivityUses["running"] == 2)
}
```

- [ ] **Step 2: Run the focused tests and verify RED.** Run `xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PackWiseTests/TripContextSnapshotTests -only-testing:PackWiseTests/ClothingQuantityTests`. Expected: compile failure because `knownDatedActivityUses` and `ClothingQuantityContext` do not exist.

- [ ] **Step 3: Add the minimal normalized use map and clothing projection.** Normalize activity IDs through the same vocabulary as `knownActivityIDs`, discard nil dates, deduplicate duplicate same-day occurrences, ignore out-of-trip dates, and include only IDs present in `rules.activities`. Define this exact clothing projection:

```swift
struct ClothingQuantityContext: Hashable, Sendable {
    var days: Int
    var style: PackingStyle
    var bag: BagType
    var laundry: LaundryAccess
    var selectedActivityIDs: Set<String>
    var datedActivityUses: [String: Int]
    var party: TripParty

    init(snapshot: TripContextSnapshot) {
        days = snapshot.durationDays
        style = snapshot.packingStyle
        bag = snapshot.bagType
        laundry = snapshot.laundryPlan
        selectedActivityIDs = Set(snapshot.knownActivityIDs)
        datedActivityUses = snapshot.knownDatedActivityUses
        party = snapshot.party
    }
}
```

- [ ] **Step 4: Run the focused tests and verify GREEN.** Expected: all snapshot and clothing tests pass with no behavior changes yet.

- [ ] **Step 5: Run the semantic diff checkpoint.** Run `python3 scripts/report_engine_goldens.py --baseline-ref a73f4cf --candidate ios/PackWiseTests/Goldens --format markdown`. Expected: clean; no golden files changed.

- [ ] **Step 6: Commit the boundary.** Commit only the four Task 1 files with `feat: derive clothing uses from normalized trip context`.

### Task 2: Replace Implicit Clothing Math with Explicit Family Policies and Evidence

**Files:**
- Modify: `ios/PackWise/Domain/Packing/ClothingQuantity.swift`
- Modify: `ios/PackWise/Domain/Packing/Catalog.swift`
- Modify: `ios/PackWiseTests/ClothingQuantityTests.swift`

**Interfaces:**
- Consumes: `ClothingQuantityContext`, `ClothingNeedPolicy.byKind`, explicit appearance offsets, and the existing age multipliers from `party.json`.
- Produces: `ClothingQuantityResult(value: Int, reason: String, evidence: ClothingQuantityEvidence)` and optional `PackingItemDraft.quantityEvidence`.

- [ ] **Step 1: Write failing per-family behavior tests.** Pin underwear/socks planned/possible/none ordering; tops' declared style/bag divergence; bottoms plateauing earlier than tops; sleepwear staying 1–2 instead of scaling; explicit three-run workout use producing three sets without laundry and fewer with planned laundry; swim drying rotation staying 1–2; and one-day floors (`tops`, underwear, socks at 2; bottoms, sleepwear, workout/swim at 1 when needed).

```swift
@Test func explicitWorkoutUsesDriveQuantityInsteadOfTripLength() throws {
    let policy = try #require(ClothingNeedPolicy.byKind["workout_top"])
    var context = clothingContext(days: 15, laundry: .none)
    context.selectedActivityIDs = ["running"]
    context.datedActivityUses = ["running": 3]
    #expect(ClothingQuantityEngine.compute(policy, context: context).value == 3)
    context.days = 30
    #expect(ClothingQuantityEngine.compute(policy, context: context).value == 3)
}
```

- [ ] **Step 2: Write failing evidence tests.** For a planned-laundry daily item assert policy ID, basis/use count, wash interval, laundry adjustment, style reuse/buffer, resolved bag cap and whether it bound, formal/appearance offset, supported age multiplier, and final result are machine-readable. For a fixed singleton outside `ClothingNeedPolicy`, assert evidence remains nil.

- [ ] **Step 3: Run `ClothingQuantityTests` and verify RED.** Expected: missing result/evidence APIs and failing workout/swim family expectations.

- [ ] **Step 4: Implement explicit policies and collapse false sensitivity granularity.** Replace `NeedSensitivity.low/high` with declared influence membership so no policy claims a distinction the engine cannot honor. Keep separate usage cases for daily wear, high-reuse bottoms, sleep rotation, scheduled workout use, swim drying rotation, and appearance wear. Resolve in this order: required uses -> reuse -> laundry cycle -> declared style adjustment -> declared bag cap -> supported age multiplier -> family floor/maximum. Planned laundry uses the policy wash interval; possible laundry moves partway toward the no-laundry count; no laundry remains duration/use-sensitive until the family maximum.

- [ ] **Step 5: Return structured evidence with the computed value.** Use a Codable/Hashable/Sendable evidence value with exact facts, not prose:

```swift
struct ClothingQuantityEvidence: Hashable, Codable, Sendable {
    var policyID: String
    var basis: String
    var requiredUses: Int
    var wearsPerItem: Double
    var washIntervalDays: Int?
    var laundryPlan: LaundryAccess
    var laundryReduced: Bool
    var styleBuffer: Int
    var bagCap: Int?
    var bagCapApplied: Bool
    var appearanceOffsetUses: Int
    var ageMultiplier: Double?
    var quantity: Int
}
```

- [ ] **Step 6: Verify GREEN and refactor without changing behavior.** Run `ClothingQuantityTests`; then rerun after removing obsolete `NeedSensitivity` and dead sleepwear branches. Expected: all tests pass and every declared influence has at least one strict divergence while undeclared influences stay inert.

- [ ] **Step 7: Run the semantic diff checkpoint.** Expected: still clean because the new engine result is not wired into `PackingEngine` yet.

- [ ] **Step 8: Commit the policy unit.** Commit Task 2 files with `feat: harden clothing quantity policies and evidence`.

### Task 3: Migrate the Engine Clothing Consumer, Swim Rotation, and Appearance Overlap

**Files:**
- Modify: `ios/PackWise/Domain/Packing/PackingEngine.swift`
- Modify: `shared/catalog/clothing.json`
- Modify: `ios/PackWiseTests/ClothingQuantityTests.swift`
- Modify: `ios/PackWiseTests/GoldenEngineTests.swift`

**Interfaces:**
- Consumes: the one snapshot compiled in `generateDetailed`, `ClothingQuantityContext(snapshot:)`, and `ClothingQuantityResult`.
- Produces: clothing drafts whose `quantity`, `quantityReason`, and `quantityEvidence` come from the normalized clothing policy path; unrelated drafts retain existing behavior and nil clothing evidence.

- [ ] **Step 1: Write failing engine integration tests.** Assert a deliberately stale raw `durationDays` cannot alter clothing because snapshot date math wins; legacy laundry chip/notes normalization reaches clothing through `snapshot.laundryPlan`; exact dated workouts beat total duration; the normalized snapshot party is used for an explicitly attributed supported age multiplier; and user-modified clothing keeps quantity, packed quantity, and existing evidence untouched.

- [ ] **Step 2: Write failing swim and appearance tests.** Change the swimsuit test expectation to a drying-rotation policy (never one per day, max two, and planned laundry no heavier than possible/no laundry). Assert business plus `niceDinner` merges canonical appearance items once and subtracts each resolved appearance garment at most once from daily-top uses; adding `running` does not inflate formal/nice-outfit quantities.

- [ ] **Step 3: Run focused tests and verify RED.** Expected: raw-context duration/laundry still drive clothing, swimsuit is fixed at one, and structured evidence is absent.

- [ ] **Step 4: Thread snapshot only to clothing.** Pass `snapshot` from `generateDetailed` into `generateSimple`/`generateForParty` and then `applyQuantities`, but continue passing raw `TripContext` to rule suggestions, coverage, constraints, warm layers, care quantities, legacy quantity kinds, and shared quantity logic. Resolve travelers from `snapshot.party`; return user-modified rows before any clothing policy call.

- [ ] **Step 5: Route swimsuit and appearance offsets.** Change only `clothing.swimsuit.quantity_kind` from `one` to the explicit swim policy kind. Compute resolved appearance units once per owner group from canonical formal/nice-outfit rows; never count multiple source signals as multiple garments. Feed that offset only to the daily-top policy.

- [ ] **Step 6: Preserve output authority.** Add/retain integration assertions that manual quantities, Not Needed overrides, user-added items, packed state, owner, and carrier survive regeneration or diff calculation. Do not auto-apply `RecommendationDiff.quantityChanges`.

- [ ] **Step 7: Verify focused suites and shared data.** Run `python3 scripts/validate_shared.py` and the focused `TripContextSnapshotTests`, `ClothingQuantityTests`, `PackingEngineTests`, `ConstraintTests`, and `WeatherChangeTests`. Expected: all pass.

- [ ] **Step 8: Record goldens and intentionally stop on the recording failure.** Run `PACKWISE_RECORD_GOLDENS=1 xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PackWiseTests/GoldenEngineTests`. Expected: golden files are rewritten and the test fails with the deliberate review message.

- [ ] **Step 9: Review the semantic diff against `a73f4cf`.** Run the reporter and classify every row under `EXPECTED CLOTHING QUANTITY CHANGES` or `UNEXPECTED BEHAVIOR CHANGES`. Expected unexpected bucket: empty. Reject any added/removed item, non-clothing quantity, coverage, constraint, ownership/carrier, unrelated reason, or user-authority change.

- [ ] **Step 10: Run goldens without record mode.** Expected: `GoldenEngineTests` pass against reviewed files.

- [ ] **Step 11: Commit behavior and reviewed goldens.** Commit Task 3 files and intended golden files with `feat: apply normalized clothing quantities in packing engine`.

### Task 4: Prove Required Fixtures, Ordering, Plateaus, and Authority

**Files:**
- Modify: `ios/PackWiseTests/ClothingQuantityTests.swift`
- Modify: `ios/PackWiseTests/GoldenEngineTests.swift`
- Modify if required for current schema only: `scripts/report_engine_goldens.py`
- Modify if reporter changes: `scripts/tests/test_report_engine_goldens.py`

**Interfaces:**
- Consumes: generated clothing evidence and the 27-fixture Phase 1 ledger.
- Produces: executable Phase 3 exit-gate assertions and a semantic report that classifies `quantityEvidence` as a trace-only field.

- [ ] **Step 1: Add required-fixture assertions.** Compare Tokyo 15-day planned vs none, Tokyo 30-day planned vs 15-day planned, Reykjavik 64-day planned as the ledger's documented Anchorage-equivalent long-trip fixture, one-day Chicago, Miami beach/light/possible, Chicago business/prepared/none, business+running, and the family/toddler fixture. Assert recognizable clothing differences and only the policies relevant to each fixture.

- [ ] **Step 2: Add matrix properties.** For every declared-sensitive policy and days `[1, 3, 5, 8, 10, 15, 21, 30, 64]`, assert the requested five-point chain is non-decreasing. Require strict divergence separately for each declared influence. Assert 15/30 planned-laundry tolerance per policy; do not impose a 15/30 plateau on no-laundry daily essentials.

- [ ] **Step 3: Add authority properties.** Assert manual quantity and packed count survive unrelated weather/context refresh, Not Needed stays rejected, and user-added items survive. Include both solo and party clothing cases so snapshot migration cannot bypass owner-scoped authority.

- [ ] **Step 4: Run focused tests and verify RED where coverage is missing.** Any failure must identify a specific family/fixture/invariant, not a broad snapshot mismatch.

- [ ] **Step 5: Make only minimal clothing-policy corrections.** Adjust policy constants or evidence plumbing only to satisfy the failing Phase 3 property. Route any footwear, outerwear, Camping, seasonal weather, sharing, or unrelated discovery to findings instead of changing that subsystem.

- [ ] **Step 6: Verify GREEN and run semantic diff.** Expected: focused tests pass; semantic report has only reviewed clothing quantity/evidence rows. If the reporter needs `quantityEvidence`, add it to `_TRACE_FIELDS`, update its parser tests first, and do not address missing legacy `carrier` fields.

- [ ] **Step 7: Commit the acceptance suite separately.** Commit tests/reporter-only changes with `test: enforce phase 3 clothing quantity gates`.

### Task 5: Full Verification, Evidence, and Phase 3 Close

**Files:**
- Create: `docs/engine-audits/2026-09-03-phase-3-clothing-quantities.md`
- Modify: `docs/plans/2026-09-02-product-hardening-program.md`

**Interfaces:**
- Consumes: all Task 1–4 commits and fresh verification output.
- Produces: one evidence commit that closes Phase 3 without opening Phase 4.

- [ ] **Step 1: Run the semantic golden diff and save exact counts.** Run `python3 scripts/report_engine_goldens.py --baseline-ref a73f4cf --candidate ios/PackWiseTests/Goldens --format markdown`. Record `EXPECTED CLOTHING QUANTITY CHANGES` by fixture/item and an explicit `UNEXPECTED BEHAVIOR CHANGES: none` only if the output proves it.

- [ ] **Step 2: Run the one-command engine audit.** Run `scripts/run_engine_audit.sh`. Because its HEAD baseline is the working Phase 3 tree after goldens are committed, expected result is all six steps passing and a clean current-tree golden check.

- [ ] **Step 3: Run full iOS tests.** Run `xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`. Record exact test/suite/failure counts from the fresh result.

- [ ] **Step 4: Run shared and API gates.** Run `python3 scripts/validate_shared.py` and `npm --prefix api run preflight`. Record exact counts/output and exit codes.

- [ ] **Step 5: Audit scope and migration mechanically.** Use `rg` and `git diff a73f4cf --` to prove the only new `TripContextSnapshot` consumer is the clothing quantity path, no presentation/SwiftData files changed, the main checkout signing diff still exists, and no Phase 4–6 subsystem changed.

- [ ] **Step 6: Write the evidence report.** Include exact commits; policy tables and approved plateau tolerances; snapshot fields consumed; required-fixture quantities; golden diff counts; authority assertions; trace/evidence coverage; all commands and counts; F-1 status; routed findings for Phases 4–6/8/10; presentation/device/M3B/M3C gate state; and a ten-item Phase 3 exit checklist.

- [ ] **Step 7: Mark Phase 3 closed, not Phase 4 started.** Update the program status only after Steps 1–6 are green. Keep physical-device verification deferred and M3B/M3C blocked.

- [ ] **Step 8: Commit evidence separately.** Commit only the evidence/program docs with `docs: close phase 3 clothing quantity hardening`.

- [ ] **Step 9: Run post-commit verification and report.** Re-run `git status --short --branch`, `git log --oneline a73f4cf..HEAD`, the semantic diff against `a73f4cf`, and any command whose result could have changed with the evidence commit. Stop and report; do not begin Phase 4.

## Self-Review

- Spec coverage: Tasks 1–4 cover normalized snapshot adoption, family-specific uses, laundry ordering, declared bag/style sensitivity, short floors, long plateaus, workout use, swim rotation, appearance overlap, supported age buffers, structured evidence, user authority, and all named ledger fixtures. Task 5 covers every required verification and the separate evidence commit.
- Scope coverage: footwear/outerwear/Camping/weather/shared constraints/GPT/lifecycle/presentation remain explicitly excluded and are findings-only.
- Golden coverage: the reporter compares against the exact Phase 2 HEAD `a73f4cf`; F-1 is untouched because current schema is compatible. Added/removed items and all non-clothing axes are explicit reject conditions.
- Type consistency: `TripContextSnapshot.knownDatedActivityUses` feeds `ClothingQuantityContext.datedActivityUses`; `ClothingQuantityEngine` returns `ClothingQuantityResult`; its `ClothingQuantityEvidence` is attached to `PackingItemDraft.quantityEvidence` and serialized by `GoldenEngineTests`.
- Placeholder scan: no TBD/TODO/implement-later steps remain. Policy tuning is constrained to named properties and must follow a failing Phase 3 test.
- Commit separation: plan, normalized boundary, policy/evidence, engine behavior/goldens, acceptance suite, and closing evidence are independently reviewable.

