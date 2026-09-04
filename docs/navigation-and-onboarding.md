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

### Screen 1 — Welcome

**PackWise**

**Pack what this trip actually needs.**

Weather, activities, trip length and the way you travel — all considered.

CTA: **Get Started**

Visual: large suitcase mark, scenic destination photography behind the headline. See [design/ui-flow-overview.png](../design/ui-flow-overview.png).

### Screen 2 — One trip can be many things

Example visual:

```text
Chicago
5 days · City trip
Rain Saturday

↓

Rain jacket
Light layer
Walking shoes
5-day quantities
```

Show that beach, city, business, activities, and luggage compose into one specific list rather than separate templates.

### Screen 3 — Your choices stay yours

> Change quantities, skip items and add your own without losing your decisions.

All three screens share one logo/wordmark position, typography hierarchy, margins, visual frame, CTA position, and pagination position. Do not advertise memory-driven personalization until the post-trip memory product ships.

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
