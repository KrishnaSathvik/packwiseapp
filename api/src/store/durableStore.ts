/**
 * State that must survive a function instance: rate-limit counters, App Attest
 * challenges, attested key records and their assertion counters.
 *
 * There are two implementations and no automatic fallback between them.
 * Production selects Redis explicitly and fails to boot without it — quietly
 * dropping security state into process memory would look like a working
 * deployment.
 */

export type RateLimitResult = {
  count: number;
  /** Epoch milliseconds when the window resets. */
  resetAt: number;
};

export type AppAttestKeyRecord = {
  keyID: string;
  /** SPKI DER, base64. */
  publicKey: string;
  environment: "development" | "production";
  lastCounter: number;
  createdAt: number;
  lastSeenAt: number;
};

export interface DurableStore {
  readonly kind: "memory" | "redis";

  /** Fixed-window counter. Returns the count after this hit. */
  incrementWindow(key: string, windowMs: number): Promise<RateLimitResult>;

  /** Stores a one-time challenge. */
  putChallenge(challenge: string, ttlMs: number): Promise<void>;

  /** Consume-once: true the first time, false for a replay or an expired one. */
  consumeChallenge(challenge: string): Promise<boolean>;

  getKeyRecord(keyID: string): Promise<AppAttestKeyRecord | undefined>;

  putKeyRecord(record: AppAttestKeyRecord): Promise<void>;

  /**
   * Advances the assertion counter only when it strictly increases. Returns
   * false on a regression or an equal value, which is a replayed assertion.
   */
  advanceCounter(keyID: string, counter: number, at: number): Promise<boolean>;
}
