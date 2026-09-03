# Final UI Refinement & Freeze Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the final presentation gaps, verify the complete product surface in the simulator and on a physical iPhone, then commit/tag a stable UI baseline before any further engine work.

**Architecture:** Existing feature views continue to consume the same persisted records and `[PackingSuggestion]` outputs. Presentation rules live in `ios/PackWise/DesignSystem/`; debug-only state construction lives in `Features/Developer/DebugPreviewScene.swift`; production Domain/Data behavior remains unchanged.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Testing, Xcode/iOS Simulator, `scripts/capture_ios_screens.sh`.

## Global constraints

- Customer-facing UI never calls PackWise an AI app.
- Local-first behavior, user authority, WeatherKit semantics, persistence, API contracts, quantities, and recommendation inclusion do not change.
- Screens compose from `PackWiseColor`, `PackWiseFont`, `PackWiseSpacing`, and PackWise primitives; no new raw colors, fonts, or paddings.
- Trips and Me are the only root tabs. Focused trip screens hide the root tab bar where it interferes.
- Minimum interaction region is 44pt; state never depends on color alone.
- The repository currently locks the root to light mode. Dark-mode re-enablement is blocked by AGENTS.md until a dark reference and dark counterparts for every color token are approved. Dark simulator captures still prove that system dark mode does not leak into the locked-light baseline.
- The pre-existing Xcode signing diff is not included in the UI baseline commit.

---

### Task 1: Baseline inventory and capture matrix

**Files:**
- Modify: `ios/PackWise/Features/Developer/DebugPreviewScene.swift`
- Modify: `scripts/capture_ios_screens.sh`
- Modify: `docs/device-pass-checklist.md`

**Interfaces:**
- Consumes: `DebugPreviewScreen`, `-PackWiseScreen`, in-memory `DebugTripSeed`.
- Produces: one stable launch identifier per required UI state and a capture manifest with light, locked-dark-system, and accessibility-large variants.

- [x] Add missing preview cases for ready/partial/completed trip cards, destination fallback, custom activities, seasonal Trip Detail, scrolled Packing List, large Item Detail, Add Item category selection, and precise/seasonal weather.
- [x] Build the simulator app with `xcodebuild -project ios/PackWise.xcodeproj -scheme PackWise -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`.
- [x] Capture the pre-change baseline with `scripts/capture_ios_screens.sh <artifact-directory> <screen>...` and inspect every PNG.
- [x] Record only observable defects in the device checklist; do not diagnose them in the evidence section.

### Task 2: Onboarding composition

**Files:**
- Modify: `ios/PackWise/Features/Onboarding/OnboardingView.swift`

**Interfaces:**
- Consumes: `PackWiseImageSlot`, `PackWisePageDots`, `PrimaryButtonStyle`.
- Produces: three safe-area-aware pages with a full-bleed photographic welcome and bottom-anchored actions.

- [x] Change Welcome to one full-screen `OnboardingImage` with a restrained readability gradient and a single overlaid content stack.
- [x] Keep the image decorative with `.accessibilityHidden(true)` and use `.scaledToFill()`.
- [x] Remove the flexible spacers that create the large gap on pages 2 and 3; place the explanatory card/illustration directly after the subtitle while retaining bottom control clearance.
- [x] Capture `onboarding`, `onboardingTrip`, and `onboardingPersonal` in all harness variants and compare against `design/ui-flow-overview.png`.

### Task 3: Setup navigation and compact selection surfaces

**Files:**
- Modify: `ios/PackWise/Features/TripSetup/TripSetupView.swift`
- Modify: `ios/PackWise/DesignSystem/PackWiseTheme.swift`
- Modify: `ios/PackWise/DesignSystem/PackWisePrimitives.swift`

**Interfaces:**
- Consumes: `SetupStep`, `PackWiseSelectionRow`, `PackWiseChip`.
- Produces: flat `Back`/`Next` navigation and consistent 44pt selection targets.

- [x] Replace `NavPillButtonStyle` on Next with flat accent text, preserving disabled state and `.fixedSize()`.
- [x] Preserve the iOS 26 `sharedBackgroundVisibility(.hidden)` path and the earlier-iOS fallback.
- [x] Verify party, trip type, bag, style, and laundry selected states use compact semantic badges and no oversized rows.
- [x] Capture every setup step at standard and accessibility-large text sizes.

### Task 4: Activities, preferences, and dormant notes

**Files:**
- Modify: `ios/PackWise/Features/TripSetup/TripSetupView.swift`
- Modify: `ios/PackWise/DesignSystem/PackWiseTokens.swift`
- Test: `ios/PackWiseTests/M1LoopTests.swift`

**Interfaces:**
- Consumes: `TripType.suggestedActivityIDs`, `PackWiseActivityStyle`, `ContextChip.tripLevel`.
- Produces: a single activity chip flow, deliberate symbols for all surfaced preset activities, grouped preference chips, and no visible inert note promise.

- [x] Write a failing test that every preset activity exposed by every trip type resolves to a deliberate non-fallback SF Symbol.
- [x] Run the focused test and confirm it fails for any missing mapping.
- [x] Add the missing presentation mappings without adding engine vocabulary.
- [x] Remove the duplicated `Your activities` section; selected preset and custom activities remain in the primary flow and are removable by tapping their selected chip.
- [x] Hide the general trip note field and its Review row until M3B provides acceptance and traveler attribution.
- [x] Run the focused test and capture selected/custom activity plus selected preference states.

### Task 5: Review payoff and destination presentation

**Files:**
- Modify: `ios/PackWise/Features/TripSetup/TripSetupView.swift`
- Modify: `ios/PackWise/DesignSystem/DestinationVisualService.swift`
- Modify: `ios/PackWise/DesignSystem/DestinationVisualView.swift`

**Interfaces:**
- Consumes: `DestinationVisualPurpose`, `TripDraft`, existing MapKit snapshot service.
- Produces: a destination-led review screen with separate Your Trip, Activities, Packing, Laundry, and Preferences blocks; graphical fallback remains immediately usable.

- [x] Split the settings-like review card into named summary blocks with no duplicated date information.
- [x] Ensure Review never displays hidden note content.
- [x] Preserve the existing Look Around quality policy and replace the generic final fallback with a designed destination-aware travel poster.
- [x] Capture city and forced-fallback destination states plus full Review.

### Task 6: Dashboard progress and completed records

**Files:**
- Modify: `ios/PackWise/Features/Trips/TripsHomeView.swift`
- Modify: `ios/PackWise/DesignSystem/PackWisePrimitives.swift`
- Test: `ios/PackWiseTests/M1LoopTests.swift`

**Interfaces:**
- Consumes: `TripRecord.packedCount`, `TripRecord.items`, `TripStatus`.
- Produces: presentation state `ready`, `inProgress`, or `complete` without an empty 0% track.

- [x] Write failing tests for zero-packed ready, partial progress, all-packed ready/completed, and empty-list states.
- [x] Extract the small presentation policy and use it in both hero and compact cards.
- [x] Render a progress bar only for meaningful partial progress; completed trips render final summary without active-task emphasis.
- [x] Capture empty, ready, partial, all-packed, and completed dashboard states.

### Task 7: Trip Detail, weather, impact, and hero controls

**Files:**
- Modify: `ios/PackWise/Features/TripDetail/TripDetailView.swift`
- Modify: `ios/PackWise/Features/Weather/WeatherStripView.swift`
- Modify: `ios/PackWise/Features/Weather/PackingImpactCard.swift`
- Modify: `ios/PackWise/DesignSystem/PackWisePrimitives.swift`

**Interfaces:**
- Consumes: normalized `TripWeatherContext`, `PackingImpact`, destination visual.
- Produces: reusable 44pt hero control, precise/partial/seasonal weather surfaces, and compact category overview.

- [x] Replace local hero circle code with one reusable control whose visible circle is small and whose hit region is 44pt.
- [x] Verify precise, partial, seasonal, cached, and unavailable weather behavior through the existing normalization/impact suite; capture the required precise and seasonal surfaces.
- [x] Verify glyph visibility with hierarchical rendering and condition-specific tint.
- [x] Keep Packing Impact an explanation surface and limit category overview to five rows plus See All.
- [x] Capture forecast and seasonal Trip Detail and Weather Detail states.

### Task 8: Packing List interaction and sheet presentation

**Files:**
- Modify: `ios/PackWise/Features/TripDetail/PackingListView.swift`
- Test: `ios/PackWiseTests/M1LoopTests.swift`

**Interfaces:**
- Consumes: `PackingItemRecord`, `PackingFilter`, existing repository mutations.
- Produces: body-tap Item Detail sheet, checkbox-only pack toggle, stable pinned headers, and selective reasons.

- [x] Preserve the leading checkbox as the only direct pack/unpack target and keep row-body tap for detail.
- [x] Present `ItemDetailView` with `.sheet(item:)` and detents `[.medium, .large]` instead of navigation push.
- [x] Verify opaque pinned headers, filter background, compact top gap, floating-plus safe-area clearance, search, and accessibility-large layout.
- [x] Capture top, scrolled, and accessibility-large list states plus medium/large Item Detail; verify the selected All filter in the capture set.

### Task 9: Add Item category selector

**Files:**
- Modify: `ios/PackWise/Features/TripDetail/PackingListView.swift`

**Interfaces:**
- Consumes: `PackingCategory.allCases`, existing custom-item save action.
- Produces: native nested category-selection sheet with PackWise rows and a visible checkmark.

- [x] Replace the stock category menu with a row that opens `Choose Category`.
- [x] Keep item name, quantity, importance, owner, and save semantics unchanged.
- [x] Capture Add Item and Choose Category.

### Task 10: Diff, proposal, Me, and navigation-state audit

**Files:**
- Modify only if a screenshot exposes a defect: `ios/PackWise/Features/TripDetail/RecommendationDiffSheet.swift`
- Modify only if a screenshot exposes a defect: `ios/PackWise/Features/Weather/WeatherChangedCard.swift`
- Modify only if a screenshot exposes a defect: `ios/PackWise/Features/Settings/MeView.swift`

**Interfaces:**
- Consumes: existing diff/proposal/current-preference models.
- Produces: unmistakable add/change/remove states, correct Keep List meaning, and current-preferences-only Me UI.

- [x] Verify glyph plus copy distinguishes add/change/remove and preserves selection defaults.
- [x] Verify Keep List dismisses only; it does not create a Not Needed override.
- [x] Verify root tabs appear only on Trips and Me.
- [x] Capture Review Changes, Weather Changed, completed trip, and Me.

### Task 11: Full simulator verification

**Files:**
- Modify: `docs/device-pass-checklist.md`

**Interfaces:**
- Consumes: complete capture manifest and automated test suite.
- Produces: dated evidence for build, tests, light, system-dark-while-locked, accessibility-large, and reference-board comparison.

- [x] Run `xcodebuild test -project ios/PackWise.xcodeproj -scheme PackWise -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` and retain the result bundle path.
- [x] Record `python3 scripts/validate_shared.py` as not applicable because no shared catalog/rule file changed.
- [x] Run the full capture matrix and inspect every output image rather than relying on the script exit code.
- [x] Record unresolved visual defects and repeat the affected task before device handoff.

### Task 12: Physical-device gate and UI baseline

**Files:**
- Modify: `docs/device-pass-checklist.md`
- Modify: `docs/implementation-decisions.md`

**Interfaces:**
- Consumes: signed Debug build, Apple development App Attest environment, physical iPhone.
- Produces: device evidence, UI-freeze record, baseline commit, and baseline tag.

- [ ] Complete sections 0–13 of `docs/device-pass-checklist.md` on the physical device, including App Attest and WeatherKit evidence.
- [ ] Run a real trip end to end and record raw observations before diagnosis.
- [ ] Fix only defects exposed by the pass, then repeat focused simulator/build/test/device verification.
- [ ] Confirm the worktree contains no unrelated files in the baseline commit; explicitly exclude the pre-existing signing diff unless the user chooses to include it.
- [ ] Commit the verified UI state with `git commit -m 'feat: freeze final UI baseline'`.
- [ ] Tag that exact commit `ui-baseline-2026-09-02` only after the device checklist is green.
- [ ] Update the implementation decision: presentation is frozen; the next authorized work is the next incomplete Engine V2/product-hardening phase.

## Self-review

- Spec coverage: all 34 UI requirements map to Tasks 1–10 or the global constraints; the mandatory capture set maps to Tasks 1 and 11; the physical-device gate maps to Task 12.
- Scope: Domain/Data/API/quantity/weather behavior is excluded. Presentation-only reason wording may change only when it restates existing structured evidence.
- Ambiguity: the dark-mode conflict is explicit. This plan verifies the current locked-light behavior and does not re-enable dark mode without the required design-system decision.
- No phase-completion claim is permitted without fresh build, test, screenshot inspection, and device evidence.
