# UI Conformance Pass — Design

**Date:** 2026-08-31
**Status:** slices 1–10 implemented; slice 0 and slice 11 need a physical device
**Scope:** every SwiftUI surface in `ios/PackWise/Features/` and `ios/PackWise/DesignSystem/`
**Explicitly not in scope:** `Domain/`, `Data/`, `api/`, `shared/`

## What this is

This is a **conformance pass**, not a redesign. The visual direction described in
[design-system.md](../design-system.md) and [design/README.md](../../design/README.md) was written
before the UI was built and has never been executed. The board at
[design/ui-flow-overview.png](../../design/ui-flow-overview.png) remains the contract. Nothing about
the intended visual language changes here; the app is brought to it.

The product logic is ahead of the presentation layer. Packing engine, quantities, explanations,
weather normalization, Packing Impact, reconciliation, party model, App Attest, and persistence all
stay untouched.

> The board adapts to the real product where necessary. The real product does not get rewritten for
> decoration.

## Findings that shaped this design

Five things were assumed about the current build that turned out to be false. Each one changes the
work.

| Assumption | Reality |
| --- | --- |
| Designed dark-mode-first | Zero occurrences of `Color.black` / `Color.white`. Every surface is semantic. The only `colorScheme` read is the Apple Weather mark in `WeatherAttributionView.swift:35`. |
| Photography deliberately omitted | The three onboarding imagesets contain `Contents.json` and no image file. `PackWiseImageSlot` resolves to nothing. |
| Custom floating tab bar | Stock `TabView` with `Tab(...)` in `RootView.swift:41-50`. The capsule is the OS. |
| Categories wrapped in custom cards | `.listStyle(.insetGrouped)` at `TripDetailView.swift:78`. `PackWiseCard` is never used in Trip Detail. The same applies to Trip Type, Bag, Style, and Activities in setup. |
| A new visual direction is needed | The direction is already written down. "Packing rows are Reminders-style. Cards are for emphasis only" is AGENTS.md non-negotiable 7, currently violated. |

Consequence: the colour system is **kept as-is**, the tab bar is **kept as-is**, and the bulk of the
"reduce card usage" work is list-style and row-content changes rather than teardown.

Size of the surface being changed:

```text
ios/PackWise/Features/ + App/     2,454 LOC across 15 files
  TripSetupView.swift               665
  TripDetailView.swift              574
  everything else                 1,215
```

## Rulings

### Trip Detail splits into overview and list

Where the board and [packing-experience.md](../packing-experience.md) disagree, the board is the
newer contract and wins.

```text
Trip Detail  ─ understand the trip        Packing List  ─ do the packing
  destination hero                          All | Left to pack | Packed | Important
  dates / duration                          ESSENTIALS                  5 / 6
  progress                                  ○ Passport               ×1
  compact weather + daily strip             ○ Wallet                 ×1
  Packing Impact                            CLOTHING                    9 / 13
  category progress rows                    ○ T-shirts               ×4
  See All ──────────────────────────────▶   ○ Rain jacket
                                              Rain expected Saturday
                                            floating +
```

This is the one place in the pass that makes a structural UX change rather than a restyle. It is
justified: opening a trip currently drops the user into a wall of checklist rows with no trip
context above it.

`View Weather` keeps the deep weather surface — expanded daily detail, precipitation, UV, wind,
snow, coverage state, attribution. Trip Detail gets a concise strip, not a duplicate.

### Destination imagery comes from MapKit, policy varies by surface

```text
Destination coordinate / MKMapItem
        │
        ├── MKLookAroundSceneRequest → MKLookAroundSnapshotter
        ├── MKMapSnapshotter
        └── gradient + SF Symbol
```

```swift
enum DestinationVisualPurpose {
    case tripThumbnail        // Look Around → Map → graphical
    case destinationPreview   // Map → graphical
    case tripHero             // Look Around → Map → graphical
}

protocol DestinationVisualService {
    func visual(for destination: Destination, purpose: DestinationVisualPurpose) async -> DestinationVisual
}
```

Destination search deliberately prefers the map. That screen answers *"did I select the right
Chicago?"*, and a map answers it better than a street-level view of an arbitrary intersection.

Look Around returns real street-level imagery, not guaranteed postcard photography. Coverage is
absent outside many metros, and a covered coordinate may still yield a storefront or a residential
street. All three tiers must therefore look **intentional** — the graphical fallback is a designed
state, never a broken-image placeholder.

Both snapshotters require the network. Cache on trip creation, when the coordinate is already known,
so Trip Detail is warm before it is ever opened. Cache key is coordinate + purpose + size class +
appearance where relevant. The cache is disposable derived UI data, never core trip data. Offline
with no cache renders the graphical fallback immediately — no spinner blocks Trip Detail.

### Packing habits are not invented

Me currently holds four self-set booleans: `usuallyWorkOut`, `usuallyBringLaptop`, `wearContacts`,
`alwaysBringMedication`. There is no learned habit data anywhere, and the post-trip memory loop is
outside MVP per [roadmap.md](../roadmap.md).

- **Me** shows only what exists. No "Usually bring / Tend to skip" block until `PackingMemory` has a
  real learning loop.
- **Onboarding panel 3** keeps its habits card. It is an illustration of a product promise, the same
  way panel 2's Chicago example is — not a display of the user's stored data.

### Kept exactly as-is

```text
semantic system colours          SF Pro / Dynamic Type
native TabView (two tabs)        SF Symbols
native navigation and sheets     accessibility behaviour
Domain/  Data/  api/  shared/    all packing and weather logic
```

## Design system additions

Built only as far as a real consumer needs them. No speculative component library.

```text
PackWiseSectionHeader      PackWiseSelectionRow
PackWiseIconBadge          PackWisePackingRow
PackWiseProgressBar        DestinationVisualView
PackWiseStatusBadge        spacing / radius / type tokens
PackWiseQuantityBadge
PackWiseWeatherChip
```

Existing primitives are reused rather than replaced: `PrimaryButtonStyle`, `SecondaryButtonStyle`,
`SelectableChip`, `ProgressSummary`, `PackWiseCard`, and `FlexibleChipWrap` / `FlowChips`
(`TripSetupView.swift:638-650`, which Activities is not currently using).

Reasons become **selective**. Secondary text appears when it carries information — `Rain expected
Saturday`, `Based on your work plans`, `Five-day trip` — and is omitted when it does not. Repeating
*"A core item for almost every trip"* under fifteen rows is noise, not provenance.

## Slice plan

Each slice is implemented, compared against the reference, checked in light and dark mode and at
larger Dynamic Type, run against the existing tests, and visually approved before the next begins.
No slice waits on another slice's review.

| # | Slice | Contains |
| --- | --- | --- |
| 0 | App Attest device verification | Sections 0, 1 and the Developer Tools probes of the device checklist. UI-independent; closes half the open gate now. |
| 1 | Foundation + Trip Detail overview | Primitives, `DestinationVisualService`, hero, progress, compact weather, daily strip, Packing Impact, category summary, See All. No item rows. |
| 2 | Packing List + Item Detail | Pushed checklist, filters, Reminders-style rows, quantities, selective reasons, Why This sheet. |
| 3 | Trips Home | Compact trip cards with thumbnails, past trips, designed empty state. |
| 4 | Trip Setup 1–8 | Destination + map preview, calendar range, party, type, activities as chips, merged bag + style, extras, review. |
| 5 | Couple / family / group detail | Same language extended; no second design system. |
| 6 | Edit / diff / weather-change | Add Item, Edit Trip, Review Changes, Weather Changed. Added / Removed / Quantity distinguished by more than colour. |
| 7 | Completed and past trips | Only data the product genuinely has. |
| 8 | Me | Preferences and "Usually true for me". Developer Tools stays `#if DEBUG` at the bottom. |
| 9 | Weather detail and state screens | Full detail, partial forecast, seasonal-only, stale, unavailable. Reuses slice 1's weather primitives. |
| 10 | Onboarding | Three screens against art-directed bundled assets. |
| 11 | Full device UI/UX QA | Sections 2, 4, 12 of the device checklist, against the finished UI. |

Slices 1–10 are implemented and committed. Each was checked in light mode,
dark mode, and at an accessibility text size by photographing the running
app — `scripts/capture_ios_screens.sh`, driven by the Debug-only
`-PackWiseScreen` seed. `ImageRenderer` cannot do this: it returns SwiftUI's
unavailable glyph for `List`, `ScrollView`, and `NavigationStack`.

Slices 0 and 11 are the two device items and cannot be done from here. Slice
0 needs a signed build on real hardware to exercise App Attest against
Apple's development environment; slice 11 needs a real finger on a real
screen. Both remain open in
[device-pass-checklist.md](../device-pass-checklist.md).

**Why Trip Detail first.** It exercises destination imagery, progress, weather, Packing Impact,
category hierarchy, status, and long-scroll behaviour simultaneously. If the primitives are wrong,
they are wrong there first — before they have been rolled across fourteen other files.

**Why onboarding last.** It is largely art direction. Building three beautiful screens while the
product behind them still does not match would prove nothing.

Setup goes from nine steps to eight visual screens by merging bag and style, as the board draws it.
The step model itself is unchanged.

## Documentation edits this requires

- **`docs/packing-experience.md`** — the daily forecast strip moves onto Trip Detail; Packing Impact
  now sits between the compact weather overview and the **packing-category summary** rather than the
  inline checklist; the checklist is described as a pushed screen.
- **`docs/trip-creation.md`** — bag and style are one screen.
- **`docs/design-system.md`** — record the destination-imagery policy and the three-tier fallback.
- **`design/README.md`** — add the additional boards once they are in the repo.

## Blocking inputs

Neither can be produced from the codebase. Both are needed before the slice that consumes them.

1. **Onboarding imagery** — three original or licensed images, art-directed to the board's crops with
   text-safe areas, dropped into the existing empty imagesets. Blocks slice 10. Layouts can be built
   against the graphical fallback before then.
2. **The additional design boards** — Review, Building your list, Packing List, Item Detail, Add
   Item, Edit Trip, Review Changes, Weather Changed, Completed Trip, Me, Packing habits, family and
   couple setup. These exist outside the repo. Until they are committed to `design/`, slices 5–8 are
   derived from the design system rather than matched to a mock.

## Out of scope

```text
new product functionality        packing memory / learning loop
Domain or Data behaviour         M3B context enrichment
custom tab bar                   M3C gap candidates
hardcoded colour values          multi-destination trips
a second visual language         stock-photo dependency
```

Behaviour is not changed to make a mockup easier to reproduce.
