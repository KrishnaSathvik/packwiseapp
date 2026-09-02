# Slice 9 — the temperature dimension

**Trigger:** the first cold-weather human read (fixtures 15/16,
MinneapolisDeepWinter). Worst list the engine had produced: six t-shirts
and one light sweater for a week at 8°F. A wrong list, not a wrong number —
someone following it gets hurt. Second finding, more damning: the catalog's
`thermal_top`, `thermal_bottom`, `scarf`, and `hoodie` were reachable only
through the skiSnow trip type — capability-shaped decoration, the fourth
never-fired artifact this rebuild.

## What landed (`9c42da5`, plus fixtures in `e454e1a`)

- **Two signals off the trip's warmest day.** `sustainedCold` (≤ 48°F) adds
  the mid layers (light sweater, hoodie); `freezingCold` (≤ 32°F) adds
  thermal base layers and a scarf. Thresholds live in weather.json
  (`freezing_max_f`), adds in its signalAdds block.
- **Warm layers rotate.** `WarmLayerQuantities` (id-routed, catalog
  frozen): ceil(days/3) capped at 3 for sweaters and thermal tops, 2
  thermal bottoms past four days. An 8°F week is now 2 sweaters + hoodie +
  2-3 thermals + scarf over the winter kit.
- **Sub-freezing precipitation is winter precipitation.** Normalization
  counts a precip day with a high ≤ freezing as a snow day, not a rain
  day — the sleet day stops packing an umbrella and a rain shell beside
  the parka. Above freezing, cold rain still earns the shell
  (`coldRainAboveFreezingStillPacksTheShell` pins it): the fix is a
  temperature gate, **not** the parka claiming `rain_shell` — the same
  no-over-claiming discipline as Step 3's warmth_light ruling.
- **One home for the rain threshold.** The split-source bug from the
  constants inventory: Trip Detail read weather.json's 0.35 while the
  engine's rainDays used the normalizer's own copy — and the mock service
  carried a fourth. Now the normalizer's defaults load from weather.json
  (a test pins them to the file), day classification lives in
  `isRainDay`/`isWinterPrecipDay` helpers both aggregators share, and
  `persistentRain`'s 0.5 moved into the thresholds block beside its
  siblings.
- **Toddler bottoms multiplier (1.4)** — the Slice 8 residual, promoted
  because cold made it dangerous. Five pants for a toddler week, not three.

## Golden diff, read before believed

Only fixtures 15, 16, and 12 moved. 15/16: umbrella and rain jacket out;
hoodie, scarf, rotated sweaters and thermals in; every new row carries a
specific reason ("Cold through your whole trip — plan to layer", "Sub-
freezing temperatures are expected", "2 to rotate through 6 cold days").
12: pants 3→5, nothing else. The two-umbrella family row and its "1 days"
copy disappeared as a side effect of reclassification; the pluralization
template bug itself still exists for real rain trips and stays on the P2
tail.

## Residuals, seen and left

- The rotation caps assume the whole trip is cold when the warmest day is
  cold — a mixed itinerary (one warm day in a cold week) drops the signal
  entirely, because signals read trip-level max temp. Aggregate
  granularity, known limitation, revisit with trip segments.
- Toddler still gets a phone charger and power bank (carried from Slice 8).
- `heavyRainDays` freezing-gating is expressed inline in two places
  (normalizer and mock) rather than a shared helper.

## Verification

136 iOS tests green (5 new: rotation, cool-fall single-layer pin,
freezing-drizzle reclassification, above-freezing shell pin, threshold
single-source pin; plus toddler bottoms in the engine suite), API 106
green, goldens deterministic across compare runs.
