# Recommendation trace coverage

Total item rows: **1717** (3 user-authority / exempt, 1714 engine-generated / scored).

## Inclusion completeness

| bucket | count | of engine-generated rows |
| --- | --- | --- |
| complete (base-essential) | 1099 | |
| complete (specific) | 505 | |
| **complete total** | **1604** | **93.6%** |
| generic-only (informational, not folded into the pass/fail metric) | 110 | |
| defect — missing reason code | 0 | |
| defect — missing causal signal | 0 | |
| **recommendations lacking causal structured provenance (refined exit metric)** | **0** | |

**Generic-only rows (110)**

- `01-chicago-5d-city-balanced: primary/essentials.sunglasses` (`trip_type.generic`: 'Suggested for a city break trip.')
- `04-tokyo-15d-prepared-checked: primary/travel_comfort.book` (`trip_type.generic`: 'Suggested for a vacation trip.')
- `07-chicago-5d-business-checked: primary/clothing.blazer` (`trip_type.generic`: 'Suggested for a business trip.')
- `07-chicago-5d-business-checked: primary/clothing.dress_shirt` (`trip_type.generic`: 'Suggested for a business trip.')
- `07-chicago-5d-business-checked: primary/footwear.dress_shoes` (`trip_type.generic`: 'Suggested for a business trip.')
- `08-running-sightseeing-footwear: primary/essentials.sunglasses` (`trip_type.generic`: 'Suggested for a city break trip.')
- `09-seattle-rain-layering: primary/essentials.sunglasses` (`trip_type.generic`: 'Suggested for a city break trip.')
- `10-one-day-trip: primary/essentials.sunglasses` (`trip_type.generic`: 'Suggested for a city break trip.')
- `11-couple-5d-rain: partner/essentials.sunglasses` (`trip_type.generic`: 'Suggested for a city break trip.')
- `11-couple-5d-rain: primary/essentials.sunglasses` (`trip_type.generic`: 'Suggested for a city break trip.')
- `12-family-toddler-7d-seasonal: partner/travel_comfort.book` (`trip_type.generic`: 'Suggested for a vacation trip.')
- `12-family-toddler-7d-seasonal: primary/travel_comfort.book` (`trip_type.generic`: 'Suggested for a vacation trip.')
- `15-minneapolis-6d-deep-winter: primary/essentials.sunglasses` (`trip_type.generic`: 'Suggested for a city break trip.')
- `16-minneapolis-7d-winter-family: partner/travel_comfort.book` (`trip_type.generic`: 'Suggested for a vacation trip.')
- `16-minneapolis-7d-winter-family: primary/travel_comfort.book` (`trip_type.generic`: 'Suggested for a vacation trip.')
- `18-reykjavik-64d-roadtrip-camping-seasonal: primary/essentials.snacks` (`trip_type.generic`: 'Suggested for a road trip trip.')
- `18-reykjavik-64d-roadtrip-camping-seasonal: primary/miscellaneous.car_charger` (`trip_type.generic`: 'Suggested for a road trip trip.')
- `18-reykjavik-64d-roadtrip-camping-seasonal: primary/miscellaneous.car_snacks` (`trip_type.generic`: 'Suggested for a road trip trip.')
- `19-phoenix-5d-city-walking-hot: primary/activities.daypack` (`trip_type.generic`: 'Suggested for a city break trip.')
- `20-seattle-5d-vacation-rain-sufficiency: primary/travel_comfort.book` (`trip_type.generic`: 'Suggested for a vacation trip.')
- `21-aspen-5d-skisnow-checked-prepared-snow: primary/activities.ski_gloves` (`trip_type.generic`: 'Suggested for a ski / snow trip.')
- `21-aspen-5d-skisnow-checked-prepared-snow: primary/activities.ski_goggles` (`trip_type.generic`: 'Suggested for a ski / snow trip.')
- `22-chicago-5d-business-running-overlap: primary/clothing.blazer` (`trip_type.generic`: 'Suggested for a business trip.')
- `22-chicago-5d-business-running-overlap: primary/clothing.dress_shirt` (`trip_type.generic`: 'Suggested for a business trip.')
- `22-chicago-5d-business-running-overlap: primary/footwear.dress_shoes` (`trip_type.generic`: 'Suggested for a business trip.')
- `24-miami-6d-family-infant-no-needs: partner/travel_comfort.book` (`trip_type.generic`: 'Suggested for a vacation trip.')
- `24-miami-6d-family-infant-no-needs: primary/travel_comfort.book` (`trip_type.generic`: 'Suggested for a vacation trip.')
- `25-chicago-5d-unknown-activity-cosplay: primary/essentials.sunglasses` (`trip_type.generic`: 'Suggested for a city break trip.')
- `26-seattle-5d-existing-rain-shell: primary/essentials.sunglasses` (`trip_type.generic`: 'Suggested for a city break trip.')
- `27-chicago-5d-custom-item-survives-regeneration: primary/essentials.sunglasses` (`trip_type.generic`: 'Suggested for a city break trip.')
- `28-yellowstone-4d-camping-mild: primary/activities.daypack` (`trip_type.generic`: 'Suggested for a outdoor trip.')
- `28-yellowstone-4d-camping-mild: primary/health.blister_pads` (`trip_type.generic`: 'Suggested for a outdoor trip.')
- `28-yellowstone-4d-camping-mild: primary/health.first_aid` (`trip_type.generic`: 'Suggested for a outdoor trip.')
- `29-yellowstone-4d-hiking-camping: primary/health.first_aid` (`trip_type.generic`: 'Suggested for a outdoor trip.')
- `30-seattle-5d-camping-rain: primary/activities.daypack` (`trip_type.generic`: 'Suggested for a outdoor trip.')
- `30-seattle-5d-camping-rain: primary/health.blister_pads` (`trip_type.generic`: 'Suggested for a outdoor trip.')
- `30-seattle-5d-camping-rain: primary/health.first_aid` (`trip_type.generic`: 'Suggested for a outdoor trip.')
- `31-phoenix-5d-camping-hot: primary/activities.daypack` (`trip_type.generic`: 'Suggested for a outdoor trip.')
- `31-phoenix-5d-camping-hot: primary/health.blister_pads` (`trip_type.generic`: 'Suggested for a outdoor trip.')
- `31-phoenix-5d-camping-hot: primary/health.first_aid` (`trip_type.generic`: 'Suggested for a outdoor trip.')
- `32-denver-5d-camping-cold: primary/health.first_aid` (`trip_type.generic`: 'Suggested for a outdoor trip.')
- `33-chicago-10d-partial-forecast-seasonal-remainder: primary/travel_comfort.book` (`trip_type.generic`: 'Suggested for a vacation trip.')
- `34-reykjavik-5d-cold-windy-no-snow: primary/essentials.sunglasses` (`trip_type.generic`: 'Suggested for a city break trip.')
- `35-denver-5d-business-snow: primary/clothing.blazer` (`trip_type.generic`: 'Suggested for a business trip.')
- `35-denver-5d-business-snow: primary/clothing.dress_shirt` (`trip_type.generic`: 'Suggested for a business trip.')
- `35-denver-5d-business-snow: primary/footwear.dress_shoes` (`trip_type.generic`: 'Suggested for a business trip.')
- `36-seattle-5d-rain-hiking: primary/health.first_aid` (`trip_type.generic`: 'Suggested for a outdoor trip.')
- `36-seattle-5d-rain-hiking: primary/toiletries.insect_repellent` (`trip_type.generic`: 'Suggested for a outdoor trip.')
- `37-family4-5d-hiking-camping-outdoor: shared/health.first_aid` (`trip_type.generic`: 'Suggested for a outdoor trip.')
- `38-couple-5d-seattle-shared-umbrella: partner/travel_comfort.book` (`trip_type.generic`: 'Suggested for a vacation trip.')
- `38-couple-5d-seattle-shared-umbrella: primary/travel_comfort.book` (`trip_type.generic`: 'Suggested for a vacation trip.')
- `39-v2-vacation-beach-maui: primary/activities.beach_towel` (`trip_type.generic`: 'Suggested for a beach trip.')
- `39-v2-vacation-beach-maui: primary/clothing.coverup` (`trip_type.generic`: 'Suggested for a beach trip.')
- `39-v2-vacation-beach-maui: primary/clothing.swimsuit` (`trip_type.generic`: 'Suggested for a beach trip.')
- `39-v2-vacation-beach-maui: primary/footwear.sandals` (`trip_type.generic`: 'Suggested for a beach trip.')
- `39-v2-vacation-beach-maui: primary/travel_comfort.book` (`trip_type.generic`: 'Suggested for a vacation trip.')
- `40-v2-vacation-citybreak-barcelona: primary/activities.daypack` (`trip_type.generic`: 'Suggested for a city break trip.')
- `40-v2-vacation-citybreak-barcelona: primary/essentials.sunglasses` (`trip_type.generic`: 'Suggested for a city break trip.')
- `40-v2-vacation-citybreak-barcelona: primary/travel_comfort.book` (`trip_type.generic`: 'Suggested for a vacation trip.')
- `41-v2-vacation-citybreak-beach-barcelona: primary/activities.beach_towel` (`trip_type.generic`: 'Suggested for a beach trip.')
- `41-v2-vacation-citybreak-beach-barcelona: primary/activities.daypack` (`trip_type.generic`: 'Suggested for a city break trip.')
- `41-v2-vacation-citybreak-beach-barcelona: primary/clothing.coverup` (`trip_type.generic`: 'Suggested for a beach trip.')
- `41-v2-vacation-citybreak-beach-barcelona: primary/clothing.hat_sun` (`trip_type.generic`: 'Suggested for a beach trip.')
- `41-v2-vacation-citybreak-beach-barcelona: primary/clothing.shorts` (`trip_type.generic`: 'Suggested for a beach trip.')
- `41-v2-vacation-citybreak-beach-barcelona: primary/clothing.swimsuit` (`trip_type.generic`: 'Suggested for a beach trip.')
- `41-v2-vacation-citybreak-beach-barcelona: primary/essentials.sunglasses` (`trip_type.generic`: 'Suggested for a city break trip.')
- `41-v2-vacation-citybreak-beach-barcelona: primary/footwear.sandals` (`trip_type.generic`: 'Suggested for a beach trip.')
- `41-v2-vacation-citybreak-beach-barcelona: primary/toiletries.sunscreen` (`trip_type.generic`: 'Suggested for a beach trip.')
- `41-v2-vacation-citybreak-beach-barcelona: primary/travel_comfort.book` (`trip_type.generic`: 'Suggested for a vacation trip.')
- `42-v2-business-citybreak-newyork: primary/activities.daypack` (`trip_type.generic`: 'Suggested for a city break trip.')
- `42-v2-business-citybreak-newyork: primary/clothing.blazer` (`trip_type.generic`: 'Suggested for a business trip.')
- `42-v2-business-citybreak-newyork: primary/clothing.dress_shirt` (`trip_type.generic`: 'Suggested for a business trip.')
- `42-v2-business-citybreak-newyork: primary/electronics.laptop` (`trip_type.generic`: 'Suggested for a business trip.')
- `42-v2-business-citybreak-newyork: primary/electronics.laptop_charger` (`trip_type.generic`: 'Suggested for a business trip.')
- `42-v2-business-citybreak-newyork: primary/essentials.sunglasses` (`trip_type.generic`: 'Suggested for a city break trip.')
- `42-v2-business-citybreak-newyork: primary/footwear.dress_shoes` (`trip_type.generic`: 'Suggested for a business trip.')
- `43-v2-business-vacation-chicago: primary/clothing.blazer` (`trip_type.generic`: 'Suggested for a business trip.')
- `43-v2-business-vacation-chicago: primary/clothing.dress_shirt` (`trip_type.generic`: 'Suggested for a business trip.')
- `43-v2-business-vacation-chicago: primary/electronics.laptop` (`trip_type.generic`: 'Suggested for a business trip.')
- `43-v2-business-vacation-chicago: primary/electronics.laptop_charger` (`trip_type.generic`: 'Suggested for a business trip.')
- `43-v2-business-vacation-chicago: primary/footwear.dress_shoes` (`trip_type.generic`: 'Suggested for a business trip.')
- `43-v2-business-vacation-chicago: primary/travel_comfort.book` (`trip_type.generic`: 'Suggested for a vacation trip.')
- `44-v2-roadtrip-outdoor-yellowstone: primary/activities.daypack` (`trip_type.generic`: 'Suggested for a outdoor trip.')
- `44-v2-roadtrip-outdoor-yellowstone: primary/health.blister_pads` (`trip_type.generic`: 'Suggested for a outdoor trip.')
- `44-v2-roadtrip-outdoor-yellowstone: primary/hydration.water_bottle` (`trip_type.generic`: 'Suggested for a outdoor trip.')
- `44-v2-roadtrip-outdoor-yellowstone: primary/toiletries.insect_repellent` (`trip_type.generic`: 'Suggested for a outdoor trip.')
- `45-v2-outdoor-skisnow-aspen: primary/activities.daypack` (`trip_type.generic`: 'Suggested for a outdoor trip.')
- `45-v2-outdoor-skisnow-aspen: primary/activities.ski_gloves` (`trip_type.generic`: 'Suggested for a ski / snow trip.')
- `45-v2-outdoor-skisnow-aspen: primary/activities.ski_goggles` (`trip_type.generic`: 'Suggested for a ski / snow trip.')
- `45-v2-outdoor-skisnow-aspen: primary/clothing.thermal_top` (`trip_type.generic`: 'Suggested for a ski / snow trip.')
- `45-v2-outdoor-skisnow-aspen: primary/health.blister_pads` (`trip_type.generic`: 'Suggested for a outdoor trip.')
- `45-v2-outdoor-skisnow-aspen: primary/health.first_aid` (`trip_type.generic`: 'Suggested for a outdoor trip.')
- `45-v2-outdoor-skisnow-aspen: primary/hydration.water_bottle` (`trip_type.generic`: 'Suggested for a outdoor trip.')
- `45-v2-outdoor-skisnow-aspen: primary/toiletries.insect_repellent` (`trip_type.generic`: 'Suggested for a outdoor trip.')
- `46-v2-vacation-wedding-lisbon: primary/clothing.formal_outfit` (`trip_type.generic`: 'Suggested for a wedding / event trip.')
- `46-v2-vacation-wedding-lisbon: primary/footwear.dress_shoes` (`trip_type.generic`: 'Suggested for a wedding / event trip.')
- `46-v2-vacation-wedding-lisbon: primary/miscellaneous.wedding_card` (`trip_type.generic`: 'Suggested for a wedding / event trip.')
- `46-v2-vacation-wedding-lisbon: primary/travel_comfort.book` (`trip_type.generic`: 'Suggested for a vacation trip.')
- `47-v2-festival-citybreak-austin: primary/activities.daypack` (`trip_type.generic`: 'Suggested for a city break trip.')
- `47-v2-festival-citybreak-austin: primary/activities.festival_earplugs` (`trip_type.generic`: 'Suggested for a festival trip.')
- `47-v2-festival-citybreak-austin: primary/essentials.hand_sanitizer` (`trip_type.generic`: 'Suggested for a festival trip.')
- `47-v2-festival-citybreak-austin: primary/essentials.sunglasses` (`trip_type.generic`: 'Suggested for a city break trip.')
- `47-v2-festival-citybreak-austin: primary/toiletries.sunscreen` (`trip_type.generic`: 'Suggested for a festival trip.')
- `48-v2-visitingfamily-vacation-boston: primary/miscellaneous.gift` (`trip_type.generic`: 'Suggested for a visiting family trip.')
- `48-v2-visitingfamily-vacation-boston: primary/travel_comfort.book` (`trip_type.generic`: 'Suggested for a vacation trip.')
- `49-v2-bags-personalitem-carryon-chicago: primary/essentials.sunglasses` (`trip_type.generic`: 'Suggested for a city break trip.')
- `50-v2-bags-carryon-checked-tokyo: primary/travel_comfort.book` (`trip_type.generic`: 'Suggested for a vacation trip.')
- `51-v2-bags-personalitem-carryon-checked-paris: primary/travel_comfort.book` (`trip_type.generic`: 'Suggested for a vacation trip.')
- `52-v2-bags-checked-backpack-reykjavik: primary/health.first_aid` (`trip_type.generic`: 'Suggested for a outdoor trip.')
- `52-v2-bags-checked-backpack-reykjavik: primary/toiletries.insect_repellent` (`trip_type.generic`: 'Suggested for a outdoor trip.')

## Quantity evidence

| bucket | count |
| --- | --- |
| fixed singletons (not held to the bar) | 1294 |
| requires evidence | 420 |
| — has evidence | 420 (100.0%) |
| — defect: missing evidence | 0 |

## User-authority rows (exempt — expected empty trace)

- `14-manual-quantity-survives-refresh: primary/clothing.tshirt` (userModified=True, quantity=3)
- `26-seattle-5d-existing-rain-shell: primary/clothing.rain_jacket` (userModified=True, quantity=1)
- `27-chicago-5d-custom-item-survives-regeneration: primary/custom.lucky_travel_journal` (userModified=None, quantity=1)

## Structural checks (Phase 8, Task 7)

| check | count |
| --- | --- |
| defect — invalid seasonal provenance | 0 |
| defect — fabricated user-authority provenance | 0 |
| defect — quantityReasonArguments keys outside the closed vocabulary | 0 |

**CLEAN**
