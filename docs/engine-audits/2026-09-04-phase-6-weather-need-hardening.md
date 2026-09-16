# Phase 6 — Weather Need Hardening

**Date:** 2026-09-04
**State:** implemented and simulator-verified; Phase 7 not started
**Branch:** `product-hardening-phase1`
**Phase 5 semantic baseline:** `e958c07`
**Approved design/plan:** `docs/superpowers/specs/2026-09-04-product-hardening-phase-6-weather-need-hardening-design.md`, `docs/superpowers/plans/2026-09-04-product-hardening-phase-6-weather-need-hardening.md`
**Implementation commits:** `7e36ec7`, `7b3bc22`, `48aaf62`, `6e9bc4a`, `db66704`

## Result

Phase 6 is closed. Normalized weather (precise, partial, seasonal, cached,
failed) now maps to conservative packing needs through one shared
classification — `TripContextSnapshot.weatherQuality` — instead of two
independently-drifting inline checks in `addWeather` and `CoverageContext`.
A partial forecast keeps its exact covered-day signals and blends the
uncovered remainder with the same seasonal heuristic a fully-unforecast trip
already gets, using `addSeasonal`'s existing `collected[id] == nil` guard as
the only safety mechanism — no new guard was needed. The cold-without-snow
glove question Phase 4 first noticed and Phase 5's closure routed here is
decided: `clothing.gloves` reaches any `sustainedCold` trip, not only
`snowExposure` ones. All eight named exit scenarios have execution evidence.
`WeatherSignal` stays at 11 cases, `PackingCapability` at 12, `ActivityNeed`
at 8; no threshold in `weather.json`'s `thresholds` block moved; the
WeatherKit fetch/cache/proposal infrastructure
(`WeatherChangeReconciler`/`TripWeatherRefresh`/`TripWeatherResolver`/
`WeatherRefreshPolicy`/`MockWeatherService`) is byte-unchanged since `e958c07`.

## Per-task results

| Task | Result | Zero-diff / semantic-golden check |
| --- | --- | --- |
| 1 — Route weather generation through `WeatherQuality` | green | `report_engine_goldens.py --baseline-ref e958c07`: **0** row changes across all 32 fixtures (1,165 unchanged rows) |
| 2 — Blend partial forecast with seasonal fallback | green | Exactly 1 new fixture (33), **0** changes to 1–32 |
| 3 — Decide and test cold-without-snow gloves | green | Exactly 2 new fixtures (33, 34 — 34 new this task), **0** changes to 1–32, confirmed via a full `engineOutputMatchesGoldens()` pass against the stale-recorded goldens *before* re-recording (not assumed) |
| 4 — Pin the weather composition matrix | green, no production change | N/A — regression-pinning only; all 3 new tests passed on first run |
| 5 — New composite golden fixtures (snow+business, rain+hiking) | green | Exactly 4 new fixtures total (33–36), **0** changes to 1–32 |
| 6 — Cached/failed generation-equivalence, rain+couple pin | green, no production change | `11-couple-5d-rain`: 55 unchanged rows, 0 changes across every category |
| 7 — Close Phase 6 | this document | Full gate set below |

### RED verification, recorded honestly

Per task, before implementation:

- **Task 1:** `completeForecastStillProducesExactlyTodaysSignals` passed
  immediately (pre-refactor characterization). `seasonalOnlyStillRoutesThroughAddSeasonalOnly`
  **failed** on first run — not because of a refactor bug (none existed yet),
  but because the plan's literal assertion (`clothing.light_jacket` survives)
  was wrong about the pre-existing baseline. See Deviations.
- **Task 2:** `partialForecastBlendsCoveredSignalsWithSeasonalRemainder` and
  `seasonalRemainderNeverDowngradesAPreciseDayItem` — the first failed as
  expected (sunscreen/sunglasses absent pre-Task-2); the second passed
  immediately (the rain jacket's reason code was already correct).
- **Task 3:** `sustainedColdWithoutSnowProducesOrdinaryGlovesNotSkiGloves`
  failed as expected (no gloves pre-rule-change). `merelyCoolEveningsDoNotProduceGloves`
  passed immediately, confirmed rather than assumed.
- **Task 4:** all three matrix tests (`windAloneAtMildTemperaturesKeepsTheWindbreaker`,
  `heatAndStrongSunMergeIntoOneSunscreenRow`, `hotDayCoolNightKeepsBothDayAndEveningLayers`)
  passed on first run with no production code touched, exactly as the design
  doc predicted — the composition machinery already handled these correctly.
- **Task 5:** both unit-level previews (`snowAndBusinessKeepDistinctFootwearForEachNeed`,
  `rainAndHikingComposeWithoutDuplication`) passed on first run, confirmed
  rather than assumed.
- **Task 6:** both new tests (`cachedForecastGeneratesIdenticallyToTheSameDataFresh`,
  `failedFetchWithNoCacheDegradesToNoWeatherGeneration`) passed on first run,
  confirmed rather than assumed.

## Decision 1 — partial forecast blends with seasonal fallback

`addWeather`'s `.partial` branch runs the existing precise-day extraction over
the covered days exactly as today, then calls `addSeasonal(context:into:)`
once, unconditionally, for the same trip. Safety comes entirely from
`addSeasonal`'s pre-existing `guard catalog.item(id: id) != nil, collected[id] == nil`
— not duplicated, not supplemented with a second check.
`CoverageContext.usesSeasonalWarmthFallback` mirrors this: true for `.partial`
(when the month/latitude check also passes), false for `.complete`.

**Real-generation confirmation of the two reason-code/composition guards**
(re-run live during Task 7, not only asserted by the test — see the Guards
section below for the exact printed values):

- `toiletries.sunscreen.reasonCode = weather.seasonal_sun`
- `essentials.sunglasses.reasonCode = weather.seasonal_sun`
- `clothing.rain_jacket.reasonCode = weather.rain_weekday` (a precise-tier
  code, never `weather.seasonal_layer`)
- `clothing.rain_jacket` count = 1 (no seasonal-tier duplicate)

## Decision 2 — cold-without-snow gloves

`shared/rules/weather.json`'s `signalAdds.sustainedCold` gains
`"clothing.gloves"`. `sustainedCold` (≤48°F trip maximum) is the broader
signal; `freezingCold` (≤32°F) is a strict subset in `WeatherSignalExtractor`,
so every `freezingCold` trip already reaches gloves through this one row.
`snowExposure`'s own row, `trip-types.json`'s `skiSnow` row, and
`CoverageResolver.priority`'s ski-glove-before-ordinary-glove ordering are
untouched — reused, not duplicated. `coldEvenings` (≤62°F minimum) was
deliberately rejected as the gate: it fires on merely cool evenings that are
not a cold-hands trip.

Checked live: `sustainedColdWithoutSnowProducesOrdinaryGlovesNotSkiGloves`
confirms `clothing.gloves` present with reason `weather.sustained_cold` and
`activities.ski_gloves` absent on a non-ski city trip; `merelyCoolEveningsDoNotProduceGloves`
confirms no gloves on a `coldEvenings`-only trip.

**Fixtures moved by this rule change:** none of the 32 pre-existing fixtures
gained a `clothing.gloves` row. Verified, not assumed: `GoldenEngineTests.engineOutputMatchesGoldens()`
was run against the stale-recorded (pre-Task-3) goldens after the rule change
and before re-recording, and it passed unchanged — confirming across **all**
32 fixtures (not only the three the plan named for manual inspection —
15/16 `MinneapolisDeepWinter`, which already has snow days so `snowExposure`
already covered them, and 18, which uses the seasonal fallback with no
forecast signals) that no existing fixture's precise-day signals reach
`sustainedCold` without `snowExposure` already covering it.

## The eight named exit scenarios

| Scenario | Evidence | Status |
| --- | --- | --- |
| hot+rain | `CoverageTests.hotRainDropsShellKeepsUmbrella` | existing, cited, unchanged |
| cold+rain | `CoverageTests.coldRainKeepsShell` | existing, cited, unchanged |
| wind+mild | `WeatherNeedHardeningTests.windAloneAtMildTemperaturesKeepsTheWindbreaker` | new, Task 4 |
| heat+strong-sun | `WeatherNeedHardeningTests.heatAndStrongSunMergeIntoOneSunscreenRow` | new, Task 4 |
| hot-day/cool-night | `WeatherNeedHardeningTests.hotDayCoolNightKeepsBothDayAndEveningLayers` | new, Task 4 |
| snow+business | golden fixture `35-denver-5d-business-snow` | new, Task 5 |
| rain+hiking | golden fixture `36-seattle-5d-rain-hiking` | new, Task 5 |
| rain+couple | golden fixture `11-couple-5d-rain` | existing, cited, re-pinned Task 6 (55 unchanged rows) |

Forecast-quality states: precise/seasonal characterized zero-diff in Task 1;
partial blended in Task 2; cached/failed closed in Task 6.

## New golden fixtures (33–36)

| ID | Scenario | Items | Reviewed result |
| --- | --- | --- | --- |
| 33 | Chicago, 10d vacation, `ChicagoRainyFall` (5 real days) | 28 | Byte-stable regression pin. Does **not** itself exercise `.partial` — see Deviations. The blend is proven by the two Task 2 unit tests instead. |
| 34 | Reykjavik, 5d city, `ReykjavikColdWindy` (cold, windy, one rain day, zero snow) | 35 | Exactly one `clothing.gloves` (`weather.sustained_cold`), one `clothing.rain_jacket` (`weather.rain_weekday`), `clothing.windbreaker` absent (suppressed/covered by the rain jacket), no `activities.ski_gloves` |
| 35 | Denver, 5d business, `DenverColdOutdoor` (snow) | 32 | `footwear.dress_shoes`, `footwear.boots`, `footwear.walking_shoes` all present (distinct capabilities, no conflict); `clothing.gloves` (Task 3); `clothing.winter_coat` (`snowExposure`); `clothing.blazer` (business) |
| 36 | Seattle, 5d outdoor/hiking, `SeattleWetCity` (rain) | 28 | `footwear.hiking_shoes`, `activities.daypack`, `hydration.water_bottle`, `health.blister_pads` all present; exactly one `clothing.rain_jacket`; `footwear.walking_shoes` suppressed and covered by `footwear.hiking_shoes` (the pre-existing pattern) |

## The four review guards — checked in real generated output, not only in test assertions

The plan's Global Constraints pin four guards. Each was re-confirmed during
Task 7 by re-running the actual `PackingEngine.generateDetailed`/`.generate`
calls with a temporary `print()` (added, captured, then reverted — no debug
output was committed; `git diff` against both files is empty after revert)
and reading the literal printed values, not just observing that the test's
own `#expect` passed:

1. **Seasonal fallback fills only the uncovered remainder, never overwrites
   or duplicates a precise-day item.** Real output:
   `rain_jacket.count=1`, and the item set for the Chicago partial-forecast
   trip contains both the precise-day `clothing.rain_jacket` and the
   seasonal-remainder `toiletries.sunscreen`/`essentials.sunglasses`
   simultaneously — no collision, no duplicate warmth-layer row. **Holds.**
2. **Seasonal-remainder items keep `addSeasonal`'s own seasonal reason codes,
   never a precise weather code.** Real output:
   `sunscreen.reasonCode=weather.seasonal_sun`,
   `sunglasses.reasonCode=weather.seasonal_sun`,
   `rain_jacket.reasonCode=weather.rain_weekday` (never `weather.seasonal_layer`
   or any seasonal code on the precise item, and never a precise code on the
   seasonal items). **Holds.**
3. **Precise-day and seasonal-remainder candidates compose through the one
   existing `collected`/`CoverageResolver` pipeline before final suppression,
   never as two independently-resolved checklists.** Confirmed structurally
   (Task 2 Step 3's `addSeasonal` call writes into the same `inout collected:
   [String: RuleSuggestion]` dictionary `addWeather`'s precise-day `add(...)`
   calls already populate, and `CoverageResolver.resolve` runs once over the
   union) and behaviorally: the combined item set from guard 1 above shows
   exactly the union with no double-suppression artifact and no second
   resolver pass evident in the output. **Holds.**
4. **A cached forecast generates identically to the same data fresh; only a
   genuine fetch failure with no usable cache degrades to no-weather
   behavior — cached and missing are not the same case.** Real output:
   `fresh.source=fixture cached.source=cache` (genuinely different `source`
   values) with `fresh.ids` and `cached.ids` byte-identical sorted arrays.
   Separately, `failedFetchWithNoCacheDegradesToNoWeatherGeneration` confirms
   `TripWeatherResolver.resolve` against a forced-unavailable service returns
   `state == .unavailable`, `engineWeather == nil`, and the resulting
   generation has no `clothing.rain_jacket` but is non-empty — the same shape
   as `noWeatherStillGenerates`, distinct from a cache hit. **Holds.**

All four guards hold in real, freshly re-run generated output as of this
closure, not only in the plan text or in the wording of the tests that assert
them.

## Mechanical scope confirmation

| Check | Result |
| --- | --- |
| `WeatherSignal` case count | 11 (unchanged) |
| `PackingCapability` case count | 12 (unchanged) |
| `ActivityNeed` case count | 8 (unchanged) |
| `shared/rules/weather.json` `thresholds` block | byte-identical to `e958c07` (only `signalAdds.sustainedCold` changed) |
| `WeatherChangeReconciler.swift` | byte-unchanged since `e958c07` |
| `TripWeatherRefresh.swift` | byte-unchanged since `e958c07` |
| `TripWeatherResolver.swift` | byte-unchanged since `e958c07` |
| `WeatherRefreshPolicy.swift` | byte-unchanged since `e958c07` |
| `MockWeatherService.swift` | byte-unchanged since `e958c07` |

## Golden review

**Expected changes:** 4 new fixtures (33, 34, 35, 36). **0** changes to any
of the 32 pre-existing fixtures across every category the semantic differ
tracks (unchanged/added/removed/quantity/trace/coverage/constraint rows).

| Category | Count |
| --- | --- |
| Fixtures compared | 32 (32 unchanged) |
| New fixtures | 4 |
| Removed fixtures | 0 |
| Unchanged rows across 1–32 | 1,165 |
| Row changes of any kind across 1–32 | 0 |

User authority preserved throughout (no fixture that pins Not Needed, manual
quantity, user-added survival, packed state, or explicit owner/carrier moved).

## Verification

| Gate | Fresh result |
| --- | --- |
| Focused suites (`WeatherNeedHardeningTests`, `CoverageTests`, `WeatherChangeTests`, `PackingEngineTests`, `ActivityContractTests`) | all pass; `WeatherNeedHardeningTests` 9/9, `CoverageTests` 21/21, `WeatherChangeTests` 22/22 |
| `scripts/run_engine_audit.sh` | all 6 steps passed: `validate_shared.py` clean; 83 Python audit tests OK; 79 focused Swift tests in 5 suites passed; semantic golden diff vs `HEAD` CLEAN; surfaced-input contract audit 49 rows (DEAD 0, CONTEXT-ONLY 1, UNTESTED 14) CLEAN; recommendation-trace audit 1,288 rows (0 defects) CLEAN |
| Full `xcodebuild test` on iPhone 17 Pro simulator | **268 tests, 18 suites, 0 failures** (`Test-PackWise-2026.09.04_08-54-54--0500.xcresult`) |
| `python3 scripts/validate_shared.py` | 202 catalog items; integrity checks passed |
| `npm --prefix api run preflight` | artifact/schema/typecheck steps passed; 106 tests, 0 failures; exit 0 |
| Semantic diff vs `e958c07` | 4 new reviewed fixtures (33–36); **0** unexpected changes to fixtures 1–32 |
| Four review guards | all confirmed in real, freshly re-run generated output (see above) |

## Routed findings

- **Golden fixture schema/pipeline cannot express a weather fixture shorter
  than trip days.** `GoldenEngineTests.buildContext` builds weather via
  `MockWeatherService.context(from:start:end:fixtureID:)`, which tiles a named
  fixture's days cyclically to fill the full requested span and always sets
  `forecastAvailableForWholeTrip: true`. This means no golden fixture, as the
  format currently exists, can demonstrate `.partial` `WeatherQuality` end to
  end through the recorded-golden pipeline — fixture 33 is a byte-stable
  regression pin of a *tiled-to-complete* 10-day forecast, not a partial one,
  and its `proves` field says so explicitly. The partial-forecast blend
  itself is fully proven at the unit level
  (`WeatherNeedHardeningTests.partialForecastBlendsCoveredSignalsWithSeasonalRemainder`,
  `.seasonalRemainderNeverDowngradesAPreciseDayItem`), which build a genuinely
  partial `TripWeatherContext` via `WeatherForecastNormalizer.context`
  directly. Extending the `GoldenFixture` schema (and `buildContext`) to
  accept an explicit weather-day-count distinct from trip-day-count, so a
  golden fixture can express real partial coverage, is routed as a follow-up
  — not in any Phase 6 task's authorized file list. No phase currently owns
  it; flagging here rather than silently working around it a second time.
- **Golden-recording env var.** The plan's shell snippets show
  `PACKWISE_RECORD_GOLDENS=1`; the actual required invocation for `xcodebuild`
  to forward the variable into the simulator test host is
  `TEST_RUNNER_PACKWISE_RECORD_GOLDENS=1` (`GoldenEngineTests.swift` reads the
  `TEST_RUNNER_`-prefixed name and says so in its own doc comment and issue
  text). Worth correcting in the next plan/skill that reuses this snippet.
- **Phase 11 (unchanged, still pending):** whether `WeatherChangeReconciler`
  should special-case a `.partial`-to-`.partial` refresh (more days arriving
  as the trip approaches, inside the existing 10-day provider horizon) as its
  own proposal category. Phase 6 only changed what one `generateDetailed`
  call produces for a partial snapshot, not refresh cadence — reconciler files
  are byte-unchanged (see Mechanical scope confirmation).
- **`CoverageContext` double-construction (unchanged, still pending, noted by
  the design doc):** `addActivityNeeds`'s `hasColdSignal` computation and
  `CoverageResolver.needs` each construct their own
  `CoverageContext(snapshot:thresholds:)` per generation. A possible
  follow-on efficiency cleanup with no behavior difference; not required for
  this phase's exit gate.
- **F-1** (golden-diff schema tolerance) stays P2, unaffected by Phase 6.
- **F-5** (party flashlight sharing) stays routed to Phase 7, untouched by
  Phase 6.
- **Context-chip/bag-type/trip-type UNTESTED tail (14 rows)** is pre-existing,
  outside Phase 6's scope, and unaffected — carried forward exactly as Phase 5
  left it (`docs/engine-audits/2026-09-03-phase-5-activity-contracts.md`).

Presentation remains frozen. Physical-device App Attest and UI/UX
verification remain deferred, not complete. M3B/M3C remain blocked by their
existing gate. Phase 7 (central constraints/party sharing, F-5), Phase 8
(trace productization), and Phase 9+ (context intelligence) are not started.

## Deviations from the approved plan

Recorded rather than silently reconciled, following Phase 4/5's precedent:

1. **`WeatherNeedHardeningTests.seasonalOnlyStillRoutesThroughAddSeasonalOnly`**
   was corrected from asserting `clothing.light_jacket` (the plan's literal
   snippet) to `clothing.light_sweater`. On the actual pre-Phase-6 baseline,
   `addSeasonal` adds both `clothing.light_sweater` (from `coldEvenings`'s
   `signalAdds` row, prepended) and `clothing.light_jacket` for a winter/
   high-latitude trip; both map to `.warmthLight` in
   `CoverageResolver.itemCapabilities`, `clothing.light_sweater` sits earlier
   in `CoverageResolver.priority`, so it claims `.warmthLight` first and
   `clothing.light_jacket` is correctly suppressed as redundant — pre-existing
   coverage-dedup behavior, unrelated to Task 1's routing refactor. This RED
   result was recorded honestly (see RED verification above) rather than
   assumed away.
2. **`WeatherNeedHardeningTests`'s `weather(fixture:start:days:)` helper**
   builds a `TripWeatherContext` via `WeatherForecastNormalizer.context`
   directly rather than `MockWeatherService.context(from:...)` as the plan's
   snippet showed. `MockWeatherService.context` tiles a fixture's days
   cyclically to fill the full requested span and always reports
   `forecastAvailableForWholeTrip: true`, so it can never itself produce a
   `.partial` `WeatherQuality` from a short named fixture — using it as
   written would have invented daily precision for the uncovered days, the
   exact thing this phase's design forbids. `WeatherForecastNormalizer.context`
   already computes whole-vs-partial coverage correctly (per
   `WeatherChangeTests.partialForecastDoesNotCoverA30DayTrip`) and is reused
   directly instead.
3. **Task 2's two new unit tests use trip type `.vacation`** instead of the
   plan's `cityBreak` default. `cityBreak`'s own `trip-types.json` `add` row
   already includes `essentials.sunglasses`, so by the time `addSeasonal` ran,
   the item was already `collected` with a `trip_type.generic` reason;
   `addSeasonal`'s never-overwrite guard correctly left it alone (working
   exactly as designed), which meant the item's presence no longer
   demonstrated the seasonal-remainder mechanism at all. `.vacation` (also
   golden fixture 33's trip type) adds neither sunglasses nor sunscreen
   generically, so both items genuinely exercise the new path.
4. **Golden fixture 33 does not itself exercise `.partial` `WeatherQuality`**
   — see the first Routed finding above. Its `proves` field was corrected to
   state this explicitly rather than overclaim; the partial-forecast blend is
   proven at the unit level instead.
5. **Recording env var:** `TEST_RUNNER_PACKWISE_RECORD_GOLDENS=1`, not
   `PACKWISE_RECORD_GOLDENS=1` as the plan's shell snippets show — see Routed
   findings.
6. **File organization:** Task 3's two new tests
   (`sustainedColdWithoutSnowProducesOrdinaryGlovesNotSkiGloves`,
   `merelyCoolEveningsDoNotProduceGloves`) were drafted first inside
   `WeatherNeedHardeningTests.swift` with a locally-defined synthetic-weather
   helper, then moved into `CoverageTests.swift` (using its own existing
   `weather(...)` helper) per the plan's explicit file-organization
   instruction, before being committed in their final location.
7. **Test-authoring order, not content:** all of `WeatherNeedHardeningTests.swift`'s
   test methods (Tasks 1–5's) were drafted in one file-creation pass rather
   than incrementally per task, for session efficiency. RED/GREEN verification
   was still performed and recorded per task exactly as the plan requires
   (see RED verification above), by running the relevant subset of tests at
   each task boundary — no verification step was skipped. One consequence:
   Task 4 required no production or test-file change at its own checkpoint
   (its tests were already present and already green from Task 1's initial
   commit), so no separate "test: pin the wind, heat-and-sun, and
   day-night-swing weather composition matrix" commit exists — that content
   is fully captured in commit `7e36ec7`.

## Exit gate

1. `WeatherQuality` routing is a zero-diff refactor (Task 1) — **green**.
2. Partial forecast blends precise + seasonal-remainder without inventing
   daily precision (Task 2) — **green**.
3. Cold-without-snow gloves decided and tested, not routed a third time
   (Task 3) — **green**.
4. All eight named exit scenarios have execution evidence — **green**.
5. All four review guards hold in real generated output, not only in test
   text — **green**.
6. `WeatherSignal` (11), `PackingCapability` (12), `ActivityNeed` (8)
   unchanged; no `weather.json` threshold moved — **green**.
7. `WeatherChangeReconciler`/`TripWeatherRefresh`/`TripWeatherResolver`/
   `WeatherRefreshPolicy`/`MockWeatherService` byte-unchanged — **green**.
8. Golden diffs contain only the 4 approved new fixtures; 0 unexpected
   changes to 1–32 — **green**.
9. User authority preserved (Not Needed, manual quantity, user-added,
   packed, owner/carrier) — **green**.
10. Focused suites, engine audit, full iOS, shared, and API gates — **green**.
11. Phase 6 evidence committed separately; Phase 7 unopened — **green on
    closure commit**.
