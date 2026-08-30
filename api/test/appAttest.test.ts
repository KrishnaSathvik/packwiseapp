import assert from "node:assert/strict";
import test from "node:test";

import { IntelligenceError } from "../src/errors.ts";
import { AppAttestIntegrityProvider, CHALLENGE_TTL_MS } from "../src/integrity/provider.ts";
import { InMemoryDurableStore } from "../src/store/memory.ts";
import { makeAttestFixture, makeRoot } from "./appAttestFixtures.ts";
import type { TestRoot } from "./appAttestFixtures.ts";

/**
 * The full server-side App Attest flow against a synthetic chain: real ECDSA
 * keys, real certificate verification, real nonce binding.
 *
 * Passing these means the protocol is implemented. It does not mean Apple has
 * accepted a real attestation — that remains a signed-device verification.
 */

type Clock = { value: number };

function setup(options: { environment?: "development" | "production"; root?: TestRoot } = {}) {
  const clock: Clock = { value: 1_700_000_000_000 };
  const root = options.root ?? makeRoot();
  const fixture = makeAttestFixture({ ...options, root });
  const store = new InMemoryDurableStore(() => clock.value);
  const provider = new AppAttestIntegrityProvider(
    store,
    {
      appID: fixture.appID,
      environment: options.environment ?? "production",
      rootCertificatePEM: fixture.rootPEM,
    },
    () => clock.value,
  );
  return { clock, fixture, store, provider, root };
}

async function reason(action: () => Promise<unknown>): Promise<string> {
  try {
    await action();
  } catch (error) {
    if (error instanceof IntelligenceError) return error.detail ?? error.code;
    throw error;
  }
  throw new Error("expected the call to be rejected");
}

test("a valid attestation registers the key", async () => {
  const { fixture, store, provider } = setup();
  await store.putChallenge(fixture.challenge, CHALLENGE_TTL_MS);

  await provider.register({
    keyID: fixture.keyID,
    attestation: fixture.attestation,
    challenge: fixture.challenge,
  });

  const record = await store.getKeyRecord(fixture.keyID);
  assert.ok(record);
  assert.equal(record.lastCounter, 0);
  assert.equal(record.environment, "production");
});

test("an attestation bound to a different challenge is rejected", async () => {
  const { fixture, store, provider, root } = setup();
  // Same root, so the chain is valid and the nonce is what fails.
  const other = makeAttestFixture({ challenge: "a-different-challenge", root });
  await store.putChallenge(fixture.challenge, CHALLENGE_TTL_MS);

  assert.equal(
    await reason(() =>
      provider.register({
        keyID: other.keyID,
        attestation: other.attestation,
        challenge: fixture.challenge,
      }),
    ),
    "challenge_mismatch",
  );
});

test("an expired challenge is rejected", async () => {
  const { clock, fixture, provider } = setup();
  const issued = await provider.issueChallenge();
  clock.value += CHALLENGE_TTL_MS + 1;

  assert.equal(
    await reason(() =>
      provider.register({
        keyID: fixture.keyID,
        attestation: fixture.attestation,
        challenge: issued.challenge,
      }),
    ),
    "challenge_invalid_or_used",
  );
});

test("a challenge cannot be replayed", async () => {
  const { fixture, store, provider } = setup();
  await store.putChallenge(fixture.challenge, CHALLENGE_TTL_MS);
  await provider.register({
    keyID: fixture.keyID,
    attestation: fixture.attestation,
    challenge: fixture.challenge,
  });

  assert.equal(
    await reason(() =>
      provider.register({
        keyID: fixture.keyID,
        attestation: fixture.attestation,
        challenge: fixture.challenge,
      }),
    ),
    "challenge_invalid_or_used",
  );
});

test("an attestation for another app is rejected", async () => {
  const root = makeRoot();
  const { store, provider } = setup({ root });
  const foreign = makeAttestFixture({ appID: "ZZZZZ99999.com.example.other", root });
  await store.putChallenge(foreign.challenge, CHALLENGE_TTL_MS);

  assert.equal(
    await reason(() =>
      provider.register({
        keyID: foreign.keyID,
        attestation: foreign.attestation,
        challenge: foreign.challenge,
      }),
    ),
    "app_id_mismatch",
  );
});

test("an attestation signed by an unrelated root is rejected", async () => {
  const { fixture, store, provider } = setup();
  const impostor = makeAttestFixture({ challenge: fixture.challenge });
  await store.putChallenge(fixture.challenge, CHALLENGE_TTL_MS);

  assert.equal(
    await reason(() =>
      provider.register({
        keyID: impostor.keyID,
        attestation: impostor.attestation,
        challenge: fixture.challenge,
      }),
    ),
    "certificate_chain_invalid",
  );
});

test("a claimed key ID that does not match the certificate is rejected", async () => {
  const { fixture, store, provider } = setup();
  await store.putChallenge(fixture.challenge, CHALLENGE_TTL_MS);

  assert.equal(
    await reason(() =>
      provider.register({
        keyID: Buffer.from("not-the-real-key-identifier-32b!!").toString("base64"),
        attestation: fixture.attestation,
        challenge: fixture.challenge,
      }),
    ),
    "key_id_mismatch",
  );
});

test("a development attestation is rejected by a production verifier", async () => {
  const root = makeRoot();
  const { store, provider } = setup({ root });
  const development = makeAttestFixture({ environment: "development", root });
  await store.putChallenge(development.challenge, CHALLENGE_TTL_MS);

  assert.equal(
    await reason(() =>
      provider.register({
        keyID: development.keyID,
        attestation: development.attestation,
        challenge: development.challenge,
      }),
    ),
    "environment_mismatch",
  );
});

async function registered() {
  const context = setup();
  await context.store.putChallenge(context.fixture.challenge, CHALLENGE_TTL_MS);
  await context.provider.register({
    keyID: context.fixture.keyID,
    attestation: context.fixture.attestation,
    challenge: context.fixture.challenge,
  });
  return context;
}

function request(fixture: ReturnType<typeof makeAttestFixture>, body: unknown, counter: number) {
  const assertion = fixture.assertion({ body, counter });
  return {
    requestID: "req-1",
    body,
    header: (name: string) =>
      ({ "x-packwise-key-id": fixture.keyID, "x-packwise-assertion": assertion })[name],
  };
}

test("a valid assertion authenticates the request", async () => {
  const { fixture, provider } = await registered();
  const identity = await provider.verify(request(fixture, { note: "hello" }, 1));
  assert.equal(identity.method, "appattest");
  assert.equal(identity.clientID, `attested:${fixture.keyID}`);
});

test("an assertion for a different body is rejected", async () => {
  const { fixture, provider } = await registered();
  const signed = request(fixture, { note: "hello" }, 1);

  assert.equal(
    await reason(() => provider.verify({ ...signed, body: { note: "tampered" } })),
    "assertion_signature_invalid",
  );
});

test("a tampered assertion is rejected", async () => {
  const { fixture, provider } = await registered();
  const signed = request(fixture, { note: "hello" }, 1);
  const original = signed.header("x-packwise-assertion")!;
  const corrupted = Buffer.from(original, "base64");
  corrupted[corrupted.length - 1] = (corrupted.at(-1) ?? 0) ^ 0xff;

  assert.equal(
    await reason(() =>
      provider.verify({
        ...signed,
        header: (name: string) =>
          ({
            "x-packwise-key-id": fixture.keyID,
            "x-packwise-assertion": corrupted.toString("base64"),
          })[name],
      }),
    ),
    "assertion_signature_invalid",
  );
});

test("a counter that does not increase is a replay", async () => {
  const { fixture, provider } = await registered();
  await provider.verify(request(fixture, { note: "first" }, 5));

  assert.equal(
    await reason(() => provider.verify(request(fixture, { note: "second" }, 5))),
    "counter_replay",
  );
  assert.equal(
    await reason(() => provider.verify(request(fixture, { note: "third" }, 3))),
    "counter_replay",
  );
  // A strictly increasing counter still works afterwards.
  await provider.verify(request(fixture, { note: "fourth" }, 6));
});

test("an unknown key is rejected", async () => {
  const { fixture, provider } = setup();
  assert.equal(
    await reason(() => provider.verify(request(fixture, { note: "hello" }, 1))),
    "unknown_key",
  );
});

test("a missing assertion is rejected", async () => {
  const { provider } = await registered();
  assert.equal(
    await reason(() =>
      provider.verify({ requestID: "req", body: {}, header: () => undefined }),
    ),
    "assertion_missing",
  );
});

test("issued challenges are single-use and time-bounded", async () => {
  const { clock, store, provider } = setup();
  const issued = await provider.issueChallenge();
  assert.equal(Date.parse(issued.expiresAt), clock.value + CHALLENGE_TTL_MS);
  assert.equal(await store.consumeChallenge(issued.challenge), true);
  assert.equal(await store.consumeChallenge(issued.challenge), false);
});
