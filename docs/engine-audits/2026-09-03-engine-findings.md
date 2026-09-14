# Engine hardening findings — Phase 1 close-out

Every defect and coverage gap discovered across Tasks 3, 4, 5, and 6, ranked
by the plan's rubric:

```text
P0 — crash/data loss, unsafe attribution, explicit-decision violation, nonsense
P1 — missing normal-trip coverage, material duplication, advertised input with no effect
P2 — weak explanation, polish, non-critical trace gap
```

No P0s were found. Nothing here crashes, loses data, misattributes an
item to the wrong traveler, silently overrides an explicit user decision, or
produces a nonsensical recommendation. Every finding below is a P1 or P2 —
Phase 1's job was to measure, not fix, so all of these route to a later
phase (`docs/plans/2026-09-02-product-hardening-program.md`'s "Program
order" table, phases 2–12) rather than being patched here.

Each finding names the fixture/item (or file/line for a code-level gap),
what's observed, the desired property, the exact command that reproduces
it, and the destination phase.

---

## P1 — missing normal-trip coverage, material duplication, advertised input with no effect

### P1-1 — 64-day high-latitude trip gets zero seasonal clothing signal

- **Fixture/item:** `18-reykjavik-64d-roadtrip-camping-seasonal` — every
  clothing row (`clothing.pants`, `.sleepwear`, `.socks`, `.tshirt`,
  `.underwear`; 26 items total).
- **Observed:** none of fixture 18's items carries a `weather.*` reason
  code — the entire clothing lineup is `base.essential.clothing`. A 64-day
  road trip starting at a fixed date and running through a 64-day span at
  64°N (Reykjavik) crosses at least one seasonal boundary, yet no sweater,
  jacket, thermal layer, glove, or hat appears anywhere in the list.
- **Cause:** `addSeasonal()` (weather rules) only reads the trip's *start*
  month; a trip long enough to run through multiple seasons is evaluated
  once, at the start month only, so mid-trip and late-trip seasonal shifts
  never register.
- **Desired:** a long high-latitude trip should surface cold/seasonal-layer
  items for the portion of the trip that falls in a colder season, not just
  the start-month season.
- **Command:**
  ```bash
  python3 -c "
  import json
  d = json.load(open('ios/PackWiseTests/Goldens/18-reykjavik-64d-roadtrip-camping-seasonal.json'))
  print([i['reasonCode'] for i in d['items'] if i['category'] == 'clothing'])
  "
  ```
- **Phase:** 6 (Weather needs — "precise/partial/seasonal matrices without
  invented precision").

### P1-2 — `camping` is a styled, selectable activity with zero engine effect

- **Fixture/item:** `18-reykjavik-64d-roadtrip-camping-seasonal` (the only
  fixture that selects `camping`).
- **Observed:** `PackWiseActivityStyle` gives `camping` a full icon and
  tint (tent, orange) — it presents as a real, supported activity — but
  `shared/rules/activity-rules.json` has no entry for it: it contributes no
  items, signals, or reason codes. It's also not reachable from any
  `TripType.suggestedActivityIDs` chip or `shared/rules/base.json` free-text
  keyword today, so a fresh trip cannot currently select it at all — the
  only way to see it is a trip whose `activities` array already contains it
  (fixture 18 was authored to exercise exactly that). This is exactly the
  rubric's "advertised input with no effect."
- **Desired:** either give `camping` a real (even minimal) rule contribution
  consistent with the plan's deferred "full camping logistics" scope
  (`docs/plans/2026-09-02-product-hardening-program.md`'s "Deferred and
  excluded" section explicitly defers tents/fuel/stoves/cookware, but a
  bare-minimum camping-adjacent item is in scope), or formally retire it as
  a selectable activity so the UI stops advertising a dead control.
- **Command:**
  ```bash
  python3 scripts/audit_engine_inputs.py \
      --contracts docs/engine-audits/surfaced-input-contracts.json --format text \
      | grep -A2 'activity/camping'
  ```
- **Phase:** 5 (Activity coverage — "every surfaced activity has behavior or
  an explicit context-only contract").

### P1-3 — ski gloves and cold-weather gloves both fire with no suppression between them

- **Fixture/item:** `21-aspen-5d-skisnow-checked-prepared-snow` —
  `activities.ski_gloves` (owner primary, `trip_type.generic`) and
  `clothing.gloves` (owner primary, `weather.snow`) both appear.
- **Observed:** confirmed as genuine duplication, not an intentional
  two-purpose split: `shared/catalog/activities.json`'s `ski_gloves` carries
  capability `"ski"`, `shared/catalog/clothing.json`'s `gloves` carries
  capability `"cold"` — disjoint capability tags — so
  `CoverageResolver`/the suppression mechanism that lets compatible
  footwear/outerwear cover multiple needs without duplication (global gate
  3) never considers them substitutes for each other. Fixture 21's
  `coverage` ledger is empty (`null`) — no suppression entry links these two
  items at all. A user packing for a ski trip is recommended two separate
  pairs of hand coverage with no note that one might already cover the
  other.
- **Desired:** either give `clothing.gloves` and `activities.ski_gloves` a
  shared capability (or an explicit substitution rule, the same mechanism
  `substitution.running_covers_walking` / `substitution.hiking_covers_walking`
  already use) so one suppresses the other, or keep both but explain why
  (e.g. "ski gloves for the slopes, a lighter pair for everyday cold") if
  that is the intended product behavior.
- **Command:**
  ```bash
  python3 -c "
  import json
  d = json.load(open('ios/PackWiseTests/Goldens/21-aspen-5d-skisnow-checked-prepared-snow.json'))
  print([(i['canonicalItemID'], i['reasonCode']) for i in d['items'] if 'glove' in i['canonicalItemID']])
  print('coverage ledger:', d.get('coverage'))
  "
  grep -A3 '"id": "clothing.gloves"' shared/catalog/clothing.json
  grep -A3 '"id": "activities.ski_gloves"' shared/catalog/activities.json
  ```
- **Phase:** 4 (Footwear and outerwear coverage — this is the phase that
  owns the coverage-suppression mechanism the finding needs, even though
  gloves are neither footwear nor outerwear by the phase's title; see
  self-review below).

### P1-4 — `WeatherRefreshPolicy` ignores partial-forecast coverage

- **Fixture/item:** none (code-level; no golden fixture exercises
  `WeatherRefreshPolicy.shouldFetch` directly — this was found reading the
  Task 4 failure-boundary audit, not from a fixture).
- **File:** `ios/PackWise/Domain/Weather/WeatherChangeReconciler.swift:101-121`.
- **Observed:** `shouldFetch` branches on `existing.source`,
  `existing.isPreciseForecast`, and `existing.providerExpiresAt`, but never
  reads `existing.forecastAvailableForPartialTrip`
  (`ios/PackWise/Domain/Weather/WeatherDomain.swift:111`). A forecast that
  covers 10 of a 30-day trip's days and one that covers all 30 refetch on
  the identical cadence — partial coverage is never retried more eagerly to
  fill in the remaining days as they enter the forecast horizon.
- **Desired:** a partially-covered forecast should refetch sooner than a
  fully-covered one, so long-trip packing lists pick up newly-available
  daily forecast data as soon as it exists rather than waiting out the same
  cadence as a trip that already has full coverage.
- **Command:**
  ```bash
  grep -n "forecastAvailableForPartialTrip\|shouldFetch" \
      ios/PackWise/Domain/Weather/WeatherChangeReconciler.swift \
      ios/PackWise/Domain/Weather/WeatherDomain.swift
  ```
- **Phase:** 6 (Weather needs).

### P1-5 — infant on the party gets several adult-oriented items no age-skip logic excludes

- **Fixture/item:** `24-miami-6d-family-infant-no-needs`, owner `child`
  (age group infant) — `activities.daypack`, `electronics.power_bank`,
  `essentials.sunglasses`, `footwear.walking_shoes`, plus full adult
  toiletries (`toiletries.body_wash`, `.shampoo`, `.toothbrush`,
  `.toothpaste`).
- **Observed:** the fixture's purpose (per
  `shared/fixtures/golden/golden-fixtures.json`) is proving that an infant
  with no declared needs must not trigger diaper/formula/stroller
  *inference* — and it correctly does not. But nothing in the young-child
  skip logic stops an infant from independently receiving a daypack, a
  power bank, sunglasses, walking shoes, and full adult toiletries, none of
  which an infant carries, uses, or needs packed on their own behalf (a
  toothbrush for a baby with no teeth, a power bank for a baby with no
  devices). These aren't inferred child-care items (which correctly stayed
  absent); they're the generic adult-traveler base-essential/activity items
  applying uniformly by trip regardless of the traveler's age group.
- **Desired:** age-group-aware suppression of adult-only baseline/activity
  items for pre-ambulatory age groups (infant, and arguably toddler for
  some of these), separate from the child-need-inference logic that already
  works correctly.
- **Command:**
  ```bash
  python3 -c "
  import json
  d = json.load(open('ios/PackWiseTests/Goldens/24-miami-6d-family-infant-no-needs.json'))
  print([i['canonicalItemID'] for i in d['items'] if i['owner'] == 'child'])
  "
  ```
- **Phase:** 10 (Family hardening and memory events — "conservative age
  behavior").

---

## P2 — weak explanation, polish, non-critical trace gap

### P2-1 — `NeedSensitivity.low` vs `.high` is declared but never behaviorally distinguished

- **Fixture/item:** none (code-level).
- **File:** `ios/PackWise/Domain/Packing/ClothingQuantity.swift:8-12,57-59`;
  every read site is `ios/PackWiseTests/ClothingQuantityTests.swift:63,74,85,223`.
- **Observed:** `NeedSensitivity` has three cases (`.none`, `.low`,
  `.high`), and every `ClothingNeedPolicy` in `ClothingNeedPolicy.all`
  declares a `.low` or `.high` value for each of `laundrySensitivity`,
  `styleSensitivity`, `bagSensitivity` — but every read site in the engine
  and its tests only ever compares against `.none` (`!= .none`). `.low` and
  `.high` are never distinguished from each other anywhere.
- **Desired:** either wire the distinction into a real behavioral
  difference (e.g. a smaller quantity delta for `.low`-sensitivity needs
  under the same laundry/style/bag change), or collapse the type to a
  boolean and stop declaring a granularity nothing reads.
- **Command:**
  ```bash
  grep -rn "laundrySensitivity\|styleSensitivity\|bagSensitivity\|NeedSensitivity" \
      ios/PackWise/Domain ios/PackWiseTests
  ```
- **Phase:** 3 (Clothing needs and quantities).

### P2-2 — sleepwear's declared quantity caps are dead code

- **Fixture/item:** none directly (code-level; documented in
  `ios/PackWiseTests/ClothingQuantityTests.swift`'s
  `everyPolicyStaysWithinItsDeclaredMinimumAndResolvedMaximum` test, commit
  `fea8c5d`).
- **File:** `ios/PackWise/Domain/Packing/ClothingQuantity.swift` —
  `ClothingQuantityEngine.compute()`'s `.sleep` usage branch.
- **Observed:** the `.sleep` branch returns a hardcoded
  `days >= 6 && style != .light ? 2 : 1` directly and never calls
  `resolve()`, so `ClothingNeedPolicy`'s declared
  `styleMaximum`/`personalItemMaximum`/`constrainedBagMaximum` for sleepwear
  are never read. The property test that checks every policy stays within
  its declared bounds passes for sleepwear only because 1/2 happens to fit
  under those unread caps, not because they're enforced.
- **Desired:** either route sleepwear through `resolve()` like every other
  need, or delete the unused fields from the sleepwear policy so the struct
  stops declaring caps nothing enforces.
- **Command:** `git show fea8c5d` (documents the exact caveat in-line).
- **Phase:** 3 (Clothing needs and quantities).

### P2-3 — `tripType.other` is a selectable enum case with an explicit empty add-list

- **Fixture/item:** none (no golden fixture sets `tripType: other`).
- **Observed:** `shared/rules/trip-types.json['other'].add` is an explicit
  empty array — selecting "Other" as a trip type contributes zero
  trip-type-specific items or reason codes, observably identical to a trip
  type absent from the rules file entirely.
- **Judgment call — P2, not P1:** unlike `camping` (P1-2), `other` reads as
  an intentional catch-all for an unclassified trip rather than a
  presentation promise the engine forgot to keep — there is nothing
  specific a generic "other" trip type could add. Still worth a decision
  (either give it the same base-essentials-only behavior explicitly
  documented as intended, or fold a couple of universally-safe adds into
  it) rather than leaving it silently empty.
- **Command:**
  ```bash
  python3 scripts/audit_engine_inputs.py \
      --contracts docs/engine-audits/surfaced-input-contracts.json --format text \
      | grep -A2 'tripType/other'
  ```
- **Phase:** 2 (Context model hardening).

### P2-4 — 44 items across 15 fixtures explain themselves only by trip type (`trip_type.generic`)

- **Fixture/item:** 44 rows across 15 fixtures — see the full list in
  `docs/engine-audits/2026-09-03-trace-coverage.md`'s "Generic-only rows"
  section. Dominated by `essentials.sunglasses` (9 fixtures),
  `electronics.headphones`/`travel_comfort.book` (9 fixtures each),
  business-trip formalwear (`clothing.blazer`/`.dress_shirt`/
  `footwear.dress_shoes`, 2 fixtures), and ski gear
  (`activities.ski_gloves`/`.ski_goggles`, 1 fixture).
- **Observed:** `scripts/audit_recommendation_traces.py`'s inclusion-
  completeness check found these are the entire "generic-only" bucket (0
  hard defects — every row still has a real reason code, signal, and
  prose). Per-fixture cross-checking (does `weather.hot`/`weather.uv` fire
  anywhere else in the same fixture) confirms `essentials.sunglasses`
  specifically is *not* an instance of the "generic fallback on a
  weather-driven item" bug the Engine V2 rebuild plan warns about — it only
  falls back to generic when no more specific weather signal exists in that
  fixture at all. `electronics.headphones`/`travel_comfort.book` have no
  more specific rule to fall back to at all (nothing in
  `shared/rules/activity-rules.json` or the weather rules ever produces a
  more specific reason for them) — this is the weakest tier of explanation
  the engine has, applied because it's the only tier available, not because
  a better one was skipped.
- **Desired:** decide, per item, whether a more specific reason is worth
  authoring (e.g. tie headphones to a flight/transit signal instead of bare
  trip type) or whether "suggested for a `{tripType}` trip" is the correct,
  final explanation for a preference item with no causal signal beyond
  trip type.
- **Command:**
  ```bash
  python3 scripts/audit_recommendation_traces.py \
      --goldens ios/PackWiseTests/Goldens --format markdown
  ```
- **Phase:** 8 (Recommendation trace productization).

### P2-5 — policy-governed clothing needs at their floor quantity give no quantity explanation, inconsistently with their siblings

- **Fixture/item:** 25 rows across 19 fixtures — `clothing.sleepwear` (22
  of the 25), `clothing.workout_top`/`.workout_bottom` (fixture 08), and
  `clothing.pants` (fixture 10). Full list in
  `docs/engine-audits/2026-09-03-trace-coverage.md`'s "Quantity evidence"
  defect rows.
- **Observed:** `scripts/audit_recommendation_traces.py` found these are
  the entire quantity-evidence-missing bucket: each is a
  `ClothingNeedPolicy`-governed need (`sleepwear`, `workout_top`,
  `workout_bottom`, `bottoms` — real laundry/style/bag sensitivity
  declared) that resolved to its floor quantity (1) with an empty
  `quantityReason`. This is inconsistent with the sibling policy-governed
  needs in the *same fixtures* — `daily_top`/`daily_underwear`/
  `daily_socks`, whose declared minimum is 2 — which *do* explain
  themselves even at that minimum (fixture 10: `clothing.tshirt`'s
  quantityReason is `"Why 2 t-shirts? You're traveling for 1 days."` while
  `clothing.pants`, resolved by the same engine on the same trip, says
  nothing about why it's 1). The product-visible effect: a user can see
  *why* they're packing 2 t-shirts but not why they're packing exactly 1
  pair of pants or 1 set of sleepwear, even though both numbers came out of
  the same policy engine.
- **Desired:** either every policy-governed need explains its resolved
  quantity, including at the floor, or the product decision "quantity 1
  needs no explanation" is made explicit and consistent — not decided
  per-need by whichever kind's floor happens to be 1 versus 2.
- **Command:**
  ```bash
  python3 scripts/audit_recommendation_traces.py \
      --goldens ios/PackWiseTests/Goldens --format text \
      | sed -n '/Quantity evidence/,/User-authority/p'
  ```
- **Phase:** 8 (Recommendation trace productization).

### P2-6 — 23 deterministic surfaced inputs have zero golden-fixture coverage

- **Fixture/item:** none, by definition — that's the finding. Full 23-item
  list: activities `boatTrip`, `museums`, `nightlife`, `photography`,
  `shopping`, `snorkeling`, `wildlife`, `yoga` (8); bag types `backpack`,
  `notSure` (2); context chips `bringingLaptop`, `dailyMedication`,
  `getColdEasily`, `laundryAvailable`, `needFormalOutfit`,
  `runWhileTraveling`, `travelingInternationally`, `usuallyWorkOut`,
  `wearContacts` (9); trip types `festival`, `outdoor`, `visitingFamily`,
  `weddingEvent` (4).
- **Observed:** `docs/engine-audits/surfaced-input-contracts.json` (Task 5)
  records each of these as `engineContract: "deterministic"` — a real
  rule keys off the value and produces observably different output — but
  `fixtureIDs` is empty for all 23: nothing in the 27-fixture golden ledger
  exercises the code path, so a regression in any of them would go
  unnoticed by the golden harness. This is a coverage gap, not a behavior
  defect — untested is not broken.
- **Desired:** a golden fixture (or a lighter-weight unit test, where a
  full fixture is overkill) per input that proves the rule still fires.
- **Routing by kind** (each closes out under the phase that owns its
  mechanism, when that phase adds fixture coverage):

  | kind | ids | phase |
  | --- | --- | --- |
  | activity | boatTrip, museums, nightlife, photography, shopping, snorkeling, wildlife, yoga | 5 (Activity coverage) |
  | bagType | backpack, notSure | 7 (Central constraints and user authority) |
  | contextChip | bringingLaptop, dailyMedication, getColdEasily, needFormalOutfit, runWhileTraveling, usuallyWorkOut, wearContacts | 7 (Central constraints and user authority — traveler-preference chips) |
  | contextChip | laundryAvailable, travelingInternationally | 2 (Context model hardening — trip-level context semantics) |
  | tripType | festival, outdoor, visitingFamily, weddingEvent | 2 (Context model hardening) |

- **Command:**
  ```bash
  python3 scripts/audit_engine_inputs.py \
      --contracts docs/engine-audits/surfaced-input-contracts.json --format text
  ```
- **Phase:** see table above (spread across phases 2, 5, 7).

---

## Self-review — judgment calls made in this ranking

- **P1 vs P2 boundary for `camping` vs `tripType.other` (P1-2 vs P2-3):**
  both are "advertised input with no effect" by the rubric's literal
  wording, which would put both at P1. I split them because `camping` is a
  specific, styled, individually-selectable activity with an icon that
  promises behavior and delivers none, observed live in a real fixture;
  `other` is a catch-all bucket where "contributes nothing specific" is a
  defensible design, not an obvious oversight. This is a judgment call, not
  a fact — a reviewer could reasonably keep both at P1.
- **Glove duplication phase routing (P1-3 → Phase 4):** Phase 4 is titled
  "Footwear and outerwear coverage," and gloves are neither. I routed it
  there anyway because Phase 4 is the phase that owns the
  capability-based coverage-suppression mechanism the fix needs — the same
  mechanism already used for `substitution.running_covers_walking` — not
  because gloves fit the phase's literal title. A reviewer might prefer
  Phase 3 (quantities) or a new catch-all; I judged the mechanism, not the
  title, to be the better routing signal.
- **P1-4 (WeatherRefreshPolicy) severity:** classified P1 ("missing normal-
  trip coverage") rather than P2 because stale partial-forecast refresh
  cadence has a real product effect on long trips (a common, normal trip
  shape, not an edge case) — but it is a timing/cadence gap, not a missing
  item, so a reviewer could reasonably call this P2 instead.
- **P1-5 (infant adult-oriented items) severity:** I judged this P1 rather
  than P0 "nonsense" — the items (sunglasses, walking shoes, a power bank,
  full toiletries) are not logically impossible for an infant the way, say,
  recommending crampons for a beach trip would be; some are even
  defensible in isolation (infant sunglasses exist). The volume and pattern
  (a consistent set of adult-traveler defaults applied uniformly regardless
  of age) is what makes it a real, if not severe, defect.
- **The trace audit's own two new findings (P2-4, P2-5)** are the most
  interpretation-heavy content in this file — both come from definitions
  this task had to operationalize (`scripts/audit_recommendation_traces.py`
  module docstring has the full reasoning). In particular, P2-5's "policy-
  sensitive" test is `quantity > 1 OR owner == "shared" OR canonical id's
  catalog quantity_kind is one ClothingNeedPolicy governs` — a data-grounded
  definition built by cross-referencing `shared/catalog/clothing.json`
  against `ClothingNeedPolicy.all`'s kinds, not a re-derivation from the
  Swift source at runtime. A different, narrower definition (e.g. "only
  rows where the resolved quantity is *not* the need's declared minimum")
  would not have found this finding at all — see the script's docstring
  and `docs/engine-audits/2026-09-03-trace-coverage.md` for the full
  reasoning trail.
- **Nothing was excluded for being inconvenient.** The 25-row quantity
  finding (P2-5) was discovered by this task's own tool, not predicted by
  the task brief, and is reported in full rather than tuned away by
  narrowing the policy-sensitive definition until the count reached zero.
