import type { AppAttestKeyRecord, DurableStore, RateLimitResult } from "./durableStore.ts";

/** Development and tests only. Selected explicitly, never as a fallback. */
export class InMemoryDurableStore implements DurableStore {
  readonly kind = "memory" as const;

  private readonly windows = new Map<string, RateLimitResult>();
  private readonly challenges = new Map<string, number>();
  private readonly keys = new Map<string, AppAttestKeyRecord>();
  private readonly now: () => number;

  constructor(now: () => number = Date.now) {
    this.now = now;
  }

  async incrementWindow(key: string, windowMs: number): Promise<RateLimitResult> {
    const at = this.now();
    const existing = this.windows.get(key);
    if (!existing || at >= existing.resetAt) {
      const fresh = { count: 1, resetAt: at + windowMs };
      this.windows.set(key, fresh);
      return fresh;
    }
    existing.count += 1;
    return existing;
  }

  async putChallenge(challenge: string, ttlMs: number): Promise<void> {
    this.challenges.set(challenge, this.now() + ttlMs);
  }

  async consumeChallenge(challenge: string): Promise<boolean> {
    const expiresAt = this.challenges.get(challenge);
    if (expiresAt === undefined) return false;
    this.challenges.delete(challenge);
    return this.now() < expiresAt;
  }

  async getKeyRecord(keyID: string): Promise<AppAttestKeyRecord | undefined> {
    return this.keys.get(keyID);
  }

  async putKeyRecord(record: AppAttestKeyRecord): Promise<void> {
    this.keys.set(record.keyID, { ...record });
  }

  async advanceCounter(keyID: string, counter: number, at: number): Promise<boolean> {
    const record = this.keys.get(keyID);
    if (!record || counter <= record.lastCounter) return false;
    record.lastCounter = counter;
    record.lastSeenAt = at;
    return true;
  }

  reset(): void {
    this.windows.clear();
    this.challenges.clear();
    this.keys.clear();
  }
}
