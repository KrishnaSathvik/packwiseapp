# PackWise Documentation

This folder is the product and engineering source of truth. Cursor rules in `.cursor/rules/` summarize the hard constraints. When a rule and a doc disagree, update both so they stay aligned.

Agents: start with [AGENTS.md](../AGENTS.md) and the always-applied PackWise rules. Open the matching file below before implementing a feature.

## Read first

| File | What it covers |
| --- | --- |
| [product-and-brand.md](product-and-brand.md) | Definition, promise, philosophy, brand language, product loop |
| [navigation-and-onboarding.md](navigation-and-onboarding.md) | Tabs, first launch, trips home |
| [trip-creation.md](trip-creation.md) | Progressive trip setup, review, generation |
| [travelers-and-parties.md](travelers-and-parties.md) | TripParty, travelers, personal vs shared packing |
| [packing-experience.md](packing-experience.md) | Trip detail, categories, items, quantities, search, add, filters |
| [weather-and-packing-impact.md](weather-and-packing-impact.md) | Weather UX, packing impact, change reconciliation |
| [intelligence-features.md](intelligence-features.md) | Ask PackWise, gaps, pack lighter, destination notes |
| [lifecycle-memory-and-me.md](lifecycle-memory-and-me.md) | Timeline, notifications, share, edit, during/after trip, memory, Me tab |
| [architecture.md](architecture.md) | Local-first stack, layers, models, catalog, feature folders |
| [packing-engine.md](packing-engine.md) | Intelligence pipeline, GPT boundary, resolver, scoring |
| [data-privacy-and-platform.md](data-privacy-and-platform.md) | Weather data, persistence, offline, API, privacy, analytics |
| [design-system.md](design-system.md) | Visual system, motion, photography, dark mode, accessibility |
| [roadmap.md](roadmap.md) | MVP, V1 after launch, V2, V3 |
| [implementation-decisions.md](implementation-decisions.md) | Frozen repo, weather, GPT, catalog, and milestone answers |
| [m3a2-verification-runbook.md](m3a2-verification-runbook.md) | The App Attest environment rule, and the ordered external verification pass gating M3B |
| [future-features.md](future-features.md) | Outfits, bags, airline limits, group packing, widgets, Siri |

## Design mocks

Visual reference lives in [`../design/`](../design/README.md). The current overview mock is [`../design/ui-flow-overview.png`](../design/ui-flow-overview.png).

## How to use these docs

- Preserve every product decision in these files. Do not leave important behavior only in chat.
- Customer-facing copy must follow [product-and-brand.md](product-and-brand.md). GPT-5.6 is internal only.
- Scope decisions come from [roadmap.md](roadmap.md). Do not pull V2/V3 work into MVP unless the user explicitly expands scope.
- Architecture and data rules come from [architecture.md](architecture.md), [packing-engine.md](packing-engine.md), and [data-privacy-and-platform.md](data-privacy-and-platform.md).
