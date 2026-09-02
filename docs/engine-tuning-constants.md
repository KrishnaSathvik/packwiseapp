# Engine tuning constants — inventory

Every judgment encoded as a constant in the packing engine: where it lives,
what it means, and where the same judgment lives twice. Surveyed 2026-09-02
against `ios/PackWise/Domain`. A model with no constants has no opinions;
the governance question is whether each opinion has exactly one home.

## The three layers

1. **Shared JSON rules** (`shared/rules/`) — data, validated by
   `scripts/validate_shared.py`, shared with the API. Most of the domain
   lives here: base essentials, trip types, activities, weather signal→item
   adds and thresholds, legacy quantity policies, substitutions, party
   sharing policies, age multipliers, reason templates.
2. **Named Swift policy tables** — constants with names, rationale
   comments, and property tests, but requiring a code change to tune:
   `ClothingNeedPolicy.all`, `CareQuantityEngine`, `CoverageResolver`'s
   capability map.
3. **Inline Swift literals** — a handful of small numbers inside
   functions. The shortest list, but the least discoverable.

## Layer 2 — named Swift constants

### ClothingQuantity.swift — `ClothingNeedPolicy.all` (the V2 clothing opinion set)

Six policies (daily_top, daily_underwear, daily_socks, bottoms, sleepwear,
workout), each declaring:

| Field | Meaning | Example values |
|---|---|---|
| `wearsPerItem` (per style) | Days of wear before washing | tops 1.5/1.25/1.0; bottoms 3/2.5/2 |
| `washIntervalDays` | Planned-laundry plateau | 7 (tops/underwear/socks), 10 (bottoms) |
| `styleBuffer` (per style) | Backups added after the laundry decision | 0/1/2 for light/balanced/prepared |
| `minimum` | Floor regardless of trip | 2 daily kinds, 1 bottoms/sleep/workout |
| `styleMaximum` (per style) | No-laundry growth cap | tops 8/12/15 |
| `constrainedBagMaximum`, `personalItemMaximum` | Bag-binding caps | tops 8 / 5 |
| workout divisors | Days per workout by style | light 3, else 2 |
| possible-laundry interpolation | A third of the way from plateau to capped no-laundry | `/ 3` in `resolve` |

All in one file, one table, guarded by the sensitivity property tests
(every declared sensitivity must produce a strict divergence). This is the
engine's core opinion set and it is well-governed — but it is *not* in the
shared data layer, and the API cannot see it.

### CareQuantity.swift — `CareQuantityEngine` (Slice 8)

| Constant | Value | Meaning |
|---|---|---|
| `dailyDiaperRate` | toddler 5, infant 8 | Diapers consumed per day |
| `diaperRestockDays` | 7 | Replenishment horizon — the consumable plateau |
| `diaperedUnderwearBackup` | 3 | Pairs kept beside diapers (partial coverage, potty-training safety) |
| extra-outfit buffer | ceil(days/3), max 3 | Accident buffer, not a second wardrobe |

Named, commented with rationale, test-pinned.

### CoverageResolver.swift — capability map

Not numeric, but policy-as-code: which garment claims which capability
(winter coat → warmth_heavy + wind_shell; rain jacket → rain_shell; …).
Decides suppressions like windbreaker-under-winter-coat. Lives in Swift
only.

## Layer 3 — inline literals worth knowing about

| Site | Value | Meaning |
|---|---|---|
| `WeatherNormalization.swift:4-6` | 10 / 0.35 / 0.6 | Daily-forecast horizon; **rain-day and heavy-rain thresholds — see finding 1** |
| `WeatherDomain.swift:283` | 0.5 | persistentRain = rain on ≥ half the trip days; not in weather.json's thresholds block with its siblings |
| `WeatherDomain.swift:151` | 0.35 | Default `rainThreshold` param on `compactHeadline` — third home for the rain threshold |
| `PackingEngine.swift:475` | 2 | Rain days needed before a second rain-related add |
| `PackingImpact.swift:125` | 2 | Days that upgrade meaningfulRain → persistentRain in impact copy |
| `PackingImpact.swift:276` | 2 | Personal-item count that collapses a rain diff row |

## Layer 1 — JSON (already governed)

`weather.json` thresholds (cold 48°F, hot 82°F, wind 22mph, UV 6, swing
20°F, rain 0.35, heavy 0.6) · `quantities.json` legacy per-kind policies
(style factors, plus/minus, caps — including `toddler_backup`, now
overridden by CareQuantityEngine for its two items) · `party.json` age
multipliers, sharing per/min, skip lists · `substitutions.json` ·
`base.json` / `trip-types.json` / `activity-rules.json` · catalog
`quantity_kind` routing. One home each, validator-checked.

## Findings

1. **The rain-day threshold had three homes and two production readers**
   (plus a fourth copy in `MockWeatherService`'s aggregation). ~~Fixed in
   Slice 9 (`9c42da5`)~~: the normalizer's defaults now load from
   weather.json with a test pinning them to the file
   (`normalizerThresholdsComeFromSharedRules`), and day classification
   lives in `isRainDay`/`isWinterPrecipDay` helpers shared by every
   aggregator. The Swift literals remain only as bundle-load fallbacks.

2. **The "prepared buffers +3" test: two files, routed by quantity kind.**
   For the V2 clothing needs the buffer is `styleBuffer` in
   `ClothingNeedPolicy.all` (one file, six entries, greppable). For every
   legacy kind it is the per-style `plus`/`laundryPlus` values in
   `quantities.json`. Whether a given item reads Swift or JSON depends on
   `ClothingQuantityEngine.handles(kind)` — invisible from either file.
   Not a three-file smell, but you must know the routing to find both.

3. **persistentRain's 0.5 ratio was the one threshold not in
   weather.json.** ~~Fixed in Slice 9~~: it now lives in the thresholds
   block as `persistent_rain_ratio`, beside `freezing_max_f` which
   arrived with the temperature dimension.

4. **Verdict on the original question:** no hardcoded *outputs* — every
   quantity in the goldens moves when its declared inputs move, and the
   sensitivity tests enforce that. The parameters are almost all named and
   clustered (two tables + one JSON layer); the residue is six inline
   literals and one genuinely duplicated judgment (finding 1), which is
   the only place the current arrangement could silently mislead.
