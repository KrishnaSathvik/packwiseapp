# Product Experience V2, Task 8.2 — Me laptop preference is a default, not engine input

Date: 2026-09-15 · Branch: `product-v2-stage-a` · Baseline: `fd9e182` (Task 8.1)

## The boundary

```text
Me "I usually bring a laptop"  →  TripDraft.fresh  →  You's bringingLaptop choice  →  engine
```

- **Engine.** `PackingEngine` no longer reads `TravelerPreferences.usuallyBringLaptop`. Both reads are gone: the solo rule path and `travelerChips` for You. The trip's own `bringingLaptop` choice is the only laptop authority.
- **Prefill.** `TripDraft.fresh(preferences:)` inserts `bringingLaptop` into You's draft chips when Me is on. Companions start with no device choice.
- **Edit.** `TripDraft.from(trip:)` restores the trip's saved choice. It never reapplies Me.
- **Regeneration.** Edit, weather refresh, and the weather-change proposal all build context with the *current* Me value. Before 8.2, that value leaked into existing trips. It no longer can.
- **Storage.** No schema change. The stored field keeps its name for store compatibility, with a doc comment on `TravelerPreferences.usuallyBringLaptop` stating the boundary.
- **Me copy.** The toggle now reads "Selected for you when you start a new trip."

## Existing trips

`LaptopChoiceBackfill` runs on every store open, after the V4 data backfill. It is idempotent.

- **When it acts.** A trip with no `bringingLaptop` choice (on the trip or on You) that holds a generated laptop row for You whose recorded cause is `preference.bringingLaptop` (reason code, provenance, or trace).
- **What it writes.** That choice, on the trip chips and You's traveler record — the same places a Task 8 save writes it.
- **Evidence.** The trip's own saved list decides, never today's Me value.
- **Left alone:** user-added laptop rows, trips without a laptop row, and trips that already have the choice.
- **Known edge.** A pre-trace row (no provenance) whose winning reason code was a higher-tier cause, such as Business, is not backfilled. A solo Business trip still gets its laptop through `soleTravelerContext`. A party Business trip that relied only on the preference would propose removing the laptop in the review diff; it would never drop it silently.

## Tests

In `TripSetupDraftTests`:

| Test | Proves |
| --- | --- |
| `meLaptopDefaultPrefillsYouOnAFreshTrip` | Me on → a fresh draft has You.Laptop, which saves on You and generates the laptop and its charger |
| `deselectingThePrefilledLaptopSavesATripWithNoLaptop` | Me still on → no laptop rows; Me is unchanged; the next fresh draft is prefilled again |
| `meLaptopDefaultPrefillsOnlyYouOnAPartyTrip` | Group of three → only You has the choice and the rows; Adult 1 and Adult 2 get nothing; no shared laptop |
| `changingMeNeverChangesAnExistingTripsLaptop` | Off trip + Me on → still off (edit and regeneration); on trip + Me off → still on |
| `laptopHasOneCauseAndThePreferenceIsNotEngineInput` | The laptop and charger each carry one laptop provenance fact; Me on with the choice removed → no laptop |
| `legacyPreferenceLaptopBecomesTheTripsOwnChoiceOnce` | The backfill acts on preference-caused rows only, survives Me off, and a second run changes nothing |

`TravelerEligibilityTests` and `FamilySharingTests` rows that used the preference as a laptop signal now use You's own choice. Their names and expectations are unchanged.

The two duplicate sources wrote an identical provenance fact, so before 8.2 the trace already showed one fact. The provenance-count assertion therefore pins the result. The real guard is the second half of that test: the preference alone is not a cause.

## Diff

- **Goldens:** 52/52 unchanged. No golden sets the laptop preference.
- **Task 7.2 device attribution:** tests unchanged and green.

## Finding (not fixed; out of 8.2 scope)

`usuallyWorkOut`, `wearContacts`, and `alwaysBringMedication` have the same shape the laptop had. The engine reads them from Me at generation time, so changing Me changes existing trips on their next regeneration. The same default-only boundary would apply, but it moves golden-free engine semantics for three signals, so it needs its own call.

## Verification

- **iOS:** 523 tests pass (517 + 6).
- **Engine audit:** passes, including shared validation, Python tests, focused suites, a clean golden diff, the surfaced-input audit, and the strict trace audit.
- **API preflight:** not needed; no shared artifact changed.
