# PackWise Intelligence API

Milestone 3. Local during development, Vercel for deployed environments.

Do not create a `/chat` endpoint. Product capabilities stay explicit:

- `POST /v1/trip/interpret` — free-form note → structured `TripContext` enrichment
- `POST /v1/packing/gaps` — contextual gap candidates
- `POST /v1/packing/optimize` — reduction candidates, backend-only in M3
- `POST /v1/integrity/challenge`, `POST /v1/integrity/attest` — App Attest registration
- `GET /health` — what this instance is configured to do, and what is missing

`/v1/trip/context` and `/v1/trip/ask` are designed but deferred to V1+. They are
recorded under `x-deferred` in `shared/contracts/intelligence-api.yaml` rather
than served.

## Status: M3A-2 implemented, external verification pending

Every request path is real, including the live OpenAI adapter and the full App
Attest flow. What has not happened is anything requiring credentials: no request
has been made to OpenAI, no real Apple attestation has been verified, no Redis
server has been talked to, and nothing has been deployed.

```text
Route
 ↓ request schema validation      generated/schemas/api.schema.json
 ↓ safetyIdentifier shape check
 ↓ AppIntegrityProvider           development | appattest (assertion + counter)
 ↓ per-capability rate limit      durable store
 ↓ capability service             minimises the context sent onward
 ↓ ModelAdapter                   fake | openai-responses
 ↓ model output schema validation generated/schemas/model-output/<capability>
 ↓ canonical + domain validation  catalog IDs, reason codes, membership, confidence
 ↓ response schema validation
 ↓ response
```

M3A-2 changes what runs, not what PackWise does. Wiring interpretation into
`TripContext` is M3B; wiring gap candidates into suggestions is M3C.

## Running it

```bash
npm install
npm run build      # regenerate api/generated from shared/
npm test           # node --test, no credentials needed
npm run typecheck
npm run dev        # vercel dev
```

## `api/generated/` is the deployment artifact

`scripts/build_intelligence_schemas.py` turns `shared/` into exactly what the
functions load at runtime. It lives inside the Vercel project root on purpose —
production never reaches sideways into `../shared`.

```text
shared/  →  scripts/build_intelligence_schemas.py  →  api/generated/
                                                      ├── schemas/api.schema.json
                                                      ├── schemas/model-output/<capability>.schema.json
                                                      ├── vocab/{canonical-items,context-chips,activities,reason-codes}.json
                                                      └── manifest.json
```

`manifest.json` carries `schemaVersion` and a content `buildHash` — a hash, not
a timestamp, so the artifact is reproducible. `scripts/validate_shared.py` and
the Vercel build command both fail if it is stale. Edit the generator, never the
generated JSON.

The model-output schemas are restricted to the Structured Outputs strict subset:
every property required, `additionalProperties: false`, no numeric or string
constraint keywords, optionality as a nullable type. Reason arguments travel as
`{name, value}` pairs because strict mode cannot express a free-form map. The
adapter hands the model **the same file** the response is then validated
against, so there is no second copy to drift.

Closed vocabularies come from `shared/rules/`, so the model physically cannot
return a chip, activity, or reason code the app does not know.

## Two validation layers

Schema validation proves shape; `src/canonical.ts` proves content. They fail
differently on purpose:

| Situation | Result |
| --- | --- |
| Invented chip, activity, or reason code | `502 invalid_model_output` — the enum is closed, so this means a broken model or a stale schema |
| Invented canonical item ID | Dropped, `200` — item IDs stay free-form in the model schema, so one bad candidate costs that candidate |
| Item already on the list | Dropped |
| Optimization for an item not on the list | Dropped |
| Confidence outside `0...1` | Field omitted, never clamped |

Rejection counts are logged. A model that starts inventing is visible.

## Retries stay conservative

PackWise already survives a failed intelligence call by falling back to the
deterministic list, so nobody waits through a retry chain.

```text
network / timeout       one bounded retry
429 / retryable 5xx     one bounded retry, honouring Retry-After
400-class, auth         never retried
malformed output        never retried in a loop
```

Backoff is full jitter within a capped exponential window. The clock, sleeper,
and random source are injected, so attempt counts and delays are asserted
deterministically without a test ever sleeping.

## App Attest

Apple's flow is stateful, so it needs the durable store:

```text
POST /v1/integrity/challenge   one-time challenge, 5-minute TTL
POST /v1/integrity/attest      verify chain, nonce, key ID, app ID,
                               environment, counter → store public key
every intelligence request     assertion over the request body,
                               strictly increasing counter
```

The assertion is computed over the exact bytes being sent, so a valid assertion
cannot be lifted onto a different request. `PACKWISE_INTEGRITY_MODE=appattest`
refuses to start without `PACKWISE_APP_ID`, `PACKWISE_APP_ATTEST_ENVIRONMENT`,
and `PACKWISE_APP_ATTEST_ROOT_PEM`, rather than downgrading.

`test/appAttestFixtures.ts` mints a synthetic root CA, credential certificate,
and CBOR attestation/assertion objects with real P-256 keys, which exercises the
verifier's actual cryptography. That proves the protocol is implemented. It does
not prove Apple accepts a real attestation — see the verification states below.

## Configuration

```bash
OPENAI_API_KEY=sk-...
PACKWISE_MODEL_CONTEXT=gpt-5.6     # /v1/trip/interpret
PACKWISE_MODEL_GAPS=gpt-5.6
PACKWISE_MODEL_OPTIMIZE=gpt-5.6
PACKWISE_SAFETY_IDENTIFIER_SECRET=...
REDIS_URL=redis://...
PACKWISE_INTEGRITY_MODE=appattest
PACKWISE_APP_ID=<teamID>.com.packwiseapp.app
PACKWISE_APP_ATTEST_ROOT_PEM=...
PACKWISE_APP_ATTEST_ENVIRONMENT=production
```

`PACKWISE_APP_ATTEST_ENVIRONMENT` is stated per deployment and never inferred —
sandbox and production keys are not interchangeable, and TestFlight and App
Store builds always use `production` regardless of the entitlement set locally.
An unset value is a boot failure, not a default. See
[docs/m3a2-verification-runbook.md](../docs/m3a2-verification-runbook.md) for
the per-build table.

The model env vars name the *capability*, not the endpoint, so the context
capability can outgrow `/v1/trip/interpret` without another rename. Model IDs
are never literals in the code.

Production refuses to boot with any of these missing. There is no fallback from
Redis to process memory, and none from `appattest` to development trust: either
would look like a working deployment. `GET /health` reports what is configured
and what is absent, by presence and never by value.

## Privacy

The OpenAI key exists only here. iOS never calls OpenAI.

Trip notes, destinations, and item names are never logged — request logs carry
`requestID`, capability, model, prompt and schema versions, duration, outcome,
rejection counts, and provider metadata (`providerResponseID`, latency, token
counts). That is enough to answer "which prompt and model produced this odd
suggestion?" without the trip.

The provider never sees the install token. The client sends an opaque
`safetyIdentifier`; the server HMACs it with `PACKWISE_SAFETY_IDENTIFIER_SECRET`
and sends only the digest as `safety_identifier`. Same install → same value;
different secret → different value; the raw token never appears in the output.
A raw App Attest key ID is never sent either.

`store: false` is explicit on every request.

## Evaluation

`test/evals.test.ts` runs the shared trip fixtures through the real pipeline
against `FakeModelAdapter`, asserting `mustInfer`, `mustNotInfer`, and
`allowedSuggestions`. That green baseline is the point: swapping in the OpenAI
adapter lets the same assertions measure whether a prompt or model change
actually improved PackWise rather than just sounding smarter.

## Verification states

Precision matters more here than a green checkmark.

**Proven offline** — the automated suite covers all of this:
fake adapter, generated schemas and their staleness check, adapter request
construction (schema attached, `store: false`, safety identifier, capability
model routing, per-capability prompts), HMAC derivation, retry and jitter policy,
error semantics, challenge issue/expiry/replay, attestation chain, nonce, key ID,
app identity and environment checks, assertion signature and body binding,
counter regression, dev/appattest mode behaviour, both durable stores, and the
deterministic fallback when intelligence fails.

**Implemented, external verification pending** — written and unit-tested, but
never exercised against the real thing: OpenAI Structured Outputs request
compatibility, a real Redis backend, a real Apple attestation and assertion, and
Vercel's serverless packaging behaviour.

**Hard external verification** — needs credentials or hardware:
production Vercel deployment, a live GPT-5.6 smoke eval, physical-device App
Attest, and the outstanding physical-device WeatherKit pass from M2. The ordered
steps are in [docs/m3a2-verification-runbook.md](../docs/m3a2-verification-runbook.md);
M3B does not start until that pass is green.
