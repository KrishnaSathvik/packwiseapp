# PackWise Product Hardening Phase 7 — Central Constraints and User Authority Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `ConstraintResolver` the single typed authority for conflicts
that happen after needs, candidates, quantities, and coverage are known —
party sharing membership/quantity, the explicit-user-authority gate, and the
already-centralized bag/style conflict family — with the priority hierarchy
proven by a real multi-dimensional test, not asserted. Decide and close
finding F-5 (Camping flashlight party sharing) as a genuine product
decision. Fill the thirteen required test gates the design doc found
missing.

**Architecture:** Full detail in
`docs/superpowers/specs/2026-09-04-product-hardening-phase-7-central-constraints-design.md`.
Summary: `ConstraintResolver` gains `SharingResolution`/`sharingResolution(for:rules:context:party:)`
(replacing two duplicated `Set(rules.party.sharedByDefault)` checks and the
free-standing `sharedQuantity`/`sharedQuantityReason` pair, all moved
verbatim) and `hasUserAuthority(_:)`/`isExplicitlyRemoved(...)` (replacing
four independently-written `isUserAdded || isUserModified` / removed-override
checks with two functions everyone calls). `optionalRuling` (bag/style),
`CatalogItem.companions` (dependencies), and `PartyInvariants` (owner/carrier
structural validity) are already correct, already closed authorities and are
not touched beyond adding tests. F-5 resolves to **personal-per-traveler,
decided deliberately, no behavior change** — a flashlight is a personal
safety item, not scarce infrastructure like an adapter or communal like
sunscreen.

**Tech Stack:** Swift 6, Swift Testing, JSON shared catalog/rules, JSON
golden fixtures, Python audit/report tooling, Xcode/iOS 18 simulator tests.

## Global Constraints

- Work on `product-hardening-phase1` from `e50592b`; preserve every Phase
  1–6 commit and the unrelated signing change in the main checkout.
- Follow the approved design at
  `docs/superpowers/specs/2026-09-04-product-hardening-phase-7-central-constraints-design.md`.
- Do not rebuild, rewire, or duplicate `CatalogItem.companions`,
  `PartyInvariants`, or `optionalRuling` — they are already the closed
  authority for their questions. Move logic only where the design doc names
  a move (party sharing, explicit-authority gate).
- No new dependency graph/solver. Dependencies stay the existing
  `companions: [String]` catalog field.
- No new `PackingCapability`, `ActivityNeed`, or `WeatherSignal` case. This
  phase adds no capability, activity, or weather behavior.
- No change to `shared/rules/party.json`'s data. `sharedByDefault` and
  `sharingPolicies` are read, not edited — F-5 needs no new row, and no
  other task in this plan adds one.
- `SharingPolicy.personalOnly`'s semantics are made truthful and tested in
  Task 1 (design doc, "Required amendment") — it must never produce an
  `ownershipType == .shared` draft with `travelerID == nil`. This is a
  required amendment, not optional polish: do not defer it. It is tested
  against a synthetic, test-local policy row only — no existing catalog
  item is assigned `.personalOnly`, and `party.json` gains no new row.
- Task 1 and Task 2 (the two refactors) must each be a **zero-diff gate**:
  `report_engine_goldens.py --baseline-ref c9cbb76` shows zero row changes
  before either task's behavior-adjacent test is trusted. `c9cbb76` is
  Phase 6's closing commit and the semantic baseline for every golden diff
  in this plan — not `e50592b`, which only adds the unrelated pycache
  housekeeping commit on top of it.
- User authority is preserved and must be provable under compounded
  change: manual quantity, Not Needed, user-added items, packed state, and
  explicit owner/carrier survive not only their own single-dimension
  refresh (already proven — see the design doc's "Existing evidence") but a
  regeneration that changes weather, activities, and duration
  simultaneously (Task 2).
- Golden regressions include any clothing/footwear/quantity/coverage/
  activity/weather change outside the fixtures each task names. Run
  `report_engine_goldens.py --baseline-ref c9cbb76` after every task that
  touches `PackingEngine.swift` or `ConstraintResolver.swift`.
- Phase 7 does not own Phase 8 (trace productization), Phase 9+ (context
  intelligence), or presentation/lifecycle work. Presentation stays frozen,
  physical-device verification stays deferred, M3B/M3C remain blocked.
- Do not edit `docs/plans/2026-09-02-product-hardening-program.md` before
  Task 8. Stop at the Phase 7 exit gate; do not begin Phase 8.

---

## File Map

- Modify `ios/PackWise/Domain/Packing/ConstraintResolver.swift`: add
  `SharingResolution`, `sharingResolution(for:rules:context:party:)` (Task
  1); add `hasUserAuthority(_:)`, `isExplicitlyRemoved(...)` (Task 2).
- Modify `ios/PackWise/Domain/Packing/PackingEngine.swift`: route
  `generateForParty`, `addCompanions`, `applyQuantities` through the new
  sharing resolution (Task 1); route `resolve`, `applyQuantities`,
  `addCompanions`, `isRemoved` through the new authority gate (Task 2);
  remove the now-dead `sharedQuantity`/`sharedQuantityReason`/inline
  `isRemoved` bodies once callers move (Tasks 1, 2).
- Modify `ios/PackWiseTests/ConstraintTests.swift`: all new authority,
  sharing-policy, and priority-hierarchy tests (Tasks 1, 2, 4, 5, 6, 7).
- Modify `ios/PackWiseTests/ActivityContractTests.swift`: F-5 decision test
  rewrite (Task 3).
- Modify `shared/fixtures/golden/golden-fixtures.json`; add new JSON
  outputs under `ios/PackWiseTests/Goldens/` (Task 7).
- Create `docs/engine-audits/2026-09-04-phase-7-central-constraints-and-user-authority.md`
  (Task 8).
- Modify `docs/plans/2026-09-02-product-hardening-program.md`: close Phase
  7 only after all gates pass, in Task 8 only.

---

### Task 1: Centralize party sharing resolution in `ConstraintResolver`

**Files:**
- Modify: `ios/PackWise/Domain/Packing/ConstraintResolver.swift`
- Modify: `ios/PackWise/Domain/Packing/PackingEngine.swift`
- Modify: `ios/PackWiseTests/ConstraintTests.swift`

**Interfaces:**
- Consumes: `PartyRulesFile.sharedByDefault: [String]`,
  `.sharingPolicies: [String: SharingPolicyRule]` (`Catalog.swift:288,297`,
  unchanged), `TripParty` (unchanged).
- Produces: `ConstraintResolver.SharingResolution`,
  `ConstraintResolver.sharingResolution(for:rules:context:party:) -> SharingResolution`.

- [ ] **Step 1: Write the failing characterization test.** This pins
  today's exact `sharedByDefault`/`sharingPolicies` output through the new
  function before any call site moves, so the refactor has a fixed target.

```swift
// ConstraintTests.swift — new `// MARK: - Party sharing resolution` section

/// The one function `generateForParty`/`addCompanions`/`applyQuantities`
/// all ask instead of independently testing `sharedByDefault` membership.
@Test func sharingResolutionMatchesTodaysSharedByDefaultMembership() throws {
    let rules = try SharedLibrary.rules()
    let solo = TripParty.solo()
    let couple = TripParty(travelMode: .couple, travelers: [Traveler.primarySelf(), Traveler(name: "Sam", role: .partner, ageGroup: .adult)])
    let ctx = context(destination: try destination("Chicago"), party: couple)

    // Shared, singlePerParty (no explicit policy row falls to the default).
    let firstAid = ConstraintResolver.sharingResolution(
        for: "health.first_aid", rules: rules.party, context: ctx, party: couple
    )
    guard case .shared(let quantity, _) = firstAid else {
        Issue.record("expected health.first_aid to resolve shared")
        return
    }
    #expect(quantity == 1)

    // Not in sharedByDefault → personal, regardless of party size.
    #expect(ConstraintResolver.sharingResolution(
        for: "miscellaneous.flashlight", rules: rules.party, context: ctx, party: couple
    ) == .personal)
    #expect(ConstraintResolver.sharingResolution(
        for: "miscellaneous.flashlight", rules: rules.party, context: context(destination: try destination("Chicago"), party: solo), party: solo
    ) == .personal)
}
```

- [ ] **Step 1b: Write the failing `personalOnly` contract tests (required
  amendment).** `SharingPolicy.personalOnly` is declared, has zero
  `sharingPolicies` rows using it, and zero test coverage — reading
  `applyQuantities` shows it currently falls through to an
  `ownershipType == .shared` draft with `travelerID == nil` if anything ever
  used it. This is not a routed finding: it is party-sharing semantics, and
  Phase 7 owns party-sharing semantics. Fix it now, while zero real data
  exercises the case, so the fix itself changes zero golden output. Test
  against a synthetic, test-local policy row on an ordinary real item — do
  **not** add a `sharingPolicies` row to `shared/rules/party.json`, since no
  current catalog item independently needs `.personalOnly`.

```swift
/// `.personalOnly` must behave exactly like "not shared" — one draft per
/// traveler, real `travelerID`, `ownershipType == .personal` — never an
/// `ownershipType == .shared` draft with `travelerID == nil` produced by
/// falling through `applyQuantities`'s old shared-quantity branch. Tested
/// against a synthetic policy row so no `party.json` row is added; a real
/// per-traveler item (`toiletries.toothbrush`) stands in as the subject so
/// the assertion is about actual generated items, not the bare function.
private func rulesWithSyntheticPersonalOnly(for canonicalItemID: String = "toiletries.toothbrush") throws -> PackingRulesFile {
    var rules = try SharedLibrary.rules()
    rules.party.sharedByDefault.append(canonicalItemID)
    rules.party.sharingPolicies[canonicalItemID] = SharingPolicyRule(policy: .personalOnly, per: nil, min: 1, value: 1)
    return rules
}

@Test func personalOnlySoloProducesOneOwnedPersonalItem() throws {
    let engine = PackingEngine(catalog: try SharedLibrary.catalog(), rules: try rulesWithSyntheticPersonalOnly())
    let items = engine.generate(context: context(destination: try destination("Chicago"), party: .solo()))
    let matches = items.filter { $0.canonicalItemID == "toiletries.toothbrush" }
    #expect(matches.count == 1)
    #expect(matches.allSatisfy { $0.ownershipType == .personal && $0.travelerID != nil })
}

@Test func personalOnlyCoupleProducesOnePersonalRowPerTraveler() throws {
    let engine = PackingEngine(catalog: try SharedLibrary.catalog(), rules: try rulesWithSyntheticPersonalOnly())
    let couple = TripParty(travelMode: .couple, travelers: [Traveler.primarySelf(), Traveler(name: "Sam", role: .partner, ageGroup: .adult)])
    let items = engine.generate(context: context(destination: try destination("Chicago"), party: couple))
    let matches = items.filter { $0.canonicalItemID == "toiletries.toothbrush" }
    #expect(matches.count == 2)
    #expect(matches.allSatisfy { $0.ownershipType == .personal })
    #expect(Set(matches.compactMap(\.travelerID)) == Set(couple.travelers.map(\.id)))
}

@Test func personalOnlyFamilyNeverProducesAnOwnerlessSharedDraft() throws {
    let engine = PackingEngine(catalog: try SharedLibrary.catalog(), rules: try rulesWithSyntheticPersonalOnly())
    let family = TripParty(travelMode: .family, travelers: [
        Traveler.primarySelf(),
        Traveler(name: "Sam", role: .partner, ageGroup: .adult),
        Traveler(name: "Emma", role: .child, ageGroup: .child)
    ])
    let items = engine.generate(context: context(destination: try destination("Chicago"), party: family))
    let matches = items.filter { $0.canonicalItemID == "toiletries.toothbrush" }
    #expect(matches.count == family.travelers.count)
    // The exact defect this test exists to prevent: never travelerID == nil
    // merely because a .personalOnly item fell through the old shared path.
    #expect(matches.allSatisfy { $0.ownershipType != .shared && $0.travelerID != nil })
}

/// The pure-function boundary, so a future edit to `sharingResolution`
/// cannot silently reintroduce the fallthrough without failing here first.
@Test func sharingResolutionNeverReturnsSharedForPersonalOnlyPolicy() throws {
    let rules = try rulesWithSyntheticPersonalOnly()
    let result = ConstraintResolver.sharingResolution(
        for: "toiletries.toothbrush", rules: rules.party,
        context: context(destination: try destination("Chicago")), party: .solo()
    )
    #expect(result == .personal)
}
```

- [ ] **Step 2: Run and verify RED.** Run:

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/ConstraintTests
```

Expected: compile failure — `ConstraintResolver.sharingResolution` and
`SharingResolution` do not exist yet.

- [ ] **Step 3: Add `SharingResolution` and `sharingResolution(for:rules:context:party:)` to `ConstraintResolver.swift`.**
  Move `sharedQuantity`/`sharedQuantityReason`'s bodies verbatim from
  `PackingEngine.swift:1008-1043`; do not change the arithmetic or the
  umbrella/generic-reason branching.

```swift
extension ConstraintResolver {
    /// Whether an item is shared across the party or stays personal, and if
    /// shared, its resolved quantity and user-facing reason. The one place
    /// `PackingEngine` asks this, replacing two independent
    /// `sharedByDefault` membership checks and the free-standing
    /// `sharedQuantity`/`sharedQuantityReason` pair.
    enum SharingResolution: Hashable, Sendable {
        case personal
        case shared(quantity: Int, reason: String)

        var isShared: Bool { if case .shared = self { true } else { false } }
    }

    static func sharingResolution(
        for canonicalItemID: String,
        rules: PartyRulesFile,
        context: TripContext,
        party: TripParty
    ) -> SharingResolution {
        guard rules.sharedByDefault.contains(canonicalItemID) else { return .personal }
        let policy = rules.sharingPolicies[canonicalItemID]
            ?? SharingPolicyRule(policy: .singlePerParty, per: nil, min: 1, value: 1)
        // Required amendment: a `.personalOnly` item never reaches the
        // shared-draft path at all — `generateForParty` calls `.isShared`
        // (Step 4), so this early return is what keeps such an item on the
        // ordinary per-traveler personal path with a real `travelerID`,
        // closing the fallthrough-to-ownerless-shared-draft bug Step 1b
        // tests. This is the fix, not a stub — do not remove it.
        guard policy.policy != .personalOnly else { return .personal }
        let quantity = sharedQuantity(policy, context: context, party: party)
        let reason = sharedQuantityReason(canonicalItemID, quantity: quantity, context: context, party: party)
        return .shared(quantity: quantity, reason: reason)
    }

    private static func sharedQuantity(_ rule: SharingPolicyRule, context: TripContext, party: TripParty) -> Int {
        let minimum = rule.min ?? 1
        let per = max(1, rule.per ?? 1)
        switch rule.policy {
        case .singlePerParty, .personalOnly:
            return rule.value ?? 1
        case .scaleByParty:
            return max(minimum, Int((Double(party.travelers.count) / Double(per)).rounded(.up)))
        case .scaleByDevices:
            return max(minimum, Int((Double(max(1, party.adults.count)) / Double(per)).rounded(.up)))
        case .scaleByDurationAndParty:
            return max(minimum, Int((Double(party.travelers.count * context.durationDays) / Double(per)).rounded(.up)))
        }
    }

    private static func sharedQuantityReason(_ canonical: String, quantity: Int, context: TripContext, party: TripParty) -> String {
        // Moved verbatim from PackingEngine.sharedQuantityReason. Reason
        // rendering still needs `ReasonRenderer`/`rules.reasons`, so this
        // stays a plain-string fallback builder here and PackingEngine's
        // caller re-renders through its own `render(_:_:fallback:)` if a
        // templated string exists — see Step 4.
        ...
    }
}
```

Note in the PR/commit: rendering templated reason strings requires
`rules.reasons.templates`, which `ConstraintResolver` does not otherwise
depend on. Keep `sharedQuantityReason` returning the exact same fallback
string shape `PackingEngine.sharedQuantityReason` already builds (umbrella
special case + generic "N for the group" case) and have `applyQuantities`
pass that fallback through `render(...)` exactly as before — this preserves
today's templated-string behavior without giving `ConstraintResolver` a
`PackingRulesFile` dependency it doesn't otherwise need.

- [ ] **Step 4: Route `PackingEngine`'s three call sites through `sharingResolution`.**

  - `generateForParty` (`:150`): replace `let sharedIDs = Set(rules.party.sharedByDefault)` /
    `if sharedIDs.contains(suggestion.canonicalItemID)` with
    `if ConstraintResolver.sharingResolution(for: suggestion.canonicalItemID, rules: rules.party, context: context, party: party).isShared`.
  - `addCompanions` (`:783`): same replacement for the companion-sharing
    check, reading `context.effectiveParty` for `party:`.
  - `applyQuantities` (`:916-924`): replace the inline policy lookup and
    `sharedQuantity`/`sharedQuantityReason` calls with one
    `ConstraintResolver.sharingResolution(for: canonical, rules: rules.party, context: context, party: party)`
    call; `case .shared(let quantity, let fallback):` sets `copy.quantity`
    and calls `render(canonical == "essentials.umbrella_compact" ? "party.shared_umbrella" : "party.shared", ..., fallback: fallback)`
    exactly as the removed inline code did; `.personal` falls through to the
    existing per-traveler quantity code unchanged.
  - Delete `PackingEngine.sharedQuantity`/`sharedQuantityReason` once no
    call site references them.

- [ ] **Step 5: Verify GREEN and zero drift.** Run:

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/ConstraintTests \
  -only-testing:PackWiseTests/PackingEngineTests \
  -only-testing:PackWiseTests/ActivityContractTests \
  -only-testing:PackWiseTests/GoldenEngineTests
PYTHONDONTWRITEBYTECODE=1 python3 scripts/report_engine_goldens.py \
  --baseline-ref c9cbb76 --candidate ios/PackWiseTests/Goldens --format markdown
```

Expected: every suite green; the golden diff shows **zero** row changes
across all 36 existing fixtures — this is the zero-diff gate proving the
move reproduces exactly the three call sites it replaced.

- [ ] **Step 6: Commit.**

```bash
git add ios/PackWise/Domain/Packing/ConstraintResolver.swift \
  ios/PackWise/Domain/Packing/PackingEngine.swift \
  ios/PackWiseTests/ConstraintTests.swift
git commit -m "refactor: centralize party sharing resolution in ConstraintResolver"
```

---

### Task 2: Centralize the explicit-user-authority gate and prove the priority hierarchy

**Files:**
- Modify: `ios/PackWise/Domain/Packing/ConstraintResolver.swift`
- Modify: `ios/PackWise/Domain/Packing/PackingEngine.swift`
- Modify: `ios/PackWiseTests/ConstraintTests.swift`

**Interfaces:**
- Consumes: `PackingItemDraft.isUserAdded`/`.isUserModified` (unchanged),
  `RecommendationOverrideDraft` (unchanged).
- Produces: `ConstraintResolver.hasUserAuthority(_:) -> Bool`,
  `ConstraintResolver.isExplicitlyRemoved(_:ownership:travelerID:overrides:) -> Bool`.

- [ ] **Step 1: Write the failing characterization tests**, pinning both
  functions against today's four call sites' behavior before anything
  moves.

```swift
// ConstraintTests.swift — new `// MARK: - Explicit authority gate` section

@Test func hasUserAuthorityIsTrueForAddedOrModifiedOnly() {
    let plain = PackingItemDraft(canonicalItemID: "clothing.tshirt", displayName: "T-Shirt", category: .clothing, quantity: 1, importance: .normal, sourceSignals: [], reason: "")
    var added = plain; added.isUserAdded = true
    var modified = plain; modified.isUserModified = true
    #expect(!ConstraintResolver.hasUserAuthority(plain))
    #expect(ConstraintResolver.hasUserAuthority(added))
    #expect(ConstraintResolver.hasUserAuthority(modified))
}

@Test func isExplicitlyRemovedMatchesTravelerAndOwnershipScoping() {
    let travelerA = UUID()
    let travelerB = UUID()
    let overrides = [RecommendationOverrideDraft(canonicalItemID: "clothing.hat_sun", action: "removed", travelerID: travelerA, ownershipType: .personal)]
    #expect(ConstraintResolver.isExplicitlyRemoved("clothing.hat_sun", ownership: .personal, travelerID: travelerA, overrides: overrides))
    #expect(!ConstraintResolver.isExplicitlyRemoved("clothing.hat_sun", ownership: .personal, travelerID: travelerB, overrides: overrides))
    #expect(!ConstraintResolver.isExplicitlyRemoved("clothing.hat_sun", ownership: .shared, travelerID: nil, overrides: overrides))
}
```

- [ ] **Step 2: Run and verify RED.** Compile failure — the two functions
  don't exist yet.

- [ ] **Step 3: Add both functions to `ConstraintResolver.swift`,** moving
  `PackingEngine.isRemoved`'s body verbatim into `isExplicitlyRemoved`:

```swift
extension ConstraintResolver {
    /// True when a draft carries explicit current-trip user state no
    /// lower-priority layer may override: a manual quantity edit or a
    /// hand-added item. Replaces the identical `isUserAdded || isUserModified`
    /// check written independently in `resolve()` and `applyQuantities()`.
    static func hasUserAuthority(_ item: PackingItemDraft) -> Bool {
        item.isUserAdded || item.isUserModified
    }

    /// True when an explicit "Not Needed" override exists for this
    /// candidate, scoped to ownership and traveler. Moved verbatim from
    /// `PackingEngine.isRemoved` — same scoping, same behavior.
    static func isExplicitlyRemoved(
        _ canonicalItemID: String,
        ownership: PackingOwnership,
        travelerID: UUID?,
        overrides: [RecommendationOverrideDraft]
    ) -> Bool {
        overrides.contains { override in
            guard override.action == "removed", override.canonicalItemID == canonicalItemID else { return false }
            if let overrideTraveler = override.travelerID, overrideTraveler != travelerID { return false }
            if let overrideOwnership = override.ownershipType, overrideOwnership != ownership { return false }
            return true
        }
    }
}
```

- [ ] **Step 4: Route the four call sites.** `PackingEngine.isRemoved` becomes
  a one-line forward (`ConstraintResolver.isExplicitlyRemoved(...)`) or is
  deleted with call sites updated directly — prefer deleting and updating
  `resolve()` (`:684`) and `addCompanions` (`:802`) to call
  `ConstraintResolver.isExplicitlyRemoved` directly, so there is exactly one
  implementation. Replace the `existingItem.isUserModified || existingItem.isUserAdded`
  check in `resolve()` (`:690`) and the `item.isUserModified || item.isUserAdded`
  check in `applyQuantities()` (`:914`) with
  `ConstraintResolver.hasUserAuthority(existingItem)` /
  `ConstraintResolver.hasUserAuthority(item)`.

- [ ] **Step 5: Verify GREEN and zero drift.** Run the same command set as
  Task 1 Step 5. Expected: zero golden row changes; all four sites' existing
  tests (`removedCompanionStaysRemoved`, `removedBaseEssentialStaysRemovedAcrossRegeneration`,
  `manualQuantitySurvivesRegenerationWithChangedContext`,
  `userAddedCanonicalAndCustomItemsSurviveRegeneration`,
  `manuallyReassignedCarrierSurvivesRegeneration`) still pass unchanged.

- [ ] **Step 6: Write the composite priority-hierarchy proof.** This is the
  test the task requires — not an assertion, an exercised conflict: one list
  carries four independent rung-1/2 facts, then a single regeneration call
  changes three rung-3 dimensions (weather, activities, duration) at once.

```swift
// MARK: - Priority hierarchy proof (task requirement: provable, not asserted)

/// Explicit user state must survive a regeneration that simultaneously
/// changes weather, activities, and duration — three independent
/// current-trip-constraint recomputations at once, not one at a time as
/// each single-fact test above exercises. This is the multi-dimensional
/// conflict the priority hierarchy names: rung 1/2 (explicit decisions)
/// must never lose to rung 3 (current trip constraints) no matter how many
/// rung-3 facts move together.
@Test func explicitUserStateSurvivesASimultaneousMultiDimensionalRefresh() throws {
    let engine = try makeEngine()
    let dest = try destination("Chicago")
    var partner = Traveler(name: "Sam", role: .partner, ageGroup: .adult)
    let party = TripParty(travelMode: .couple, travelers: [Traveler.primarySelf(), partner])

    var first = engine.generate(context: context(destination: dest, days: 5, activities: ["sightseeing", "walking"], bag: .checked, party: party))

    // Rung 1/2 fact 1: manual quantity edit ("T-shirts 7 → 3" shape).
    guard let tshirtIndex = first.firstIndex(where: { $0.canonicalItemID == "clothing.tshirt" && $0.travelerID == party.primary.id }) else {
        Issue.record("Expected a primary t-shirt row")
        return
    }
    first[tshirtIndex].quantity = 3
    first[tshirtIndex].isUserModified = true

    // Rung 1/2 fact 2: Not Needed override (rain jacket, "must not silently return" shape).
    let overrides = [RecommendationOverrideDraft(canonicalItemID: "clothing.rain_jacket", action: "removed")]

    // Rung 1/2 fact 3: user-added custom item.
    first.append(PackingItemDraft(
        canonicalItemID: nil, displayName: "Travel journal", category: .travelComfort,
        quantity: 1, importance: .optional, sourceSignals: [.userPreference], reason: "Added by you",
        isUserAdded: true, ownershipType: .personal, travelerID: party.primary.id
    ))

    // Rung 1/2 fact 4: explicit carrier reassignment (owner unchanged, carrier moved).
    if let contactsIndex = first.firstIndex(where: { $0.canonicalItemID == "toiletries.contacts_solution" }) {
        first[contactsIndex].assignedTravelerID = party.primary.id
    }

    // Three rung-3 dimensions move together: longer trip, new activity,
    // and rain weather that would otherwise re-suggest the rain jacket.
    let rainy = /* wet 8-day forecast fixture, matching WeatherChangeTests' `forecast(...)` helper shape */
    let second = engine.generate(
        context: context(destination: dest, days: 8, activities: ["sightseeing", "walking", "museum"], bag: .checked, party: party, weather: rainy),
        existing: first,
        overrides: overrides
    )

    let tshirt = try #require(second.first { $0.canonicalItemID == "clothing.tshirt" && $0.travelerID == party.primary.id })
    #expect(tshirt.quantity == 3, "manual quantity must survive weather + activity + duration change together")
    #expect(!second.contains { $0.canonicalItemID == "clothing.rain_jacket" }, "Not Needed must not silently return even with fresh rain weather")
    #expect(second.contains { $0.displayName == "Travel journal" && $0.isUserAdded })
    let contactsSolution = try #require(second.first { $0.canonicalItemID == "toiletries.contacts_solution" })
    #expect(contactsSolution.assignedTravelerID == party.primary.id, "carrier reassignment must survive")
    #expect(contactsSolution.travelerID == partner.id, "owner must remain the partner despite the carrier move")
}
```

Fill in the `rainy` weather fixture using `ConstraintTests`'s existing
destination/context helpers plus a synthetic `TripWeatherContext` built the
same way `WeatherChangeTests.swift`'s private `forecast(...)` helper does
(rain probability high enough to trigger `clothing.rain_jacket`'s
`signalAdds` row if the override didn't exist).

- [ ] **Step 7: Run and verify GREEN.** Run
  `-only-testing:PackWiseTests/ConstraintTests` alone first to confirm the
  new test passes in isolation, then the full command set from Step 5.

- [ ] **Step 8: Commit.**

```bash
git add ios/PackWise/Domain/Packing/ConstraintResolver.swift \
  ios/PackWise/Domain/Packing/PackingEngine.swift \
  ios/PackWiseTests/ConstraintTests.swift
git commit -m "refactor: centralize the explicit-user-authority gate and prove the priority hierarchy"
```

---

### Task 3: Decide and close F-5 — Camping flashlight party sharing

**Files:**
- Modify: `ios/PackWiseTests/ActivityContractTests.swift`
- Modify: `ios/PackWiseTests/ConstraintTests.swift`

**Interfaces:**
- Consumes: `ActivityContracts.needCandidates[.portableLight] == ["miscellaneous.flashlight"]`
  (unchanged), `ConstraintResolver.sharingResolution` (Task 1).
- Produces: a decided, tested, documented product contract — no production
  behavior change.

- [ ] **Step 1: Replace the Phase-5 pinned test's stale comment and assert
  the decision explicitly.** The existing test
  (`ActivityContractTests.swift:354-365`) currently frames the behavior as
  undecided ("Phase 5 makes no party-sharing decision... this test records
  the baseline that decision will be made against"). Update the comment to
  record the Phase 7 decision, keep every existing assertion (behavior is
  unchanged):

```swift
/// Decision (Phase 7, F-5): a flashlight is a personal-safety item, not
/// scarce infrastructure (like a travel adapter) or naturally communal
/// (like sunscreen) — the three properties everything else in
/// `sharedByDefault` has. At a dark campsite, someone getting up alone at
/// night, or the party splitting into two groups, each person needs their
/// own light source independently. `miscellaneous.flashlight` staying out
/// of `sharedByDefault` is deliberate, not an oversight — see
/// `docs/superpowers/specs/2026-09-04-product-hardening-phase-7-central-constraints-design.md`.
///
/// Scope guard: this decides sharing only — a flashlight is not
/// `singlePerParty`. It does not decide traveler/age eligibility (whether
/// every traveler class, including an infant or toddler, independently
/// receives one); that is Family Hardening's (Phase 10) call via
/// `skipForYoungChildren`/`skipForInfantsAndToddlers`, not this phase's.
@Test func aPartyCampingTripKeepsFlashlightsPersonalPerTraveler() throws {
    // ... existing body unchanged ...
}
```

- [ ] **Step 2: Add the six scenario tests the task requires that aren't
  covered yet** (solo, couple, Hiking+Camping, one traveler carrying a
  shared item, explicit owner assignment, unassigned explicit personal
  item), in `ActivityContractTests.swift` next to the existing test:

```swift
/// Solo camping: exactly one flashlight, owned by the sole traveler.
@Test func soloCampingGetsOneFlashlightOwnedByTheSoleTraveler() throws {
    let engine = try makeEngine()
    let generation = engine.generateDetailed(context: try campingContext(activities: ["camping"]))
    let lights = generation.items.filter { $0.canonicalItemID == "miscellaneous.flashlight" }
    #expect(lights.count == 1)
    #expect(lights.first?.ownershipType == .personal)
}

/// Couple camping: two flashlights, one per traveler — the case the
/// design doc argues matters most for staying personal, not least.
@Test func coupleCampingGetsOneFlashlightPerTraveler() throws {
    let engine = try makeEngine()
    let couple = TripParty(travelMode: .couple, travelers: [Traveler.primarySelf(), Traveler(name: "Sam", role: .partner, ageGroup: .adult)])
    let items = engine.generate(context: try campingContext(activities: ["camping"], party: couple))
    let lights = items.filter { $0.canonicalItemID == "miscellaneous.flashlight" }
    #expect(lights.count == 2)
    #expect(Set(lights.compactMap(\.travelerID)) == Set(couple.travelers.map(\.id)))
}

/// Hiking + Camping composes into one outdoor trip (Phase 5) but still
/// produces one flashlight per traveler, not per activity.
@Test func hikingPlusCampingStillGivesOneFlashlightPerTravelerNotPerActivity() throws {
    let engine = try makeEngine()
    let party = TripParty(travelMode: .couple, travelers: [Traveler.primarySelf(), Traveler(name: "Sam", role: .partner, ageGroup: .adult)])
    let items = engine.generate(context: try campingContext(activities: ["hiking", "camping"], party: party))
    #expect(items.filter { $0.canonicalItemID == "miscellaneous.flashlight" }.count == 2)
}

/// A traveler with `packingResponsibility == .anotherTraveler` still owns
/// their own flashlight; the party's carrier convention (`carrierID`)
/// changes who packs it, never whose it is.
@Test func oneTravelerCarryingAnothersItemsDoesNotMergeTheirFlashlights() throws {
    let engine = try makeEngine()
    var child = Traveler(name: "Emma", role: .child, ageGroup: .child)
    child.packingResponsibility = .guardian
    let party = TripParty(travelMode: .family, travelers: [Traveler.primarySelf(), child])
    let items = engine.generate(context: try campingContext(activities: ["camping"], party: party))
    let lights = items.filter { $0.canonicalItemID == "miscellaneous.flashlight" }
    #expect(lights.count == 2, "each traveler still gets their own — carrying someone's bag does not merge ownership")
    #expect(Set(lights.compactMap(\.travelerID)) == Set(party.travelers.map(\.id)))
    let childLight = try #require(lights.first { $0.travelerID == child.id })
    #expect(childLight.assignedTravelerID == party.primary.id, "the guardian carries it; the child still owns it")
}

/// An explicit carrier reassignment on a flashlight survives regeneration,
/// exactly like `manuallyReassignedCarrierSurvivesRegeneration` proves for
/// contacts solution — owner and carrier stay distinct here too.
@Test func explicitFlashlightCarrierReassignmentSurvivesRegeneration() throws {
    let engine = try makeEngine()
    let couple = TripParty(travelMode: .couple, travelers: [Traveler.primarySelf(), Traveler(name: "Sam", role: .partner, ageGroup: .adult)])
    var first = engine.generate(context: try campingContext(activities: ["camping"], party: couple))
    guard let index = first.firstIndex(where: { $0.canonicalItemID == "miscellaneous.flashlight" && $0.travelerID == couple.primary.id }) else {
        Issue.record("Expected the primary's flashlight")
        return
    }
    let partnerID = couple.travelers.first { $0.role == .partner }!.id
    first[index].assignedTravelerID = partnerID

    let second = engine.generate(context: try campingContext(activities: ["camping"], party: couple, days: 6), existing: first)
    let flashlight = try #require(second.first { $0.canonicalItemID == "miscellaneous.flashlight" && $0.travelerID == couple.primary.id })
    #expect(flashlight.assignedTravelerID == partnerID)
    #expect(flashlight.travelerID == couple.primary.id, "owner is unaffected by the carrier reassignment")
}

/// A user-added, explicitly-personal flashlight with no traveler chosen
/// stays unassigned rather than being guessed onto the primary — the same
/// fail-safe `generateDetailed` already applies to any explicit party item
/// (`PackingEngine.swift:49-58`), exercised here on the F-5 item itself.
@Test func unassignedExplicitPersonalFlashlightStaysUnassigned() throws {
    let engine = try makeEngine()
    let couple = TripParty(travelMode: .couple, travelers: [Traveler.primarySelf(), Traveler(name: "Sam", role: .partner, ageGroup: .adult)])
    let extra = PackingItemDraft(
        canonicalItemID: "miscellaneous.flashlight", displayName: "Small flashlight", category: .miscellaneous,
        quantity: 1, importance: .optional, sourceSignals: [.userPreference], reason: "Added by you",
        isUserAdded: true, ownershipType: .personal, travelerID: nil
    )
    let generation = engine.generateDetailed(context: try campingContext(activities: ["camping"], party: couple), existing: [extra])
    let unassigned = generation.items.first { $0.id == extra.id }
    #expect(unassigned?.travelerID == nil, "ambiguous ownership must not be inferred, per the Global Constraints")
}
```

- [ ] **Step 2: Run and verify GREEN.** These are expected to pass with
  **no production code change** — F-5's decision is "current behavior is
  correct," so this task converts an undecided baseline into a decided,
  fully-scenario-tested contract, the same shape Phase 5's Task 4 used for
  `tripType.other` and Phase 6's Task 4 used for the composition matrix. If
  any fails, that is a real defect in `PartyInvariants`/`resolve`'s
  ambiguous-item handling and must be fixed at the minimal cause, not routed
  a fourth time.

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/ActivityContractTests \
  -only-testing:PackWiseTests/ConstraintTests
```

- [ ] **Step 3: Commit.**

```bash
git add ios/PackWiseTests/ActivityContractTests.swift ios/PackWiseTests/ConstraintTests.swift
git commit -m "test: decide F-5 — Camping flashlight stays personal-per-traveler"
```

---

### Task 4: Party sharing-policy scenario tests — shared umbrella, family scaling, ambiguous party row

**Files:**
- Modify: `ios/PackWiseTests/ConstraintTests.swift`

**Interfaces:**
- Consumes: `rules.party.sharingPolicies["essentials.umbrella_compact"]`
  (`scaleByParty`, `per: 2`), `["toiletries.sunscreen"]` (`scaleByParty`,
  `per: 3`), `["electronics.travel_adapter"]` (`scaleByDevices`, `per: 2`)
  — all unchanged JSON, read via `ConstraintResolver.sharingResolution`
  (Task 1).
- Produces: gates 3, 4, and 12 — none of which had a test before this task.

- [ ] **Step 1: Write the failing tests.**

```swift
// MARK: - Sharing policy scenarios (gates 3, 4, 12)

/// A couple with rain in the forecast gets one shared umbrella
/// (`scaleByParty`, `per: 2`, `min: 1`) — the exact case the task names.
@Test func coupleWithRainSharesOneUmbrellaNotOnePerPerson() throws {
    let engine = try makeEngine()
    let couple = TripParty(travelMode: .couple, travelers: [Traveler.primarySelf(), Traveler(name: "Sam", role: .partner, ageGroup: .adult)])
    // ctx with a rainy forecast, built the same way ConstraintTests'
    // existing helpers construct weather — see WeatherChangeTests.forecast(...).
    let items = engine.generate(context: rainyContext(party: couple))
    let umbrellas = items.filter { $0.canonicalItemID == "essentials.umbrella_compact" }
    #expect(umbrellas.count == 1)
    #expect(umbrellas.first?.ownershipType == .shared)
    #expect(umbrellas.first?.quantity == 1, "per:2 with a 2-person party rounds up to 1")
    #expect(umbrellas.first?.quantityReason.localizedCaseInsensitiveContains("group") == true)
}

/// A family of 5 scales sunscreen (`scaleByParty`, `per: 3`, `min: 1`) —
/// one bottle per three travelers, rounded up, never one per person.
@Test func familyOfFiveScalesSharedSunscreenByPartySize() throws {
    let engine = try makeEngine()
    let party = TripParty(travelMode: .family, travelers: [
        Traveler.primarySelf(), Traveler(name: "Sam", role: .partner, ageGroup: .adult),
        Traveler(name: "Jo", role: .child, ageGroup: .teen),
        Traveler(name: "Ali", role: .child, ageGroup: .child),
        Traveler(name: "Em", role: .child, ageGroup: .toddler)
    ])
    let items = engine.generate(context: sunnyContext(party: party))
    let sunscreen = try #require(items.first { $0.canonicalItemID == "toiletries.sunscreen" })
    #expect(sunscreen.ownershipType == .shared)
    #expect(sunscreen.quantity == 2, "ceil(5/3) = 2")
}

/// `scaleByDevices` (travel adapter) scales by adult/teen count, not full
/// party size — a toddler doesn't carry a device.
@Test func travelAdapterScalesByDeviceCarryingTravelersOnly() throws {
    let engine = try makeEngine()
    let party = TripParty(travelMode: .family, travelers: [
        Traveler.primarySelf(), Traveler(name: "Sam", role: .partner, ageGroup: .adult),
        Traveler(name: "Em", role: .child, ageGroup: .toddler)
    ])
    let items = engine.generate(context: context(destination: try destination("Chicago"), party: party, type: .international))
    let adapter = try #require(items.first { $0.canonicalItemID == "electronics.travel_adapter" })
    #expect(adapter.quantity == 1, "ceil(2 adults / 2 per) = 1, the toddler does not count")
}

/// An explicit party item with no chosen traveler stays unassigned rather
/// than being guessed onto the primary — `PackingEngine.swift:49-58`'s
/// fail-safe, exercised generically (F-5's Task 3 test exercises the same
/// path specifically for the flashlight).
@Test func ambiguousExplicitPersonalItemStaysUnassignedInAPartyList() throws {
    let engine = try makeEngine()
    let couple = TripParty(travelMode: .couple, travelers: [Traveler.primarySelf(), Traveler(name: "Sam", role: .partner, ageGroup: .adult)])
    let extra = PackingItemDraft(
        canonicalItemID: nil, displayName: "Shared travel journal", category: .travelComfort,
        quantity: 1, importance: .optional, sourceSignals: [.userPreference], reason: "Added by you",
        isUserAdded: true, ownershipType: .personal, travelerID: nil
    )
    let generation = engine.generateDetailed(context: context(destination: try destination("Chicago"), party: couple), existing: [extra])
    let unassigned = try #require(generation.items.first { $0.id == extra.id })
    #expect(unassigned.travelerID == nil)
    #expect(unassigned.ownershipType == .personal, "stays personal-but-unowned, not silently promoted to shared")
}
```

Add local `rainyContext(party:)`/`sunnyContext(party:)` helpers built from
`ConstraintTests`'s existing `context(...)` plus a `TripWeatherContext`
constructed the same way `WeatherChangeTests.swift`'s `forecast(...)`
helper builds one (rain probability high enough for
`essentials.umbrella_compact`'s `rainProbabilityAdd` threshold; UV/heat high
enough for `toiletries.sunscreen`'s `highUVExposure`/`hotOutdoorExposure`
threshold).

- [ ] **Step 2: Run and verify RED or honest GREEN.** These may pass
  immediately — the design doc's read of `sharedQuantity`'s arithmetic found
  no structural conflict on paper, only an absence of tests. Run them and
  record the actual result rather than assuming; if any fails, the minimal
  fix belongs in `ConstraintResolver.sharedQuantity` (Task 1's new home for
  it), not a test rewrite.

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/ConstraintTests
```

- [ ] **Step 3: Commit.**

```bash
git add ios/PackWiseTests/ConstraintTests.swift
git commit -m "test: pin shared-item scaling and ambiguous-party-row scenarios"
```

---

### Task 5: Dependency authority — user-added equivalent pre-empts the auto-companion

**Files:**
- Modify: `ios/PackWiseTests/ConstraintTests.swift`

**Interfaces:**
- Consumes: `CatalogItem.companions` (unchanged), `addCompanions`'s
  `presentByGroup`/`presentShared` dedup (unchanged, verified in the design
  doc's "already a small, closed, declarative table" section).
- Produces: gate 6 (explicit user-added item satisfying dependency/coverage)
  — distinct from `removedCompanionStaysRemoved` (override-based) and
  `companionNotDuplicatedWhenRulesAlreadyEmitIt` (rules-based); this is the
  "user pre-added the equivalent by hand" case, untested until now.

- [ ] **Step 1: Write the failing test.**

```swift
/// A user who hand-adds the laptop charger themselves (not via the
/// dependency mechanism, not via an override) pre-empts the automatic
/// companion — the same de-duplication `companionNotDuplicatedWhenRulesAlreadyEmitIt`
/// proves for a rules-suggested charger, exercised here for a
/// user-added one, which is the case the task calls out specifically:
/// "must respect user-added equivalents."
@Test func userAddedChargerPreemptsTheAutomaticLaptopCompanion() throws {
    let laptop = PackingItemDraft(
        canonicalItemID: "electronics.laptop", displayName: "Laptop", category: .electronics,
        quantity: 1, importance: .normal, sourceSignals: [.userPreference], reason: "Added by you",
        isUserAdded: true
    )
    let ownCharger = PackingItemDraft(
        canonicalItemID: "electronics.laptop_charger", displayName: "My charger", category: .electronics,
        quantity: 1, importance: .normal, sourceSignals: [.userPreference], reason: "Added by you",
        isUserAdded: true
    )
    let items = try makeEngine().generate(
        context: context(destination: try destination("Chicago")),
        existing: [laptop, ownCharger]
    )
    #expect(items.filter { $0.canonicalItemID == "electronics.laptop_charger" }.count == 1)
    let charger = try #require(items.first { $0.canonicalItemID == "electronics.laptop_charger" })
    #expect(charger.id == ownCharger.id, "the user's own draft survives; the dependency pass never adds a second")
    #expect(charger.displayName == "My charger", "the user's own display name is not overwritten by the companion's rendering")
}
```

- [ ] **Step 2: Run and verify RED or honest GREEN.** Expected to pass
  immediately per the design doc's read of `addCompanions`'s
  `presentByGroup` check — record the actual result.

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/ConstraintTests
```

- [ ] **Step 3: Commit.**

```bash
git add ios/PackWiseTests/ConstraintTests.swift
git commit -m "test: pin that a user-added equivalent pre-empts the automatic companion"
```

---

### Task 6: Bag/style conflict gates — Prepared+personal item, Light+checked bag

**Files:**
- Modify: `ios/PackWiseTests/ConstraintTests.swift`

**Interfaces:**
- Consumes: `ConstraintResolver.optionalRuling(importance:tags:bag:style:)`
  (unchanged — already the sole bag/style authority per the design doc).
- Produces: gates 1 (cited, already proven) and 2 (new).

- [ ] **Step 1: Cite gate 1.** No new test — `preparedVersusPersonalItemResolvesExplicitly`
  (`ConstraintTests.swift:125-142`) already proves it: the conflict is
  recorded as a `ConstraintDecision` under `style.prepared_vs_personal_item`,
  and the dropped items exist on a checked bag but not a personal item.
  Record this citation in the Task 8 exit report; no code change here.

- [ ] **Step 2: Write the failing Light+checked-bag test.** Nothing today
  proves a checked bag never trims regardless of style —
  `bag.isSpaceConstrained` is `false` for `.checked`
  (`TripTypes.swift:121-122`), so `optionalRuling`'s guard clause should
  short-circuit to `keep: true` before style is even considered.

```swift
/// A checked bag never trims optional extras, regardless of style — the
/// "checked and road-trip luggage never trim" half of
/// `optionalRuling`'s doc comment, unproven by any existing test. Compares
/// against the identical trip on a carry-on, which does trim under Light.
@Test func lightStyleNeverTrimsOnACheckedBag() throws {
    let engine = try makeEngine()
    let dest = try destination("Chicago")
    let checked = engine.generateDetailed(context: context(destination: dest, type: .vacation, bag: .checked, style: .light))
    let carryOn = engine.generateDetailed(context: context(destination: dest, type: .vacation, bag: .carryOn, style: .light))
    #expect(checked.constraintDecisions.isEmpty, "a checked bag has nothing to trim under any style")
    #expect(!carryOn.constraintDecisions.isEmpty, "the same trip on a carry-on does trim under Light — the contrast proves the bag, not the style, gates the constraint")
}
```

- [ ] **Step 3: Run and verify GREEN with no production change.** Expected
  to pass immediately — `optionalRuling`'s existing guard
  (`bag.appliesBagConstraint, bag.isSpaceConstrained`) already implements
  this; the task converts an unproven assumption into a guarded contract.
  If it fails, the minimal fix belongs in `ConstraintResolver.optionalRuling`,
  not the test.

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/ConstraintTests
```

- [ ] **Step 4: Confirm the "prefer critical items / multifunction /
  compact-high-value, suppress bulky optional backups" charter language is
  already satisfied** by the collaboration between `optionalRuling`'s
  importance guard (only `.optional` items are ever touched — critical,
  important, and normal items are never trimmed) and
  `essentialOptionalTags` (base/rain/cold/medication tags survive
  regardless), cited via the existing `essentialOptionalTagsSurvivePersonalItem`
  test (`:145-153`). Record this as a design-doc citation in the Task 8
  report — no catalog tags for "multifunction"/"compact"/"bulky" exist
  today (confirmed: `python3 -c "..."` tag inventory across
  `shared/catalog/*.json` finds no such tags), and introducing them would be
  a catalog-vocabulary expansion outside this phase's file list. The
  existing importance + essential-tag mechanism already achieves the
  intended outcome without a new vocabulary.

- [ ] **Step 5: Commit.**

```bash
git add ios/PackWiseTests/ConstraintTests.swift
git commit -m "test: pin that a checked bag never trims regardless of style"
```

---

### Task 7: New golden fixtures and party/sharing determinism

**Files:**
- Modify: `shared/fixtures/golden/golden-fixtures.json`
- Create: new JSON outputs under `ios/PackWiseTests/Goldens/`
- Modify: `ios/PackWiseTests/ConstraintTests.swift`

**Interfaces:**
- Consumes: the existing fixture schema (unchanged since Phase 1).
- Produces: full-output ledger evidence for a family camping trip (F-5 +
  party scaling together) and a couple rain trip (shared umbrella), plus
  gate 13 (repeated-generation determinism) scoped to the party/sharing
  surface this phase touches.

- [ ] **Step 1: Add two fixtures.**

| ID | Scenario | Measures |
| --- | --- | --- |
| 37 | Family of 4 · Yellowstone · 5d · outdoor · hiking+camping · checked · balanced | F-5: four personal flashlights, not one shared; sunscreen/insect-repellent scale by party; owner distinct from carrier for the toddler's items |
| 38 | Couple · Seattle · 5d · vacation · walking+sightseeing · rain · carry-on | one shared umbrella (`scaleByParty`), personal rain jackets per traveler, medication (if any) stays personal |

```json
{
  "id": "37-family4-5d-hiking-camping-outdoor",
  "proves": "F-5: flashlight stays personal-per-traveler for a family (four rows, not one shared); sunscreen and insect repellent scale by sharingPolicies; owner and carrier remain distinct for the toddler's items",
  "destination": "Yellowstone",
  "days": 5,
  "tripType": "outdoor",
  "activities": ["hiking", "camping"],
  "bag": "checked",
  "style": "balanced",
  "laundry": "none",
  "homeCountryCode": "US",
  "party": {
    "travelMode": "family",
    "travelers": [
      {"role": "self", "ageGroup": "adult"},
      {"role": "partner", "ageGroup": "adult"},
      {"role": "child", "ageGroup": "child"},
      {"role": "child", "ageGroup": "toddler"}
    ]
  }
},
{
  "id": "38-couple-5d-seattle-shared-umbrella",
  "proves": "A couple with rain in the forecast shares one umbrella (scaleByParty, per:2) rather than one each; personal rain jackets remain per-traveler",
  "destination": "Seattle",
  "weatherFixture": "SeattleWetCity",
  "startDate": "2026-10-05",
  "days": 5,
  "tripType": "vacation",
  "activities": ["walking", "sightseeing"],
  "bag": "carryOn",
  "style": "balanced",
  "laundry": "none",
  "homeCountryCode": "US",
  "party": {
    "travelMode": "couple",
    "travelers": [
      {"role": "self", "ageGroup": "adult"},
      {"role": "partner", "ageGroup": "adult"}
    ]
  }
}
```

Match the fixture JSON's actual party-encoding shape to whatever
`GoldenFixture`/`GoldenEngineTests.buildContext` already decodes — read the
existing party-carrying fixtures (12, 16) for the exact field names before
writing 37/38; do not invent a new schema field.

- [ ] **Step 2: Run `python3 scripts/validate_shared.py`, then record:**

```bash
PACKWISE_RECORD_GOLDENS=1 xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/GoldenEngineTests
```

The recorder intentionally fails after writing. Run the semantic report
against `c9cbb76`: expected exactly two new fixtures (37, 38), zero changes
to fixtures 1–36.

```bash
PYTHONDONTWRITEBYTECODE=1 python3 scripts/report_engine_goldens.py \
  --baseline-ref c9cbb76 --candidate ios/PackWiseTests/Goldens --format markdown
```

- [ ] **Step 3: Add the party/sharing determinism test (gate 13).** The
  Phase 1 baseline already proved whole-ledger byte-identical determinism
  once; this adds one check scoped to the surface Task 1/2 actually moved —
  traveler iteration and the `sharedCollected` dictionary merge are new
  territory for a determinism claim this phase makes.

```swift
/// Two consecutive generations of the same family/camping/sharing-heavy
/// context produce byte-identical ownership, carrier, and shared-quantity
/// output — the party-sharing surface Task 1/2 moved is new territory for
/// a determinism claim; the Phase 1 baseline's whole-ledger determinism
/// evidence (`docs/engine-audits/2026-09-03-phase-1-baseline.md`) is cited,
/// not re-derived, for everything else.
@Test func repeatedGenerationOnASharingHeavyPartyContextIsByteIdentical() throws {
    let engine = try makeEngine()
    let party = TripParty(travelMode: .family, travelers: [
        Traveler.primarySelf(), Traveler(name: "Sam", role: .partner, ageGroup: .adult),
        Traveler(name: "Jo", role: .child, ageGroup: .child)
    ])
    let ctx = context(destination: try destination("Chicago"), days: 5, activities: ["hiking", "camping"], bag: .checked, party: party)
    let first = try makeEngine().generateDetailed(context: ctx)
    let second = try makeEngine().generateDetailed(context: ctx)
    #expect(first.items == second.items)
    #expect(first.constraintDecisions == second.constraintDecisions)
    #expect(first.coverageSuppressions == second.coverageSuppressions)
}
```

- [ ] **Step 4: Run and verify GREEN.**

```bash
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PackWiseTests/ConstraintTests \
  -only-testing:PackWiseTests/GoldenEngineTests
```

- [ ] **Step 5: Commit.**

```bash
git add shared/fixtures/golden/golden-fixtures.json ios/PackWiseTests/Goldens \
  ios/PackWiseTests/ConstraintTests.swift
git commit -m "test: add family-camping and couple-umbrella golden fixtures and sharing determinism"
```

---

### Task 8: Close Phase 7

**Files:**
- Create: `docs/engine-audits/2026-09-04-phase-7-central-constraints-and-user-authority.md`
- Modify: `docs/plans/2026-09-02-product-hardening-program.md`

**Interfaces:**
- Consumes: Tasks 1–7.
- Produces: full audit evidence, a per-gate table for all 13 required test
  gates, the F-5 decision record, and the Phase 7 closure section.

- [ ] **Step 1: Run the full gate set.**

```bash
scripts/run_engine_audit.sh
xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
python3 scripts/validate_shared.py
npm --prefix api run preflight
PYTHONDONTWRITEBYTECODE=1 python3 scripts/report_engine_goldens.py --baseline-ref c9cbb76 --candidate ios/PackWiseTests/Goldens --format markdown
```

- [ ] **Step 2: Write the exit report.** Cover, at minimum: a 13-row gate
  table (gate → task → test name → cited-existing or new); the "already
  centralized vs. genuinely scattered" findings from the design doc,
  re-confirmed against the actual post-refactor code (bag/style: unchanged,
  already centralized; dependencies: unchanged, already a closed table;
  party sharing: now centralized in `ConstraintResolver.sharingResolution`;
  explicit authority: now centralized in `ConstraintResolver.hasUserAuthority`/`isExplicitlyRemoved`;
  ownership/carrier: unchanged, deliberately left split between `resolve()`
  and `PartyInvariants`); the F-5 decision and its rationale; the full
  reviewed golden diff (fixtures 37–38 new, zero unexpected changes to
  1–36); mechanical scope confirmation (no new `PackingCapability`,
  `ActivityNeed`, or `WeatherSignal` case; `party.json` byte-unchanged;
  `PartyInvariants`, `CatalogItem.companions`, `optionalRuling` byte-
  unchanged beyond what Task 1/2 read); the `SharingPolicy.personalOnly`
  amendment (decided and tested this phase, not routed — state that
  explicitly, since the design doc's first draft had proposed routing it);
  routed findings (F-1, the UNTESTED tail, the `CoverageContext`
  double-construction note).

- [ ] **Step 3: Close Phase 7 in the program tracker.** Update
  `docs/plans/2026-09-02-product-hardening-program.md`: change the header
  status line, add a "Phase 7 closure" section in the style of the Phase
  1–6 closure sections, update the "Program order" table's Phase 7
  exit-evidence cell, and name what Phase 8 inherits — matching exactly how
  Phase 5's and Phase 6's closure sections named what the next phase
  inherited.

- [ ] **Step 4: Commit the closure.**

```bash
git add docs/engine-audits/2026-09-04-phase-7-central-constraints-and-user-authority.md \
  docs/plans/2026-09-02-product-hardening-program.md
git commit -m "docs: close product hardening phase 7 central constraints and user authority"
```

---

## Self-Review

- **Spec coverage:** Task 1 centralizes party sharing (the one place the
  design doc found the roadmap's "scattered" framing accurate) as a
  zero-diff move. Task 2 centralizes the explicit-authority gate and adds
  the composite, multi-dimensional priority-hierarchy proof the task
  explicitly requires ("provable, not asserted"). Task 3 gives F-5 a
  genuine, tested, documented decision — personal-per-traveler, deliberate,
  not a default. Tasks 4–6 fill every remaining required test gate (3, 4,
  6, 12, 2; gates 1, 5, 7, 8, 9, 10 are cited existing evidence, named
  exactly where they live). Task 7 adds ledger evidence and the one new
  determinism claim this phase's own new surface needs. Task 8 is one
  reproducible exit command set and a separate evidence commit.
- **All 13 required gates map to a named task and a named test, not
  prose:** (1) Prepared+personal item — cited, `ConstraintTests.swift:125`.
  (2) Light+checked bag — Task 6, `lightStyleNeverTrimsOnACheckedBag`. (3)
  couple shared umbrella — Task 4, `coupleWithRainSharesOneUmbrellaNotOnePerPerson`.
  (4) family shared-item scaling — Task 4, `familyOfFiveScalesSharedSunscreenByPartySize`
  + `travelAdapterScalesByDeviceCarryingTravelersOnly`. (5) owner vs.
  carrier — cited, `ConstraintTests.swift:270,292`. (6) user-added item
  satisfying dependency — Task 5, `userAddedChargerPreemptsTheAutomaticLaptopCompanion`.
  (7) manual quantity survival — cited, `ConstraintTests.swift:184` and
  `ClothingQuantityTests.swift:485`. (8) Not Needed survival — cited,
  `ConstraintTests.swift:160`, `WeatherChangeTests.swift:183`,
  `PackingEngineTests.swift:716`. (9) packed-state survival — cited,
  `ConstraintTests.swift:249`. (10) user-added custom item survival —
  cited, `ConstraintTests.swift:209`. (11) flashlight party semantics —
  Task 3, six new scenario tests plus the existing pinned test's rewritten
  decision comment. (12) ambiguous/unassigned party row — Task 4,
  `ambiguousExplicitPersonalItemStaysUnassignedInAPartyList` (Task 3 also
  covers it specifically for the flashlight). (13) repeated-generation
  determinism — cited (Phase 1 baseline, whole-ledger) plus Task 7's new
  sharing-scoped check.
- **Architecture boundary:** `ConstraintResolver` becomes the sharing and
  explicit-authority authority via two verbatim-logic moves, not a rewrite
  — the same "move, don't reinvent" discipline Phase 6 applied to
  `WeatherQuality` routing. `optionalRuling`, `CatalogItem.companions`, and
  `PartyInvariants` are read but not touched, because the design doc found
  each already correct and already closed — stated explicitly rather than
  silently reconciled with the roadmap's framing, which called all of this
  "scattered" when only part of it was.
- **Framing gap named explicitly, per the task's own instruction:** the
  master roadmap's Phase 7 entry implies eight scattered mechanisms; the
  design doc's "current shape" section shows three are already centralized
  (bag/style, dependencies, and — in a different but equally valid
  authority — ownership/carrier), one is genuinely scattered and gets moved
  (party sharing), and one is correct-but-duplicated-four-ways and gets
  consolidated (explicit authority). This is recorded in the design doc and
  restated in Task 8's exit report, matching Phase 5's and Phase 6's
  precedent for naming a roadmap/reality gap rather than reconciling it
  silently.
- **F-5 is genuinely decided, not deferred a third time:** the design doc
  states the product reasoning (personal-safety item, fails all three
  properties that make the rest of `sharedByDefault` shared), Task 3 tests
  every scenario the task names, and no code changes — the task's own
  escape clause ("expected behavior, decided deliberately") applies exactly.
- **Judgment calls made and recorded, not hidden:** `SharingPolicy.personalOnly`
  is a real, narrow bug (dead, untested, semantics don't match its name)
  found while designing Task 1. The first design draft proposed routing it
  forward as an out-of-scope finding; review amended that — party sharing
  semantics are exactly Task 1's subject, zero current data exercises the
  case, so fixing it here is both in-scope and zero-diff. Task 1's Step 1b
  adds the four required tests against a synthetic policy row; no
  `sharingPolicies` row is added to `party.json`. `PartyInvariants` is
  deliberately left outside `ConstraintResolver` as a second, legitimate
  closed authority rather than folded in, the same relationship
  `CoverageResolver` has to `ActivityContracts`. F-5's scope is also
  explicitly bounded: it decides sharing, not traveler/age eligibility,
  which stays Phase 10's.
- **Design-doc decision: written**, because Phase 7 touches four existing
  subsystems at once (bag/style, party sharing, dependencies, ownership),
  needed to establish which were actually scattered before writing a single
  line of the plan, and carries a genuine product decision (F-5) with a
  real rejected alternative (`singlePerParty`) — the same bar Phase 4, 5,
  and 6 used.
- **Type/name consistency:** `ConstraintResolver.SharingResolution`,
  `.sharingResolution(for:rules:context:party:)`, `.hasUserAuthority(_:)`,
  and `.isExplicitlyRemoved(_:ownership:travelerID:overrides:)` are the only
  new symbols this phase introduces; every task after Task 2 consumes them
  without renaming.
- **Placeholder scan:** complete; no unresolved markers. Phase 8 (trace
  productization) and Phase 9+ (context intelligence) are routed, not
  started inside Phase 7. This plan does not touch
  `docs/plans/2026-09-02-product-hardening-program.md` before Task 8, and
  Task 8 is not executed by the planning pass that produced this document.
