# Weather and Packing Impact

PackWise is not a general weather app. Weather exists only to change packing.

M1, M2A, M2B, and **M2C are closed**. Packing Impact remains an explanation layer over persisted provenance. Weather-change diffs never silently rewrite the list. No M4 notifications.

## M2A — WeatherKit foundation (closed)

Plumbing only. Real weather is infrastructure. It does not leak WeatherKit types or M2B/M2C product behavior into the app.

```text
MapKit destination
        ↓
coordinates + timezone
        ↓
WeatherKitWeatherService
        ↓
normalized TripWeatherContext
        ↓
WeatherSnapshot persistence/cache
        ↓
Packing engine weather signals
```

Domain never consumes WeatherKit types. The packing engine only sees `TripWeatherContext`.

## M2B — Packing Impact (closed)

Show the user how current trip conditions affected the packing list.

```text
TripWeatherContext
        ↓
Packing Engine
        ↓
PackingSuggestion (reasonCode, reasonArguments, sourceSignals)
        ↓
Recommendation Resolver
        ↓
Persisted PackingItem
        ↓
PackingImpactBuilder
        ↓
Packing Impact UI
```

`PackingImpactBuilder` is a grouping/presentation layer, not another rules engine.

**Packing Impact does not infer recommendations. It explains recommendations the engine already made.**

Never independently decide “UV is 7, therefore add sunscreen.” That remains engine responsibility.

### Compact Trip Detail

Place Packing Impact below the trip/weather headline and above the checklist.

- Hide the section entirely when weather caused no packing change. Do not show “No weather impact on your packing list.”
- Group by meaningful weather signal. Family trips get one rain impact, not one card per traveler.
- Compact summary can collapse personal rain layers plus shared umbrellas; tap to list Krishna / Maya / Arjun / Shared.
- **View Weather** opens a restrained read-only weather detail page.
- Read-only weather detail has no refresh controls. List edits from weather belong to M2C.

### Weather detail (restrained)

Destination, trip forecast summary, daily strip, only relevant precipitation / UV / wind / snow, Packing Impact, Apple Weather attribution when the snapshot is Apple weather. No hourly chart. Fixture weather must not claim Apple Weather.

### Copy

Deterministic templates from `reasonCode` + arguments (`shared/rules/reasons.json`). Do not store arbitrary final prose. GPT is not required and must not become necessary.

### “Why this?” consistency

Packing Impact only surfaces the weather contribution. If Impact says cool evenings added a light sweater, Why this? must agree on weather provenance for that item. Activity sources may also exist; they are not the Impact grouping key.

### Coverage honesty

```text
forecastComplete     → real weather + Packing Impact
forecastPartial      → “Forecast available for part of your trip.” Impact only claims covered dates (from item provenance)
seasonalOnly         → not called Packing Impact from weather unless seasonal rules actually affected the list; then “Seasonal conditions,” visually distinct
failedUsingCache     → show the cached forecast normally
unavailable          → no weather card / no impact; packing list continues
```

### M2B acceptance

1. Packing Impact is derived from persisted recommendation provenance.
2. It never independently recommends or removes items.
3. Weather-only impacts are grouped by meaningful signal.
4. Personal and shared affected items both work.
5. Family trips do not produce repetitive duplicate cards.
6. “Why this?” remains consistent with Packing Impact.
7. No impact section appears when weather caused no packing change.
8. Fixture weather works in simulator/previews.
9. Real WeatherKit snapshots show Apple attribution; fixtures do not.
10. Partial / far-future / no-weather states do not overclaim forecast certainty.
11. Existing packing behavior remains unchanged.
12. No weather refresh or diff behavior is added yet.

## Trip weather state

Internal rendering states. Do not expose these names in UI.

```text
unavailable
seasonalOnly
forecastPartial
forecastComplete
stale
refreshing
failedUsingCache
```

## Weather refresh vs recommendation refresh

Keep these separate. M2A obtains and persists snapshots. M2C decides whether packing should change.

```text
Weather refresh
= obtain a newer snapshot

Recommendation refresh
= determine whether that snapshot materially changes packing
```

A forecast can move `72°F → 70°F` without bothering the user.

```text
raw forecast change
      ↓
weather signal change?
      ↓
packing consequence change?
      ↓
only then notify/show diff
```

## Packing Impact examples

```text
Rain expected Saturday
→ Rain jacket added

Cool evenings
→ Light layer added

High UV
→ Sunscreen recommended
```

Other contexts can have packing impact later.

### Carry-on Impact

> PackWise reduced duplicate clothing to help keep the list smaller.

### Activity Impact

> Hiking added trail footwear and a daypack.

This is what differentiates PackWise weather from Apple Weather.

## Weather must focus on trip dates

If the trip is Sep 12–16, show Sep 12–16.

Do not show current 10-day city weather simply because WeatherKit provides it.

Trip context always wins.

## Future weather

For faraway trips:

> **Forecast isn't available yet.**
>
> Your list currently uses seasonal conditions and trip details. PackWise will check the forecast closer to departure.

Once forecast becomes available (M2C):

> **The forecast is in.**
>
> 3 suggestions changed.

Then the user reviews.

## M2C — Weather-change diffs (closed)

```text
Snapshot A
   ↓
fetch Snapshot B
   ↓
normalized signal diff
   ↓
packing consequence?
   ↓
recommendationDiff()
   ↓
WeatherChangeProposal (pending)
   ↓
user review
   ↓
apply selected changes
```

Compare **normalized packing signals**, not raw WeatherKit values. `72°F → 69°F` is not a packing event. `no rain → meaningfulRain` is.

A raw forecast change is not a packing change. The list stays user-owned until a proposal is explicitly applied.

### Frozen lifecycle

**One actionable proposal per trip.** A newer refresh reconciles against the current list and newest snapshot, then replaces the pending proposal. The previous pending record is `superseded`, not stacked. Historical proposals may remain internally. The UI shows only the current pending proposal.

**Stale proposals are invalidated** before present/apply against trip context and the current packing list. If the user already added a suggested item, that add is pruned. If the remaining diff is empty, or the trip was edited, the proposal is `invalidated` and cannot apply. Packed-state-only changes do not invalidate.

**Snapshot persistence and proposal acceptance are separate.** Save the new `WeatherSnapshot` immediately. A packing consequence becomes a pending proposal. Dismissing the proposal leaves the forecast current and the list unchanged. The user is rejecting the packing change, not the forecast.

**Dismiss is not Not Needed.** `Not Needed` is an explicit item-level rejection and writes `TripRecommendationOverride`. Dismissing weather changes (`Keep List`) only marks the proposal `dismissed`. It must not create the same history.

Internal proposal states (never shown as these words):

```text
pending
applied
dismissed
superseded
invalidated
```

Refresh when the trip opens or the app becomes active, if the snapshot is expired or a seasonal trip has entered the forecast horizon. Do not add pull-to-refresh or background notifications in M2. M4 notifications sit on top of an existing pending proposal; they do not own weather logic.

M1 preservation still applies: Not Needed is never silently restored, manual quantities and custom items are preserved, packed state is preserved, removals are never auto-applied.

Engineering freeze is done. A signed WeatherKit pass on a physical iPhone remains the last M2 verification: live forecast, Packing Impact, Apple attribution, cached reopen, Weather Changed review/apply, and packed / custom / manual / Not Needed preservation.

## Weather change flow

Never silently wreck someone's list.

Weather refresh produces a new `WeatherSnapshot`. Only a **meaningful** packing-signal change reruns recommendation logic and creates a proposal from `recommendationDiff()`.

Example:

**Weather Changed**

> Rain is now expected Saturday.

PackWise suggests:

```text
+ Light rain jacket
+ Compact umbrella
```

The same review sheet as Edit Trip. Additions default on; removals default off. **User always controls the list.**

Buttons on the review sheet:

- **Update List** — apply the selected suggestion rows
- **Keep List** — dismiss this proposal now; do not write Not Needed overrides

`Not Needed` remains an item-level action on a packing row, not a weather-card action.

## If something is no longer needed

Example:

> Temperatures are now expected to be 12°F warmer.

Potential suggestion:

```text
Heavy sweater may no longer be necessary.
```

Buttons:

- **Remove**
- **Keep**

The user always controls the list.

## Architecture notes

Weather implementation details live in [data-privacy-and-platform.md](data-privacy-and-platform.md):

- WeatherKit → adapter → `TripWeatherContext`
- Store a local `WeatherSnapshot`
- Diff only meaningful changes (M2C)
- Produce a packing recommendation diff
- User accepts or rejects

Domain logic never deals directly with WeatherKit types. `PackingImpactBuilder` only groups existing item provenance.
