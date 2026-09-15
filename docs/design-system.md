# Design System

Visual source of truth: the 10-screen sheet at [design/ui-flow-overview.png](../design/ui-flow-overview.png). It is the only sheet; where it is silent, derive from its rules rather than inventing.

> **Ruling (2026-08-31):** the app matches the sheet exactly. The palette is the fixed hex set in `ios/PackWise/DesignSystem/PackWiseTheme.swift` and the app renders light-only (`.preferredColorScheme(.light)`). Dark Mode is a later project with its own reference sheet — do not approximate one. The "semantic colors / Dark Mode from day one" guidance below this line is superseded where it conflicts.

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

- Trip setup uses native Back/cancel, a compact progress indicator, and a sticky bottom primary action in one shared shell. Do not place Next at top-right.
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

MapKit and the asset catalog, never a stock-photo service. A vendor for three
prettier screens would add a network dependency and a licensing pipeline to a
local-first app, and an unrelated photo is worse than none.

One policy for every surface (Task 9, `MapKitDestinationVisualService`):

```text
trusted imagery        bundled Destination-<name> asset, only ever of that place
  ↓ unavailable
street imagery         Look Around, landmark-gated — OFF in production
  ↓ unavailable
MKMapSnapshotter       flat satellite imagery of the destination's region
  ↓ offline / failure
graphical              brand blue, one route motif in the decoration band
```

Street imagery is off because the only evidence so far failed: Checkpoint V's
Chicago hero was glass office doors. Turn it on only with a usefulness rule
proven on real destinations.

The map is satellite, not the standard style: standard maps draw their own
city labels under the destination title, and satellite is dark enough for
white text under the shared scrim. The span follows the destination's
granularity (city, region, country). Snapshots are cached by a deterministic
key (rounded coordinate, scale, purpose, size, style version) in memory and in
Caches — disposable derived UI data, never core trip data.

Offline, a cold cache renders the graphical tier at once; failures are not
persisted and retry after a minute. The view has an explicit loading state in
the final geometry, so text never moves when a visual resolves.

### Destination heroes

Review, the Trips Home card, and Trip Detail are sizes of one primitive,
`DestinationHero`: the same visual policy, scrim, typography
(`heroTitle` / `heroCardTitle` / `heroMetadata`), and text safe region.

- The visual is a background: text sets the height above the minimum, so large
  text grows the hero downward.
- Decoration — the graphical motif and the map marker — lives only in the band
  above the text and below any hero controls. The marker hides rather than
  cover text at large sizes.
- Apple's imagery attribution sits in the bottom-left corner. It is a
  licensing requirement: hero text keeps a constant clearance above it, and no
  card overlaps the hero's bottom edge.
- Increase Contrast strengthens the scrim.

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
