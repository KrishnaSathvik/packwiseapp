# Future Features

These are specified so later work stays consistent with PackWise. They are **not MVP**. See [roadmap.md](roadmap.md).

## Outfit Planner — V2

Inside Trip: **Outfits**

Example:

```text
Saturday
72°F · Rain
Sightseeing + Dinner

Day
T-shirt
Jeans
Sneakers
Rain jacket

Dinner
Same jeans
Button-down
Sneakers
```

PackWise focuses on reuse.

At bottom:

> These outfits use 12 clothing items across five days.

This helps reduce packing.

## Bag Manager — V2

Inside Trip: **Bags**

```text
Carry-on

Estimated
17.6 / 22 lb

Clothing          8.4 lb
Shoes             4.1 lb
Electronics       3.2 lb
Other             1.9 lb
```

Always say **estimated**.

PackWise can suggest:

> Switching from two pairs of shoes to one could save about 1.8 lb.

## Airline bag limits — later

If useful:

```text
Delta Carry-on
22 × 14 × 9 in
```

Airline-specific rules change. This needs remotely maintained data if it ever ships.

Do not hardcode airline rules deep inside Swift.

## Group packing — later

Shared trip:

```text
Yellowstone
4 travelers
```

Sections:

### Mine

Personal list.

### Shared

```text
First aid kit        Sarah
Cooler               Krishna
Binoculars           John
Sunscreen            Unassigned
```

PackWise can identify duplication:

> Three people are bringing sunscreen. Make one shared item?

## Widgets — later

Home Screen:

```text
CHICAGO
Tomorrow

38 / 42 packed
4 left
```

Lock Screen:

```text
Chicago · Tomorrow
89% packed
```

Tap → Left to Pack.

## App Intents / Siri — later

Natural actions:

> Add travel adapter to my Tokyo list.

> What's left to pack?

> Mark passport packed.

> How packed am I for Chicago?

Very natural PackWise extension. Not in MVP.

## Natural-language trip creation — V1 after launch

See [trip-creation.md](trip-creation.md). Label: **Tell PackWise about your trip.** Never **Chat with AI**.
