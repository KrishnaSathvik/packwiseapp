import assert from "node:assert/strict";
import test from "node:test";

import { IntelligenceError } from "../src/errors.ts";
import { ProviderError, providerErrorForStatus } from "../src/model/errors.ts";
import { BASE_BACKOFF_MS, MAX_BACKOFF_MS, backoffDelay, runModel } from "../src/model/run.ts";
import type { Clock } from "../src/model/run.ts";
import type { ModelAdapter, ModelRequest } from "../src/model/adapter.ts";

/**
 * The retry policy is conservative on purpose: PackWise already survives a
 * failed intelligence call, so nobody should wait through a retry chain.
 */

function testClock(): Clock & { slept: number[]; time: number } {
  const clock = {
    time: 0,
    slept: [] as number[],
    now() {
      return clock.time;
    },
    async sleep(ms: number) {
      clock.slept.push(ms);
      clock.time += ms;
    },
    random() {
      return 0.5;
    },
  };
  return clock;
}

function failingAdapter(errors: (Error | undefined)[]): ModelAdapter & { calls: number } {
  let index = 0;
  return {
    name: "scripted",
    calls: 0,
    async produce(_request: ModelRequest) {
      this.calls += 1;
      const error = errors[index];
      index += 1;
      if (error) throw error;
      return { output: { ok: true } };
    },
  };
}

async function run(adapter: ModelAdapter, clock: Clock) {
  return runModel({
    adapter,
    capability: "gaps",
    input: {},
    safetyIdentifier: "opaque-identifier",
    requestID: "req-1",
    clock,
  });
}

test("status codes classify into the kinds the policy acts on", () => {
  assert.equal(providerErrorForStatus(429).kind, "rate_limited");
  assert.equal(providerErrorForStatus(401).kind, "auth");
  assert.equal(providerErrorForStatus(403).kind, "auth");
  assert.equal(providerErrorForStatus(500).kind, "server");
  assert.equal(providerErrorForStatus(503).kind, "server");
  assert.equal(providerErrorForStatus(400).kind, "client");
  assert.equal(providerErrorForStatus(422).kind, "client");
});

test("only transient kinds are retryable", () => {
  for (const kind of ["network", "timeout", "rate_limited", "server"] as const) {
    assert.equal(new ProviderError(kind).isRetryable, true, kind);
  }
  for (const kind of ["client", "auth", "malformed"] as const) {
    assert.equal(new ProviderError(kind).isRetryable, false, kind);
  }
});

test("a transient failure is retried once and then succeeds", async () => {
  const clock = testClock();
  const adapter = failingAdapter([new ProviderError("network")]);
  const result = await run(adapter, clock);

  assert.deepEqual(result.output, { ok: true });
  assert.equal(adapter.calls, 2);
  assert.equal(clock.slept.length, 1);
});

test("a 400-class failure is never retried", async () => {
  const clock = testClock();
  const adapter = failingAdapter([providerErrorForStatus(400)]);

  await assert.rejects(() => run(adapter, clock), IntelligenceError);
  assert.equal(adapter.calls, 1);
  assert.deepEqual(clock.slept, []);
});

test("an auth failure is never retried", async () => {
  const clock = testClock();
  const adapter = failingAdapter([providerErrorForStatus(401)]);

  await assert.rejects(() => run(adapter, clock), IntelligenceError);
  assert.equal(adapter.calls, 1);
});

test("a malformed provider response is not retried in a loop", async () => {
  const clock = testClock();
  const adapter = failingAdapter([new ProviderError("malformed")]);

  await assert.rejects(
    () => run(adapter, clock),
    (error: unknown) =>
      error instanceof IntelligenceError && error.code === "invalid_model_output",
  );
  assert.equal(adapter.calls, 1);
});

test("retries are bounded, not endless", async () => {
  const clock = testClock();
  const adapter = failingAdapter([
    new ProviderError("server"),
    new ProviderError("server"),
    new ProviderError("server"),
  ]);

  await assert.rejects(
    () => run(adapter, clock),
    (error: unknown) => error instanceof IntelligenceError && error.code === "model_unavailable",
  );
  assert.equal(adapter.calls, 2);
});

test("jitter keeps the delay inside the capped exponential window", () => {
  assert.equal(backoffDelay(0, 0), 0);
  assert.equal(backoffDelay(0, 0.999), Math.floor(0.999 * BASE_BACKOFF_MS));
  assert.ok(backoffDelay(1, 0.999) <= BASE_BACKOFF_MS * 2);
  assert.ok(backoffDelay(10, 0.999) <= MAX_BACKOFF_MS);
  for (let attempt = 0; attempt < 6; attempt += 1) {
    for (const random of [0, 0.25, 0.5, 0.99]) {
      const delay = backoffDelay(attempt, random);
      assert.ok(delay >= 0 && delay <= MAX_BACKOFF_MS);
    }
  }
});

test("Retry-After from the provider wins over computed backoff", async () => {
  const clock = testClock();
  const adapter = failingAdapter([
    new ProviderError("rate_limited", { status: 429, retryAfterSeconds: 1 }),
  ]);
  await run(adapter, clock);
  assert.deepEqual(clock.slept, [1000]);
});

test("an errors-from-the-API decision is never retried", async () => {
  const clock = testClock();
  const adapter = failingAdapter([new IntelligenceError("rate_limited")]);

  await assert.rejects(
    () => run(adapter, clock),
    (error: unknown) => error instanceof IntelligenceError && error.code === "rate_limited",
  );
  assert.equal(adapter.calls, 1);
});

test("latency is measured for every attempt that succeeds", async () => {
  const clock = testClock();
  const adapter: ModelAdapter = {
    name: "slow",
    async produce() {
      clock.time += 120;
      return { output: {} };
    },
  };
  const result = await run(adapter, clock);
  assert.equal(result.latencyMs, 120);
});
