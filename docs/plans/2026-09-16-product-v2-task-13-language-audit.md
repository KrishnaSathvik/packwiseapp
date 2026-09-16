# Product Experience V2 — Task 13 language audit

Date: 2026-09-16. Baseline: `80e49a0`, branch `product-v2-stage-a`. Tasks 11.1 and 12 approved. Task 14 and Phase 9 are outside this change.

## Presentation architecture

`RecommendationTrace.provenance(for:)` → pure `RecommendationReasonRenderer` → Packing List (including Trip Detail's row reuse), Item Detail, underlying group members, and proposed-change rows. No current trip metadata or weather is an input. Presentation context supplies only the current record owner's display identity. The trace's quantity and authority facets remain separate. Nothing is persisted by the renderer; `recommendationTraceRaw` remains the provenance encoding.

Deterministic display priority: explicit child/owned needs and device evidence; selected activities; accepted weather facts; specific contributing trip types; other specific facts; quiet generic fallback. Stable template order is independent of input ordering. Only curated compatible pairs combine (Beach/Festival, Business/Event, City/Sightseeing, hot/high UV). All other facts remain in the trace. Generic reasons are omitted from list rows; detail retains one concise sentence. The broad source-signal chips were removed from detail; expanded trace visualization is deferred.

`PackingReasonPresentation` and its singular `tripType` interpolation are deleted. Features no longer read `item.reason` for recommendation prose. The engine's legacy `ReasonRenderer`, reason codes/arguments and serialized strings remain for existing contracts, audits and compatibility; they are not a second customer inclusion renderer. Old records without structured provenance show no invented inclusion reason. No migration or schema changes. Explicit user-added/custom records get no generated reason; user-modified generated records keep their inclusion trace, while stale computed quantity explanations are hidden.

Quantity explanations use the existing trace facet. Shared quantities read `N for the group.` Applied clothing bag caps read `Packed lighter to fit your luggage.` The evidence stores the cap, not the bag's identity, so the renderer does not guess “personal item.” Checked luggage with no decision adds no prose. Coverage remains internal. Owner names are presentation labels only; they never contribute device or need signals.

## Naming decisions

Nightlife and Nice Dinner already share the `dinner`/`smart_casual` need. Rename `clothing.nice_outfit` to **Smart casual outfit**; retain both activities and the canonical identity. Their reasons are respectively “For nights out.” and “For a nicer dinner.” No activity split, item addition, or behavior change.

- **Formal outfit** stays: age-neutral and suitable for the child eligibility contract.
- **Sun hat** stays: the shared adult/child canonical item already has age-neutral wording.
- Road-trip items retain **Road-trip snacks**, **Car charger**, **Travel pillow**, and **Travel blanket**. They describe their objects without claiming air travel. **Flight snacks** remains a distinct flight-oriented catalog entry; naming changes do not merge identities.
- **Travel toiletry bottles** (3-1-1/liquids keywords) and **Empty water bottle** (flight/hydration) replace the two misleading security-bottle labels.
- **Visa or entry documents** expands abbreviated copy. Passport, Photo ID, Boarding pass, Travel insurance info, Hotel confirmation, Health insurance card, Document copies, Printed itinerary, and Emergency contacts stay; these are documents/items, not claims of legal requirements.
- Keys/House keys, general/road/flight snacks, generic/children's wipes, and earbuds/headphones remain distinct catalog concepts. No item is merged based on a similar name.
- There is no tablet-charger canonical item in this catalog. Tablet-owned copy is covered without adding one; existing companion device facts are rendered without looking at another traveler's devices.

## Every renamed item

| Canonical ID | Before | After | Decision |
| --- | --- | --- | --- |
| `clothing.nice_outfit` | Nice dinner outfit | Smart casual outfit | The dinner/smart_casual contract also serves Nightlife; broaden wording without changing behavior. |
| `documents.visa` | Visa / entry docs | Visa or entry documents | Expand the abbreviation and use natural alternatives. |
| `electronics.outlet_splitter` | USB hub / splitter | USB hub | Catalog keyword identifies a USB hub; splitter could imply mains power. |
| `kids.snacks` | Kid snacks | Children’s snacks | Use natural possessive wording. |
| `kids.sunscreen` | Kid sunscreen | Children’s sunscreen | Use natural possessive wording. |
| `kids.activities` | Small activities | Coloring supplies | The crayons/coloring keywords identify supplies; Small activities was vague. |
| `miscellaneous.ziplocks` | Ziplock bags | Resealable bags | Use the generic noun rather than a brand-like spelling. |
| `miscellaneous.wedding_card` | Card for event | Greeting card | Natural noun phrase that fits the event contract. |
| `toiletries.aftershave` | Aftershave / serum | Aftershave | The catalog only identifies aftershave; serum is a different product. |
| `travel_comfort.reusable_bottle` | Empty security bottle set | Travel toiletry bottles | Liquids/3-1-1 keywords identify toiletry containers, distinct from a drinking bottle. |
| `travel_comfort.empty_security_bottle` | Empty security bottle | Empty water bottle | The flight hydration item is filled after security, not a security product. |

## Complete customer-visible catalog inventory

All 202 entries are customer-visible inventory; no internal records were added to this table. Reasons below are actual renderer output from the 52 engine fixtures where available (the first fixture containing the item, not an exhaustive list of causes). “No generated example” means those fixtures do not generate it, not that it is unreachable. Such entries were still reviewed by their catalog name, keywords and capabilities; manually adding any of them displays no generated recommendation reason.

| Canonical ID | Existing display name | Final display name | Changed? | Review decision | Representative customer reason |
| --- | --- | --- | --- | --- | --- |
| `activities.daypack` | Daypack | Daypack | no | Keep: clear noun phrase appropriate to the item. | Useful for sightseeing and days around the city. |
| `activities.hiking_poles` | Hiking poles | Hiking poles | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `activities.rain_cover` | Pack rain cover | Pack rain cover | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `activities.snorkel` | Snorkel set | Snorkel set | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `activities.goggles` | Swim goggles | Swim goggles | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `activities.beach_towel` | Beach towel | Beach towel | no | Keep: clear noun phrase appropriate to the item. | Useful for beach days. |
| `activities.dry_bag` | Dry bag | Dry bag | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `activities.yoga_mat_travel` | Travel yoga mat | Travel yoga mat | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `activities.running_belt` | Running belt | Running belt | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `activities.binoculars` | Binoculars | Binoculars | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `activities.guidebook` | Guidebook / maps | Guidebook / maps | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `activities.museum_tickets` | Attraction tickets | Attraction tickets | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `activities.workout_band` | Resistance band | Resistance band | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `activities.tennis_shoes_note` | Court shoes | Court shoes | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `activities.ski_goggles` | Ski goggles | Ski goggles | no | Keep: clear noun phrase appropriate to the item. | For snow activities. |
| `activities.ski_gloves` | Ski gloves | Ski gloves | no | Keep: clear noun phrase appropriate to the item. | For snow activities. |
| `activities.base_layers_ski` | Ski base layers | Ski base layers | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `activities.festival_earplugs` | High-fidelity earplugs | High-fidelity earplugs | no | Keep: clear noun phrase appropriate to the item. | For the festival. |
| `activities.portable_fan` | Portable fan | Portable fan | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `clothing.tshirt` | T-shirts | T-shirts | no | Keep: clear noun phrase appropriate to the item. | Everyday clothing for the trip. |
| `clothing.casual_shirt` | Casual shirts | Casual shirts | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `clothing.dress_shirt` | Dress shirts | Dress shirts | no | Keep: clear noun phrase appropriate to the item. | For work. |
| `clothing.blouse` | Blouses | Blouses | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `clothing.underwear` | Underwear | Underwear | no | Keep: clear noun phrase appropriate to the item. | Everyday clothing for the trip. |
| `clothing.socks` | Socks | Socks | no | Keep: clear noun phrase appropriate to the item. | Everyday clothing for the trip. |
| `clothing.sleepwear` | Sleepwear | Sleepwear | no | Keep: clear noun phrase appropriate to the item. | Everyday clothing for the trip. |
| `clothing.pants` | Pants | Pants | no | Keep: clear noun phrase appropriate to the item. | Everyday clothing for the trip. |
| `clothing.jeans` | Jeans | Jeans | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `clothing.shorts` | Shorts | Shorts | no | Keep: clear noun phrase appropriate to the item. | For hot weather. |
| `clothing.skirt` | Skirt | Skirt | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `clothing.dress` | Dresses | Dresses | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `clothing.formal_outfit` | Formal outfit | Formal outfit | no | Keep: clear noun phrase appropriate to the item. | For the event. |
| `clothing.blazer` | Blazer | Blazer | no | Keep: clear noun phrase appropriate to the item. | For work. |
| `clothing.tie` | Tie | Tie | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `clothing.light_sweater` | Light sweater | Light sweater | no | Keep: clear noun phrase appropriate to the item. | Rain is expected during your trip. |
| `clothing.hoodie` | Hoodie | Hoodie | no | Keep: clear noun phrase appropriate to the item. | For cold weather throughout the trip. |
| `clothing.light_jacket` | Light jacket | Light jacket | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `clothing.rain_jacket` | Rain jacket | Rain jacket | no | Keep: clear noun phrase appropriate to the item. | Rain is expected during your trip. |
| `clothing.windbreaker` | Windbreaker | Windbreaker | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `clothing.winter_coat` | Winter coat | Winter coat | no | Keep: clear noun phrase appropriate to the item. | Snow is expected during your trip. |
| `clothing.thermal_top` | Thermal top | Thermal top | no | Keep: clear noun phrase appropriate to the item. | For freezing weather. |
| `clothing.thermal_bottom` | Thermal bottoms | Thermal bottoms | no | Keep: clear noun phrase appropriate to the item. | For freezing weather. |
| `clothing.gloves` | Gloves | Gloves | no | Keep: clear noun phrase appropriate to the item. | Snow is expected during your trip. |
| `clothing.beanie` | Beanie / warm hat | Beanie / warm hat | no | Keep: clear noun phrase appropriate to the item. | Snow is expected during your trip. |
| `clothing.scarf` | Scarf | Scarf | no | Keep: clear noun phrase appropriate to the item. | For freezing weather. |
| `clothing.swimsuit` | Swimsuit | Swimsuit | no | Keep: clear noun phrase appropriate to the item. | For swimming. |
| `clothing.coverup` | Swim cover-up | Swim cover-up | no | Keep: clear noun phrase appropriate to the item. | Useful for the beach. |
| `clothing.workout_top` | Workout tops | Workout tops | no | Keep: clear noun phrase appropriate to the item. | For running. |
| `clothing.workout_bottom` | Workout bottoms | Workout bottoms | no | Keep: clear noun phrase appropriate to the item. | For running. |
| `clothing.sports_bra` | Sports bras | Sports bras | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `clothing.nice_outfit` | Nice dinner outfit | Smart casual outfit | yes | The dinner/smart_casual contract also serves Nightlife; broaden wording without changing behavior. | For a nicer dinner. |
| `clothing.belt` | Belt | Belt | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `clothing.pajamas_backup` | Backup sleep shirt | Backup sleep shirt | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `clothing.compression_socks` | Compression socks | Compression socks | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `clothing.hat_sun` | Sun hat | Sun hat | no | Keep: clear noun phrase appropriate to the item. | For hot weather. |
| `documents.passport` | Passport | Passport | no | Keep: clear noun phrase appropriate to the item. | For international travel. |
| `documents.id` | Photo ID | Photo ID | no | Keep: clear noun phrase appropriate to the item. | Useful for this trip. |
| `documents.boarding_pass` | Boarding pass | Boarding pass | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `documents.travel_insurance` | Travel insurance info | Travel insurance info | no | Keep: clear noun phrase appropriate to the item. | For international travel. |
| `documents.hotel_confirmation` | Hotel confirmation | Hotel confirmation | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `documents.visa` | Visa / entry docs | Visa or entry documents | yes | Expand the abbreviation and use natural alternatives. | Check the entry requirements that apply to you. |
| `documents.health_card` | Health insurance card | Health insurance card | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `documents.copies` | Document copies | Document copies | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `documents.itinerary` | Printed itinerary | Printed itinerary | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `documents.emergency_contacts` | Emergency contacts | Emergency contacts | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `electronics.phone_charger` | Phone charger | Phone charger | no | Keep: clear noun phrase appropriate to the item. | Useful for this trip. |
| `electronics.power_bank` | Portable charger | Portable charger | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `electronics.laptop` | Laptop | Laptop | no | Keep: clear noun phrase appropriate to the item. | For work. |
| `electronics.laptop_charger` | Laptop charger | Laptop charger | no | Keep: clear noun phrase appropriate to the item. | For work. |
| `electronics.tablet` | Tablet | Tablet | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `electronics.headphones` | Headphones | Headphones | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `electronics.earbuds_case` | Earbuds | Earbuds | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `electronics.travel_adapter` | Travel adapter | Travel adapter | no | Keep: clear noun phrase appropriate to the item. | For international travel. |
| `electronics.outlet_splitter` | USB hub / splitter | USB hub | yes | Catalog keyword identifies a USB hub; splitter could imply mains power. | No generated example in fixtures; no reason when manually added. |
| `electronics.camera` | Camera | Camera | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `electronics.camera_charger` | Camera charger | Camera charger | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `electronics.memory_card` | Memory card | Memory card | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `electronics.kindle` | E-reader | E-reader | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `electronics.watch_charger` | Watch charger | Watch charger | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `electronics.extension_cord` | Short extension cord | Short extension cord | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `electronics.hdmi` | HDMI cable | HDMI cable | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `electronics.mouse` | Travel mouse | Travel mouse | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `electronics.power_strip` | Travel power strip | Travel power strip | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `electronics.sim_ejector` | SIM ejector | SIM ejector | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `essentials.wallet` | Wallet | Wallet | no | Keep: clear noun phrase appropriate to the item. | Useful for this trip. |
| `essentials.phone` | Phone | Phone | no | Keep: clear noun phrase appropriate to the item. | Useful for this trip. |
| `essentials.keys` | Keys | Keys | no | Keep: clear noun phrase appropriate to the item. | Useful for this trip. |
| `essentials.home_keys` | House keys | House keys | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `essentials.sunglasses` | Sunglasses | Sunglasses | no | Keep: clear noun phrase appropriate to the item. | Useful for city days. |
| `essentials.watch` | Watch | Watch | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `essentials.cash` | Local cash | Local cash | no | Keep: clear noun phrase appropriate to the item. | For international travel. |
| `essentials.reusable_bag` | Reusable tote | Reusable tote | no | Keep: clear noun phrase appropriate to the item. | For shopping. |
| `essentials.pen` | Pen | Pen | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `essentials.notebook` | Small notebook | Small notebook | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `essentials.lip_balm` | Lip balm | Lip balm | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `essentials.hand_sanitizer` | Hand sanitizer | Hand sanitizer | no | Keep: clear noun phrase appropriate to the item. | For the festival. |
| `essentials.snacks` | Travel snacks | Travel snacks | no | Keep: clear noun phrase appropriate to the item. | For the road trip. |
| `hydration.water_bottle` | Water bottle | Water bottle | no | Keep: clear noun phrase appropriate to the item. | For hiking. |
| `essentials.umbrella_compact` | Compact umbrella | Compact umbrella | no | Keep: clear noun phrase appropriate to the item. | Rain is expected during your trip. |
| `footwear.walking_shoes` | Walking shoes | Walking shoes | no | Keep: clear noun phrase appropriate to the item. | For walking days. |
| `footwear.running_shoes` | Running shoes | Running shoes | no | Keep: clear noun phrase appropriate to the item. | For running. |
| `footwear.hiking_shoes` | Hiking shoes | Hiking shoes | no | Keep: clear noun phrase appropriate to the item. | For hiking. |
| `footwear.dress_shoes` | Dress shoes | Dress shoes | no | Keep: clear noun phrase appropriate to the item. | For work. |
| `footwear.sandals` | Sandals | Sandals | no | Keep: clear noun phrase appropriate to the item. | Useful for beach days. |
| `footwear.flip_flops` | Flip-flops | Flip-flops | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `footwear.boots` | Boots | Boots | no | Keep: clear noun phrase appropriate to the item. | Snow is expected during your trip. |
| `footwear.water_shoes` | Water shoes | Water shoes | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `footwear.house_slippers` | Travel slippers | Travel slippers | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `footwear.shoe_bags` | Shoe bags | Shoe bags | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `health.daily_medication` | Daily medication | Daily medication | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `health.prescription_copy` | Prescription copy | Prescription copy | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `health.pain_reliever` | Pain reliever | Pain reliever | no | Keep: clear noun phrase appropriate to the item. | Useful for this trip. |
| `health.allergy` | Allergy medicine | Allergy medicine | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `health.bandages` | Bandages | Bandages | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `health.first_aid` | Mini first-aid kit | Mini first-aid kit | no | Keep: clear noun phrase appropriate to the item. | For outdoor activities. |
| `health.motion_sickness` | Motion sickness tablets | Motion sickness tablets | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `health.electrolytes` | Electrolytes | Electrolytes | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `health.vitamins` | Vitamins | Vitamins | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `health.thermometer` | Travel thermometer | Travel thermometer | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `health.blister_pads` | Blister pads | Blister pads | no | Keep: clear noun phrase appropriate to the item. | Useful for sightseeing. |
| `health.eye_drops` | Eye drops | Eye drops | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `health.inhaler` | Inhaler | Inhaler | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `health.insect_bite` | Bite cream | Bite cream | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `health.hand_warmers` | Hand warmers | Hand warmers | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `kids.diapers` | Diapers | Diapers | no | Keep: clear noun phrase appropriate to the item. | For Child. |
| `kids.wipes` | Wipes | Wipes | no | Keep: clear noun phrase appropriate to the item. | Useful for this trip. |
| `kids.changing_pad` | Changing pad | Changing pad | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `kids.bottles` | Bottles | Bottles | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `kids.formula` | Formula / feeding supplies | Formula / feeding supplies | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `kids.pacifiers` | Pacifiers | Pacifiers | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `kids.burp_cloths` | Burp cloths | Burp cloths | no | Keep: clear noun phrase appropriate to the item. | Useful for this trip. |
| `kids.extra_outfits` | Extra outfits | Extra outfits | no | Keep: clear noun phrase appropriate to the item. | Useful for this trip. |
| `kids.sleep_sack` | Sleep sack | Sleep sack | no | Keep: clear noun phrase appropriate to the item. | Useful for this trip. |
| `kids.carrier` | Baby carrier | Baby carrier | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `kids.stroller` | Stroller | Stroller | no | Keep: clear noun phrase appropriate to the item. | Useful for this trip. |
| `kids.baby_medication` | Child medication | Child medication | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `kids.comfort_item` | Comfort toy / blanket | Comfort toy / blanket | no | Keep: clear noun phrase appropriate to the item. | For Child. |
| `kids.sippy` | Sippy cup | Sippy cup | no | Keep: clear noun phrase appropriate to the item. | Useful for this trip. |
| `kids.snacks` | Kid snacks | Children’s snacks | yes | Use natural possessive wording. | Useful for this trip. |
| `kids.sunscreen` | Kid sunscreen | Children’s sunscreen | yes | Use natural possessive wording. | No generated example in fixtures; no reason when manually added. |
| `kids.activities` | Small activities | Coloring supplies | yes | The crayons/coloring keywords identify supplies; Small activities was vague. | Useful for this trip. |
| `kids.swim_diapers` | Swim diapers | Swim diapers | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `kids.night_light` | Night light | Night light | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `kids.car_seat` | Car seat | Car seat | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `miscellaneous.gift` | Host gift | Host gift | no | Keep: clear noun phrase appropriate to the item. | Useful while visiting family. |
| `miscellaneous.reusable_utensils` | Reusable utensils | Reusable utensils | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `miscellaneous.collapsible_bowl` | Collapsible bowl | Collapsible bowl | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `miscellaneous.ziplocks` | Ziplock bags | Resealable bags | yes | Use the generic noun rather than a brand-like spelling. | No generated example in fixtures; no reason when manually added. |
| `miscellaneous.tape` | Mini tape / repair kit | Mini tape / repair kit | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `miscellaneous.multi_tool` | Travel multi-tool | Travel multi-tool | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `miscellaneous.flashlight` | Small flashlight | Small flashlight | no | Keep: clear noun phrase appropriate to the item. | For camping. |
| `miscellaneous.car_charger` | Car charger | Car charger | no | Keep: clear noun phrase appropriate to the item. | For the road trip. |
| `miscellaneous.car_snacks` | Road-trip snacks | Road-trip snacks | no | Keep: clear noun phrase appropriate to the item. | For the road trip. |
| `miscellaneous.wedding_card` | Card for event | Greeting card | yes | Natural noun phrase that fits the event contract. | For the event. |
| `miscellaneous.baby_wipes` | Extra wipes | Extra wipes | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `miscellaneous.stain_cloth` | Microfiber cloth | Microfiber cloth | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `toiletries.toothbrush` | Toothbrush | Toothbrush | no | Keep: clear noun phrase appropriate to the item. | Useful for this trip. |
| `toiletries.toothpaste` | Toothpaste | Toothpaste | no | Keep: clear noun phrase appropriate to the item. | Useful for this trip. |
| `toiletries.floss` | Floss | Floss | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `toiletries.deodorant` | Deodorant | Deodorant | no | Keep: clear noun phrase appropriate to the item. | Useful for this trip. |
| `toiletries.shampoo` | Shampoo | Shampoo | no | Keep: clear noun phrase appropriate to the item. | Useful for this trip. |
| `toiletries.conditioner` | Conditioner | Conditioner | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `toiletries.body_wash` | Body wash | Body wash | no | Keep: clear noun phrase appropriate to the item. | Useful for this trip. |
| `toiletries.face_wash` | Face wash | Face wash | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `toiletries.moisturizer` | Moisturizer | Moisturizer | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `toiletries.sunscreen` | Sunscreen | Sunscreen | no | Keep: clear noun phrase appropriate to the item. | Useful for strong sun. |
| `toiletries.aftershave` | Aftershave / serum | Aftershave | yes | The catalog only identifies aftershave; serum is a different product. | No generated example in fixtures; no reason when manually added. |
| `toiletries.razor` | Razor | Razor | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `toiletries.shaving_cream` | Shaving cream | Shaving cream | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `toiletries.hairbrush` | Hairbrush | Hairbrush | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `toiletries.hair_ties` | Hair ties | Hair ties | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `toiletries.makeup` | Makeup | Makeup | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `toiletries.makeup_remover` | Makeup remover | Makeup remover | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `toiletries.nail_clippers` | Nail clippers | Nail clippers | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `toiletries.tweezers` | Tweezers | Tweezers | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `toiletries.cotton_swabs` | Cotton swabs | Cotton swabs | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `toiletries.contacts_solution` | Contact solution | Contact solution | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `toiletries.contact_case` | Contact case | Contact case | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `toiletries.glasses_case` | Glasses case | Glasses case | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `toiletries.retainer_case` | Retainer case | Retainer case | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `toiletries.perfume` | Fragrance | Fragrance | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `toiletries.insect_repellent` | Insect repellent | Insect repellent | no | Keep: clear noun phrase appropriate to the item. | For camping. |
| `toiletries.aloe` | Aloe / after-sun | Aloe / after-sun | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `toiletries.laundry_sheets` | Laundry sheets | Laundry sheets | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `toiletries.stain_remover` | Stain remover pen | Stain remover pen | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `toiletries.tissues` | Travel tissues | Travel tissues | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `toiletries.wipes` | Face / body wipes | Face / body wipes | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `travel_comfort.neck_pillow` | Travel pillow | Travel pillow | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `travel_comfort.eye_mask` | Sleep mask | Sleep mask | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `travel_comfort.earplugs` | Earplugs | Earplugs | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `travel_comfort.blanket` | Travel blanket | Travel blanket | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `travel_comfort.compression_packing` | Packing cubes | Packing cubes | no | Keep: clear noun phrase appropriate to the item. | Useful for this trip. |
| `travel_comfort.laundry_bag` | Laundry bag | Laundry bag | no | Keep: clear noun phrase appropriate to the item. | Useful for this trip. |
| `travel_comfort.toiletry_bag` | Toiletry bag | Toiletry bag | no | Keep: clear noun phrase appropriate to the item. | Useful for this trip. |
| `travel_comfort.reusable_bottle` | Empty security bottle set | Travel toiletry bottles | yes | Liquids/3-1-1 keywords identify toiletry containers, distinct from a drinking bottle. | No generated example in fixtures; no reason when manually added. |
| `travel_comfort.snacks_flight` | Flight snacks | Flight snacks | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `travel_comfort.book` | Book or magazine | Book or magazine | no | Keep: clear noun phrase appropriate to the item. | Useful for this trip. |
| `travel_comfort.cards` | Card game | Card game | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `travel_comfort.gum` | Gum | Gum | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `travel_comfort.empty_security_bottle` | Empty security bottle | Empty water bottle | yes | The flight hydration item is filled after security, not a security product. | Fill it after airport security. |
| `travel_comfort.lock` | Bag lock | Bag lock | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |
| `travel_comfort.luggage_tag` | Luggage tag | Luggage tag | no | Keep: clear noun phrase appropriate to the item. | No generated example in fixtures; no reason when manually added. |

## Verification and evidence

See the companion Task 13 verification report for test totals, semantic comparison, screenshot review, accessibility limits and final commits.
