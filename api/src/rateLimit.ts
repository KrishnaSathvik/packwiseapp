import type { DurableStore } from "./store/durableStore.ts";
import { CAPABILITY_CONFIG } from "./versions.ts";
import type { Capability } from "./versions.ts";

/**
 * Per-capability budgets, held in whatever durable store the runtime selected.
 * Deliberately tight: intelligence is an enhancement, and the deterministic
 * list is unaffected when a caller runs out of budget.
 */
export class RateLimiter {
  private readonly store: DurableStore;
  private readonly now: () => number;

  constructor(store: DurableStore, now: () => number = Date.now) {
    this.store = store;
    this.now = now;
  }

  /** @returns seconds until the window resets, or null when the call is allowed. */
  async check(capability: Capability, clientID: string): Promise<number | null> {
    const { requests, windowMs } = CAPABILITY_CONFIG[capability].rateLimit;
    const result = await this.store.incrementWindow(`${capability}:${clientID}`, windowMs);
    if (result.count <= requests) return null;
    return Math.max(1, Math.ceil((result.resetAt - this.now()) / 1000));
  }
}
