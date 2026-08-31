# PackWise — Agent Guide

PackWise is a personal packing intelligence app for iPhone. The user describes a trip. PackWise produces a relevant, explainable, adjustable list that gets more personal over time.

**Promise:** Pack what you need. Leave what you don't.

**Feeling:** I don't have to think through packing from scratch anymore.

## Non-negotiables

1. Never market or label PackWise as an AI app in customer-facing UI, copy, notifications, or onboarding. GPT-5.6 is internal only.
2. Local-first. The packing list works offline. External services enhance; they do not own user data.
3. GPT never writes SwiftData. Structured suggestions go through validation, the Recommendation Resolver, and user acceptance.
4. Never call OpenAI from the iPhone. Secrets stay on the PackWise Intelligence API.
5. Explicit user decisions always win. Removed items do not silently return.
6. Two tabs only: **Trips** and **Me**. The trip is the container for weather, packing, and Ask PackWise.
7. Packing rows are Reminders-style. Cards are for emphasis only.
8. Weather is trip-dated, not a general weather app. Never silently rewrite a list when the forecast changes.
9. Stay in MVP unless the user expands scope. See `docs/roadmap.md`.
10. No signup, no location permission, no notification permission, no paywall on first launch.

## Where to look

| Question | File |
| --- | --- |
| What is PackWise? Brand language? | `docs/product-and-brand.md` |
| Tabs, onboarding, home | `docs/navigation-and-onboarding.md` |
| Trip setup steps | `docs/trip-creation.md` |
| Travelers, parties, shared items (frozen) | `docs/travelers-and-parties.md` |
| List, items, quantities, search | `docs/packing-experience.md` |
| Weather, packing impact, diffs | `docs/weather-and-packing-impact.md` |
| Ask PackWise, gaps, pack lighter | `docs/intelligence-features.md` |
| Timeline, notifications, memory, Me | `docs/lifecycle-memory-and-me.md` |
| Stack, layers, models, catalog | `docs/architecture.md` |
| Pipeline, GPT, resolver, API | `docs/packing-engine.md` |
| Persistence, privacy, analytics | `docs/data-privacy-and-platform.md` |
| Visual system, motion, a11y | `docs/design-system.md` |
| MVP / V1 / V2 / V3 | `docs/roadmap.md` |
| Later features | `docs/future-features.md` |
| M3A-2 external verification steps | `docs/m3a2-verification-runbook.md` |
| Physical-device App Attest + UI/UX pass | `docs/device-pass-checklist.md` |
| Screen mock | `design/ui-flow-overview.png` |

Cursor rules in `.cursor/rules/` repeat the hard constraints. Keep rules and docs aligned when a decision changes.

## Frozen implementation decisions

See `docs/implementation-decisions.md`. **M3A-2 implementation is complete; external verification is pending** OpenAI, Redis, Vercel, and signed-device credentials. M1, M2, M3A-1, and M3A-2 code are closed — do not reopen their architecture unless a device or live-integration pass exposes a genuine defect.

Be precise about what is verified: fixture-backed cryptographic verification is not Apple-service verification, and a green test suite is not a deployment. Acceptance criteria are tracked in three states, and each external step retains evidence rather than a checkbox. Do not start M3B or M3C before the M3A exit gate in `docs/m3a2-verification-runbook.md` is green — its last two items are a physical-device App Attest pass in Apple's development environment and a full device UI/UX pass. TestFlight production App Attest is deferred to distribution and does not gate M3B. The outstanding M2 WeatherKit device pass runs in the same session but is M2-owned and does not gate M3A.

The next code should be either a fix the external pass discovers, or — once the gate is green — the first deliberate M3B context-enrichment change. Not more infrastructure.

`PACKWISE_APP_ATTEST_ENVIRONMENT` is stated per deployment, never inferred: TestFlight and App Store builds always use `production` regardless of the local entitlement. An unset value is a boot failure, not a default.

M3A-2 changes what runs, not what PackWise does. Wiring interpretation into `TripContext` is M3B; wiring gap candidates into suggestions is M3C.

- Monorepo: `ios/`, `api/`, `shared/`, `docs/`
- iOS 18, `com.packwiseapp.app`, display name PackWise
- Deterministic engine first; GPT protocol exists from day one
- Real WeatherKit in M2A (closed); mock fixtures remain for tests/previews
- Home country preference; international = destination ≠ home
- Bag “Not sure yet” applies no bag constraint
- Units follow locale
- Catalog source of truth: `shared/catalog/`
- Destinations: MapKit in production; `shared/fixtures/test-destinations.json` is test/preview/weather-fixture matching only
- WeatherKit attribution is mandatory wherever Apple weather is shown
- Run `python3 scripts/validate_shared.py` after catalog/rule edits

## Implementation defaults

- Swift, SwiftUI, SwiftData, Swift Concurrency, Observation
- MapKit destination search is M1. WeatherKit is M2. UserNotifications and share are M4
- Canonical item IDs from `shared/`, not stringly-typed item names
- Repositories between views and SwiftData
- Feature folders as specified in `docs/architecture.md`
- Native iOS controls. SF Pro. SF Symbols. Semantic colors. Dark Mode from day one
