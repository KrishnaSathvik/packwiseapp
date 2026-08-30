import assert from "node:assert/strict";
import test from "node:test";

import { ConfigError, loadConfig, missingRequirements } from "../src/config.ts";
import { deriveSafetyIdentifier } from "../src/safetyIdentifier.ts";
import { createAdapter, createStore } from "../src/runtime.ts";
import { InMemoryDurableStore } from "../src/store/memory.ts";
import { RedisDurableStore } from "../src/store/redis.ts";
import { FakeRedisClient } from "../src/store/redisClient.ts";
import type { DurableStore } from "../src/store/durableStore.ts";

const PRODUCTION_ENV = {
  PACKWISE_ENV: "production",
  OPENAI_API_KEY: "sk-live",
  PACKWISE_MODEL_CONTEXT: "gpt-5.6",
  PACKWISE_MODEL_GAPS: "gpt-5.6",
  PACKWISE_MODEL_OPTIMIZE: "gpt-5.6",
  PACKWISE_SAFETY_IDENTIFIER_SECRET: "server-secret",
  REDIS_URL: "redis://localhost:6379",
  PACKWISE_INTEGRITY_MODE: "appattest",
  PACKWISE_APP_ID: "ABCDE12345.com.packwise.app",
  PACKWISE_APP_ATTEST_ENVIRONMENT: "production",
  PACKWISE_APP_ATTEST_ROOT_PEM: "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----",
} satisfies NodeJS.ProcessEnv;

// ------------------------------------------------------------------- config

test("a fully configured production environment loads", () => {
  const config = loadConfig(PRODUCTION_ENV);
  assert.equal(config.mode, "production");
  assert.equal(config.integrityMode, "appattest");
  assert.equal(config.storeMode, "redis");
  assert.deepEqual(missingRequirements(config), []);
});

test("production refuses to boot with anything critical missing", () => {
  for (const key of Object.keys(PRODUCTION_ENV).filter((name) => name !== "PACKWISE_ENV")) {
    const env = { ...PRODUCTION_ENV } as Record<string, string>;
    delete env[key];
    assert.throws(() => loadConfig(env), ConfigError, `${key} should be required`);
  }
});

test("production never silently accepts development integrity", () => {
  assert.throws(
    () => loadConfig({ ...PRODUCTION_ENV, PACKWISE_INTEGRITY_MODE: "development" }),
    (error: unknown) =>
      error instanceof ConfigError && error.missing.includes("PACKWISE_INTEGRITY_MODE=appattest"),
  );
});

test("development runs with nothing configured", () => {
  const config = loadConfig({});
  assert.equal(config.mode, "development");
  assert.equal(config.integrityMode, "development");
  assert.equal(config.storeMode, "memory");
});

test("App Attest without its identity, environment, or root is refused in any mode", () => {
  assert.throws(
    () => loadConfig({ PACKWISE_INTEGRITY_MODE: "appattest" }),
    (error: unknown) =>
      error instanceof ConfigError &&
      error.missing.includes("PACKWISE_APP_ID") &&
      error.missing.includes("PACKWISE_APP_ATTEST_ENVIRONMENT") &&
      error.missing.includes("PACKWISE_APP_ATTEST_ROOT_PEM"),
  );
});

test("the App Attest environment is never inferred or defaulted", () => {
  // Sandbox and production keys are not interchangeable, and TestFlight always
  // uses production regardless of the local entitlement. An unset value must be
  // an error, not a guess.
  const env = { ...PRODUCTION_ENV } as Record<string, string>;
  delete env.PACKWISE_APP_ATTEST_ENVIRONMENT;
  assert.throws(
    () => loadConfig(env),
    (error: unknown) =>
      error instanceof ConfigError && error.missing.includes("PACKWISE_APP_ATTEST_ENVIRONMENT"),
  );

  // Nothing else in the environment can stand in for it.
  for (const noise of [{ NODE_ENV: "production" }, { VERCEL_ENV: "production" }]) {
    assert.throws(() => loadConfig({ ...env, ...noise }), ConfigError);
  }

  assert.equal(loadConfig({}).appAttestEnvironment, undefined);
  assert.equal(
    loadConfig({ ...PRODUCTION_ENV, PACKWISE_APP_ATTEST_ENVIRONMENT: "development" })
      .appAttestEnvironment,
    "development",
  );
});

test("a live OpenAI key without the HMAC secret is refused", () => {
  // Otherwise the raw install token would be sent as safety_identifier.
  assert.throws(
    () => loadConfig({ OPENAI_API_KEY: "sk-live" }),
    (error: unknown) =>
      error instanceof ConfigError &&
      error.missing.includes("PACKWISE_SAFETY_IDENTIFIER_SECRET"),
  );

  const config = loadConfig({
    OPENAI_API_KEY: "sk-live",
    PACKWISE_SAFETY_IDENTIFIER_SECRET: "local-secret",
  });
  assert.equal(config.mode, "development");
  assert.equal(createAdapter(config).name, "openai-responses");
});

test("production never falls back to the memory store or the fake adapter", () => {
  const config = { ...loadConfig(PRODUCTION_ENV), storeMode: "memory" as const };
  assert.throws(() => createStore(config), /durable store/);

  const withoutKey = { ...loadConfig(PRODUCTION_ENV) };
  delete withoutKey.openAIKey;
  assert.throws(() => createAdapter(withoutKey), /OPENAI_API_KEY/);
});

test("development selects the fake adapter and the memory store", () => {
  const config = loadConfig({});
  assert.equal(createStore(config).kind, "memory");
  assert.equal(createAdapter(config).name, "fake");
});

// --------------------------------------------------------- safety identifier

test("the same install always derives the same identifier", () => {
  const first = deriveSafetyIdentifier("install-token-1", "secret");
  assert.equal(deriveSafetyIdentifier("install-token-1", "secret"), first);
});

test("different installs and different secrets derive different identifiers", () => {
  const base = deriveSafetyIdentifier("install-token-1", "secret");
  assert.notEqual(deriveSafetyIdentifier("install-token-2", "secret"), base);
  assert.notEqual(deriveSafetyIdentifier("install-token-1", "other-secret"), base);
});

test("the raw install token never appears in the derived identifier", () => {
  const token = "install-token-that-should-not-leak";
  const derived = deriveSafetyIdentifier(token, "secret");
  assert.ok(!derived.includes(token));
  assert.match(derived, /^[A-Za-z0-9_-]+$/);
  assert.ok(derived.length >= 8 && derived.length <= 128);
});

test("an empty secret is refused rather than producing a weak identifier", () => {
  assert.throws(() => deriveSafetyIdentifier("install", ""));
});

// ------------------------------------------------------------- durable store

function stores(): { name: string; make: (now: () => number) => DurableStore }[] {
  return [
    { name: "memory", make: (now) => new InMemoryDurableStore(now) },
    { name: "redis", make: (now) => new RedisDurableStore(new FakeRedisClient(now), now) },
  ];
}

for (const { name, make } of stores()) {
  test(`${name}: rate-limit windows count and expire`, async () => {
    let time = 1_000;
    const store = make(() => time);

    const first = await store.incrementWindow("gaps:client", 60_000);
    assert.equal(first.count, 1);
    assert.equal((await store.incrementWindow("gaps:client", 60_000)).count, 2);
    // A different key is a different budget.
    assert.equal((await store.incrementWindow("gaps:other", 60_000)).count, 1);

    time += 60_001;
    assert.equal((await store.incrementWindow("gaps:client", 60_000)).count, 1);
  });

  test(`${name}: challenges are consume-once and time-bounded`, async () => {
    let time = 1_000;
    const store = make(() => time);

    await store.putChallenge("challenge-a", 5_000);
    assert.equal(await store.consumeChallenge("challenge-a"), true);
    assert.equal(await store.consumeChallenge("challenge-a"), false);

    await store.putChallenge("challenge-b", 5_000);
    time += 5_001;
    assert.equal(await store.consumeChallenge("challenge-b"), false);

    assert.equal(await store.consumeChallenge("never-issued"), false);
  });

  test(`${name}: assertion counters only move forward`, async () => {
    let time = 1_000;
    const store = make(() => time);
    await store.putKeyRecord({
      keyID: "key-1",
      publicKey: "spki",
      environment: "production",
      lastCounter: 0,
      createdAt: time,
      lastSeenAt: time,
    });

    assert.equal(await store.advanceCounter("key-1", 1, time), true);
    assert.equal(await store.advanceCounter("key-1", 1, time), false);
    assert.equal(await store.advanceCounter("key-1", 0, time), false);
    assert.equal(await store.advanceCounter("key-1", 7, time), true);
    assert.equal(await store.advanceCounter("unknown-key", 1, time), false);

    const record = await store.getKeyRecord("key-1");
    assert.equal(record?.lastCounter, 7);
  });
}
