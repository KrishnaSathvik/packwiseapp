# Product Hardening Phase 6 — Weather Need Hardening Design

**Date:** 2026-09-04
**Base:** `product-hardening-phase1` at `e958c07`
**State:** approved design; implementation not started

## Objective

Normalized weather (precise, partial, seasonal, cached, failed) maps to
conservative packing needs without inventing precision the forecast doesn't
have. A partial forecast's covered dates keep their exact signals; its
uncovered dates fall back to the same seasonal heuristic already trusted for
a fully-unforecast trip — never zero, never invented daily detail. The
routed cold-without-snow glove question is decided and tested, not left
routed a third time. Eight named composite scenarios — hot+rain, cold+rain,
wind+mild, heat+strong-sun, hot-day/cool-night, snow+business, rain+hiking,
rain+couple — each have execution evidence, existing or new.

## The current shape

Four files carry weather from a forecast to a packing item, and Phase 6
touches exactly these, none of the WeatherKit fetch/cache/proposal plumbing
around them:

- `WeatherSignalExtractor.extract(weather:thresholds:outdoorActivities:tripDays:)`
  (`ios/PackWise/Domain/Weather/WeatherDomain.swift:276`) turns one
  `TripWeatherContext` into a `Set<WeatherSignal>` — 11 closed cases,
  threshold-driven, from `shared/rules/weather.json`'s `thresholds` block.
- `PackingEngine.addWeather(context:into:)`
  (`ios/PackWise/Domain/Packing/PackingEngine.swift:518`) turns signals into
  candidate items via `rules.weather.signalAdds`, one `if signals.contains`
  block per signal, each keeping the highest-tier reason when an item is
  already claimed by another family.
- `PackingEngine.addSeasonal(context:into:)` (`:610`) is the zero-forecast
  fallback: month + latitude only (`winter && |lat|>30` adds a light layer,
  `summer && |lat|<45` adds sunscreen + sunglasses), gated by
  `guard ... collected[id] == nil` so it never overwrites a higher-tier item.
- `CoverageResolver.needs(context:)` / `CoverageContext.init(snapshot:thresholds:)`
  (`ios/PackWise/Domain/Packing/CoverageResolver.swift:29,171`) is Phase 4's
  closed capability layer: it independently re-derives the same signal set
  from `snapshot.weather` (its own inline
  `weather.isPreciseForecast || !weather.dailyForecast.isEmpty` check,
  parallel to `addWeather`'s) to decide which capabilities — `.rainShell`,
  `.warmthLight`, `.warmthHeavy`, `.windShell`, `.coldFootwear`,
  `.coldHands` — a trip needs, then suppresses duplicate items that claim an
  already-covered capability.

One more piece already exists and is currently unread by any of the above:
`TripContextSnapshot.weatherQuality: WeatherQuality`
(`ios/PackWise/Domain/TripContextSnapshot.swift:112`), Phase 2's typed
`missing` / `seasonalOnly` / `partial(coveredDays:tripDays:)` / `complete`
classification, computed every generation and — per the Phase 2 closure
note — "read by no decision logic anywhere in the engine." `addWeather` and
`CoverageContext` each re-derive their own cruder version of the same
question inline. This is exactly the "natural extension of an existing
surface" the master roadmap asks Phase 6 to check for, and it already
exists, unused.

`WeatherChangeReconciler`, `TripWeatherRefresh`, `TripWeatherResolver`,
`WeatherRefreshPolicy`, and `MockWeatherService` are the fetch/cache/proposal
infrastructure. `WeatherChangeReconciler.reconcile` already calls
`engine.recommendationDiff`, which calls the same `generateDetailed` this
design changes — so a Phase 6 behavior change reaches proposals for free,
with no reconciler edit. None of these five files change in Phase 6.

## What already passes — cited, not re-invented

Reading the actual test suites before designing anything found real,
green, already-specific evidence for four of the eight named scenarios and
the partial-forecast *classification* half of a fifth:

| Scenario | Evidence | What it proves |
| --- | --- | --- |
| hot+rain | `CoverageTests.hotRainDropsShellKeepsUmbrella` | Miami, 91°F/rain 0.45: umbrella survives, rain jacket is suppressed as refuted (warm rain is umbrella weather) |
| cold+rain | `CoverageTests.coldRainKeepsShell` | Seattle, 57°F/rain 0.6: rain jacket survives |
| rain+wind (adjacent) | `CoverageTests.rainShellCoversWind` | rain jacket suppresses windbreaker with named coverage |
| large swing | `CoverageTests.temperatureSwingKeepsOneLightLayer` | exactly one light layer, not two |
| winter layering | `CoverageTests.winterLayeringSurvivesCoverage` | coat + sweater + boots all survive together |
| ski/cold-hand boundary | `CoverageTests.skiGlovesCoverColdHandsWithoutAnIDPairRule`, `coldNonSkiTripNeedsColdHandsButNotSnowSportHands`, `skiIntentResolvesHandOverlapWithoutForecastWeather` | ski gloves suppress ordinary gloves generically; **`coldNonSkiTripNeedsColdHandsButNotSnowSportHands` proves `.coldHands` is already a real coverage need on a cold, non-ski trip — using a synthetically injected `clothing.gloves` candidate, because nothing in the engine emits one there today** |
| partial-forecast classification | `WeatherChangeTests.partialForecastDoesNotCoverA30DayTrip` | a 30-day trip with 10 days of provider data is correctly flagged `forecastAvailableForPartialTrip`, not silently treated as complete |
| rain+couple | golden fixture `11-couple-5d-rain` ("Personal rain layers, shared umbrella ×1") | personal-vs-shared rain coverage for a party already reviewed and frozen |
| Phoenix heat, no cold bloat | golden fixture `19-phoenix-5d-city-walking-hot` | PhoenixHotDry (108°F, UV 10-11, swing 25°F — already both hot **and** high-swing) produces no cold-weather gear |

Phase 6 does not re-derive these. It cites them as baseline and adds
regression coverage only where a task's own change could disturb them.

## Gaps found — each mapped to a task

1. **Partial forecast never blends with seasonal for its uncovered
   remainder.** `addWeather`'s guard is
   `weather.isPreciseForecast || !weather.dailyForecast.isEmpty` — true for
   *any* non-empty forecast, partial or complete — so a 30-day trip with 10
   days of real data gets exactly those 10 days' signals and **nothing** for
   the other 20: no seasonal warmth check, no seasonal sun check, nothing.
   `addSeasonal` is never called. This is the literal gap the master
   roadmap's "combine precise covered dates with seasonal uncovered dates
   without inventing precision" describes, and Task 1's `WeatherQuality`
   routing plus Task 2's blend closes it. → **Task 2.**
2. **Cold-without-snow gloves.** `shared/rules/weather.json`'s
   `signalAdds` only lists `clothing.gloves` under `snowExposure`; the only
   other glove source is `trip-types.json`'s `skiSnow` row
   (`activities.ski_gloves`, unconditional). `CoverageResolver.needs`
   already inserts `.coldHands` whenever weather signals intersect
   `[snowExposure, sustainedCold, freezingCold]` — proven live by
   `coldNonSkiTripNeedsColdHandsButNotSnowSportHands`, which has to inject a
   synthetic candidate to exercise that need because nothing real ever
   reaches it. A cold, non-snow, non-ski trip (Reykjavik in named-fixtures,
   currently unused by any golden fixture: highs 39-44°F, zero snow days)
   generates no hand protection at all today. → **Task 3.**
3. **wind+mild is untested in isolation.** The only windbreaker test,
   `rainShellCoversWind`, pairs wind with rain specifically to prove
   suppression; nothing proves a windbreaker actually survives and appears
   when wind is high and rain/cold are both absent. → **Task 4.**
4. **heat+strong-sun composition is untested.** `hotOutdoorExposure` and
   `highUVExposure` both list `toiletries.sunscreen` in their own
   `signalAdds` row; nothing pins that firing both at once yields exactly
   one sunscreen row (not two, not a downgrade) plus sunglasses and a sun
   hat. → **Task 4.**
5. **hot-day/cool-night is untested and structurally never exercised.** No
   existing fixture or unit test sets `hotOutdoorExposure`,
   `coldEvenings`, and `largeTemperatureSwing` simultaneously (a desert
   day/night swing — e.g. 85°F high, 58°F low, both thresholds and the
   20°F swing cross at once). → **Task 4.**
6. **snow+business is untested.** No golden fixture pairs `.business` with
   a snow-producing weather fixture; `07-chicago-5d-business-checked` and
   `22-chicago-5d-business-running-overlap` both use `ChicagoRainyFall`
   (no snow). Reading the capability table shows no structural conflict —
   `footwear.dress_shoes → .formal`, `footwear.boots → .coldFootwear`,
   distinct capabilities — but "no visible conflict on paper" is not
   evidence; Phase 6 must generate it and read the actual list. → **Task 5.**
7. **rain+hiking is untested.** Every golden fixture that selects
   `hiking` uses `weatherFixture: null` (seasonal) or `DenverColdOutdoor`
   (cold+snow, fixture 32); none combine hiking with a rain signal to prove
   the rain shell, `ActivityContracts.needs(for: ["hiking"])`'s trail
   footwear/day-carry/hydration/blister-care, and the coverage suppression
   of ordinary walking shoes all compose without duplication. → **Task 5.**

## Architecture: route both weather-reading families through `WeatherQuality`

Both `addWeather` and `CoverageContext` currently answer "do I have real
forecast data" with their own inline
`weather.isPreciseForecast || !weather.dailyForecast.isEmpty` check. Task 1
replaces both with a `switch` on the snapshot's existing
`weatherQuality: WeatherQuality`, so partial/seasonal/missing/complete is
answered in exactly one place instead of two copies that could drift.

```text
snapshot.weatherQuality
        ├─ .complete            → today's addWeather behavior, unchanged
        ├─ .partial(covered, _) → today's addWeather behavior on the
        │                          covered days, PLUS addSeasonal's
        │                          heuristic for the remainder (Task 2)
        ├─ .seasonalOnly        → addSeasonal only, unchanged
        └─ .missing             → addSeasonal only, unchanged
```

This is a pure routing change with a zero-diff gate before Task 2 adds new
behavior: `.complete`, `.seasonalOnly`, and `.missing` must produce byte
identical output to today, proving the switch reproduces the two inline
checks it replaces before anything new is layered on `.partial`.

`addWeather`'s signature changes from `(context:into:)` to
`(context:snapshot:into:)` — `ruleSuggestions(for:snapshot:)` already holds
the snapshot Task 1 needs; no new compilation happens.

## Decision 1 — partial forecast blends with seasonal for its uncovered remainder

For `.partial(coveredDays:tripDays:)`, `addWeather` runs its existing
precise-day extraction and `add` calls exactly as today over
`weather.dailyForecast` (the covered days only — `WeatherSignalExtractor`
already only sees what's in the clipped forecast), and **then** calls
`addSeasonal(context:into:)` once, unconditionally, for the same trip.

This is safe by construction, not by a new guard: `addSeasonal` already
does `guard catalog.item(id: id) != nil, collected[id] == nil else {
continue }` for every candidate — it only ever fills a gap, never
overwrites or duplicates an item the precise days already justified. Calling
it after the precise pass on a partial forecast is the same call already
made unconditionally on a fully-missing forecast; Task 2 only widens *when*
it fires, not *what* it does. No new heuristic, no day-level invented
precision — the uncovered remainder gets exactly the same conservative
month/latitude signal a fully-unforecast trip already gets, and the covered
remainder keeps its exact provider data. `CoverageContext` needs the mirror
change: `usesSeasonalWarmthFallback` becomes true whenever
`weatherQuality` is `.partial` or `.seasonalOnly` or `.missing` (today it is
false whenever any forecast, even one partial day, exists), so a covered
rain shell need and an uncovered-remainder warmth need can both be true on
the same trip.

**New golden fixture** (Task 2): a trip whose `days` exceeds a named
weather fixture's day count, so the last several days are structurally
unforecast — a 10-day Chicago trip in July against `ChicagoRainyFall`'s 5
days of data. Chicago (41.8°N) is deliberately chosen over Seattle: its
precise window already trips `coldEvenings` (lows 58–61°F), so a
winter-fallback demonstration would immediately collide with Phase 4's
existing `.warmthLight` coverage dedup and the seasonal candidate would be
correctly *suppressed*, not present — an ambiguous, priority-order-dependent
assertion to build a design example around. The **summer** branch avoids
this entirely: `toiletries.sunscreen` and `essentials.sunglasses` map to no
`PackingCapability` at all, so nothing about them is ever suppressed, and
Chicago's precise window (highs 69–78°F, UV 3–5) never triggers
`hotOutdoorExposure` or `highUVExposure` on its own. Expected: the precise
5 days' rain signal fires exactly as fixtures 1/7/8/10/22/25/27 already show
for `ChicagoRainyFall`, and the seasonal-sun check runs once for the whole
trip's July classification, adding sunscreen and sunglasses for the
genuinely unforecast remainder — with no invented rain count for days 6–10
and no duplicate/competing warmth-layer decision to arbitrate.

## Decision 2 — cold-without-snow gloves

**Decision:** add `"clothing.gloves"` to `signalAdds.sustainedCold` in
`shared/rules/weather.json`. `sustainedCold` (max trip temperature ≤ 48°F)
is the broader signal — `freezingCold` (≤ 32°F) is a strict subset of it in
`WeatherSignalExtractor`, so anywhere `freezingCold` fires, `sustainedCold`
already fired too, and gloves already reach it. `snowExposure` keeps its
own existing row untouched, so a snow trip's gloves are unaffected. No new
`WeatherSignal` case, no new `PackingCapability`, no new reason code:
`clothing.gloves` already maps to `.coldHands` in
`CoverageResolver.itemCapabilities`, is already ordered behind
`activities.ski_gloves` in `CoverageResolver.priority` (so a ski trip's
existing ski-glove suppression is untouched), and `weather.sustained_cold`
is an existing rendered template.

This is the minimum change that closes the gap `coldNonSkiTripNeedsColdHandsButNotSnowSportHands`
already proved was open, reusing the exact mechanism (`signalAdds` →
`addWeather` → `CoverageResolver`) every other weather item already goes
through — not a new cold-hands code path.

**Alternative considered and rejected:** gating gloves on `coldEvenings`
instead of `sustainedCold`. `coldEvenings` (min temperature ≤ 62°F) fires
on far milder trips — a cool evening in Chicago in fall is not a
cold-hands trip — and would produce gloves on trips no user would expect
them on. `sustainedCold`'s "the warmest day is still cold" framing is the
one that actually means "you need your hands covered," matching its
existing reason copy ("Cold through your whole trip — plan to layer").

**New golden fixture** (Task 3): Reykjavik using the existing
`ReykjavikColdWindy` named weather fixture (currently unused by any golden
fixture) with a non-ski, non-snow trip type — highs 39–44°F (sustainedCold,
no snow day in the data), lows down to 28°F (coldEvenings), wind to 32 mph
(highWindExposure), one rain day at 40°F (coldRain, since `highF > 32` and
`rainProbability ≥ 0.35`). Expected new row: exactly one `clothing.gloves`,
reason `weather.sustained_cold`, no `activities.ski_gloves` (trip type
isn't `.skiSnow`), rain jacket present (coldRain forces the rain-shell need
even though the trip isn't purely hot), windbreaker suppressed by the rain
jacket per the existing `rainShellCoversWind` behavior.

## Decision 3 — the four composition scenarios are matrix unit tests, not new named weather fixtures

`CoverageTests.swift`'s private `weather(days:start:highF:lowF:rain:uv:wind:snow:swingDay:)`
helper already builds a synthetic single-day-repeated `TripWeatherContext`
inline — the same tool `hotRainDropsShellKeepsUmbrella` and
`coldRainKeepsShell` already use. wind+mild, heat+strong-sun, and
hot-day/cool-night are exact-threshold compositions, not scenarios that
need a destination, a party, or activities to be meaningful — the existing
matrix-test idiom (`requiredOverlapMatrixProducesMinimalFocusedSetsDeterministically`)
is the right size for them, not a new `shared/fixtures/weather/named-fixtures.json`
entry and a golden-diff review. Concretely:

- **wind+mild:** `highF: 68, lowF: 54, wind: 26, rain: 0.1` — no rain shell
  need, no cold-hand need, no seasonal warmth fallback; `clothing.windbreaker`
  present and *not* suppressed (nothing else claims `.windShell`).
- **heat+strong-sun:** `highF: 95, lowF: 75, uv: 10` — both `hotOutdoorExposure`
  and `highUVExposure` fire; exactly one `toiletries.sunscreen` row, one
  `essentials.sunglasses` row, `clothing.hat_sun` present, no duplication
  from the two independent `signalAdds` rows that both name sunscreen.
- **hot-day/cool-night:** `highF: 85, lowF: 58` — `hotOutdoorExposure`
  (85≥82), `coldEvenings` (58≤62), and `largeTemperatureSwing`
  (85−58=27≥20) all fire together; `clothing.shorts` and
  `clothing.light_sweater` both present (day heat and night cool are not
  contradictory), and `temperatureSwingKeepsOneLightLayer`'s "exactly one
  light layer" property still holds when a second signal (`coldEvenings`)
  also nominates the same layer.

## Decision 4 — snow+business and rain+hiking need new golden fixtures

Unlike Decision 3's threshold-only compositions, these two combine a
weather signal with a *different existing family* (trip type, activity
contracts) whose interaction is exactly what a reviewed golden fixture is
for — matching how Phase 5 added fixtures 28–32 rather than asserting
Camping's behavior purely in unit tests.

- **snow+business:** `.business` trip type + a snow-producing forecast
  (`DenverColdOutdoor`, unused for this purpose today). Read the actual
  list rather than assuming: dress shoes (`.formal`), boots
  (`.coldFootwear`), winter coat + gloves (`snowExposure`'s existing row),
  laptop/blazer (business's existing row) — and confirm nothing suppresses
  the walking shoes base-essential incorrectly, since neither dress shoes
  nor boots claim `.everydayWalking`.
- **rain+hiking:** `hiking` activity + a rain-producing forecast
  (`SeattleWetCity` or `ChicagoRainyFall`, neither currently paired with
  hiking). Confirm `ActivityContracts.needs(for: ["hiking"])`'s four
  candidates (trail footwear, day carry, hydration, blister care) and the
  weather-driven rain shell coexist with exactly one suppression
  (`footwear.walking_shoes` covered by `footwear.hiking_shoes`, per Phase
  4/5's existing evidence) and no duplicate rain item.

## Non-goals

- Rebuilding or rewiring `WeatherChangeReconciler`, `TripWeatherRefresh`,
  `TripWeatherResolver`, `WeatherRefreshPolicy`, or `MockWeatherService`.
  Phase 11 owns running V2 needs/coverage through the reconciler as a
  distinct integration step; Phase 6 changes what `generateDetailed`
  produces, which the reconciler already consumes via
  `engine.recommendationDiff` with no reconciler edit required.
- New `WeatherSignal` cases, new `PackingCapability` cases, or a new
  `ActivityNeed`. Every gap in this design closes with the existing
  closed vocabularies.
- Changing `WeatherSignalExtractor`'s thresholds. No threshold in
  `shared/rules/weather.json`'s `thresholds` block moves.
- UI, copy tone, notification, or lifecycle changes. `weather.sustained_cold`'s
  existing copy is reused verbatim for the new glove row.
- `WeatherChangeProposal`/proposal-diff behavior changes beyond what
  falls out of `generateDetailed` producing different candidates — no new
  proposal type, no new `WeatherSignalChange` case.
- Re-deriving evidence the test suite already has. Hot+rain, cold+rain,
  rain+wind suppression, temperature-swing dedup, winter layering, and
  rain+couple are cited, not re-implemented.
- A `headlamp` or any other new catalog item. `clothing.gloves` already
  exists and is fully wired into `CoverageResolver`.

## Verification plan

- `scripts/report_engine_goldens.py --baseline-ref e958c07` after each task:
  Task 1 must show **zero** row changes (pure routing); Tasks 2–5 show only
  the new/changed fixtures each task names, reviewed by hand before commit.
- Focused suites: `WeatherChangeTests`, `CoverageTests`, `ActivityContractTests`,
  `PackingEngineTests`, `TripContextSnapshotTests`, `GoldenEngineTests`.
- `scripts/run_engine_audit.sh`, full `xcodebuild test`, `python3 scripts/validate_shared.py`,
  `npm --prefix api run preflight` at close.
- `docs/engine-audits/<date>-phase-6-weather-need-hardening.md` exit report
  in the Phase 4/5 style: reviewed diff, per-scenario evidence table
  (existing-cited vs. new), routed findings.

## Routed findings anticipated

- **F-1** (golden-diff schema tolerance) stays P2, unaffected by Phase 6.
- **F-5** (party flashlight sharing) stays routed to Phase 7, untouched.
- Whether `WeatherChangeReconciler` should special-case a `.partial`-to-
  `.partial` refresh (more days arriving as the trip approaches, inside the
  existing 10-day provider horizon) as its own proposal category is a
  Phase 11 question; Phase 6 only changes what a single `generateDetailed`
  call produces for a partial snapshot, not the refresh cadence.
- Whether `CoverageContext`'s two remaining call sites (`addActivityNeeds`'s
  `hasColdSignal` computation and `CoverageResolver.needs`) should
  themselves be unified into one shared instance per generation, instead of
  each constructing their own `CoverageContext(snapshot:thresholds:)`, is a
  possible follow-on efficiency cleanup with no behavior difference — noted,
  not required for Phase 6's exit gate.
