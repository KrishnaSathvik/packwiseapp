# Slice 10 — copy warmth and the P2 tail

**Trigger:** the audit counted "A core item for almost every trip" on
60-70% of a typical list (18-20 rows on Chicago, 53 of 84 on the family
trip). The template catalog and fallback ladder already existed — this
slice populated tiers, it built no machinery.

## What landed

**`524d679` — per-category copy.** Base essentials emit
`base.essential.<category>` (specific tier, so
`everyShippedReasonCodeHasTemplate` keeps guarding the shipped path) with
one short line per category — "Easy to forget, hard to replace" on the ID,
"The pocket check before you head out" on essentials, "Small to pack,
annoying to replace mid-trip" on toiletries. Specific, not longer: no
item-level lines, because no base item genuinely differs from its category
yet — the tier arrives when one does. The generic string survives only as
the ladder's insurance rung, and the signaled-item ban now treats any
`base.essential*` code as generic. A typical list has **zero** generic
rows, from eighteen. Riders: a one-day trip stops packing cubes and a
laundry bag (`short_trip_skips` in base.json — data, not code; the
toiletry bag stays); the shared-umbrella copy pluralizes both placeholders
("1 days" and "1 umbrellas" both die) and says "your group", true of a
couple where "your family" wasn't.

**`6a41883` — the P2 tail.** Goldens labeled `engineVersion: v2` (the
17-line diff is exactly the labels); the weather summary counts rain days
("Rain is expected on 3 days, starting Monday") instead of naming only the
first; the Completed badge gets an `onPhoto` style (solid white capsule —
a 12% tint wash disappeared over the branded panel); trip setup pins its
toolbar background to the screen color, removing the grouped-gray band.
Both visual fixes verified by simulator screenshot via the debug harness.

## Notes

- The Packing List UI already hides pure base-essential reasons
  (`showsReason`); the warm copy shows in Item Detail and anywhere a
  reason renders alone. The hide stays — a warm line repeated fifteen
  times is still noise.
- The API's canonical vocab test pinned the retired `base.essential`
  code; it now asserts the retirement instead.

## Verification

141 iOS tests green (5 new across CopyWarmthTests), API 106 green after
the vocab pin update, goldens re-recorded and reviewed: the copy commit
touched all 17 fixtures with the only quantity-line changes being the two
organizers leaving the one-day trip; the tail commit's golden diff is 17
version labels. Screenshots of the completed-trip hero and a setup step
confirm the two visual fixes.
