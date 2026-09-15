# Navigation and Onboarding

## Navigation architecture

Keep navigation extremely small.

### Tab 1 — Trips

Main experience. Contains:

```text
Upcoming trips
Current packing
Past trips
Create trip
```

### Tab 2 — Me

Contains:

```text
Packing preferences
Packing habits
Saved items
Default packing style
Default bags
Units
Notifications
iCloud
Privacy
```

### Do not create tabs for

```text
Weather
Assistant
Explore
Discover
Tools
Packing
Profile
Notifications
```

The **Trip** is the container for almost everything. Weather, Ask PackWise, Final Check, packing list, and destination notes all live inside a trip, not as top-level destinations.

Bottom tab bar labels: **Trips** and **Me**.

## First launch

Onboarding must communicate value in seconds.

No signup requirement.

No notification permission on first launch.

No location permission.

No subscription wall.

All three screens share one shell (Task 9): the PackWise mark in the same
place, a framed hero, the title and supporting copy, then page dots and the
primary action pinned to the bottom safe area. Only the hero differs. Type
follows Dynamic Type; at accessibility sizes the hero yields height so the copy
stays on screen.

Copy describes what PackWise does today. Do not advertise memory-driven
personalization until the post-trip memory product ships, and never say AI.

### Screen 1 — Pack for the trip you're actually taking

> Destination, dates, weather and plans shape your list.

Hero: travel photograph with four input pills — Destination, Dates, Weather,
Plans. CTA: **Continue**

### Screen 2 — One trip can be many things

> Beach, city, business, activities and luggage work together.

Hero: one trip card with Beach, City Break, and Business selected, its
activities, and its bags. CTA: **Continue**

### Screen 3 — Your choices stay yours

> Change quantities, skip items and add your own without losing your decisions.

Hero: a changed quantity, a skipped item, and an added item.
CTA: **Create My First Trip**

## Home — Trips

This screen should be extremely clean.

```text
PackWise                                  +

Upcoming

┌────────────────────────────────────────┐
│ Chicago                                │
│ Sep 12 – Sep 16 · 5 days             │
│                                        │
│ ☀︎ 61–78°     Rain Saturday           │
│                                        │
│ ███████████████░░░       74%          │
│ 31 of 42 packed                        │
│                                        │
│ 11 items left                          │
└────────────────────────────────────────┐


Later

Tokyo
Nov 4 – Nov 12
Packing list ready


Past Trips

Maui
Aug 14 – Aug 20
✓ Completed
```

Main CTA: **+ New Trip**

Nothing else competes visually.

### Upcoming trip card must show

- Destination name
- Date range and day count
- Weather summary for the trip dates
- Progress: percent, packed count, remaining count
- Actionable remainder copy (`11 items left`)

### Later / ready trips

Show destination, dates, and a quiet status such as **Packing list ready**. No fake urgency.

### Past trips

Destination, dates, completed badge. Do not clone the upcoming card treatment.

Progress copy rules live in [packing-experience.md](packing-experience.md).
