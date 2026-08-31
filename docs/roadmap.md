# Roadmap and Scope

## MVP

The real PackWise MVP:

```text
Onboarding

Trips Home

Trip Setup
- destination
- dates
- who's traveling (solo / couple / family)
- type
- activities
- bag
- packing style
- optional context

MapKit destination search

WeatherKit

Packing Catalog

Deterministic Packing Engine

GPT-5.6 contextual recommendation layer

Smart quantities

Recommendation explanations

Packing checklist

Custom items

Progress

Packing Impact

Weather detail

Weather change reconciliation

Share list

Basic notifications

Local SwiftData persistence
```

That is already a real product.

MVP still includes the internal GPT layer and explanations. It does not include a visible chatbot, post-trip memory loop, or V2 surfaces.

## Do not put these in MVP

Even though they are good:

```text
Outfit planner
Bag weight
Realtime group collaboration / invites
Widgets
Watch app
Siri
Android
Public profiles
Community packing lists
Travel booking
Full climate database
Social features
Complex subscription tiers
```

The fundamental experience must be exceptional first.

Also keep out of MVP unless the user explicitly expands scope:

```text
Natural-language trip creation
Post-trip review
Visible Packing Memory / habits personalization
What am I forgetting?
Pack lighter
iCloud sync
Watch app
Account / signup
Location permission
Subscription wall
```

## V1 after launch

```text
Post-trip review
Packing Memory
What am I forgetting?
Pack lighter
Past-trip personalization
Natural-language trip creation
iCloud sync
Final Check improvements
```

This is when the personalization loop becomes visible.

## V2

```text
Outfit planning
Bag assignment
Weight estimates
Advanced repeat-trip intelligence
Widgets
App Intents
Bag assignment UI
Travel companion packing across devices
```

## V3

Only if demand points there:

```text
Realtime group trips
Cross-device family profiles
Airline luggage rules
Cross-platform accounts
Android
Web
```

## Build milestones

Frozen in [implementation-decisions.md](implementation-decisions.md).

```text
M1 ✅ Core packing loop
M2 ✅ Weather lifecycle
    ⏳ Physical-device WeatherKit verification (M2-owned; runs in the
       same device session as M3A but does not gate M3A)
M3
    M3A Intelligence API foundation
        M3A-1 ✅ contract + plumbing, FakeModelAdapter (frozen)
        M3A-2 ✅ implementation — Responses API, production App Attest,
               durable state, Vercel packaging
    M3A external verification ← CURRENT
        ✅ OpenAI, live eval 18/18, real Redis, Vercel Production
        ⏳ physical-device App Attest (development) + full device UI/UX pass
        ⏸ TestFlight production App Attest — deferred to distribution
    M3B 🔒 do not start
    M3C 🔒 do not start
    M3B Trip-context enrichment
    M3C Packing-gap detection
M4  Share, notifications, Final Check
```

- **M1 (closed):** app shell, onboarding, MapKit destination search, trip setup, SwiftData, catalog, deterministic engine, packing checklist, mock weather fixtures, M1 loop closure (Create → Generate → Trip Detail → Edit safely → Pack → Complete → Past).
- **M2A (closed):** WeatherKit foundation — real `WeatherKitWeatherService`, normalize into `TripWeatherContext`, persist `WeatherSnapshot` coverage/cache metadata, `TripWeatherState`, Apple Weather attribution infrastructure. Fixtures stay for tests/previews.
- **M2B (closed):** Packing Impact card on Trip Detail, driven by existing recommendation provenance. Restrained read-only weather detail.
- **M2C (closed):** weather refresh vs recommendation refresh, packing-signal diff, user-reviewed `WeatherChangeProposal` (reuse `recommendationDiff()`). One pending proposal per trip; stale proposals invalidate; snapshot save is independent of packing acceptance; dismiss ≠ Not Needed. No M4 notifications. Do not reopen M2 architecture unless device WeatherKit verification exposes a genuine defect.
- **M3 (now):** Context Intelligence. GPT-5.6 enriches PackWise's existing engine; it does not replace it.
  - **M3A:** Intelligence API foundation — `RemoteContextIntelligenceService`, Structured Outputs, schema/canonical validation, prompt versioning, `store: false`, `safety_identifier`, rate limits, App integrity boundary. Typed endpoints: `/v1/trip/interpret`, `/v1/packing/gaps`, `/v1/packing/optimize`. No big new UX.
    - **M3A-1 (closed):** every contract real before any model behaviour is real. Generated request/response and model-output schemas, canonical + reason-code validation, request IDs, prompt/schema versioning, per-capability rate limits, `AppIntegrityProvider` with the development provider, Swift HTTP client and `RemoteContextIntelligenceService`, `FakeModelAdapter`, and the nine evaluation fixtures with `note` / `mustInfer` / `mustNotInfer` / `allowedSuggestions`. No OpenAI key required.
    - **M3A-2 (implementation complete, verification pending):** live infrastructure, not product behavior. `OpenAIResponsesModelAdapter` using the generated strict schema, real prompt templates, `store: false`, HMAC'd install-scoped `safety_identifier`, conservative timeout/retry, production App Attest with durable challenge/key/counter state, Redis-backed rate limiting, `shared/` vocabulary as a build artifact rather than a runtime path, Vercel deployment, live evaluation smoke suite. The normal generation flow still behaves exactly as it did — wiring happens in M3B and M3C. Acceptance criteria are tracked in three states (proven offline / implemented, verification pending / hard external verification) in [implementation-decisions.md](implementation-decisions.md). The external pass and its exit gate are in [m3a2-verification-runbook.md](m3a2-verification-runbook.md); capture evidence per step, not just a checkbox. M3A closes on its own six items — the outstanding M2 WeatherKit device pass shares the session but belongs to M2. TestFlight production App Attest is deferred to actual App Store distribution and does not gate M3B; a locally signed build cannot exercise Apple's production environment.
  - **M3B:** Trip-note interpretation merges into `TripContext`. GPT does not insert packing items.
  - **M3C:** Packing-gap candidates through the Recommendation Resolver as optional suggestions. No dedicated “What am I forgetting?” UI.
  - Optimize is backend-only in M3. Ask PackWise UI and Pack lighter UI are V1+.
- **M4:** notifications, sharing, Final Check, polish

Keep out of M2: GPT, Packing Memory, post-trip review, transportation, bag assignment, collaboration, map thumbnail, extra catalog items, weather alerts as a major surface.

Keep out of M3: Ask PackWise UI, Pack lighter UI, dedicated gap-check screen, `/chat`, GPT writing SwiftData, GPT inventing canonical items, GPT changing quantities, numeric confidence in the UI, “AI unavailable” alerts during generation.

Production destination resolution uses MapKit (done in M1). Bundled destinations exist only for deterministic previews, tests, and mock-weather fixture matching. M2A adds WeatherKit behind PackWise-owned models — not a weather app, and not MapKit itself.

## Scope rule for agents

If a request is not in MVP and the user did not explicitly ask to build it, do not implement it. Specify it, or keep it in [future-features.md](future-features.md).

When implementing MVP, still design models and APIs so V1 personalization can land without a rewrite: `PackingMemory`, `RecommendationOverride`, `PostTripFeedback`, and canonical item IDs exist from day one even if some UI is hidden.
