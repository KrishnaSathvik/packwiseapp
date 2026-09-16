# Task 13.1 — quantity editor domain

Baseline: `7d7cc4d`, `product-v2-stage-a`. This fixes F13-1 without changing engine decisions.

## Audit before implementation

All 52 current golden fixtures contain 1,717 records. Maximum observed: **35**, `kids.diapers`, in `12-family-toddler-7d-seasonal` and `16-minneapolis-7d-winter-family`. Rule: toddler rate 5/day × min(duration, 7).

| Route | Domain / maximum |
| --- | --- |
| ClothingQuantity daily tops, underwear, socks | Adult policy caps 15; post-cap infant multipliers produce tops 27 and underwear 23; toddler tops 27, underwear/socks 21 |
| ClothingQuantity bottoms/hot bottoms | Adult cap 8; toddler bottoms multiplier 1.4 produces 12; hot bottoms have no multiplier |
| ClothingQuantity sleep/workout/swim | 2 / 6 / 2 respectively; selected or dated activity uses remain capped |
| WarmLayerQuantities | Sweater/thermal top 3, thermal bottom 2 |
| CareQuantity diapers | Infant 8/day × 7 = **56**; toddler 5/day × 7 = 35, then restock plateau |
| CareQuantity extra outfits | ceil(days/3), capped at 3 |
| Catalog `one` | Fixed 1 before shared scaling; activity equipment also uses this route |
| Legacy `layer`, `formal_top` | Style-fixed, maximum 2 (warm rotation can override layer) |
| Legacy `dresses` | ceil(days/4) light/balanced; ceil(days/3) prepared; **no product cap** |
| Legacy daily/style/reuse/workout policies | Duration formulas remain in quantities.json, but their clothing kinds route through ClothingQuantity instead |
| Legacy `toddler_backup` | Duration plus style buffer remains declared, but both catalog consumers (diapers/extra outfits) route through CareQuantity first |
| Shared single-per-party | Fixed 1 in current policies |
| Shared party/device scaling | ceil(eligible consumers/per) or ceil(resolved devices/per); no policy cap |
| Shared duration × party | Snacks: ceil(eligible consumers × days/4); no policy cap |

All 202 catalog entries were enumerated by `quantity_kind`; all 15 policy keys in `shared/rules/quantities.json` and sharing policies in `party.json` were inspected against routing in `PackingEngine.applyQuantities`. Defaults do not establish a separate editor maximum. Trip dates and sharing do not establish a finite product quantity cap. Thus **56 is a bounded-family maximum, not the complete engine maximum**. For example 365 days with four eligible snack consumers produces 365; dresses may also exceed 56.

## Decision

Both Item Detail and Add Item use **one `QuantityEditorPolicy.range = 1...Int.max`**. The upper bound is the existing Swift `Int` storage domain, not an invented product limit. Every valid positive persisted/generated quantity fits. Opening has no normalization/clamping side effect. Native Stepper bounds disable decrement at 1 and increment at Int.max. No change to generator math, catalog, rules, schema, ownership, or quantity authority.

This does not claim the engine can safely compute trips at Int.max duration: intermediate arithmetic has its own limits. It means the editor can represent the positive quantity value already stored. Direct numeric entry for very large counts could be a later usability enhancement.

## Verification boundaries

Regression coverage: 1, 5, 30, 35, 56, 1000 and Int.max; legal decrement/increment arithmetic; disk save and two independent container reopens; manual authority, packed count, category, owner and carrier preserved. Existing regeneration test now uses manual quantity **35**, retaining checks for packed state, Not Needed and carrier through a changed activity. Existing engine tests independently prove generated toddler diapers = 35.

These are automated model/domain tests, **not a UI tap test or physical process relaunch**. Physical Item Detail open → decrement → increment → save → relaunch remains required by the exit checkpoint. No spoken VoiceOver result is inferred from these tests.
