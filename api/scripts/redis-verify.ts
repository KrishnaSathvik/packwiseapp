import { loadConfig } from "../src/config.ts";
import { CHALLENGE_TTL_MS } from "../src/integrity/provider.ts";
import { createStore } from "../src/runtime.ts";
import type { DurableStore } from "../src/store/durableStore.ts";

/**
 * Step 2 of docs/m3a2-verification-runbook.md: prove against a real Redis the
 * behaviours `FakeRedisClient` could only approximate.
 *
 *   node --env-file=.env.local scripts/redis-verify.ts write
 *   # then stop and restart — a new process, nothing shared in memory
 *   node --env-file=.env.local scripts/redis-verify.ts read
 *
 * `write` runs the single-process cases and leaves state behind. `read` proves
 * that state survived a process that no longer exists.
 *
 * Prints PASS/FAIL only — never the Redis URL, credentials, or identifiers.
 */

const phase = process.argv[2] ?? "write";
if (phase !== "write" && phase !== "read") {
  console.error("usage: redis-verify.ts [write|read]");
  process.exit(1);
}

const config = loadConfig();
if (config.storeMode !== "redis") {
  console.error("REDIS_URL is not set. This script only verifies the real store.");
  process.exit(1);
}

const store: DurableStore = createStore(config);
if (store.kind !== "redis") {
  console.error(`expected the redis store, got ${store.kind}`);
  process.exit(1);
}

// A per-run prefix keeps repeated verification runs from colliding, while the
// restart cases still need a key that is stable across processes.
const STABLE_KEY = "verify:persisted-key";
const STABLE_CHALLENGE = "verify:persisted-challenge";

const results: { name: string; pass: boolean; detail?: string }[] = [];

function check(name: string, pass: boolean, detail?: string): void {
  results.push({ name, pass, ...(detail ? { detail } : {}) });
  console.log(`  ${pass ? "PASS" : "FAIL"}  ${name}${detail ? `  — ${detail}` : ""}`);
}

async function writePhase(): Promise<void> {
  console.log("Real Redis verification — write phase\n");

  // 3. Connectivity.
  try {
    await store.getKeyRecord("connectivity-probe");
    check("Connection", true);
  } catch (error) {
    check("Connection", false, error instanceof Error ? error.message : "unreachable");
    return;
  }

  // 4. Challenge TTL — Redis enforces the expiry, not our clock.
  const shortLived = `verify:ttl:${Date.now()}`;
  await store.putChallenge(shortLived, 1_000);
  const beforeExpiry = await store.consumeChallenge(`${shortLived}-absent`);
  await new Promise((resolve) => setTimeout(resolve, 1_400));
  const afterExpiry = await store.consumeChallenge(shortLived);
  check("Challenge TTL", afterExpiry === false && beforeExpiry === false, "expired challenge rejected");

  // 4. Consume once — the basis of replay protection.
  const single = `verify:once:${Date.now()}`;
  await store.putChallenge(single, CHALLENGE_TTL_MS);
  const first = await store.consumeChallenge(single);
  const second = await store.consumeChallenge(single);
  check("Consume once", first === true && second === false, "second consume rejected");

  // 4. Key state and counter, left behind for the read phase.
  const now = Date.now();
  await store.putKeyRecord({
    keyID: STABLE_KEY,
    publicKey: "verification-placeholder",
    environment: "development",
    lastCounter: 0,
    createdAt: now,
    lastSeenAt: now,
  });
  const one = await store.advanceCounter(STABLE_KEY, 1, now);
  const two = await store.advanceCounter(STABLE_KEY, 2, now);
  const replay = await store.advanceCounter(STABLE_KEY, 1, now);
  check(
    "Counter regression blocked",
    one === true && two === true && replay === false,
    "1 ok, 2 ok, 1 again rejected",
  );

  await store.putChallenge(STABLE_CHALLENGE, CHALLENGE_TTL_MS);

  // 6. Rate limiting counts in Redis.
  const window = `verify:rate:${Date.now()}`;
  const counts: number[] = [];
  for (let index = 0; index < 3; index += 1) {
    counts.push((await store.incrementWindow(window, 60_000)).count);
  }
  check("Rate limit counts", counts.join(",") === "1,2,3", `saw ${counts.join(",")}`);

  console.log(
    "\nState left for the read phase. Restart the process, then run:\n" +
      "  node --env-file=.env.local scripts/redis-verify.ts read",
  );
}

async function readPhase(): Promise<void> {
  console.log("Real Redis verification — read phase (new process)\n");

  const record = await store.getKeyRecord(STABLE_KEY);
  check("Key survives restart", record !== undefined, record ? `counter ${record.lastCounter}` : "missing");

  // The counter reached 2 in the write phase, in a process that is now gone.
  const replay = await store.advanceCounter(STABLE_KEY, 1, Date.now());
  const equal = await store.advanceCounter(STABLE_KEY, 2, Date.now());
  const forward = await store.advanceCounter(STABLE_KEY, 3, Date.now());
  check(
    "Counter survives restart",
    replay === false && equal === false && forward === true,
    "old counters still rejected, 3 accepted",
  );

  const consumed = await store.consumeChallenge(STABLE_CHALLENGE);
  check("Challenge survives restart", consumed === true, "issued before restart, consumed after");

  const again = await store.consumeChallenge(STABLE_CHALLENGE);
  check("Consume once across restart", again === false);
}

await (phase === "write" ? writePhase() : readPhase());

const failed = results.filter((row) => !row.pass);
console.log(`\n${failed.length === 0 ? "PASS" : "FAIL"} — ${results.length - failed.length}/${results.length}`);
process.exit(failed.length === 0 ? 0 : 1);
