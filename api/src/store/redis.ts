import type { AppAttestKeyRecord, DurableStore, RateLimitResult } from "./durableStore.ts";
import type { RedisClient } from "./redisClient.ts";

const PREFIX = "packwise:v1";

/**
 * Redis-backed durable state. Correct across function instances, which is what
 * in-memory rate limiting and App Attest state are not.
 *
 * `advanceCounter` is a read-then-write rather than a Lua script. Two
 * concurrent assertions from the same key can therefore both observe the same
 * `lastCounter`; the loser is a duplicate of an assertion the client already
 * made, not a replay by an attacker, and the next request still enforces the
 * increase. Tighten to a script if that ever needs to be exact.
 */
export class RedisDurableStore implements DurableStore {
  readonly kind = "redis" as const;

  private readonly client: RedisClient;
  private readonly now: () => number;

  constructor(client: RedisClient, now: () => number = Date.now) {
    this.client = client;
    this.now = now;
  }

  async incrementWindow(key: string, windowMs: number): Promise<RateLimitResult> {
    const redisKey = `${PREFIX}:rate:${key}`;
    const count = await this.client.incr(redisKey);
    if (count === 1) {
      await this.client.pexpire(redisKey, windowMs);
      return { count, resetAt: this.now() + windowMs };
    }
    const ttl = await this.client.pttl(redisKey);
    // A key with no TTL means a lost expire; re-arm rather than leak the window.
    if (ttl < 0) {
      await this.client.pexpire(redisKey, windowMs);
      return { count, resetAt: this.now() + windowMs };
    }
    return { count, resetAt: this.now() + ttl };
  }

  async putChallenge(challenge: string, ttlMs: number): Promise<void> {
    await this.client.set(`${PREFIX}:challenge:${challenge}`, "1", { pxMs: ttlMs });
  }

  async consumeChallenge(challenge: string): Promise<boolean> {
    // GETDEL, not DEL: the read-and-delete is atomic, so a replay fails even if
    // both arrive at once, and the returned value reflects expiry. DEL's count
    // does not — Upstash reports 1 for an already-expired key, which would let
    // an expired challenge through.
    return (await this.client.getdel(`${PREFIX}:challenge:${challenge}`)) !== null;
  }

  async getKeyRecord(keyID: string): Promise<AppAttestKeyRecord | undefined> {
    const raw = await this.client.get(`${PREFIX}:key:${keyID}`);
    return raw === null ? undefined : (JSON.parse(raw) as AppAttestKeyRecord);
  }

  async putKeyRecord(record: AppAttestKeyRecord): Promise<void> {
    await this.client.set(`${PREFIX}:key:${record.keyID}`, JSON.stringify(record));
  }

  async advanceCounter(keyID: string, counter: number, at: number): Promise<boolean> {
    const record = await this.getKeyRecord(keyID);
    if (!record || counter <= record.lastCounter) return false;
    await this.putKeyRecord({ ...record, lastCounter: counter, lastSeenAt: at });
    return true;
  }
}
