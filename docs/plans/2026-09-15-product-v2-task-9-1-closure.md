# Product Experience V2, Task 9.1 — Me defaults, destination failure states, and hero QA closure

Date: 2026-09-15 · Branch: `product-v2-stage-a` · Baseline: `bc27bc4` (Task 9)

## 1. Every Me habit is a new-trip default

- **Engine.** `PackingEngine` reads no Me habit: not work out, laptop, contacts, or medication.
  - The deleted reads were the solo rule path, `travelerChips` for You, and the party trip-wide reset that existed only to undo them.
  - The only `TravelerPreferences` value the engine still reads is the confirmed home country, used for the "international" check. That is a fact about the user, not a habit; see finding F9.1-1.
- **One table.** `MeHabit` / `MeDefaultChoices` maps work out → `usuallyWorkOut`, laptop → `bringingLaptop`, contacts → `wearContacts`, and medication → `dailyMedication`.
  - `TripDraft.fresh` prefills You from it.
  - `TripDraft.from(trip:)` restores the trip's saved choices and never reapplies Me.
  - Companions start empty.
- **Storage.** No schema change; the stored preference names stay.
- **Me copy.** One line under "Usually true for me", "Selected for you when you start a new trip.", now covers all four toggles. It replaces the laptop row's own subtitle; no new control.
- **Backfill.** `MeHabitChoiceBackfill` generalizes Task 8.2's `LaptopChoiceBackfill` and runs on every store open. It is idempotent.
  - **Acts when:** for each habit, the trip holds a generated row for You whose recorded cause (reason code, provenance, or trace) is that habit's reason code, and the trip has no matching choice on its chips or on You.
  - **Writes:** the choice, on the trip chips and You's traveler record.
  - **Never** reads today's Me values, and ignores user-added rows.

In `TripSetupDraftTests`, each contract test runs once per habit (four arguments):

| Test | Proves |
| --- | --- |
| `meHabitPrefillsYouOnAFreshTrip` | Me on → the draft has the choice, saved on You, with the habit's rows |
| `deselectingAPrefilledHabitSavesATripWithoutIt` | Me still on → the list equals the no-habit baseline exactly; Me is unchanged; the next new trip is prefilled |
| `meHabitPrefillsOnlyYouOnAPartyTrip` | Group of three → only You has the choice and the rows |
| `changingMeNeverChangesAnExistingTrip` | Saved on or off, then Me flipped → the same context chips, the same party, the same list |
| `habitRowsHaveOneCauseAndMeAloneIsNotACause` | Each habit row has exactly one habit provenance fact; Me with the choice removed contributes none |

Two tests are not per-habit:

- `habitTableCoversEveryMeToggle`
- `legacyHabitRowsBecomeTheTripsOwnChoicesOnce`: 4 + 1 choices from list evidence; a user-added row is ignored; a second run (a relaunch) changes nothing.

## 2. Destination search states

- **`DestinationSearching` now throws.** `[]` means the search ran and nothing matched; a thrown error means it could not run.
  - `MapKitDestinationSearch` maps `MKError.placemarkNotFound` to `[]` and every other failure to `DestinationSearchError.unavailable`.
- **`DestinationSearchModel`** (`@MainActor`, `@Observable`) records the outcome: idle, searching, results, no matches, or unavailable. It never reads or writes the selection.
- **Copy:**
  - "No matches — We couldn't find that destination. Try another city, region, or country."
  - "Can't search right now — Check your connection and try again." plus **Try Again**.
- **Change no longer clears the destination.** While changing, "Selected: Chicago · Keep" shows above the search, Next stays enabled, and the destination is replaced only when another result is chosen. A failed search can't lose it.
- **Tests** (injected scripted providers, no MapKit network):
  - `successfulEmptySearchIsNoMatchesNotAFailure`
  - `thrownProviderErrorIsUnavailable`
  - `retryAfterFailureRecovers`
  - `selectedDestinationSurvivesSearchFailure`
  - `emptyQueryResetsToIdleWithoutSearching`
  - the phase table

## 3. Status bar over the Trip Detail hero

**Root cause:**

- Trip Detail hid its navigation bar, so it had no way to request a status-bar appearance.
- Worse, the app root applied `.preferredColorScheme(.light)`. That window-wide preference pins the status bar to dark glyphs and overrides any per-screen request; an experiment confirmed it: removing only that line turned the glyphs light.

**Fix:**

- **Light-only now comes from `UIUserInterfaceStyle = Light`** in `Info.plist`, the platform's app-wide opt-out. The root and onboarding color-scheme preferences are removed. AGENTS.md and `docs/design-system.md` record why a root color-scheme preference must not return.
- **Trip Detail keeps a present but clear navigation bar.**
  - Its back and options controls are toolbar items, with the shared glass background hidden, as in the setup shell.
  - It requests `toolbarColorScheme(.dark)` while the hero is under the status bar (`StatusBarOverHero`, driven by `onScrollGeometryChange`), then `.light` once white content scrolls under it.
- **Top shade** is strengthened to 0.45 (0.6 under Increase Contrast), so light glyphs read over any photo.

Verified in captures:

| State | Status-bar glyphs |
| --- | --- |
| Map, trusted photo (the pale-sky onboarding photograph), graphical fallback, loading surface | light |
| Popping back to a light root; pushing on to a light screen | dark |
| Trips Home, setup, onboarding | dark |
| Simulator in dark system appearance | app stays light; Detail glyphs stay light |

Scrolled Detail is covered by `statusBarRequestsLightGlyphsOnlyWhileTheHeroIsUnderIt`; `simctl` cannot scroll, so there is no capture of it.

## 4. Trips Home weather line

- **Wrapping.** The weather text has layout priority and fixed vertical size.
- **Accessibility sizes.** The range and the detail take a line each ("61° – 78°" / "Rain Sunday"). "Forecast closer to departure" wraps.
- **Unchanged:** the meaning, the symbol, and the card structure.

## Also closed in 9.1

**Attribution-safe imagery.**

- **Problem.** The accessibility-large Home card grew taller than the map's aspect, and centered fill cropping cut Apple's "Maps" attribution off the left edge.
- **Fix.** `AttributionSafeImage` fills from the bottom-leading corner, so overflow crops only from the top and trailing edge. `markerPoint` follows the same geometry.
- **Test:** `imageryFillKeepsTheBottomLeadingCorner`, across all purposes and several aspects.

**Approved final layout.** The Trip Detail progress card sits below the hero; nothing overlaps hero content. No longer a deviation.

## Evidence

- **Sheet:** `docs/device-evidence/product-v2/task9-1-closure-sheet.png`.
  - Search: no match, failure, and failure-keeps-selection (standard and accessibility-large).
  - Detail: map, trusted photo, graphical, loading, and accessibility-large.
  - Navigation: after pop, after push.
  - Home: weather present and long-destination-no-forecast (standard and accessibility-large).
  - Dark system appearance.
- **New Debug states:** `setupDestinationNoMatch`, `setupDestinationUnavailable`, `setupDestinationUnavailableKept`, `tripDetailTrusted`, `tripDetailLoading`, `statusBarAfterPop`, `statusBarAfterPush`, `tripsHomeLong`. `M1LoopTests.task9ReferenceStatesAreAllCapturable` pins the destination states.

## Semantic diff

- **Goldens:** 52/52 unchanged. No golden sets a Me habit, so the engine change cannot move one.
- **Moved behavior:** only existing trips that depended on today's Me values, which is the bug.
- **Unchanged for current-trip state:** item IDs, quantities, coverage, constraints, sharing, and ownership and carrier.

## Findings (not fixed)

- **F9.1-1.** Home country is still read live. A trip is international when its destination differs from the *current* confirmed home country, so changing home country in Me later can add or remove international documents on an existing trip's next regeneration. This is a different kind of input from a habit; it needs its own call.

## Verification

- **iOS:** 544 tests in 34 suites pass. The clean Debug build has 0 Swift warnings; the only lines are the existing AppIntents metadata notice.
- **Engine audit:** passes. Shared validation, Python tests (121 OK), focused Swift suites (107), a clean golden diff (52/52 unchanged), the surfaced-input audit, and the strict trace audit are all clean.
- **API preflight:** not run; no shared or generated artifact changed.
