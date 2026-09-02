# Slice 8 — child/care needs and quantities

**Trigger:** the 2026-09-01 E2E audit's Part D human read of fixture 12 (the
promoted hardening item, first time a person read a family list). Findings:
diapers ×9 for 7 days, toddler deodorant marked important, underwear ×12
beside diapers, t-shirts ×13 beside extra outfits ×9, and a spread of adult
carryables on the toddler's list.

**Diagnosis:** Step 2's per-use quantity treatment was scoped to clothing
only, so the child/care family stayed on V1 duration arithmetic — the socks
×16 bug wearing a different hat. The age gate had a second hole: every
traveler starts from the full trip-wide base-essential set, filtered only by
`skipForYoungChildren`, which never listed personal-care items.

## What landed

Two commits, each ending in a reviewed golden diff on fixture 12.

**`d2b7124` — age gate.** `skipForYoungChildren` (through school age) gains
deodorant, adult pain reliever, blister pads, and the photo ID. A new
`skipForInfantsAndToddlers` rules list holds the carryables a school-age
child plausibly owns — headphones, a book, their own packing organizers —
so only under-fours lose those. Golden diff: removals only, the toddler's
nine copies.

**`76ba3e0` — per-use care quantities.** `CareQuantityEngine`
(`Domain/Packing/CareQuantity.swift`), routed by canonical id because the
frozen catalog gives diapers and extra outfits one shared `quantity_kind`:

- **Diapers**: daily rate × days (toddler 5/day, infant 8/day), capped at a
  week's worth with a buy-more-there reason on longer trips.
- **Extra outfits**: ceil(days/3), at most 3 — an accident buffer, not a
  second wardrobe beside the age-multiplied daily clothing.
- **Underwear beside diapers**: capped at 3 as a backup, reason naming
  diapers. Same coverage idea as formal tops absorbing t-shirt days.

## Adjudication: partial coverage, keyed to the explicit need

`ChildNeed.diapers` is a user-ticked plan-for chip, never inferred from age
(`toddlerWithoutNeedsDoesNotAssumeDiapers` guards that). The underwear
reduction keys off that explicit tick — and stays **partial** (three pairs
kept) rather than total, because "diapers ticked" does not disambiguate a
fully diapered toddler from a potty-training one. Partial is wrong only in
the cheap direction: a couple of spare pairs for the diapered child versus
missing underwear for the training one.

## Residuals, seen and deliberately left

- Toddler still gets a phone charger and power bank (no phone). Not
  audit-flagged; candidate for a future carryables pass.
- Toddler pants ×3 beside tops ×13 — the toddler multiplier set has no
  bottoms entry. Reads light, not broken.
- T-shirts ×13 / socks ×12 stand: that is the age-multiplier design
  (roughly two changes a day), and with extra outfits reduced to 3 it no
  longer double-provisions.
- The reason-codes vocab regen in `d2b7124` was mostly catch-up staleness
  from the reason-template-catalog slice; `validate_shared.py` now flags it.

## Verification

35 engine tests green (7 new: per-use diapers, infant rate, restock
plateau, outfit buffer, partial underwear coverage keyed to the need, the
no-diapers pin at ×12, and the two age-gate tests). Full iOS suite 130
green, API 106 green. Golden diffs reviewed row by row before belief; no
fixture other than 12 moved.
