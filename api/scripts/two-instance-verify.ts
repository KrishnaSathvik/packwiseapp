/**
 * Step 2, cases 5 and 6 of docs/m3a2-verification-runbook.md: prove that two
 * processes sharing one Redis enforce each other's state. This is the property
 * serverless depends on, and the one the in-memory store can never demonstrate.
 *
 * Start two servers against the same REDIS_URL, then run this:
 *
 *   node --env-file=.env.local scripts/serve.ts 3000
 *   node --env-file=.env.local scripts/serve.ts 3001
 *   node --env-file=.env.local scripts/two-instance-verify.ts
 *
 * Prints PASS/FAIL only — no URLs, credentials, or identifiers.
 */

import { CAPABILITY_CONFIG } from "../src/versions.ts";
import { SAFETY_IDENTIFIER, tripContext } from "../test/helpers.ts";

const A = process.env.PACKWISE_INSTANCE_A ?? "http://127.0.0.1:3000";
const B = process.env.PACKWISE_INSTANCE_B ?? "http://127.0.0.1:3001";

const results: { name: string; pass: boolean; detail?: string }[] = [];

function check(name: string, pass: boolean, detail?: string): void {
  results.push({ name, pass, ...(detail ? { detail } : {}) });
  console.log(`  ${pass ? "PASS" : "FAIL"}  ${name}${detail ? `  — ${detail}` : ""}`);
}

async function post(base: string, path: string, body: unknown): Promise<Response> {
  return fetch(`${base}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

const interpretBody = {
  note: "Five days in Chicago, walking the city and hitting a few museums.",
  context: tripContext(),
  safetyIdentifier: SAFETY_IDENTIFIER,
};

console.log("Two-instance shared-state verification\n");

// Both instances must be up and healthy before anything is proved.
for (const [label, base] of [
  ["A", A],
  ["B", B],
] as const) {
  try {
    const response = await fetch(`${base}/health`);
    const body = (await response.json()) as { store?: { kind: string; reachable: boolean } };
    check(
      `Instance ${label} healthy`,
      response.status === 200 && body.store?.kind === "redis" && body.store.reachable === true,
      `store ${body.store?.kind ?? "?"}`,
    );
  } catch {
    check(`Instance ${label} healthy`, false, "not reachable");
  }
}

if (results.some((row) => !row.pass)) {
  console.log("\nStart both servers first.");
  process.exit(1);
}

// 5. A challenge issued by one instance is consumable by the other. Skipped
// unless App Attest is on, since the routes only exist in that mode.
const challengeResponse = await post(A, "/v1/integrity/challenge", {});
if (challengeResponse.status === 200) {
  const { challenge } = (await challengeResponse.json()) as { challenge: string };
  const attest = await post(B, "/v1/integrity/attest", {
    keyID: "not-a-real-key",
    attestation: "not-a-real-attestation",
    challenge,
  });
  // B must reject on the attestation, not on the challenge: reaching the crypto
  // is what proves it saw A's challenge.
  const body = (await attest.json()) as { message?: string };
  const sawChallenge = attest.status === 401 && !(body.message ?? "").includes("challenge_invalid_or_used");
  check("Challenge crosses instances", sawChallenge, body.message ?? "");

  const replay = await post(B, "/v1/integrity/attest", {
    keyID: "not-a-real-key",
    attestation: "not-a-real-attestation",
    challenge,
  });
  const replayBody = (await replay.json()) as { message?: string };
  check(
    "Consumed challenge is dead on both",
    (replayBody.message ?? "").includes("challenge_invalid_or_used"),
    replayBody.message ?? "",
  );
} else {
  console.log("  SKIP  App Attest routes are off (PACKWISE_INTEGRITY_MODE=development)");
}

// 6. The rate limit is one shared budget, not one per process. Under App Attest
// the intelligence routes demand an assertion first, so this case is only
// meaningful in development mode; scripts/attest-cross-verify.ts covers the
// attested path.
if (challengeResponse.status === 200) {
  console.log("  SKIP  rate limit — App Attest is on; run in development mode");
  const failedEarly = results.filter((row) => !row.pass);
  console.log(`\n${failedEarly.length === 0 ? "PASS" : "FAIL"} — ${results.length - failedEarly.length}/${results.length}`);
  process.exit(failedEarly.length === 0 ? 0 : 1);
}

const limit = CAPABILITY_CONFIG.interpret.rateLimit.requests;
let statusesA: number[] = [];
for (let index = 0; index < limit; index += 1) {
  statusesA.push((await post(A, "/v1/trip/interpret", interpretBody)).status);
}
const exhausted = statusesA.every((status) => status === 200);

const nextOnA = await post(A, "/v1/trip/interpret", interpretBody);
const nextOnB = await post(B, "/v1/trip/interpret", interpretBody);

check(`Instance A served ${limit} then limited`, exhausted && nextOnA.status === 429, `then ${nextOnA.status}`);
check(
  "Instance B honours A's rate limit",
  nextOnB.status === 429,
  nextOnB.status === 429 ? "shared budget" : `B returned ${nextOnB.status} — limiter is not shared`,
);

const failed = results.filter((row) => !row.pass);
console.log(`\n${failed.length === 0 ? "PASS" : "FAIL"} — ${results.length - failed.length}/${results.length}`);
process.exit(failed.length === 0 ? 0 : 1);
