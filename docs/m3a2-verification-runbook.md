# M3A-2 Verification Runbook

M3A-2 implementation is complete. What remains is proving it against the real
services. Everything below needs credentials or hardware; nothing below is
implementation work.

Run the steps in order. Each one removes a class of failure from the next, so
a problem found in step 4 is genuinely an App Attest problem rather than a
Redis or deployment problem wearing a disguise. `scripts/live-smoke.ts` prints
the evidence for step 1.

Do not start M3B until the six M3A items below are green. The live adapter can
now cross the most sensitive boundary in PackWise; that boundary should be proven
against real services before model output is allowed to enrich actual trip
context. Step 6 is M2-owned and shares the device session but does not gate M3A
or M3B — see the exit gate at the end.

---

## The App Attest environment rule

**Read this before anything else.** Sandbox and production App Attest keys are
not interchangeable, and a build distributed through TestFlight or the App Store
uses the **production** environment regardless of the entitlement value set
locally. Getting this wrong produces attestations the server rejects with
`environment_mismatch`, which looks like a code bug and is not one.

| Build | App Attest environment the server should expect |
| --- | --- |
| Local / dev-signed build | `development` — unless deliberately signed and configured for production |
| Local / dev build explicitly using the production entitlement | `production` |
| **TestFlight** | **`production`** |
| **App Store** | **`production`** |

Encode it explicitly per deployment:

```bash
# Local development API
PACKWISE_APP_ATTEST_ENVIRONMENT=development

# Production and TestFlight API
PACKWISE_APP_ATTEST_ENVIRONMENT=production
```

Never infer it from `NODE_ENV`, `VERCEL_ENV`, or anything else. The API enforces
this: an unset value is a boot failure, not a default. `PACKWISE_APP_ID` and
`PACKWISE_APP_ATTEST_ROOT_PEM` are required alongside it.

On the app side, `PACKWISE_REQUIRE_ATTESTATION` must be set for any build that
talks to a production API. When it is set and the device cannot attest, requests
are refused rather than sent unattested.

---

## 1. OpenAI live adapter

One real call per capability against `PACKWISE_MODEL_*`. Run it first: the
store stays on memory and integrity stays on development, so the provider is the
only new variable.

```bash
cp api/.env.example api/.env.local     # fill in the key and the HMAC secret
node --env-file=.env.local scripts/live-smoke.ts
node --env-file=.env.local scripts/live-smoke.ts --evals
```

```text
[ ] /v1/trip/interpret returns schema-valid output
[ ] /v1/packing/gaps returns schema-valid output
[ ] /v1/packing/optimize returns schema-valid output
[ ] Structured Outputs accepts the generated strict schemas unchanged
[ ] store:false is on every request
[ ] safety_identifier is the HMAC, stable across calls from one install
[ ] the capability env vars actually select the model
[ ] logs carry model, providerResponseID, latency, token counts
[ ] live eval smoke run over the nine fixtures
```

**Result, 2026-08-30 — green.** Structured Outputs accepted the generated
strict schemas unchanged. 18/18 on the nine fixtures: no `mustInfer` misses, no
`mustNotInfer` violations, no suggestions outside `allowedSuggestions`, zero
`unrenderable_reason` rejections. gpt-5.6, `interpret/1` / `gaps/1`, schema
`2026-08-29`, 1.2–4.3s per call, ~10.8k tokens for the suite.

Two findings came out of it. The reason-argument names were unconstrained, so a
model could return a code whose template could not render — now closed by the
schema and by `canRenderReason`. And `fineDining` / `niceDinner` were duplicate
activities mapping to the same item, which the eval failed on; they are merged.
Both are fixed and re-verified.

Still open, not blocking this step: gaps returned `[]` on all nine fixtures.
Valid — `allowedSuggestions` bounds what may be proposed, not what must be — but
investigate with realistic current packing lists before editing `gaps/1`. The
eval passes 3–4 items as the current list, which the model may read as
deliberate rather than incomplete.

If Structured Outputs rejects a generated schema, fix
`scripts/build_intelligence_schemas.py` and regenerate — never hand-edit
`api/generated/`, and never introduce a second schema for the model to read.

Expect the live eval to differ from the `FakeModelAdapter` baseline. That
difference is the measurement, not a failure: compare against the baseline
before changing any prompt.

## 2. Real Redis

Redis is not needed to prove the provider, so it comes second: keep the store
on memory for step 1 and change one thing at a time. It becomes mandatory before
M3A can be called externally verified, because production App Attest challenges
and counters and the rate limits all need state that survives an instance.

Point a local API at a real Redis instance (Upstash or Redis Cloud via the
Vercel Marketplace) and confirm the durable behaviours that `FakeRedisClient`
only simulates.

```bash
# 1. connectivity, and that a bad credential fails closed rather than
#    quietly using memory
node --env-file=.env.local scripts/serve.ts 3000
curl -s localhost:3000/health          # store.kind redis, reachable true
REDIS_URL=redis://127.0.0.1:6399 node --env-file=.env.local scripts/serve.ts 3002
curl -s localhost:3002/health          # 503, reachable false, still kind redis

# 2. TTL, consume-once, counter — then restart and prove the state survived a
#    process that no longer exists
node --env-file=.env.local scripts/redis-verify.ts write
node --env-file=.env.local scripts/redis-verify.ts read

# 3. two instances, one Redis: state created by A is enforced by B
node --env-file=.env.local scripts/serve.ts 3000
node --env-file=.env.local scripts/serve.ts 3001
node --env-file=.env.local scripts/two-instance-verify.ts
```

```text
[ ] challenge TTL expires the challenge
[ ] challenge consume-once holds
[ ] rate limits count and reset per capability
[ ] App Attest key record persists
[ ] assertion counter persists and only moves forward
[ ] restarting the API, or a second instance, does not lose any of it
```

That last line is the whole reason this step exists — it is the one thing the
in-memory store could never demonstrate.

**Result, 2026-08-30 — PASS.**

```text
Provider: Upstash (REST transport)
Environment: development
Generated buildHash: 1234eef772da96e4

Connection                    PASS
Bad config fails closed       PASS   503, kind stays redis, 0.75s
Challenge TTL                 PASS
Consume once                  PASS
Key survives restart          PASS
Counter survives restart      PASS
Counter regression blocked    PASS
Rate limit shared             PASS   A served 20, B returned 429
Second-instance state         PASS   register on B via A's challenge,
                                     counter enforced both directions
```

Two defects found, both invisible to the fake:

1. **An unreachable store hung instead of failing.** node-redis retries
   forever, so `/health` and every request stalled rather than erroring — on
   serverless that is a function timeout, not a failure. Fixed with a bounded
   reconnect strategy and a timeout on every operation.
2. **`DEL` returns 1 for an already-expired key on Upstash**, so
   `consumeChallenge` accepted expired challenges. `GET` returned null and
   `PTTL` returned -2 for the same key; only `DEL`'s count disagreed.
   `consumeChallenge` now uses atomic `GETDEL`, whose result reflects expiry.
   The fake modelled Redis's documented behaviour correctly — the real service
   differs, which is exactly why this step is not optional.

## 3. Vercel deployment

Root Directory is `api`. The build command is `npm run vercel-build`, which
checks `api/generated/` against its own manifest and typechecks — self-contained,
because the repo outside the project root may not be present at build time.
Drift between `shared/` and the artifact is caught by `npm run preflight`
locally and in CI, which does have the whole repo.

Production runs `PACKWISE_INTEGRITY_MODE=appattest` from the first deploy. A
production endpoint that rejects every unattested request is safer than one
temporarily accepting development trust, so do **not** relax it while waiting on
the device pass.

Run the deployed OpenAI smoke against a **Preview** deployment with development
integrity, keeping Production failing closed:

```bash
node scripts/live-smoke.ts --base-url=https://<preview>.vercel.app
```

```text
[ ] api/generated/ is packaged with the functions
[ ] nothing resolves ../shared at runtime
[ ] GET /health reports the expected configuration and no missing keys
[ ] production boots only with the full environment set
[ ] REDIS_URL points at the real instance
[ ] OPENAI_API_KEY is set and present only server-side
[ ] development trust is disabled — PACKWISE_INTEGRITY_MODE=appattest
[ ] appattest mode fails closed on an unattested request
[ ] all three intelligence routes answer
[ ] both integrity routes answer
[ ] buildHash in /health matches the locally verified artifact
[ ] an unauthenticated intelligence request is rejected, not served
[ ] state written by one invocation is read by another
```

**Preview result, 2026-08-30 — PASS.**

```text
Project: packwiseapp-api (root: api)
Deployment: preview
buildHash: 1234eef772da96e4   matches the locally verified artifact

Build (verify-artifact + typecheck)   PASS
/health                               PASS   200, missing []
Redis reachable from serverless       PASS   upstash-rest
Deployed interpret / gaps / optimize  PASS   200, gpt-5.6, interpret|gaps|optimize/1
Cross-invocation shared state         PASS   deployed writes read back from
                                             another process via Redis
```

Deployment Protection was disabled on this project so the API is reachable
without Vercel SSO — a mobile client cannot complete an SSO flow, and PackWise's
protection is App Attest, not URL secrecy. The consequence for Preview is that
it runs development integrity with only the anonymous rate limit in front of the
OpenAI key; Production must therefore be `appattest` from its first deploy.

Two deployment issues, both fixed:

1. `vercel link` run from the wrong directory placed `.vercel` in `api/api/`,
   making the functions folder the project root. Re-linked with `--cwd`.
2. Setting a `buildCommand` makes Vercel expect static output. A functions-only
   project has none, so it gets an empty `public/` and the build stays purely a
   verification gate.

**Production result, 2026-08-30 — PASS.**

```text
https://packwiseapp-api.vercel.app
buildHash: 1234eef772da96e4

/health                          200, missing []
integrity                        appattest, environment production
store                            redis / upstash-rest, reachable
PACKWISE_APP_ID present          yes
App Attest root present          yes

POST /v1/trip/interpret          401 assertion_missing
POST /v1/packing/gaps            401 assertion_missing
POST /v1/packing/optimize        401 assertion_missing
POST /v1/integrity/challenge     200, challenge issued
```

Those 401s are the passing result. Production will not spend the OpenAI key for
anyone who merely knows the URL, and it has been `appattest` since its first
deploy — never relaxed to development trust.

`PACKWISE_APP_ID` is `766WG2GGCA.com.packwiseapp.app`; the Team ID was read from
the provisioning profiles on the build machine, which all agree. The Apple App
Attestation Root CA came from Apple's certificate authority host, self-signed,
valid to 2045, SHA-256
`1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32`.

### Before the device pass

The bundle identifier is `com.packwiseapp.app`, registered with automatic
signing and the App Attest capability. A missing local provisioning profile
proves nothing on its own — Xcode creates one on the first device run once the
App ID and capability exist.

A development-signed build attests in Apple's **development** environment, and a
production verifier rejects those with `environment_mismatch`. That deployment
now exists and is separate from Production:

```text
https://packwiseapp-dev.vercel.app    appattest, environment development
https://packwiseapp-api.vercel.app    appattest, environment production
```

The dev endpoint is a stable alias, so the iOS build does not need re-pointing
every deploy. Do not change Production's environment to accommodate a
development build.

The iOS side is wired per configuration, so nothing is hardcoded in Swift:

```text
Debug     PACKWISE_API_BASE_URL=https://packwiseapp-dev.vercel.app
          PACKWISE_APPATTEST_ENV=development
Release   PACKWISE_API_BASE_URL=https://packwiseapp-api.vercel.app
          PACKWISE_APPATTEST_ENV=production
both      PACKWISE_REQUIRE_ATTESTATION=YES
```

The entitlements file is shared by both configurations — a single
`CODE_SIGN_ENTITLEMENTS` covers Debug and Release — so App Attest is never
enabled for only one of them. The environment inside it is a build-setting
substitution, which is what differs.

Two Xcode traps worth remembering:

1. `GENERATE_INFOPLIST_FILE` silently drops custom `INFOPLIST_KEY_*` settings.
   Only keys Xcode recognises are injected, so PackWise uses an explicit
   `Info.plist` with `$(BUILD_SETTING)` substitution.
2. Values reaching the Info.plist that way are **strings**, so `YES` arrives as
   text. Reading `PACKWISE_REQUIRE_ATTESTATION` as `Bool?` alone would leave
   every build silently unattested.

## 4. Physical iPhone App Attest

A signed build on a real device against the deployed API.

```text
[ ] DCAppAttestService.isSupported is true
[ ] key generation succeeds
[ ] challenge is issued
[ ] real Apple attestation verifies against the Apple root
[ ] registration stores the key
[ ] first signed assertion is accepted
[ ] second assertion advances the counter
[ ] a tampered body is rejected
[ ] a replayed assertion is rejected
```

The synthetic-chain tests already cover the last two logically. This step is
about Apple's real attestation format and root, which no fixture can stand in
for.

## 5. TestFlight production-environment pass

Worth doing separately from step 4 precisely because TestFlight forces the
production App Attest environment. A device pass that succeeded with a
development-signed build proves nothing about this.

```text
[ ] PACKWISE_APP_ATTEST_ENVIRONMENT=production on the API
[ ] PACKWISE_REQUIRE_ATTESTATION is set in the build
[ ] attestation and assertions succeed end to end
```

## 6. M2 WeatherKit device pass

Do this in the same device session — it has been outstanding since M2.

```text
[ ] live forecast for a real destination
[ ] Packing Impact reflects it
[ ] Apple Weather attribution is shown wherever weather appears
[ ] reopening the trip uses the cache rather than refetching
[ ] a weather change produces a proposal
[ ] applying it preserves overrides, custom items, manual quantities, and packed state
```

---

## Evidence

Record evidence for each step, not just a tick. A checkbox is someone's memory;
evidence makes the "M3A closed" decision objective months later, and makes a
regression attributable.

| Step | Evidence to retain |
| --- | --- |
| OpenAI | request ID, model returned, prompt and schema versions, latency and token metadata, eval result |
| Redis | restart / two-instance persistence output, plus the TTL and consume-once results |
| Vercel | deployment URL and environment, commit SHA and `manifest.buildHash`, `/health` output |
| Device App Attest | environment, registration success, assertion #1 and #2, replay and tamper rejections |
| TestFlight | production-environment App Attest verification from the TestFlight build |
| WeatherKit | live forecast, attribution, cache reopen, weather-change reconciliation result |

**Never** put secrets in the evidence: no API keys, no `PACKWISE_SAFETY_IDENTIFIER_SECRET`,
no raw install tokens or derived identifiers, no attestation private material, no
full trip notes. Record the shape of what happened, the same rule the request
logs already follow.

---

## M3A exit gate

M3A closes only when all six of its own items are verified:

```text
[x] Live OpenAI Structured Outputs verified   2026-08-30
[x] Live eval smoke reviewed                 2026-08-30, 18/18 green
[x] Real Redis verified                      2026-08-30
[x] Production Vercel deployment verified    2026-08-30
[ ] Physical-device App Attest verified
[ ] TestFlight production App Attest verified
```

The M2 WeatherKit device pass is **not** on that list. It belongs to M2, and
conflating the two would misattribute ownership. Run it in the same device
session — the runbook keeps it in step 6 for exactly that reason — but track it
separately, so if it is the only unchecked item the project can accurately say:

> M3A verified. M2 device verification still pending.

```text
[ ] M2 WeatherKit physical-device pass verified   (M2-owned)
```

---

## When the pass is green

```text
M3A-2 implementation ✅
        ↓
external verification ✅
        ↓
M3A closed
        ↓
M3B trip-context enrichment
```

M3B should be small: the dangerous plumbing — validation, canonical rejection,
the resolver boundary, integrity, rate limits, fallback — is already built and
proven. M3B wires interpretation into `TripContext`; M3C wires gap candidates
into suggestions.

If any step fails, fix it inside M3A rather than carrying it forward. That is
what "do not start M3B yet" is protecting.
