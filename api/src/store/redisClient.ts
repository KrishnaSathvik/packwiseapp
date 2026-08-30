/**
 * The only Redis surface the store needs. Keeping it this narrow means the
 * Redis-backed store is fully testable against `FakeRedisClient` without a
 * server, and swapping Upstash for Redis Cloud is one file.
 */
export interface RedisClient {
  get(key: string): Promise<string | null>;
  /** @returns false when `nx` was requested and the key already existed. */
  set(key: string, value: string, options?: { pxMs?: number; nx?: boolean }): Promise<boolean>;
  del(key: string): Promise<number>;
  /**
   * Atomic read-and-delete. Required for consume-once: `DEL` alone cannot
   * express it, because Upstash reports 1 for a key that has already expired,
   * which would let an expired challenge through.
   */
  getdel(key: string): Promise<string | null>;
  incr(key: string): Promise<number>;
  /** Remaining TTL in milliseconds, or -1 when the key has none. */
  pttl(key: string): Promise<number>;
  pexpire(key: string, ms: number): Promise<boolean>;
}

type Entry = { value: string; expiresAt?: number };

/** In-process Redis stand-in with real TTL semantics against an injected clock. */
export class FakeRedisClient implements RedisClient {
  private readonly entries = new Map<string, Entry>();
  private readonly now: () => number;

  constructor(now: () => number = Date.now) {
    this.now = now;
  }

  private live(key: string): Entry | undefined {
    const entry = this.entries.get(key);
    if (!entry) return undefined;
    if (entry.expiresAt !== undefined && this.now() >= entry.expiresAt) {
      this.entries.delete(key);
      return undefined;
    }
    return entry;
  }

  async get(key: string): Promise<string | null> {
    return this.live(key)?.value ?? null;
  }

  async set(key: string, value: string, options: { pxMs?: number; nx?: boolean } = {}): Promise<boolean> {
    if (options.nx === true && this.live(key) !== undefined) return false;
    this.entries.set(key, {
      value,
      ...(options.pxMs === undefined ? {} : { expiresAt: this.now() + options.pxMs }),
    });
    return true;
  }

  async del(key: string): Promise<number> {
    // Expired keys are already gone as far as a caller is concerned, so this
    // must report 0 rather than deleting a value real Redis would have dropped.
    const present = this.live(key) !== undefined;
    this.entries.delete(key);
    return present ? 1 : 0;
  }

  async getdel(key: string): Promise<string | null> {
    const entry = this.live(key);
    this.entries.delete(key);
    return entry?.value ?? null;
  }

  async incr(key: string): Promise<number> {
    const entry = this.live(key);
    const next = Number(entry?.value ?? "0") + 1;
    this.entries.set(key, {
      value: String(next),
      ...(entry?.expiresAt === undefined ? {} : { expiresAt: entry.expiresAt }),
    });
    return next;
  }

  async pttl(key: string): Promise<number> {
    const entry = this.live(key);
    if (!entry) return -2;
    if (entry.expiresAt === undefined) return -1;
    return Math.max(0, entry.expiresAt - this.now());
  }

  async pexpire(key: string, ms: number): Promise<boolean> {
    const entry = this.live(key);
    if (!entry) return false;
    entry.expiresAt = this.now() + ms;
    return true;
  }

  reset(): void {
    this.entries.clear();
  }
}
