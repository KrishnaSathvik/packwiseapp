# Design

Visual reference for PackWise. Product behavior lives in [`../docs/`](../docs/README.md). Visual rules live in [`../docs/design-system.md`](../docs/design-system.md).

## Current mocks

| File | What it shows |
| --- | --- |
| [ui-flow-overview.png](ui-flow-overview.png) | Ten-screen iPhone flow: onboarding, trips home, trip setup, trip detail |

Match this mock when building UI. Do not invent a second visual language.

## Screen map

The overview mock is a single horizontal flow. Left to right:

1. **Welcome** — Suitcase mark, wordmark PackWise, headline “Pack what this trip actually needs.” Value line about weather-aware suggestions that get more personal. Primary **Get Started** over coastal photography.
2. **How it works** — Chicago · 5 days · forecast example becoming Rain jacket / Light layer / Walking shoes with “why” labels.
3. **Personalization** — Remembers what you bring, skip, and your packing style. CTA **Create My First Trip**.
4. **Trips home** — Upcoming Chicago card with dates, weather, 31 of 42 packed. Past Tokyo and Maui with Completed. Tab bar: **Trips** (selected) and **Me**.
5. **Destination** — “Where are you going?” search, Chicago results, map thumbnail.
6. **Dates** — Native-feeling calendar. Sep 12–16, 5 days · 4 nights.
7. **Trip type** — “What kind of trip is it?” icon list. Vacation selected.
8. **Activities** — “What will you be doing?” selectable chips plus **Your activities**.
9. **Bag and style** — “How are you traveling?” Carry-on selected. “How do you prefer to pack?” Light / Balanced / Prepared.
10. **Trip detail** — Chicago header, progress, weather card with “3 items affected”, category rows (Essentials 4/6, Clothing 9/13, Footwear 2/3), floating **+**.

## Visual constants from the mock

- Primary blue for CTAs, selected states, progress, and key icons
- White grouped cards with soft shadow
- SF Pro
- Outline SF-style icons
- 2-tab bar only
- Photography on welcome and trip cards, not on the packing list itself
- Progressive setup with Back / Next, not one long form

## Adding new mocks

Name files by surface, not by generator or timestamp.

Good: `trip-detail-weather-changed.png`, `final-check.png`, `me-packing-habits.png`

Avoid: `ChatGPT Image Aug 28, 2026, 07_55_25 PM.png`
