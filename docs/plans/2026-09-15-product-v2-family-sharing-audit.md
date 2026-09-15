# Product Experience V2, Tasks 6–7.1 — family eligibility and sharing audit

Date: 2026-09-15 · Branch: `product-v2-stage-a` · Baselines: `744c02e` (Task 5 closed), `3ca4bf3` (Task 6)

Two independent questions, answered by two authorities, in this order:

```text
candidate × traveler
  → TravelerEligibilityResolver   is it appropriate for this traveler?     (Task 6)
  → ConstraintResolver sharing    personal or shared, and how many?       (Task 7)
  → quantity, coverage, constraints (unchanged)
```

Eligibility never decides quantity, sharing, carrier, or coverage. Sharing reads no age, need, or signal; `FamilySharingTests.sharingAuthorityNeverReimplementsEligibility` enforces it.

## Commits

| Commit | Scope |
| --- | --- |
| `744c02e` | Task 5 decisions closed as approved semantics |
| `3ca4bf3` | Task 6: eligibility authority, metadata for all 202 items, validator, eligibility ledger |
| `df38dd5` | Task 7: sharing policies, scaling evidence, report trace fields, this audit |
| Task 7.1 | Device ownership needs evidence, child formal outfit, infant sun hat, eligible-consumer scaling ([section](#task-71--family-eligibility-and-sharing-refinement)) |

## Task 6 — eligibility

### Vocabulary

Every catalog item has exactly one family in `shared/rules/party.json` `eligibility`. `scripts/validate_shared.py` fails on any of these:

- a missing or unknown entry;
- a `kids.*` item classified `universal` or `adultOrTeen`;
- a medication, contacts, phone-charger, or laptop item classified permissively;
- a document filtered by age group;
- an age-group add its metadata forbids;
- a need candidate that doesn't require exactly that need.

| Family | Eligible when | Otherwise | Examples |
| --- | --- | --- | --- |
| `universal` | always | — | sunscreen, first aid, travel adapter, beach towel |
| `adultOrTeen` | adult or teen | `ineligible: adult_or_teen_only` | wallet, keys, deodorant, pain reliever, blazer, dress shoes |
| `ageSpecific` | traveler's age is listed | `ineligible: not_for_age_group` | ordinary clothing and footwear (not infant); daypack, book, flashlight (school-age+); burp cloths (infant) |
| `explicitChildNeed` | the traveler's own need is selected | `requiresExplicitSignal: child_need.<need>` | diapers, wipes, stroller, car seat, carrier, formula, child medication, comfort item |
| `deviceSignalRequired` | named signal: the traveler's own chip or preference, or a solo list's own trip context; unnamed: the primary traveler only (Task 7.1) | `requiresExplicitSignal: device_signal_required` / `device_signal.<chip>` | phone, phone charger, power bank, headphones; laptop (signal `bringingLaptop`) |
| `travelerSignalRequired` | the traveler's own signal, at any age | `requiresExplicitSignal: traveler_signal.<chip>` | daily medication, prescription copy (`dailyMedication`); contacts (`wearContacts`) |
| `travelerDocument` | `all`, or `adultOrTeen` by age | `ineligible: adult_or_teen_only` | passport, visa (all); photo ID (adult/teen) |

- **Signals are attributed, never inferred.** A traveler's signals are their own chips; the primary's also include their preferences. On a party list, trip-wide context (a Work activity, a Business or Leisure trip type) is no one's signal, so it makes no traveler of any age eligible for a laptop. On a solo list that context can only be the traveler's own.
- **Missing metadata resolves conservatively:** eligible for an adult, `ineligible: missing_eligibility_metadata` for anyone younger.
- **Explicit user rows are never evaluated.** An added or edited row for a traveler passes the gate untouched, so eligibility controls generated recommendations only. Companions follow their trigger: a laptop the user adds for a child still brings its charger.

**Replaced:** `shouldSkip` (`skipForYoungChildren`, `skipForInfantsAndToddlers`, and a hardcoded wallet/phone/keys/watch list); the infant `skipAdultClothing` flag; and the party-activity tag filter (`item.tags` contains age or `shared_ok`). The child age rule no longer adds `electronics.earbuds_case`.

### Travel-document matrix (design 9.3)

| Document | Eligibility | Sharing | Trigger | Test |
| --- | --- | --- | --- | --- |
| Passport | every traveler, infant/toddler/child included | `personalOnly`, one each | confirmed international trip | `TravelerEligibilityTests.internationalFamilyDocumentsFollowTheApprovedMatrix`; `FamilySharingTests.groupOfAdults…` |
| Visa / entry docs | every traveler | `personalOnly`, one each | confirmed international trip; the reason says to check requirements | same |
| Photo ID | adults and teens; never a young child by default | `personalOnly` | base identity rule | same |
| Travel insurance info | all parties | `singlePerParty` | international adds | `FamilySharingTests.groupOfAdults…` |
| Boarding pass, health card | every traveler | `personalOnly` | no rule emits them today | — |
| Hotel confirmation, itinerary, copies, emergency contacts | adults/teens | `singlePerParty` | no rule emits them today | — |

No citizenship, custody, consent-letter, or destination-specific legal requirement is inferred.

### Toddler and infant results

- **Toddler with no needs or signals** (`toddlerWithNoSignalsGetsClothingButNoDevicesMedicationContactsOrEquipment`):
  - Gets none of: phone, phone charger, headphones, laptop and charger, power bank, deodorant, daily medication, pain reliever, contacts solution or case, photo ID, wallet, keys, stroller, car seat, diapers, wipes, comfort item, child medication.
  - Still gets tops, pants, socks, sleepwear, walking shoes, and a weather-supported layer.
- **Each toddler need alone** (`eachToddlerNeedContributesOnlyItsOwnFamily`) adds exactly its own family:
  - diapers → diapers + wipes;
  - stroller → stroller;
  - car seat → car seat;
  - medication → child medication;
  - comfort item → comfort item.
- **Infant with no needs** loses daypack, sunglasses, walking shoes, toothbrush, toothpaste, shampoo, body wash, and devices. It keeps extra outfits, sleep sack, and burp cloths.
- **School-age child** gets no phone, charger, headphones, earbuds case, wallet, keys, ID, or deodorant, but keeps clothing, shoes, toothbrush, and a book.
- **Teen** keeps phone, charger, ID, and deodorant.

### Cross-traveler attribution

| Scenario | Result | Test |
| --- | --- | --- |
| Primary brings a laptop, takes daily medication, wears contacts | primary gets laptop, charger, and medication; partner and toddler get none of them | `primaryLaptopAndMedicationNeverReachTheChild` |
| Toddler's own medication need | child medication on the toddler only; never adult daily medication | `childMedicationComesOnlyFromTheChildsOwnNeed` |
| Business trip plus Work activity (unattributed device context) | the school-age child gets no laptop, charger, or headphones | `unattributedDeviceContextClaimsNoChild` |
| A child's own laptop signal | laptop eligible; the phone charger still is not | `aChildsOwnDeviceSignalIsHonored` |
| Solo trip; group of four adults on a Business/Work trip | no eligibility decisions recorded | `soloAndAdultPartiesRecordNoEligibilityDecisions` |

### User authority (Task 6)

`explicitChildRowsSurviveRegenerationDespiteDefaultEligibility` covers:

- a user-added toddler headphones row survives with its owner;
- a manual quantity (2) and explicit carrier on a toddler phone-charger row survive, even though eligibility would no longer generate it;
- a manual toddler T-shirt quantity survives;
- an explicit carrier on toddler socks survives;
- Not Needed on the toddler's pants stays scoped to the toddler, and the adults keep pants;
- the diff never offers the authority rows for removal.

### Ledger and golden diff (Task 6 vs `744c02e`)

Ineligible candidates are recorded per traveler in `EngineGeneration.eligibilityDecisions` and the golden `eligibility` block. This includes rules that were previously skipped silently. The semantic report compares the block under ELIGIBILITY CHANGES.

- **Solo, couple, group, and adult fixtures (48):** unchanged, 1832 items.
- **Family fixtures (4):** 24 rows removed, 0 added, and no quantity, trace, coverage, or constraint changes.

| Fixture | Removed row | Reason |
| --- | --- | --- |
| `12`, `16` toddler | daypack | `ineligible: not_for_age_group` |
| `12`, `16` toddler | phone charger, power bank | `requiresExplicitSignal: device_signal_required` |
| `24` infant | daypack, sunglasses, walking shoes, body wash, shampoo, toothbrush, toothpaste | `ineligible: not_for_age_group` |
| `24` infant | phone charger, power bank | `requiresExplicitSignal: device_signal_required` |
| `37` school-age child | phone, phone charger | `requiresExplicitSignal: device_signal_required` |
| `37` school-age child | wallet, keys | `ineligible: adult_or_teen_only` |
| `37` school-age child | earbuds case | rule change: removed from the child age add (age is not device evidence) |
| `37` toddler | daypack, water bottle, flashlight | `ineligible: not_for_age_group` |
| `37` toddler | phone charger | `requiresExplicitSignal: device_signal_required` |

`PackingEngineTests.schoolAgeChildKeepsCarryablesButNotAdultCareItems` previously required headphones for a school-age child. It now forbids them, per the approved rule that age alone never justifies a device.

## Task 7 — sharing

### Policy changes

| Item | Before | After | Why |
| --- | --- | --- | --- |
| Toothpaste, shampoo, body wash | personal, one per traveler | `scaleByParty` per 4 | shared bottles; per-person rows were the device-pass duplication |
| Conditioner (not generated) | personal | `scaleByParty` per 4 | follows shampoo |
| Laundry bag | personal | `scaleByParty` per 3 | one bag serves two to three people's luggage |
| Pain reliever, blister pads, motion-sickness medicine | personal | `singlePerParty` | one pack for the party; eligibility still limits who it's for |
| Laundry sheets | personal | `singlePerParty` | trip-level laundry plan |
| Travel insurance info | personal | `singlePerParty` | design 9.3 |
| Camera memory card | personal while the camera was shared | `singlePerParty` | follows the one party camera |
| Reusable bag, binoculars, car charger, car snacks, host gift, wedding card, kids' sunscreen | personal | `singlePerParty` | one per party by nature |
| Dry bag | personal | `scaleByParty` per 4 | protects the party's valuables |
| Party documents, power strip, outlet splitter, extension cord (not generated) | personal | `singlePerParty` | reviewed classification for future rules |
| Beach towel | shared `singlePerParty` (implicit) | `personalOnly` | one towel for a family of four was an undercount |
| Bandages, camera, camera charger, insect repellent, wipes | shared, implicit single | explicit `singlePerParty` | no behavior change; no shared item relies on an implicit default |

Unchanged and deliberately personal: clothing, underwear, socks, footwear, toothbrush, toiletry bag, packing cubes, deodorant, phone and laptop chargers, headphones, books, prescription and child medication, passport, visa, photo ID, water bottle, flashlight (F-5 not reopened), and daypack. Unchanged shared policies: sunscreen (per 3), umbrella (per 2), travel adapter (device owners per 2), snacks (duration × party per 4), first aid, stroller, carrier.

### Scaling evidence

Every shared row's `quantityReasonArguments` now names its basis through `ConstraintResolver.sharingEvidence`. It is the one Phase 8 quantity trace; no new reason system was added.

```text
Laundry bag ×2    sharingPolicy: scaleByParty   travelerCount: 4   per: 3   quantity: 2
Travel adapter ×2 sharingPolicy: scaleByDevices deviceCount: 4     per: 2   quantity: 2
Umbrella ×2       sharingPolicy: scaleByParty   travelerCount: 3   per: 2   quantity: 2   rainDays: 1
Pain reliever ×1  sharingPolicy: singlePerParty travelerCount: 2            quantity: 1
```

- **Prose:** a plural quantity renders "2 for the group — not one per person."; a single one renders "One for the group…".
- **Vocabulary:** the closed argument set gains `sharingPolicy`, `per`, and `deviceCount`, in both the Swift test and `audit_recommendation_traces.py`.
- **Test:** `everySharedQuantityAboveOneCarriesItsScalingBasis`.

### Scenarios (`FamilySharingTests`)

| Scenario | Verified |
| --- | --- |
| Couple (Seattle rain) | two personal toothbrushes; toothpaste, shampoo, body wash, pain reliever, and laundry bag once each ×1; one shared umbrella; two personal phone chargers |
| You + Adult 1 + toddler | tops, socks, walking shoes, sleepwear personal ×3; toiletries shared once; no personal toothpaste/shampoo/body-wash rows |
| You + Adult 1 + Adult 2 + Child 1 | every shared item appears once; laundry bag ×2, toothpaste ×1; T-shirts one row per traveler |
| You + 3 other adults (Tokyo) | no child items; no shared item gets a guessed carrier; four personal passports; one shared insurance summary; adapters ×2 by device owners |
| Solo | all personal; toiletries ×1 as before |
| Camping and beach, larger family | flashlights personal; beach towels one per traveler |
| Six-person family on a boat/wildlife/beach/shopping trip with laundry | binoculars, motion-sickness medicine, kids' sunscreen, laundry sheets, carrier, and reusable bag once each; dry bag ×2 |

### Owner and carrier

`sharingNeverChangesOwnerOrCarrierSemantics`:

- An explicit carrier on shared toothpaste survives, and the item stays `shared` with no owner.
- A user-added child row keeps its owner (child) and carrier (partner) distinct.
- `PartyInvariants.violations` is empty before and after regeneration.

### Family item counts

| Fixture | Party | Before (`744c02e`) | After Task 6 | After Task 7 |
| --- | --- | --- | --- | --- |
| `11` | adult + adult | 55 (27 + 27, shared 1) | 55 | 49 (21 + 21, shared 7) |
| `38` | adult + adult | 57 (28 + 28, shared 1) | 57 | 51 (22 + 22, shared 7) |
| `12` | adult + adult + toddler | 75 (26 + 26 + toddler 20, shared 3) | 72 (toddler 17) | 63 (20 + 20 + toddler 14, shared 9) |
| `16` | adult + adult + toddler | 98 (34 + 34 + toddler 28, shared 2) | 95 (toddler 25) | 86 (28 + 28 + toddler 22, shared 8) |
| `24` | adult + adult + infant | 70 (28 + 28 + infant 12, shared 2) | 61 (infant 3) | 55 (22 + 22 + infant 3, shared 8) |
| `37` | adult + adult + child + toddler | 96 (25 + 25 + 24 + 19, shared 3) | 87 (child 19, toddler 15) | 74 (19 + 19 + 15 + 12, shared 9) |

### Duplicate rows removed (Task 7 vs `3ca4bf3`)

- **Every party fixture:** each traveler's personal toothpaste, shampoo, body wash, pain reliever, blister pads, and laundry bag became one shared row. Children lost their toothpaste, shampoo, and body wash rows; the school-age child in `37` also lost a laundry bag.
- **Totals:** 85 personal rows became 36 shared rows.
- **Laundry bag:** ×2 for the four-person party in `37`; every other shared row resolves to ×1.
- **Evidence:** 12 existing shared rows (umbrella, stroller, wipes, sunscreen, first aid, insect repellent) gained scaling arguments with unchanged quantities. These are the 12 TRACE CHANGES.
- **Unchanged:** the 46 non-party fixtures, with zero changes of any kind.

The semantic report now also compares `quantityReasonArguments`, `satisfiedCapabilities`, and `bagStyleConstraintFact`, which it had silently ignored. Re-run under the stricter comparison, the Task 5 and Task 6 diffs still show zero trace changes.

## Catalog-wide adjudication

Generated from `shared/rules/party.json` and `shared/catalog/*.json`. "Generated" means some rule can emit the item (rule sources, trip-type needs, weather, age rules, companions).

### Generated items (115)

| Canonical ID | Name | Eligibility | Sharing | Quantity basis | Justification | Test coverage |
| --- | --- | --- | --- | --- | --- | --- |
| `activities.beach_towel` | Beach towel | universal | personalOnly | one per eligible traveler | Was a single shared towel for any party size (an undercount); one per traveler. | FamilySharingTests.flashlight…BeachTowels; goldens 06,23,39,41 |
| `activities.binoculars` | Binoculars | ageSpecific: adult/teen/child | singlePerParty | 1 for the party | One pair shared on a wildlife day. | FamilySharingTests.auditedTripExtras… |
| `activities.daypack` | Daypack | ageSpecific: adult/teen/child | personalOnly | one per eligible traveler | A bag the traveler carries; school-age and up. | TravelerEligibilityTests.infant…, fixtures 12/16/24/37; goldens 01,08,09,10,11,12… |
| `activities.dry_bag` | Dry bag | ageSpecific: adult/teen/child | scaleByParty | ceil(eligible consumers / 4) | Protects the party's valuables; one per four eligible travelers. | FamilySharingTests.auditedTripExtras… |
| `activities.festival_earplugs` | High-fidelity earplugs | universal | personalOnly | one per eligible traveler | Appropriate for any traveler. | goldens 47 |
| `activities.goggles` | Swim goggles | ageSpecific: adult/teen/child | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `activities.running_belt` | Running belt | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `activities.ski_gloves` | Ski gloves | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | goldens 21,45 |
| `activities.ski_goggles` | Ski goggles | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | goldens 21,45 |
| `activities.snorkel` | Snorkel set | ageSpecific: adult/teen/child | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `activities.yoga_mat_travel` | Travel yoga mat | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `clothing.beanie` | Beanie / warm hat | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | goldens 15,16,21,32,35,45 |
| `clothing.blazer` | Blazer | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | goldens 07,22,35,42,43 |
| `clothing.coverup` | Swim cover-up | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | goldens 39,41 |
| `clothing.dress_shirt` | Dress shirts | adultOrTeen | personalOnly | personal `formal_top` policy | Adult/teen item by age. | goldens 07,22,35,42,43 |
| `clothing.formal_outfit` | Formal outfit | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Task 7.1: size-agnostic event outfit, so children and toddlers at a formal event get one; infants keep the infant clothing model. Copy is a Task 13 naming item. | TravelerEligibilityTests.childrenAtAWedding…; goldens 46 |
| `clothing.gloves` | Gloves | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | goldens 15,16,32,34,35 |
| `clothing.hat_sun` | Sun hat | ageSpecific: all ages | personalOnly | one per eligible traveler | Task 7.1: infants included; still only from sun context (hot weather, sun-exposure need). | TravelerEligibilityTests.sunnyInfantTrips…; goldens 06,19,23,24,31,39… |
| `clothing.hoodie` | Hoodie | ageSpecific: adult/teen/child/toddler | personalOnly | personal `layer` policy | Age-appropriate by group. | goldens 15,16,21,32,34,35… |
| `clothing.light_jacket` | Light jacket | ageSpecific: adult/teen/child/toddler | personalOnly | personal `layer` policy | Age-appropriate by group. | none (see findings) |
| `clothing.light_sweater` | Light sweater | ageSpecific: adult/teen/child/toddler | personalOnly | personal `layer` policy | Age-appropriate by group. | goldens 01,02,03,04,05,07… |
| `clothing.nice_outfit` | Nice dinner outfit | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | goldens 07,51 |
| `clothing.pants` | Pants | ageSpecific: adult/teen/child/toddler | personalOnly | personal `bottoms` policy | Age-appropriate by group. | goldens 01,02,03,04,05,06… |
| `clothing.rain_jacket` | Rain jacket | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | goldens 01,02,03,04,05,07… |
| `clothing.scarf` | Scarf | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | goldens 15,16,21 |
| `clothing.shorts` | Shorts | ageSpecific: adult/teen/child/toddler | personalOnly | personal `hot_bottoms` policy | Age-appropriate by group. | goldens 06,19,23,24,31,39… |
| `clothing.sleepwear` | Sleepwear | ageSpecific: adult/teen/child/toddler | personalOnly | personal `sleepwear` policy | Age-appropriate by group. | TravelerEligibilityTests.toddler…, FamilySharingTests.family…; goldens 01,02,03,04,05,06… |
| `clothing.socks` | Socks | ageSpecific: adult/teen/child/toddler | personalOnly | personal `daily_socks` policy | Age-appropriate by group. | TravelerEligibilityTests.toddler…, FamilySharingTests.family…; goldens 01,02,03,04,05,06… |
| `clothing.swimsuit` | Swimsuit | ageSpecific: adult/teen/child/toddler | personalOnly | personal `swimwear` policy | Age-appropriate by group. | goldens 06,23,39,41 |
| `clothing.thermal_bottom` | Thermal bottoms | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | goldens 15,16,21 |
| `clothing.thermal_top` | Thermal top | ageSpecific: adult/teen/child/toddler | personalOnly | personal `layer` policy | Age-appropriate by group. | goldens 15,16,21,30,32,45 |
| `clothing.tshirt` | T-shirts | ageSpecific: adult/teen/child/toddler | personalOnly | personal `daily_top` policy | Age-appropriate by group. | TravelerEligibilityTests.toddler…, FamilySharingTests.family…; goldens 01,02,03,04,05,06… |
| `clothing.underwear` | Underwear | ageSpecific: adult/teen/child/toddler | personalOnly | personal `daily_underwear` policy | Age-appropriate by group. | goldens 01,02,03,04,05,06… |
| `clothing.windbreaker` | Windbreaker | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `clothing.winter_coat` | Winter coat | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | goldens 15,16,21,32,35,45 |
| `clothing.workout_bottom` | Workout bottoms | ageSpecific: adult/teen/child/toddler | personalOnly | personal `workout_bottom` policy | Age-appropriate by group. | goldens 02,03,04,05,08,13… |
| `clothing.workout_top` | Workout tops | ageSpecific: adult/teen/child/toddler | personalOnly | personal `workout_top` policy | Age-appropriate by group. | goldens 02,03,04,05,08,13… |
| `documents.id` | Photo ID | travelerDocument: adultOrTeen | personalOnly | one per eligible traveler | Design 9.3: adults and teens; never blindly attached to a young child. | TravelerEligibilityTests.internationalFamily…; goldens 01,02,03,04,05,06… |
| `documents.passport` | Passport | travelerDocument: all | personalOnly | one per eligible traveler | Design 9.3: every traveler including infants/toddlers, one each. | TravelerEligibilityTests.internationalFamily…, FamilySharingTests.group…; goldens 02,03,04,05,13,14… |
| `documents.travel_insurance` | Travel insurance info | universal | singlePerParty | 1 for the party | Design 9.3: one party summary, never per family member. | FamilySharingTests.groupOfAdults…; goldens 02,03,04,05,13,14… |
| `documents.visa` | Visa / entry docs | travelerDocument: all | personalOnly | one per eligible traveler | Design 9.3: traveler-specific entry documents for every traveler; reason says to verify requirements. | TravelerEligibilityTests.internationalFamily…; goldens 02,03,04,05,13,14… |
| `electronics.camera` | Camera | deviceSignalRequired | singlePerParty | 1 for the party | Unchanged: one party camera. | goldens 52 |
| `electronics.camera_charger` | Camera charger | deviceSignalRequired | singlePerParty | 1 for the party | Follows the one party camera. | goldens 52 |
| `electronics.earbuds_case` | Earbuds | deviceSignalRequired | personalOnly | one per eligible traveler | Personal device; removed from the child age rule (age is not device evidence). | TravelerEligibilityTests.schoolAge… |
| `electronics.headphones` | Headphones | deviceSignalRequired | personalOnly | one per eligible traveler | Personal device. | TravelerEligibilityTests, PackingEngineTests.schoolAgeChild…; goldens 02,03,04,05,07,12… |
| `electronics.laptop` | Laptop | deviceSignalRequired: bringingLaptop | personalOnly | one per eligible traveler | Task 7.1: only the traveler's own laptop signal (or a solo trip's own context); Business/Work never gives every adult a laptop. | TravelerEligibilityTests.deviceOwnershipRequires…, primaryLaptop…, aTeensOwnLaptop…; goldens 07,22,35,42,43 |
| `electronics.laptop_charger` | Laptop charger | deviceSignalRequired: bringingLaptop | personalOnly | one per eligible traveler | Companion of the owner's laptop only. | TravelerEligibilityTests.deviceOwnershipRequires…, explicitlyAdded…; goldens 07,22,35,42,43 |
| `electronics.memory_card` | Memory card | deviceSignalRequired | singlePerParty | 1 for the party | Was personal while the camera was shared — now follows the one party camera. | goldens 52 |
| `electronics.phone_charger` | Phone charger | deviceSignalRequired | personalOnly | one per eligible traveler | Task 7.1: the primary traveler only; no companion has device evidence. | FamilySharingTests.couple…, TravelerEligibilityTests.unsignaledDevices…; goldens 01,02,03,04,05,06… |
| `electronics.power_bank` | Portable charger | deviceSignalRequired | personalOnly | one per eligible traveler | Personal device. | TravelerEligibilityTests.toddler…, fixtures 12/16/24; goldens 01,08,09,10,11,12… |
| `electronics.travel_adapter` | Travel adapter | universal | scaleByDevices | ceil(deviceCount / 2) | Unchanged Phase 7 basis: `deviceCount` is adults and teens, now computed by the engine so sharing reads no age (see finding 7.1-F2). | FamilySharingTests.groupOfAdults…, travelAdapterScales…; goldens 02,03,04,05,13,14… |
| `essentials.cash` | Local cash | adultOrTeen | personalOnly | one per eligible traveler | Adults/teens carry their own cash. | goldens 02,03,04,05,13,14… |
| `essentials.hand_sanitizer` | Hand sanitizer | universal | personalOnly | one per eligible traveler | Appropriate for any traveler. | goldens 47 |
| `essentials.keys` | Keys | adultOrTeen | personalOnly | one per eligible traveler | Adults/teens. | TravelerEligibilityTests.toddler…; goldens 01,02,03,04,05,06… |
| `essentials.phone` | Phone | deviceSignalRequired | personalOnly | one per eligible traveler | Task 7.1: the primary traveler only. | TravelerEligibilityTests.unsignaledDevices…, schoolAge…Teen; goldens 01,02,03,04,05,06… |
| `essentials.reusable_bag` | Reusable tote | adultOrTeen | singlePerParty | 1 for the party | One shopping bag for the party. | FamilySharingTests.auditedTripExtras…; goldens 50 |
| `essentials.snacks` | Travel snacks | universal | scaleByDurationAndParty | ceil(travelers × days / 4) | Unchanged: scales with party and duration. | goldens 18 |
| `essentials.sunglasses` | Sunglasses | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Sun protection; not for infants. | TravelerEligibilityTests.infant…; goldens 01,02,03,04,05,06… |
| `essentials.umbrella_compact` | Compact umbrella | universal | scaleByParty | ceil(travelers / 2) | Unchanged Phase 7 weather/party policy: one per two travelers. | FamilySharingTests.couple…, fixture 38; goldens 01,02,03,04,05,06… |
| `essentials.wallet` | Wallet | adultOrTeen | personalOnly | one per eligible traveler | Adults/teens. | TravelerEligibilityTests.toddler…; goldens 01,02,03,04,05,06… |
| `footwear.boots` | Boots | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | goldens 15,16,21,32,35,45 |
| `footwear.dress_shoes` | Dress shoes | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | goldens 07,22,35,42,43,46 |
| `footwear.flip_flops` | Flip-flops | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `footwear.hiking_shoes` | Hiking shoes | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | goldens 18,29,32,36,37,52 |
| `footwear.running_shoes` | Running shoes | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | goldens 02,03,04,05,08,13… |
| `footwear.sandals` | Sandals | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | goldens 06,23,39,41 |
| `footwear.walking_shoes` | Walking shoes | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Ordinary footwear; not for pre-walking infants. | TravelerEligibilityTests (toddler keeps, infant loses); goldens 01,06,07,09,10,11… |
| `footwear.water_shoes` | Water shoes | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `health.blister_pads` | Blister pads | adultOrTeen | singlePerParty | 1 for the party | A pack serves the party. | goldens 01,02,03,04,05,08… |
| `health.daily_medication` | Daily medication | travelerSignalRequired: dailyMedication | personalOnly | one per eligible traveler | Prescription medication is personal and only from that traveler's own signal. | TravelerEligibilityTests.primaryLaptopAndMedication… |
| `health.eye_drops` | Eye drops | travelerSignalRequired: wearContacts | personalOnly | one per eligible traveler | Only from the traveler's own signal. | none (see findings) |
| `health.first_aid` | Mini first-aid kit | universal | singlePerParty | 1 for the party | One kit per party (Phase 7). | goldens 28,29,30,31,32,36… |
| `health.motion_sickness` | Motion sickness tablets | adultOrTeen | singlePerParty | 1 for the party | One pack for the adults/teens on a boat day. | FamilySharingTests.auditedTripExtras… |
| `health.pain_reliever` | Pain reliever | adultOrTeen | singlePerParty | 1 for the party | Adult/teen dosing; one bottle for the adults, never one each. | FamilySharingTests.coupleShares…, everySharedQuantity…; goldens 01,02,03,04,05,06… |
| `health.prescription_copy` | Prescription copy | travelerSignalRequired: dailyMedication | personalOnly | one per eligible traveler | Follows the traveler's own medication. | none (see findings) |
| `hydration.water_bottle` | Water bottle | ageSpecific: adult/teen/child | personalOnly | one per eligible traveler | Personal equipment; school-age and up (toddlers use a sippy cup). | fixture 37; goldens 18,28,29,30,31,32… |
| `kids.activities` | Small activities | ageSpecific: child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | goldens 12,16,37 |
| `kids.baby_medication` | Child medication | explicitChildNeed: medication | personalOnly | one per eligible traveler | Child medication only from that child's explicit need; personal to the child. | TravelerEligibilityTests.childMedication…, eachToddlerNeed… |
| `kids.bottles` | Bottles | explicitChildNeed: formula | personalOnly | one per eligible traveler | Only from the child's explicit need. | none (see findings) |
| `kids.burp_cloths` | Burp cloths | ageSpecific: infant | personalOnly | one per eligible traveler | Age-appropriate by group. | TravelerEligibilityTests.infant…; goldens 24 |
| `kids.car_seat` | Car seat | explicitChildNeed: carSeat | personalOnly | one per eligible traveler | Explicit car-seat need only. | TravelerEligibilityTests.eachToddlerNeed… |
| `kids.carrier` | Baby carrier | explicitChildNeed: carrier | singlePerParty | 1 for the party | One per party, from the child's explicit need. | FamilySharingTests.auditedTripExtras… |
| `kids.changing_pad` | Changing pad | explicitChildNeed: diapers | personalOnly | one per eligible traveler | Only from the child's explicit need. | none (see findings) |
| `kids.comfort_item` | Comfort toy / blanket | explicitChildNeed: comfortItem | personalOnly | one per eligible traveler | Explicit comfort-item need only. | TravelerEligibilityTests.eachToddlerNeed…; goldens 12,16 |
| `kids.diapers` | Diapers | explicitChildNeed: diapers | personalOnly | personal `toddler_backup` policy | Explicit diapers need only. | TravelerEligibilityTests.eachToddlerNeed…; goldens 12,16 |
| `kids.extra_outfits` | Extra outfits | ageSpecific: toddler/infant | personalOnly | personal `toddler_backup` policy | Infant/toddler clothing backups by age. | TravelerEligibilityTests.infant…; goldens 12,16,24,37 |
| `kids.formula` | Formula / feeding supplies | explicitChildNeed: formula | personalOnly | one per eligible traveler | Only from the child's explicit need. | none (see findings) |
| `kids.pacifiers` | Pacifiers | explicitChildNeed: pacifier | personalOnly | one per eligible traveler | Only from the child's explicit need. | none (see findings) |
| `kids.sippy` | Sippy cup | ageSpecific: toddler | personalOnly | one per eligible traveler | Judgment: a toddler's drinking cup (age-appropriate), not formula/feeding equipment, which needs the formula need. | goldens 12,16,37 |
| `kids.sleep_sack` | Sleep sack | ageSpecific: infant | personalOnly | one per eligible traveler | Age-appropriate by group. | TravelerEligibilityTests.infant…; goldens 24 |
| `kids.snacks` | Kid snacks | ageSpecific: child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | goldens 12,16,37 |
| `kids.stroller` | Stroller | explicitChildNeed: stroller | singlePerParty | 1 for the party | One per party, from the child's explicit need. | TravelerEligibilityTests.eachToddlerNeed…; goldens 12,16 |
| `kids.sunscreen` | Kid sunscreen | ageSpecific: child/toddler | singlePerParty | 1 for the party | Children's sunscreen serves every eligible child from one bottle. | FamilySharingTests.auditedTripExtras… |
| `kids.swim_diapers` | Swim diapers | explicitChildNeed: diapers | personalOnly | one per eligible traveler | Explicit diapers need only (was age-tag filtered). | none (see findings) |
| `kids.wipes` | Wipes | explicitChildNeed: diapers | singlePerParty | 1 for the party | One per party, from a diapers need. | TravelerEligibilityTests.eachToddlerNeed…; goldens 12,16 |
| `miscellaneous.car_charger` | Car charger | deviceSignalRequired | singlePerParty | 1 for the party | One car. | goldens 18 |
| `miscellaneous.car_snacks` | Road-trip snacks | universal | singlePerParty | 1 for the party | Road-trip snacks for the car. | goldens 18 |
| `miscellaneous.flashlight` | Small flashlight | ageSpecific: adult/teen/child | personalOnly | one per eligible traveler | Phase 7 F-5 preserved: personal, not shared; eligibility limits it to school-age and up. | FamilySharingTests.flashlight…, ActivityContractTests F-5; goldens 18,28,29,30,31,32… |
| `miscellaneous.gift` | Host gift | adultOrTeen | singlePerParty | 1 for the party | One host gift from the party. | goldens 48 |
| `miscellaneous.wedding_card` | Card for event | adultOrTeen | singlePerParty | 1 for the party | One card from the party. | goldens 46 |
| `toiletries.body_wash` | Body wash | ageSpecific: adult/teen/child/toddler | scaleByParty | ceil(travelers / 4) | Same model as shampoo. | FamilySharingTests; goldens 01,02,03,04,05,06… |
| `toiletries.contact_case` | Contact case | travelerSignalRequired: wearContacts | personalOnly | one per eligible traveler | Only from the traveler's own signal. | none (see findings) |
| `toiletries.contacts_solution` | Contact solution | travelerSignalRequired: wearContacts | personalOnly | one per eligible traveler | Only from the traveler's own signal. | TravelerEligibilityTests.toddler…, primaryLaptopAndMedication… |
| `toiletries.deodorant` | Deodorant | adultOrTeen | personalOnly | one per eligible traveler | Adults/teens. | TravelerEligibilityTests.toddler…, schoolAge…; goldens 01,02,03,04,05,06… |
| `toiletries.insect_repellent` | Insect repellent | universal | singlePerParty | 1 for the party | One bottle covers a party for a trip. | goldens 18,28,29,30,31,32… |
| `toiletries.laundry_sheets` | Laundry sheets | adultOrTeen | singlePerParty | 1 for the party | Trip-level laundry plan; one pack for the party. | FamilySharingTests.auditedTripExtras… |
| `toiletries.shampoo` | Shampoo | ageSpecific: adult/teen/child/toddler | scaleByParty | ceil(travelers / 4) | Hotel-style shared bottle; one per four travelers. | FamilySharingTests; goldens 01,02,03,04,05,06… |
| `toiletries.sunscreen` | Sunscreen | universal | scaleByParty | ceil(travelers / 3) | Unchanged Phase 7 policy: one bottle per three travelers. | goldens 02,03,04,05,06,12… |
| `toiletries.toothbrush` | Toothbrush | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Personal; not for infants. | FamilySharingTests.couple…, TravelerEligibilityTests.infant…; goldens 01,02,03,04,05,06… |
| `toiletries.toothpaste` | Toothpaste | ageSpecific: adult/teen/child/toddler | scaleByParty | ceil(eligible consumers / 4) | A tube serves several people; per-traveler rows were the device-pass duplication. An infant is not a consumer. | FamilySharingTests (couple, family, larger family, solo, eligible consumers); goldens 01,02,03,04,05,06… |
| `travel_comfort.book` | Book or magazine | ageSpecific: adult/teen/child | personalOnly | one per eligible traveler | Each reader brings their own; school-age and up. | goldens 04,12,16,20,24,33… |
| `travel_comfort.compression_packing` | Packing cubes | ageSpecific: adult/teen/child | personalOnly | one per eligible traveler | Organizes one traveler's own clothing; school-age and up (younger children's clothes go in a guardian's cubes). | goldens 01,02,03,04,05,06… |
| `travel_comfort.empty_security_bottle` | Empty security bottle | ageSpecific: adult/teen/child | personalOnly | one per eligible traveler | Age-appropriate by group. | goldens 01,02,03,05,06,08… |
| `travel_comfort.laundry_bag` | Laundry bag | ageSpecific: adult/teen/child | scaleByParty | ceil(eligible consumers / 3) | Collects dirty clothes for two to three people's luggage; fixture 37's toddler is not a consumer, so ×1. | FamilySharingTests.sharedQuantitiesScaleFromEligibleConsumers, largerFamily…; goldens 01,02,03,04,05,06… |
| `travel_comfort.toiletry_bag` | Toiletry bag | ageSpecific: adult/teen/child | personalOnly | one per eligible traveler | Holds the traveler's personal toiletries (toothbrush, deodorant, razor); shared tubes don't make it shared. | goldens 01,02,03,04,05,06… |

### Catalog items no rule generates (87)

These appear only when a user adds them, and user rows are never evaluated. Their metadata is still complete so a future rule inherits a reviewed classification.

| Canonical ID | Name | Eligibility | Sharing | Quantity basis | Justification | Test coverage |
| --- | --- | --- | --- | --- | --- | --- |
| `activities.base_layers_ski` | Ski base layers | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `activities.guidebook` | Guidebook / maps | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `activities.hiking_poles` | Hiking poles | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `activities.museum_tickets` | Attraction tickets | universal | personalOnly | one per eligible traveler | Appropriate for any traveler. | none (see findings) |
| `activities.portable_fan` | Portable fan | universal | personalOnly | one per eligible traveler | Appropriate for any traveler. | none (see findings) |
| `activities.rain_cover` | Pack rain cover | ageSpecific: adult/teen/child | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `activities.tennis_shoes_note` | Court shoes | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `activities.workout_band` | Resistance band | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `clothing.belt` | Belt | ageSpecific: adult/teen/child | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `clothing.blouse` | Blouses | ageSpecific: adult/teen/child/toddler | personalOnly | personal `daily_top` policy | Age-appropriate by group. | none (see findings) |
| `clothing.casual_shirt` | Casual shirts | ageSpecific: adult/teen/child/toddler | personalOnly | personal `daily_top` policy | Age-appropriate by group. | none (see findings) |
| `clothing.compression_socks` | Compression socks | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `clothing.dress` | Dresses | ageSpecific: adult/teen/child/toddler | personalOnly | personal `dresses` policy | Age-appropriate by group. | none (see findings) |
| `clothing.jeans` | Jeans | ageSpecific: adult/teen/child/toddler | personalOnly | personal `bottoms` policy | Age-appropriate by group. | none (see findings) |
| `clothing.pajamas_backup` | Backup sleep shirt | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `clothing.skirt` | Skirt | ageSpecific: adult/teen/child/toddler | personalOnly | personal `bottoms` policy | Age-appropriate by group. | none (see findings) |
| `clothing.sports_bra` | Sports bras | adultOrTeen | personalOnly | personal `workout_top` policy | Adult/teen item by age. | none (see findings) |
| `clothing.tie` | Tie | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `documents.boarding_pass` | Boarding pass | travelerDocument: all | personalOnly | one per eligible traveler | Personal travel document. | none (see findings) |
| `documents.copies` | Document copies | adultOrTeen | singlePerParty | 1 for the party | Adult/teen item by age. | none (see findings) |
| `documents.emergency_contacts` | Emergency contacts | adultOrTeen | singlePerParty | 1 for the party | Adult/teen item by age. | none (see findings) |
| `documents.health_card` | Health insurance card | travelerDocument: all | personalOnly | one per eligible traveler | Personal travel document. | none (see findings) |
| `documents.hotel_confirmation` | Hotel confirmation | adultOrTeen | singlePerParty | 1 for the party | Adult/teen item by age. | none (see findings) |
| `documents.itinerary` | Printed itinerary | adultOrTeen | singlePerParty | 1 for the party | Adult/teen item by age. | none (see findings) |
| `electronics.extension_cord` | Short extension cord | adultOrTeen | singlePerParty | 1 for the party | Adult/teen item by age. | none (see findings) |
| `electronics.hdmi` | HDMI cable | deviceSignalRequired: bringingLaptop | personalOnly | one per eligible traveler | Follows the traveler's own laptop signal. | none (see findings) |
| `electronics.kindle` | E-reader | deviceSignalRequired | personalOnly | one per eligible traveler | Personal device: the primary traveler only. | none (see findings) |
| `electronics.mouse` | Travel mouse | deviceSignalRequired: bringingLaptop | personalOnly | one per eligible traveler | Follows the traveler's own laptop signal. | none (see findings) |
| `electronics.outlet_splitter` | USB hub / splitter | adultOrTeen | singlePerParty | 1 for the party | Adult/teen item by age. | none (see findings) |
| `electronics.power_strip` | Travel power strip | adultOrTeen | singlePerParty | 1 for the party | Not generated; one per party if emitted. | none (see findings) |
| `electronics.sim_ejector` | SIM ejector | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `electronics.tablet` | Tablet | deviceSignalRequired | personalOnly | one per eligible traveler | Personal device: the primary traveler only. | TravelerEligibilityTests.explicitlyAdded… (user row) |
| `electronics.watch_charger` | Watch charger | deviceSignalRequired | personalOnly | one per eligible traveler | Personal device: the primary traveler only. | none (see findings) |
| `essentials.home_keys` | House keys | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `essentials.lip_balm` | Lip balm | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `essentials.notebook` | Small notebook | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `essentials.pen` | Pen | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `essentials.watch` | Watch | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `footwear.house_slippers` | Travel slippers | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `footwear.shoe_bags` | Shoe bags | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `health.allergy` | Allergy medicine | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `health.bandages` | Bandages | universal | singlePerParty | 1 for the party | Unchanged: party kit. | none (see findings) |
| `health.electrolytes` | Electrolytes | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `health.hand_warmers` | Hand warmers | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `health.inhaler` | Inhaler | travelerSignalRequired: dailyMedication | personalOnly | one per eligible traveler | Only from the traveler's own signal. | none (see findings) |
| `health.insect_bite` | Bite cream | universal | personalOnly | one per eligible traveler | Appropriate for any traveler. | none (see findings) |
| `health.thermometer` | Travel thermometer | universal | personalOnly | one per eligible traveler | Appropriate for any traveler. | none (see findings) |
| `health.vitamins` | Vitamins | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `kids.night_light` | Night light | ageSpecific: child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `miscellaneous.baby_wipes` | Extra wipes | universal | personalOnly | one per eligible traveler | Appropriate for any traveler. | none (see findings) |
| `miscellaneous.collapsible_bowl` | Collapsible bowl | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `miscellaneous.multi_tool` | Travel multi-tool | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `miscellaneous.reusable_utensils` | Reusable utensils | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `miscellaneous.stain_cloth` | Microfiber cloth | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `miscellaneous.tape` | Mini tape / repair kit | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `miscellaneous.ziplocks` | Ziplock bags | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `toiletries.aftershave` | Aftershave / serum | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `toiletries.aloe` | Aloe / after-sun | universal | personalOnly | one per eligible traveler | Appropriate for any traveler. | none (see findings) |
| `toiletries.conditioner` | Conditioner | ageSpecific: adult/teen/child/toddler | scaleByParty | ceil(travelers / 4) | Not generated; would follow shampoo if a rule ever emits it. | none (see findings) |
| `toiletries.cotton_swabs` | Cotton swabs | universal | personalOnly | one per eligible traveler | Appropriate for any traveler. | none (see findings) |
| `toiletries.face_wash` | Face wash | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `toiletries.floss` | Floss | ageSpecific: adult/teen/child | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `toiletries.glasses_case` | Glasses case | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `toiletries.hair_ties` | Hair ties | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `toiletries.hairbrush` | Hairbrush | ageSpecific: adult/teen/child/toddler | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `toiletries.makeup` | Makeup | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `toiletries.makeup_remover` | Makeup remover | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `toiletries.moisturizer` | Moisturizer | ageSpecific: adult/teen/child | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `toiletries.nail_clippers` | Nail clippers | universal | personalOnly | one per eligible traveler | Appropriate for any traveler. | none (see findings) |
| `toiletries.perfume` | Fragrance | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `toiletries.razor` | Razor | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `toiletries.retainer_case` | Retainer case | ageSpecific: adult/teen/child | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `toiletries.shaving_cream` | Shaving cream | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `toiletries.stain_remover` | Stain remover pen | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `toiletries.tissues` | Travel tissues | universal | personalOnly | one per eligible traveler | Appropriate for any traveler. | none (see findings) |
| `toiletries.tweezers` | Tweezers | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `toiletries.wipes` | Face / body wipes | universal | personalOnly | one per eligible traveler | Appropriate for any traveler. | none (see findings) |
| `travel_comfort.blanket` | Travel blanket | universal | personalOnly | one per eligible traveler | Appropriate for any traveler. | none (see findings) |
| `travel_comfort.cards` | Card game | ageSpecific: adult/teen/child | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `travel_comfort.earplugs` | Earplugs | ageSpecific: adult/teen/child | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `travel_comfort.eye_mask` | Sleep mask | ageSpecific: adult/teen/child | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `travel_comfort.gum` | Gum | ageSpecific: adult/teen/child | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `travel_comfort.lock` | Bag lock | adultOrTeen | personalOnly | one per eligible traveler | Adult/teen item by age. | none (see findings) |
| `travel_comfort.luggage_tag` | Luggage tag | universal | personalOnly | one per eligible traveler | Appropriate for any traveler. | none (see findings) |
| `travel_comfort.neck_pillow` | Travel pillow | ageSpecific: adult/teen/child | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `travel_comfort.reusable_bottle` | Empty security bottle set | ageSpecific: adult/teen/child | personalOnly | one per eligible traveler | Age-appropriate by group. | none (see findings) |
| `travel_comfort.snacks_flight` | Flight snacks | universal | personalOnly | one per eligible traveler | Appropriate for any traveler. | none (see findings) |

## Decisions and findings

Findings 1, 3, 4, and 5 below are the Task 6–7 review calls. Task 7.1 resolved them; see the next section.

1. **Superseded by Task 7.1 — adults and teens were presumed device owners.** Trip-wide device context (Business, Work, Leisure headphones) still reaches every adult and teen, as it did before, and never a child. This keeps adult lists unchanged. Attributing a work laptop to one specific adult would need a per-traveler work signal, which setup doesn't collect.
2. **Sippy cup is age-specific (toddler), not formula/feeding equipment.** It is a drinking cup; bottles and formula require the `formula` need, which setup offers only for infants.
3. **Superseded by Task 7.1 — formal clothing stayed adult/teen**, which preserves the old child exclusion. A child attending a wedding therefore gets nothing formal. This is a missing-dimension candidate for review, not changed here.
4. **Superseded by Task 7.1 — infant sun protection:** the infant clothing model (extra outfits and sleep sack) has no sun hat. Fixture `24`'s Miami infant now has 3 personal rows, all appropriate, but no sun hat. Recorded, not invented.
5. **Superseded by Task 7.1 — party scaling counted every traveler, infants included** (for example, toothpaste per 4). Counting only eligible users would move eligibility into sharing, which the architecture forbids. The effect is at most one extra shared tube in large parties with infants.
6. **No shared naming helper exists.** The fallback labels "You / Adult 1 / Adult 2 / Child 1 / Shared" belong to Task 8/11. The engine and goldens use role slugs.
7. **Test coverage gap:** 16 generated items have no golden row and no explicit Task 6/7 test: goggles, running belt, snorkel, yoga mat, light jacket, windbreaker, flip-flops, water shoes, eye drops, prescription copy, bottles, changing pad, formula, pacifiers, swim diapers, and contact case. Several are exercised by other suites (coverage and multi-bag tests emit flip-flops and shells). All are personal, and their eligibility is enforced by the validator's metadata and age-rule checks.

## Task 7.1 — family eligibility and sharing refinement

Baseline: `68990b5` (Tasks 6–7). Four review calls, one pass.

### Device ownership needs evidence

Age answers "can this traveler use it?", never "does this traveler own it?".

| Device kind | Eligible when | Otherwise |
| --- | --- | --- |
| Named signal (`bringingLaptop`: laptop, laptop charger, HDMI, mouse) | the traveler's own chip or preference; on a solo list, also the trip's own context | `requiresExplicitSignal: device_signal.bringingLaptop` |
| No named signal (phone, phone charger, power bank, headphones, earbuds, tablet, e-reader, camera…) | the primary traveler (`role == self`) | `requiresExplicitSignal: device_signal_required` |

- **Primary traveler (decision for review, 7.1-D1).** Setup collects no per-traveler phone signal. The one traveler with evidence is the primary, who runs PackWise on their own phone. Without this, adding a partner would remove your own phone from your list.
- **Solo context (7.1-D2).** A solo trip's Business type or Work activity can only belong to its traveler, so the solo laptop is unchanged. On a party list the same context names no one, and nobody gets a laptop without their own signal.
- **Teen age rule.** The teen age rule no longer adds earbuds or a phone charger. `validate_shared.py` now rejects any age-group add of a device, because its mirror evaluates a companion with no device evidence.
- **User authority.** Explicit rows are never evaluated. A user-added laptop for Adult 1 keeps its charger companion. A user-added child tablet survives. An edited Adult 1 phone-charger row keeps its quantity, owner, and carrier.

| Scenario | Result | Test |
| --- | --- | --- |
| Solo adult + Laptop | laptop + charger | `deviceOwnershipRequiresATravelerScopedSignal` |
| Solo Business, no preference | laptop + charger (sole-traveler context) | same |
| Business party of 2 adults, only You has Laptop | You: laptop + charger; Adult 1: none | same |
| Business party, no signal anywhere | nobody; You's withheld laptop is recorded as `device_signal.bringingLaptop` | same; `soloRecordsNoEligibilityDecisionsAndAdultPartiesOnlyWithheldDevices` |
| Partner and teen with no device signal | no phone, charger, power bank, headphones, earbuds, or laptop; You keep phone + charger | `unsignaledDevicesReachOnlyThePrimaryTraveler`, `schoolAgeChildAndTeenFollowAgeWithoutDeviceInference` |
| Teen with own `bringingLaptop` chip | laptop + charger, still no phone items; never propagates to You | `aTeensOwnLaptopSignalIsHonoredWithoutAddingOtherDevices` |
| User-added child tablet, Adult 1 laptop | both survive; laptop brings its charger; never offered for removal | `explicitlyAddedChildAndCompanionElectronicsSurvive` |

### Formal events

- **Outfit.** `clothing.formal_outfit` is now `ageSpecific` for adults, teens, children, and toddlers, so a child or toddler at a wedding gets an event outfit.
- **Accessories stay adult/teen.** Dress shoes, blazer, dress shirt, and tie never reach a child.
- **Infants.** An infant keeps the infant clothing model.
- **No formal context.** Without one, no child gets an outfit.
- **Naming.** "Formal outfit" wording for children goes to Task 13.
- **Test:** `childrenAtAWeddingGetAFormalOutfitButNoAdultAccessories`.

### Infant sun hat

- **Eligibility.** `clothing.hat_sun` now includes infants. Its only sources are hot-weather signals and the beach `sunExposure` need, so a hat still needs sun context. Hot Miami or a beach trip adds it; wet Seattle does not.
- **No new infant sun care.** Sunglasses stay excluded and nothing adds kids' sunscreen.
- **Existing gap, unchanged.** `toiletries.sunscreen` remains `universal`, so it still counts an infant consumer. No infant sunscreen *product* is inferred. This is recorded as finding 7.1-F1.
- **Test:** `sunnyInfantTripsAddASunHatOnlyWithSunContext`.

### Eligible-consumer scaling

```text
candidate × traveler → TravelerEligibilityResolver → eligible travelers per shared item
  → PackingEngine.sharingBasis → SharingBasis(partyTravelerCount, eligibleConsumerCount, deviceCount)
  → ConstraintResolver.sharingResolution → quantity + evidence
```

- **Scaling basis.** `scaleByParty` and `scaleByDurationAndParty` now scale by `eligibleConsumerCount`: the travelers eligibility passed the item for during generation. A shared companion is never generated per traveler, so it asks the resolver directly. Policy names are unchanged.
- **No age in sharing.** `ConstraintResolver` receives counts only. Membership is now its own `isShared(_:rules:)`. The adapter's adult/teen `deviceCount` moved out to the engine, and the source guard also forbids `.adults`, `.travelers`, `.children`, and `TripParty`.
- **Evidence.** Keys are unchanged, and one key is added to the closed vocabulary (Swift and `audit_recommendation_traces.py`).

| Asked for | Key |
| --- | --- |
| policy | `sharingPolicy` |
| partyTravelerCount | `travelerCount` (the whole party; existing key, kept to avoid churn) |
| eligibleConsumerCount | `eligibleConsumerCount` (new) |
| deviceCount | `deviceCount` (`scaleByDevices` only) |
| divisor | `per` |
| resolvedQuantity | `quantity` |

Customer prose is unchanged ("One for the group — not one per person."). `sharedQuantitiesScaleFromEligibleConsumers` forbids eligibility and age words in it.

| Scenario | Party / consumers | Quantity |
| --- | --- | --- |
| You + Adult 1 + infant — toothpaste | 3 / 2 | 1 |
| You + Adult 1 + toddler — body wash | 3 / 3 | 1 |
| Four-person family with infant — body wash | 4 / 3 | 1 |
| Four-person family with infant — sunscreen (universal) | 4 / 4 | 2 |
| Four adults + infant — toothpaste per 4 | 5 / 4 | **1** (was 2) |
| Two adults + child + toddler — laundry bag per 3 | 4 / 3 | **1** (was 2) |
| Three adults + child — laundry bag per 3 | 4 / 4 | 2 |
| Six-person party — dry bag per 4 | 6 / 4 | **1** (was 2) |
| Group of four adults — travel adapter | deviceCount 4 | 2 (unchanged) |

### Golden diff (vs `68990b5`)

- **Solo fixtures (46):** zero changes of any kind.
- **Party fixtures (6):** 21 rows removed, 1 added, 1 quantity change, 48 evidence-only trace changes, 7 eligibility ledger changes.
- **Other categories:** no coverage or constraint changes.

| Fixture | Identity | Change | Eligibility reason | Sharing reason | Quantity |
| --- | --- | --- | --- | --- | --- |
| `11` couple | partner | − phone, phone charger, power bank | `requiresExplicitSignal: device_signal_required` | personal | 1 → — |
| `38` couple | partner | − phone, phone charger, power bank, headphones | same | personal | 1 → — |
| `12` toddler family | partner | − phone, phone charger, power bank, headphones | same | personal | 1 → — |
| `16` winter family | partner | − phone, phone charger, power bank, headphones | same | personal | 1 → — |
| `24` infant family | partner | − phone, phone charger, power bank, headphones | same | personal | 1 → — |
| `24` infant family | child (infant) | + sun hat | now eligible (was `ineligible: not_for_age_group`); hot Miami weather | personal | — → 1 |
| `37` family of four | partner | − phone, phone charger | `requiresExplicitSignal: device_signal_required` | personal | 1 → — |
| `37` family of four | shared | laundry bag | toddler not a consumer (adult/teen/child item) | `scaleByParty` per 3: consumers 3, party 4 | 2 → 1 |
| all six | shared | every shared row gains `eligibleConsumerCount` | — | evidence only | unchanged |

- **Primary rows:** You never lose a row.
- **Children:** they lose nothing, because they already had no devices.

| Fixture | After Task 7 | After Task 7.1 |
| --- | --- | --- |
| `11` | 49 | 46 (21 + 18, shared 7) |
| `38` | 51 | 47 (22 + 18, shared 7) |
| `12` | 63 | 59 (20 + 16 + toddler 14, shared 9) |
| `16` | 86 | 82 (28 + 24 + toddler 22, shared 8) |
| `24` | 55 | 52 (22 + 18 + infant 4, shared 8) |
| `37` | 74 | 72 (19 + 17 + 15 + 12, shared 9) |

### Findings

- **7.1-D1 (decision for review).** Unnamed-signal devices go to the primary traveler only. The alternative is strict "no signal → nobody", which removes You's own phone from every party list while a solo list keeps it.
- **7.1-D2 (decision for review).** A solo list's trip context is its traveler's own laptop signal. Solo fixtures are unchanged.
- **7.1-F1.** Universal sunscreen still counts infants as consumers. No infant sun-care product was added or inferred, per the task scope.
- **7.1-F2.** `scaleByDevices` keeps Phase 7's adult/teen `deviceCount` ("existing semantics"). It is not a device-ownership claim, but it no longer matches the stricter ownership model. Revisit if adapters should follow evidenced device owners.
- **7.1-F3.** A per-traveler device setup signal (phone or laptop for Adult 1 or a teen) would restore companion devices with evidence. It belongs to setup (Task 8+), not the engine.
