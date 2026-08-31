# Implementation Decisions

Frozen answers for the first build. Update this file if a decision changes.

## Repo

```text
ios/          Native iOS 18 app
api/          Intelligence API
shared/
  catalog/    Canonical items by category (source of truth)
  rules/      Base, trip-types, activities, weather, quantities, substitutions, party
  schemas/    JSON schemas for CI
  contracts/  Typed Intelligence API OpenAPI
  fixtures/   Test-only destinations, weather, trip evals
docs/
design/
```

`shared` is data and contracts only. Do not share Swift business logic with TypeScript. The Python generator is a bootstrap/validation tool, not the long-term authoring system. Edit JSON/YAML directly.

## App identity

- Display name: **PackWise**
- Bundle ID: `com.packwiseapp.app`
- Minimum iOS: **18.0**

## Destinations

Production search is MapKit in M1:

```text
User types → MKLocalSearch → PackWise Destination
  persist displayName, city, region, country, countryCode, coordinates, timeZone
```

Resolve timezone from the MapKit result, never from the device. Completer polish and a map thumbnail are not M1 blockers.

`shared/fixtures/test-destinations.json` is **test/preview/weather-fixture matching only**. Never ship a static city database as the product destination source.

## Weather

- Real WeatherKit in Milestone 2A; mock fixtures remain for tests/previews
- Production uses `WeatherKitWeatherService`; tests/previews use `MockWeatherService`
- `WeatherService`: `forecast`, `attribution`, `availability`
- Domain code never consumes WeatherKit types. Adapter output is `TripWeatherContext`.
- **WeatherKit attribution is mandatory** in any production UI that displays Apple weather data (`WeatherService.attribution`, Apple Weather mark, legal link). Fixture/seasonal lists do not show Apple attribution.
- Persist `fetchedAt`, coverage dates, `providerFetchedAt`, and `providerExpiresAt` on `WeatherSnapshot` (encoded `TripWeatherContext` payload). Do not invent a hardcoded “expires in 3 hours” TTL
- Model coverage: `coverageStart`, `coverageEnd`, `forecastAvailableForWholeTrip`, `forecastAvailableForPartialTrip`, `source`
- `TripWeatherState`: `unavailable | seasonalOnly | forecastPartial | forecastComplete | stale | refreshing | failedUsingCache`. These names are internal; UI copy is human.
- Model alerts now (`TripWeatherAlert`) even if M2 does not show an alerts product
- Packing generation must never fail because weather failed
- Weather refresh (newer snapshot) and recommendation refresh (packing consequence) stay separate. Meaningful-change detection compares packing signals, not raw forecast fields.
- WeatherKit includes up to 500,000 calls/month with Apple Developer Program membership; cache using provider expiration

Weather path:

```text
WeatherSignalExtractor → PackingConditions → WeatherPackingRules
```

Signals include `meaningfulRain`, `persistentRain`, `coldRain`, `highUVExposure`, `hotOutdoorExposure`, `coldEvenings`, `highWindExposure`, `snowExposure`, `largeTemperatureSwing`.

Thresholds in `shared/rules/weather.json` are defaults, not the whole intelligence system. Combine rain × activity, temperature × duration, wind × rain, UV × outdoor, cold × user sensitivity.

## Home country

```text
homeCountryCode: String?
homeCountrySource: userConfirmed | deviceSuggested
```

Prefill from device region. Do not treat device region as fact. Strong international-document recommendations require `userConfirmed` or an explicit “traveling internationally” chip.

Never claim “Visa required.” Visa/entry docs are a reminder to check requirements. Do not assert plug types without a maintained data source.

## Catalog

- Canonical IDs are stable. Display names and `localizationKey` can change
- Prefer one canonical item plus capabilities over duplicate objects
- `hydration.water_bottle` is the single water-bottle item (everyday / hiking / outdoor)
- `travel_comfort.empty_security_bottle` is the TSA liquids-empty bottle, not a second water bottle
- Substitution uses capabilities, not blunt dedupe-only groups
- `companions` recommend related items (laptop → charger)
- `travelRestrictionReviewRequired` suppresses confident recommendations for regulated items (multi-tools, etc.) until we have a trusted rules source
- Icons are presentation only. Recommendation logic never depends on SF Symbol names
- Quantity kinds resolve through `shared/rules/quantities.json`

## Travelers and parties

`TripParty` and `Traveler` are foundational. Solo is internally one traveler; the UI stays as simple as today.

```text
travelMode: solo | couple | family | group
Traveler: role, ageGroup, packingResponsibility, guardianTravelerID?, needs[]
PackingItem.travelerID = owner; assignedTravelerID = carrier
Bag: ownerTravelerID?, ownershipType personal|shared
sharingPolicy: singlePerParty | scaleByParty | scaleByDevices | scaleByDurationAndParty | personalOnly
```

Kid age groups make items eligible. Clothes and backup outfits can be automatic. Diapers, formula, strollers, and similar needs require a setup chip or a stronger signal.

SwiftData: `PackWiseSchemaV1` → `PackWiseSchemaV2` via `PackWiseMigrationPlan`. Stores created before versioning have no version hash; the container recovers those once, then later changes must add a new schema version.

**Frozen for V1 architecture.** Domain invariants live in `PartyInvariants`. `sharingPolicy` stays in `shared/rules/party.json`; packing items store the resolved quantity and reason only.

See `docs/travelers-and-parties.md`.

## Trip domain fields (exist now, UI later if needed)

- `travelerCount` is derived from `TripParty.travelers.count`
- `transportation`: `flight | drive | train | cruise | other | unknown`
- `laundryAccess`: `none | possible | planned`
- `datedActivities[]` — MVP activities remain trip-wide; do not design the model so an activity can only apply to the whole trip

## Intelligence

Frozen M3 principle:

```text
Deterministic engine
        ↓
core packing list

GPT-5.6
        ↓
context enrichment / gap finding / unusual-trip reasoning

Recommendation Resolver
        ↓
final user-controlled result
```

GPT must never become `trip → GPT → arbitrary list`. The deterministic engine remains the authority for canonical items, quantities, party logic, substitutions, overrides, and reconciliation.

GPT output is a **suggestion, never persisted truth**:

```text
Model output
   ↓
schema validation
   ↓
canonical / enum validation
   ↓
domain validation
   ↓
Recommendation Resolver
   ↓
user-facing suggestion
```

Never `GPT → SwiftData`. Especially for family items, medicine, travel documents, regulated items, and destination-specific claims.

- Deterministic engine first; GPT protocol from day one
- Free-text keyword matching is **offline fallback only**. Do not grow it into an NLP dictionary
- Model policy lives on the server only. Never hardcode model IDs in iOS or scatter them through the API:
  `PACKWISE_MODEL_CONTEXT`, `PACKWISE_MODEL_GAPS`, `PACKWISE_MODEL_OPTIMIZE` (the env var names the *capability*, not the endpoint, so `/v1/trip/interpret` reads `PACKWISE_MODEL_CONTEXT`) (initially all `gpt-5.6`, which currently routes to GPT-5.6 Sol). Terra / Luna are later evaluation options, not M3 defaults
- Structured Outputs with JSON Schema, not loose JSON mode or prose parsing
- Every intelligence response records `model`, `promptVersion`, `schemaVersion`, `requestID`, `generatedAt`
- Send an opaque `safety_identifier` derived from a stable installation ID — never name, email, or device name
- Responses API `store: false` for M3. Storage behavior is intentional, not default
- Per-capability timeouts, one retry on transient 429/5xx, no retry on 4xx validation failures
- Per-capability rate limits and a short-lived result cache keyed by feature + normalized context + list state + prompt version
- Request logs: `requestID`, capability, model, prompt/schema versions, duration, outcome. Do **not** log raw trip notes, custom item names, or full payloads
- Minimize context sent to OpenAI. Interpret: note + already-known type/activities/destination/dates/bag/style. Gaps: those plus weather summary, current canonical item IDs, important overrides, a small relevant preference/memory slice. Never the whole history
- App integrity in M3A: `AppIntegrityProvider` → `DevelopmentAppIntegrityProvider` (local/simulator) and `AppAttestIntegrityProvider` (device). API accepts development requests locally; enforce real attestations before external TestFlight. Routes are `/v1/integrity/challenge` and `/v1/integrity/attest`
- `PACKWISE_APP_ATTEST_ENVIRONMENT` is stated per deployment, never inferred from `NODE_ENV` or anything else. Sandbox and production keys are not interchangeable, and TestFlight and App Store builds always use `production` regardless of the local entitlement. Unset is a boot failure
- Users see PackWise recommendations, never “AI recommendations”
- Confidence is internal and **numeric, `0...1`**, for ranking/suppression thresholds. Out-of-range values are dropped, not clamped. Map to Required / Recommended / Helpful / Optional. Never show “91% confident”
- GPT cannot overwrite user overrides
- GPT cannot change quantities owned by the quantity engine. Gap `action` is `recommend` only. `quantity_change` exists on `/v1/packing/optimize` (backend-only in M3)
- Unknown canonical IDs, activity IDs, chips, and signals are **rejected**, never created dynamically
- Silent deterministic fallback during generation. No “AI unavailable” alert. Explicit later surfaces (What am I forgetting?) may say PackWise couldn’t check additional suggestions

M3 endpoint set (no `/chat`):

```text
POST /v1/trip/interpret     M3A + M3B
POST /v1/packing/gaps       M3A + M3C
POST /v1/packing/optimize   M3A contract + tests; no UI
```

Specified, not M3 product work: `/v1/trip/context`, `/v1/trip/ask`. Do not implement `/v1/trip/context` as a GPT-writes-items path.

Interpret returns structured **TripContext enrichment**, not packing items. Validate against known activity IDs (`shared/rules/activity-rules.json`), `ContextChip` raw values, and a closed signal enum. Merge into `TripContext`; the engine decides items.

Gaps return structured candidates. Canonical validation → Recommendation Resolver (already present? substitution? Not Needed? party ownership? bag constraints? restriction metadata?) → optional list items. No dedicated gap-check UI in M3.

Optimize stays backend-only. Ask PackWise UI, Pack lighter UI, and “What am I forgetting?” are V1+.

Evaluation fixtures live in `shared/fixtures/trips/` alongside the deterministic engine fixtures, so one scenario asserts both layers. They must pass before remote intelligence is the production default. Schema: `shared/schemas/trip-eval.schema.json`.

```text
mustInclude / mustNotInclude   final deterministic packing expectations
note                           free-form trip note, the input to interpretation
mustInfer / mustNotInfer       chips and activities interpretation must / must not produce
allowedSuggestions             canonical IDs that are legitimate gap suggestions here
```

The nine intelligence scenarios: `TokyoInternationalWalking`, `ReykjavikPhotography`, `MiamiBeachCarryOn`, `DenverOutdoorCold`, `ChicagoCityRainy5Day`, `BusinessTrip3Day`, `WeddingWeekend`, `FamilyToddlerThemePark`, `LongHaulInternationalFlight`. `OneDayNoWeather`, `PreserveManualQuantity`, and `OverrideKeepsRainJacketDeleted` remain engine-only fixtures with no `note`.

`mustInfer` / `mustNotInfer` vocabulary is validated against `shared/rules/base.json` context chips and `shared/rules/activity-rules.json` activities by `scripts/validate_shared.py`, which also fails if the Swift `ContextChip` enum drifts from the rules.

M3 acceptance criteria:

1. Deterministic generation succeeds with the API completely offline
2. OpenAI key exists only server-side
3. Model responses use Structured Outputs
4. Every returned canonical item is validated
5. Unknown IDs are rejected, never created dynamically
6. GPT cannot overwrite user overrides
7. GPT cannot directly change quantities owned by the quantity engine
8. Free-form note enrichment improves `TripContext`
9. Gap detection only proposes missing contextual items
10. Duplicate / substituted items are filtered
11. Request logging contains no unnecessary personal trip notes
12. `safety_identifier` is stable and privacy-preserving
13. Storage behavior is intentional (`store: false`)
14. Model + prompt + schema versions are recorded for debugging
15. GPT failure leaves PackWise fully usable
16. Evaluation fixtures pass before enabling the capability by default

## M3A-1 (frozen)

Contracts and validation seams are real; the model is not. Do not reopen M3A-1
architecture unless M3A-2 exposes a genuine defect.

```text
generated schemas (api + strict model-output)
canonical / reason-code / vocabulary validation
request IDs, prompt + schema versioning
per-capability rate limits (in-memory)
AppIntegrityProvider + DevelopmentAppIntegrityProvider
Swift IntelligenceHTTPClient + RemoteContextIntelligenceService
FakeModelAdapter
nine evaluation fixtures with note / mustInfer / mustNotInfer / allowedSuggestions
```

Seven of the nine intelligence scenarios already existed as engine fixtures;
`FamilyToddlerThemePark` and `LongHaulInternationalFlight` were added.

## M3A-2 — live infrastructure, not product behavior

M3A-2 changes what runs, not what PackWise does. At the end of it all three
routes work against real GPT-5.6, and the normal generation flow still behaves
exactly as it does today. Wiring interpretation into `TripContext` is M3B;
wiring gaps into suggestions is M3C.

```text
Live OpenAI adapter
+ production App Attest
+ durable abuse/security state
+ Vercel deployment
+ live integration verification
```

### Live adapter

`OpenAIResponsesModelAdapter` sits behind the existing `ModelAdapter` seam
alongside `FakeModelAdapter`. It uses the **generated**
`shared/schemas/intelligence/model-output.schema.json` as its Structured Outputs
schema — never a second hand-written copy.

```text
store            = false
safety_identifier = HMAC(server secret, install identity)
model            = PACKWISE_MODEL_CONTEXT / GAPS / OPTIMIZE
schema           = generated model-output.schema.json
```

### Safety identifier

PackWise has no accounts, so the identifier is install-scoped, not a user
identity system:

```text
random install identifier   (already shipped: InstallIdentity)
        ↓ persisted locally
server receives opaque ID
        ↓ HMAC with server secret
safety_identifier
```

Never send a raw App Attest key ID to OpenAI. HMAC it server-side first. This
gives abuse correlation without attaching anything personal.

### App Attest needs durable state

Apple's flow is stateful: one-time challenge → attestation → stored public key →
assertions with a monotonic counter. Process memory cannot hold this.

```text
AppAttestKeyRecord            AppAttestChallenge
- keyID                       - challenge
- publicKey                   - expiresAt
- environment                 - consumed
- lastCounter
- createdAt
- lastSeenAt
```

Storage shape stays backend-only. `PACKWISE_INTEGRITY_MODE=appattest` must never
silently downgrade to development trust.

### Durable rate limiting

In-memory limits are correct for tests and a single instance, not for
serverless. M3A-2 moves them to Redis (Upstash or Redis Cloud via the Vercel
Marketplace; Vercel KV is sunset), which also holds App Attest challenges and
key state, short intelligence caches, and replay prevention. Postgres is not
needed for this milestone.

Vercel WAF is an outer abuse layer, not a replacement: per-capability limits for
`interpret` / `gaps` / `optimize` stay in the API.

### Shared vocabulary must be a build artifact

Production must not depend on `../shared` happening to be present at runtime.
Generate deterministic artifacts into the API's own tree instead:

```text
shared/
  ↓ generator
api/generated/
├── schemas/
├── catalog-index/
├── reason-codes/
└── vocab/
```

`PACKWISE_SHARED_DIR` stays a local tooling convenience, not the production
architecture.

### Retries stay conservative

The core app already survives intelligence failure, so there is no reason to
make anyone wait through a retry chain.

```text
timeout                    → one retry, transient network/provider only
4xx schema / input failure → never retry
model schema violation     → do not blindly retry
429 / 5xx                  → bounded retry with jitter
```

### Live response metadata

Server-side only, not in the client DTO: `model`, `providerResponseID`,
`latencyMs`, `inputTokens`, `outputTokens`. Enough to answer "which prompt and
model produced this odd suggestion?" without logging the trip note.

### M3A-2 acceptance criteria

Three states, because "blocked" and "done" are both wrong for most of this.
Fixture-backed cryptographic verification is not Apple-service verification, and
saying so is the point.

**✅ Proven offline** — covered by the automated suite:

```text
 1. Fake adapter still works in tests
 2. Live OpenAI adapter uses the generated strict schemas
 3. No OpenAI key exists in iOS
 4. store:false is explicit
 5. safety_identifier is privacy-preserving and stable
 6. Capability model env vars select the model
 7. Model/schema failures follow the existing 502 policy
 8. Domain-invalid candidates are dropped individually
 9. App Attest challenge endpoint exists
12. Replay challenge is rejected
13. Assertion counter regression is rejected
14. appattest mode never silently downgrades
15. Development mode remains explicit
19. GPT failure leaves iOS core packing unaffected
```

**🟡 Implemented, external verification pending** — written and unit-tested,
never exercised against the real thing:

```text
10. Real attestation can be registered      (verified against synthetic chain)
11. Assertions verify on intelligence routes (verified against synthetic chain)
16. Rate limiting is durable across instances (verified against FakeRedisClient)
17. shared vocabulary deploys reliably       (api/generated built and checked)
```

**⏳ Hard external verification** — needs credentials or hardware:

```text
18. Production Vercel deployment answers all routes
20. Live eval smoke suite runs successfully
    OpenAI Structured Outputs request compatibility
    Real Redis backend
    Physical-device App Attest
    Physical-device WeatherKit (outstanding from M2)
```

Do not record 18 or 20 as done until they have actually run. The honest
checkpoint is: **M3A-2 implementation complete; external verification pending
OpenAI, Redis, Vercel, and signed-device credentials.**

Do not start M3B before that verification pass. M3B is where model behavior
first reaches real trip context. The ordered steps — live OpenAI, then
real Redis, then Vercel, then physical-device App Attest, then TestFlight, then
the outstanding M2 WeatherKit pass — are in
[m3a2-verification-runbook.md](m3a2-verification-runbook.md), along with the
per-build App Attest environment table.

### M3B open contract issue: interpretation is not traveler-scoped

Found in the M3A live eval baseline, logged rather than fixed — it belongs to
M3B, not to the vocabulary cleanup that surfaced it.

`FamilyToddlerThemePark`'s note says *"she has an ear infection we're still
treating."* Interpretation returned the `dailyMedication` chip. The note is
about the toddler; the chip is about the person the list is being built for.

```text
note mentions a traveler's condition
        ↓
interpretation returns a chip
        ↓
chip has no traveler                ← the gap
        ↓
merged into the primary traveler's context
```

`ContextChip` is already per-traveler in the domain — `Traveler.chips` exists,
and `ContextChip.tripLevel` distinguishes the two that are not personal. The
interpretation contract does not carry that distinction, so a chip inferred from
a note about someone else lands on the wrong person.

M3B has to decide before wiring interpretation into `TripContext`:

- does `InterpretTripResponse` carry a traveler reference per chip, and if so
  how is a traveler identified to the model without sending names;
- or does interpretation return trip-level context only, leaving anything
  traveler-scoped to explicit user input.

The second is smaller and matches the current M3 boundary. Either way this must
be settled before the enrichment merges, because a medication chip on the wrong
traveler is exactly the class of mistake the resolver boundary exists to prevent.

### What M3A-2 built

```text
OpenAIResponsesModelAdapter + OpenAITransport (injectable)
Versioned prompts: interpret/1, gaps/1, optimize/1
HMAC safety identifier
Retry + full jitter + timeout, injected clock/random/sleeper
Provider response metadata, server-side only

DurableStore
├── InMemoryDurableStore
└── RedisDurableStore → RedisClient → { RealRedisClient, FakeRedisClient }

App Attest: challenge, registration, assertion verification,
            replay protection, counter protection
            (CBOR + DER readers, node:crypto chain and signature verification)

api/generated/ build artifact + Vercel packaging + environment validation
iOS AppAttestIntegrityProvider + UnavailableAppIntegrityProvider
```

Prompt tuning is deliberately not part of this. M3A-2 needs versioned production
prompts that satisfy the architecture; tuning without live evals is guesswork.

### Two device-dependent passes now outstanding

```text
M2    real WeatherKit signed-device verification
M3A   real App Attest signed-device verification
```

Both can be done in the same TestFlight/device session.

### Vocabulary: one activity per packing behavior

`fineDining` and `niceDinner` both mapped to `clothing.nice_outfit` — same
quantity, same importance, same explanation, same UI. Two IDs for one behavior
is duplication, and the live eval failed on it: the model picked one synonym,
the fixture asserted the other.

`niceDinner` is canonical. It names the packing intent — needing a nicer outfit
for a dinner — rather than the restaurant's tier. `fineDining` is removed from
the vocabulary; `ActivityVocabulary.renames` normalizes persisted values on read
so trips saved before the merge heal without a store migration. Phrasings like
"fancy dinner", "fine dining", and "upscale dinner" stay synonyms that interpret
to `niceDinner`.

Add a distinction when the packing behavior diverges — for example if
`formalDinner` ever means a suit rather than smart casual — not to satisfy an
eval.

## Reasons

Every generated item carries `reasonCode`, `reasonArguments`, and `sourceSignals`. UI renders templates. GPT may improve copy later; deterministic reasons must already be specific (“Rain is expected on 3 of your 5 travel days.”).

## Milestones

M1 is closed. M2 is code-complete. Do not reopen M1 or M2 architecture unless physical-device WeatherKit verification exposes a genuine defect.

```text
M1 ✅ Core packing loop
  Create → Generate → Trip Detail → Edit safely → Pack → Complete → Past
  MapKit destination search, SwiftData, catalog, deterministic engine
  Mock weather fixtures for tests/previews
  Edit-trip recommendationDiff (preserve packed, custom, quantities, overrides)
  Delete vs Not Needed, Hide Packed, Complete Trip / Past

M2 ✅ Weather lifecycle
  ⏳ Physical-device WeatherKit verification
  M2A WeatherKit foundation
  M2B Packing Impact
  M2C weather-change diffs (one pending proposal, stale invalidation,
      snapshot vs packing acceptance, dismiss ≠ Not Needed)

M3 ← CURRENT — Context intelligence
  GPT-5.6 enriches the existing engine; it does not replace it
  M3A Intelligence API foundation (no big new UX)
      M3A-1 contract + plumbing, FakeModelAdapter, no OpenAI key required — done
      M3A-2 OpenAIResponsesModelAdapter, prompts, production App Attest
  M3B Trip-context enrichment (free-form note → TripContext)
  M3C Packing-gap detection (resolver-filtered optional suggestions)
  /v1/packing/optimize is backend-only; Pack lighter UI is V1+

M4 — Departure experience
  Share sheet, notifications, Final Check, near-departure state, polish

V1+
  Post-trip review, Packing Memory learning, Ask PackWise UI,
  What am I forgetting?, pack lighter UI, iCloud
```

Keep out of M2: GPT explanations, natural-language weather Q&A, Packing Memory, post-trip review, transportation UI, bag assignment, collaboration, weather alerts as a major surface, complex climate database, map thumbnail, extra catalog items. Severe-weather fields may exist on the normalized model; they are not an M2 product surface.

Keep out of M3: Ask PackWise UI, Pack lighter UI, dedicated “What am I forgetting?” screen, natural-language trip creation, `/chat`, GPT writing SwiftData, GPT inventing canonical items, GPT changing quantities, hardcoded model IDs, numeric confidence in the UI, “AI unavailable” alerts during generation, M4 notifications/share/Final Check, reopening M2 architecture.

- **M1 (closed):** shell, onboarding, MapKit destination search, trip setup, SwiftData, catalog, deterministic engine, checklist, mock weather, M1 loop closure
- **M2A (closed):** real WeatherKit + normalize/persist + coverage/cache + attribution infrastructure
- **M2B (closed):** Packing Impact from persisted provenance
- **M2C (closed):** meaningful weather-change diffs, one pending proposal, stale invalidation, snapshot vs packing acceptance, dismiss ≠ Not Needed
- **M3 (now):** GPT-5.6 Intelligence API — M3A foundation, M3B note enrichment, M3C gaps. Engine remains authority
- **M4:** notifications, sharing, Final Check, polish

Do not grow the catalog unless a real trip fails. Do not write Packing Memory from pack/Not Needed. Transportation stays a domain field without a setup screen until the engine has meaningful flight/drive/train/cruise behavior.
