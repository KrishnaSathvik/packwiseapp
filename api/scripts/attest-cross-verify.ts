import { spawn } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { makeAttestFixture, makeRoot } from "../test/appAttestFixtures.ts";
import { tripContext, SAFETY_IDENTIFIER } from "../test/helpers.ts";

/**
 * Step 2, case 5 of docs/m3a2-verification-runbook.md, the strongest one:
 * an App Attest key registered through one instance must be enforced — counter
 * and all — by a different instance that never saw the registration.
 *
 *   node --env-file=.env.local scripts/attest-cross-verify.ts
 *
 * Spawns both servers itself against the configured Redis, using a synthetic
 * root so App Attest can run locally. Real Apple attestation is still a
 * signed-device verification.
 */

// The servers must trust the root before they start, but the attestation can
// only be minted once a server has issued a challenge — so the root is created
// first and the fixture is bound to the real challenge later.
const root = makeRoot();
const seed = makeAttestFixture({ root, environment: "development" });
const dir = mkdtempSync(join(tmpdir(), "packwise-attest-"));
writeFileSync(join(dir, "root.pem"), seed.rootPEM);

const env = {
  ...process.env,
  PACKWISE_INTEGRITY_MODE: "appattest",
  PACKWISE_APP_ID: seed.appID,
  PACKWISE_APP_ATTEST_ENVIRONMENT: "development",
  PACKWISE_APP_ATTEST_ROOT_PEM: seed.rootPEM,
  // The store is what is under test; no reason to spend live model calls.
  OPENAI_API_KEY: "",
};

const servers = [3000, 3001].map((port) =>
  spawn(process.execPath, ["--env-file=.env.local", "scripts/serve.ts", String(port)], {
    env,
    stdio: "ignore",
  }),
);

const A = "http://127.0.0.1:3000";
const B = "http://127.0.0.1:3001";

const results: { name: string; pass: boolean; detail?: string }[] = [];

function check(name: string, pass: boolean, detail?: string): void {
  results.push({ name, pass, ...(detail ? { detail } : {}) });
  console.log(`  ${pass ? "PASS" : "FAIL"}  ${name}${detail ? `  — ${detail}` : ""}`);
}

async function ready(base: string): Promise<boolean> {
  for (let attempt = 0; attempt < 30; attempt += 1) {
    try {
      const response = await fetch(`${base}/health`);
      const body = (await response.json()) as { store?: { reachable: boolean } };
      if (body.store?.reachable === true) return true;
    } catch {
      // still starting
    }
    await new Promise((resolve) => setTimeout(resolve, 300));
  }
  return false;
}

async function post(base: string, path: string, body: unknown, headers: Record<string, string> = {}) {
  const response = await fetch(`${base}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  return {
    status: response.status,
    body: text.length > 0 ? (JSON.parse(text) as Record<string, unknown>) : {},
  };
}

type Fixture = ReturnType<typeof makeAttestFixture>;
let fixture: Fixture = seed;

/** The client signs the exact bytes it sends, so the body must round-trip identically. */
function signed(body: unknown, counter: number): Record<string, string> {
  return {
    "X-PackWise-Key-ID": fixture.keyID,
    "X-PackWise-Assertion": fixture.assertion({ body, counter }),
  };
}

try {
  console.log("App Attest across instances — one Redis, two processes\n");

  if (!(await ready(A)) || !(await ready(B))) {
    check("Both instances healthy", false, "servers did not become ready");
    throw new Error("servers unavailable");
  }
  check("Both instances healthy", true);

  // A issues the challenge; the attestation is minted against it and presented
  // to B, which never saw the exchange.
  const issued = await post(A, "/v1/integrity/challenge", {});
  const challenge = (issued.body as { challenge: string }).challenge;
  fixture = makeAttestFixture({ root, challenge, environment: "development" });

  const registration = await post(B, "/v1/integrity/attest", {
    keyID: fixture.keyID,
    attestation: fixture.attestation,
    challenge,
  });
  check(
    "Register on B with a challenge issued by A",
    registration.status === 204,
    registration.status === 204 ? "accepted" : String(registration.body.message ?? registration.status),
  );

  const request = {
    note: "Five days in Chicago, walking the city and hitting a few museums.",
    context: tripContext(),
    safetyIdentifier: SAFETY_IDENTIFIER,
  };

  const first = await post(A, "/v1/trip/interpret", request, signed(request, 1));
  check("Assertion accepted by A", first.status === 200, String(first.body.message ?? first.status));

  // The counter advanced on A. B must already know.
  const replayOnB = await post(B, "/v1/trip/interpret", request, signed(request, 1));
  check(
    "B rejects the counter A already consumed",
    replayOnB.status === 401 && replayOnB.body.message === "counter_replay",
    String(replayOnB.body.message ?? replayOnB.status),
  );

  const forwardOnB = await post(B, "/v1/trip/interpret", request, signed(request, 2));
  check("B accepts the next counter", forwardOnB.status === 200, String(forwardOnB.body.message ?? forwardOnB.status));

  const replayOnA = await post(A, "/v1/trip/interpret", request, signed(request, 2));
  check(
    "A rejects the counter B just consumed",
    replayOnA.status === 401 && replayOnA.body.message === "counter_replay",
    String(replayOnA.body.message ?? replayOnA.status),
  );

  // A valid assertion for a different body must not authenticate this one.
  const tampered = await post(A, "/v1/trip/interpret", { ...request, note: "different note" }, signed(request, 3));
  check(
    "An assertion cannot be lifted onto another request",
    tampered.status === 401,
    String(tampered.body.message ?? tampered.status),
  );
} finally {
  for (const server of servers) server.kill();
}

const failed = results.filter((row) => !row.pass);
console.log(`\n${failed.length === 0 ? "PASS" : "FAIL"} — ${results.length - failed.length}/${results.length}`);
process.exit(failed.length === 0 ? 0 : 1);
