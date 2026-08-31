# Design System

Visual source of truth: [design/ui-flow-overview.png](../design/ui-flow-overview.png) and [design/README.md](../design/README.md).

## Direction

> **Apple-native travel utility with quiet intelligence.**

PackWise should look like a first-party iOS utility, not a generic startup template and not a travel-magazine collage.

## Typography

SF Pro. Use Dynamic Type. Do not ship custom display fonts for body UI.

## Icons

SF Symbols where suitable. Outline-style icons in the mock (suitcase, map pin, calendar, suitcase-with-items, backpack, sliders).

## Color

- Primary action blue for buttons, selected chips, progress fills, and key icons
- System backgrounds and grouped backgrounds, not hardcoded `#FFFFFF` / `#000000`
- Semantic system colors so Dark Mode is native-quality from day one
- Progress and packed-state use the same primary blue
- Weather and status use SF weather symbols plus quiet secondary text

Exact hex values should be tokenized in `DesignSystem/` once implementation starts. Until then, match the mock: vibrant medium blue, generous white space, soft card shadows.

## UI primitives

```text
native navigation
native sheets
native context menus
native date controls
Swift Charts
large touch targets
subtle materials
```

- Trip setup uses a top **Back** / **Next** header, not a custom wizard chrome
- Main app uses a 2-tab bar: **Trips** and **Me**
- Packing rows are Reminders-style, not cards
- Cards are reserved for trip summaries, weather, weather-changed, final check, and packing suggestions
- Bottom sheets for item detail and add item
- Floating **+** on Trip Detail for adding items

## Photography

Destination imagery can help emotionally. Do not plaster every screen with giant stock photos.

Use selectively:

```text
Trip hero
Past trip card
Completed-trip moment
Onboarding welcome
```

The packing list prioritizes utility.

### Where destination imagery comes from

MapKit, never a stock-photo service. A vendor for three prettier screens
would add a network dependency and a licensing pipeline to a local-first app.

```text
destination coordinate
  ├── MKLookAroundSceneRequest → MKLookAroundSnapshotter
  ├── MKMapSnapshotter
  └── gradient + SF Symbol
```

Policy differs per surface:

```text
trip thumbnail        Look Around → map → graphical
destination preview   map → graphical
trip hero             Look Around → map → graphical
```

Destination search prefers the map deliberately. That screen answers "did I
select the right Chicago?", and a map answers it better than a street-level
view of an arbitrary intersection.

Look Around returns real street-level imagery, not guaranteed postcard
photography, and coverage is absent outside many metros. All three tiers must
look **intentional** — the graphical tier is a designed state, never a broken
image placeholder.

Both snapshotters need the network, so cache on trip creation while the
coordinate is already known. The cache is disposable derived UI data in the
Caches directory, never core trip data. Offline with a cold cache renders the
graphical tier immediately rather than holding a spinner.

Look Around snapshots carry Apple's Maps attribution in the bottom-left
corner. It is a licensing requirement and must not be covered.

## Motion

Subtle.

- Check an item: small haptic
- Category completes: slightly stronger feedback
- 100%: small suitcase completion moment
- Weather changes: smooth content transition

No excessive confetti.

Honor Reduce Motion.

## Dark Mode

Must be native-quality from the beginning.

Do not bolt dark mode on at launch.

Use semantic system colors rather than raw:

```text
#FFFFFF
#000000
```

## Accessibility

Ship with:

```text
Dynamic Type
VoiceOver
Reduce Motion
high contrast
44pt minimum targets
color-independent state
Fahrenheit/Celsius
Imperial/Metric
```

Accessibility is architecture, not cleanup.

Color-independent state means packed / important / weather-affected must not rely on color alone.

## Copy tone

Quiet, specific, useful. No cheerleading. No AI vocabulary. See [product-and-brand.md](product-and-brand.md).
