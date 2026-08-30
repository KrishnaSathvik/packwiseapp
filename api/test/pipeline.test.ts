import assert from "node:assert/strict";
import test from "node:test";

import { interpretCapability } from "../src/capabilities/interpret.ts";
import { loadConfig } from "../src/config.ts";
import { AppAttestIntegrityProvider, DevelopmentAppIntegrityProvider } from "../src/integrity/provider.ts";
import { deriveSafetyIdentifier } from "../src/safetyIdentifier.ts";
import { makeAttestFixture } from "./appAttestFixtures.ts";
import { createHandler } from "../src/pipeline.ts";
import { InMemoryDurableStore } from "../src/store/memory.ts";
import { SAFETY_IDENTIFIER, capture, post, tripContext } from "./helpers.ts";

function handler(overrides: Parameters<typeof createHandler>[1] = {}) {
  return createHandler(interpretCapability, {
    store: new InMemoryDurableStore(),
    integrity: new DevelopmentAppIntegrityProvider(),
    ...overrides,
  });
}

const validBody = {
  note: "Five days in Chicago, walking the city and hitting a few museums.",
  context: tripContext(),
  safetyIdentifier: SAFETY_IDENTIFIER,
};

test("rejects anything but POST", async () => {
  const { response, captured } = capture();
  await handler()({ method: "GET", headers: {} }, response);
  assert.equal(captured.status, 405);
  assert.equal((captured.body as { error: string }).error, "method_not_allowed");
});

test("rejects a request that fails schema validation", async () => {
  const { response, captured } = capture();
  await handler()(post({ context: tripContext(), safetyIdentifier: SAFETY_IDENTIFIER }), response);
  assert.equal(captured.status, 400);
  assert.equal((captured.body as { error: string }).error, "invalid_request");
});

test("rejects an activity outside the shared vocabulary", async () => {
  const { response, captured } = capture();
  await handler()(
    post({ ...validBody, context: tripContext({ activities: ["scubaDiving"] }) }),
    response,
  );
  assert.equal(captured.status, 400);
});

test("rejects a safetyIdentifier that is not an opaque token", async () => {
  const { response, captured } = capture();
  await handler()(post({ ...validBody, safetyIdentifier: "person@example.com" }), response);
  assert.equal(captured.status, 400);
  assert.equal((captured.body as { error: string }).error, "invalid_safety_identifier");
});

test("echoes a request ID on success and on failure", async () => {
  const ok = capture();
  await handler()(post(validBody, { "x-request-id": "req-123" }), ok.response);
  assert.equal(ok.captured.status, 200);
  assert.equal(ok.captured.headers["X-Request-ID"], "req-123");
  assert.equal((ok.captured.body as { meta: { requestID: string } }).meta.requestID, "req-123");

  const failed = capture();
  await handler()({ method: "GET", headers: { "x-request-id": "req-456" } }, failed.response);
  assert.equal((failed.captured.body as { requestID: string }).requestID, "req-456");
});

test("stamps prompt, schema, and model version on every response", async () => {
  const { response, captured } = capture();
  await handler()(post(validBody), response);
  const { meta } = captured.body as {
    meta: { promptVersion: string; schemaVersion: string; model: string; generatedAt: string };
  };
  assert.equal(meta.promptVersion, "interpret/1");
  assert.ok(meta.schemaVersion.length > 0);
  assert.equal(meta.model, "fake");
  assert.ok(Date.parse(meta.generatedAt) > 0);
});

test("rate limits per capability and reports Retry-After", async () => {
  const limited = handler({ store: new InMemoryDurableStore() });
  let last = capture();
  for (let attempt = 0; attempt < 21; attempt += 1) {
    last = capture();
    await limited(post(validBody), last.response);
  }
  assert.equal(last.captured.status, 429);
  assert.equal((last.captured.body as { error: string }).error, "rate_limited");
  assert.ok(Number(last.captured.headers["Retry-After"]) > 0);
});

test("an App Attest deployment refuses a request with no assertion", async () => {
  const { response, captured } = capture();
  const store = new InMemoryDurableStore();
  const fixture = makeAttestFixture();
  await handler({
    store,
    integrity: new AppAttestIntegrityProvider(store, {
      appID: fixture.appID,
      environment: "production",
      rootCertificatePEM: fixture.rootPEM,
    }),
  })(post(validBody), response);

  assert.equal(captured.status, 401);
  assert.equal((captured.body as { error: string }).error, "unauthorized");
});

test("the provider sees an HMAC, never the install token the client sent", async () => {
  const seen: string[] = [];
  const { response, captured } = capture();
  await handler({
    config: { ...loadConfig({}), safetyIdentifierSecret: "server-secret" },
    adapter: {
      name: "recording",
      async produce(request) {
        seen.push(request.safetyIdentifier);
        return { output: { inferredActivities: [], inferredChips: [], noteSummary: null } };
      },
    },
  })(post(validBody), response);

  assert.equal(captured.status, 200);
  assert.equal(seen.length, 1);
  assert.notEqual(seen[0], SAFETY_IDENTIFIER);
  assert.equal(seen[0], deriveSafetyIdentifier(SAFETY_IDENTIFIER, "server-secret"));
});

test("a model failure surfaces as unavailable, not a malformed 200", async () => {
  const { response, captured } = capture();
  await handler({
    adapter: {
      name: "broken",
      async produce() {
        throw new Error("connection reset");
      },
    },
  })(post(validBody), response);
  assert.equal(captured.status, 503);
  assert.equal((captured.body as { error: string }).error, "model_unavailable");
});

test("model output that breaks its schema is rejected", async () => {
  const { response, captured } = capture();
  await handler({
    adapter: {
      name: "loose",
      async produce() {
        return { output: { inferredActivities: "walking", inferredChips: [], noteSummary: null } };
      },
    },
  })(post(validBody), response);
  assert.equal(captured.status, 502);
  assert.equal((captured.body as { error: string }).error, "invalid_model_output");
});
