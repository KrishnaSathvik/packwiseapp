import { IntelligenceError } from "../errors.ts";
import { CAPABILITY_CONFIG, modelFor } from "../versions.ts";
import type { Capability } from "../versions.ts";
import type { ModelAdapter, ModelResult } from "./adapter.ts";
import { ProviderError } from "./errors.ts";

/**
 * One place that owns timeout and retry policy, so swapping FakeModelAdapter
 * for the Responses API does not also change failure behaviour.
 *
 * The policy is deliberately conservative. PackWise already survives a failed
 * intelligence call by falling back to the deterministic list, so there is no
 * reason to make anyone wait through a retry chain:
 *
 *   network / timeout      one bounded retry
 *   429 / retryable 5xx    one bounded retry, honouring Retry-After
 *   400-class, auth        never retried — the same request would fail again
 *   malformed output       never retried in a loop
 */
export type Clock = {
  now(): number;
  sleep(ms: number, signal?: AbortSignal): Promise<void>;
  /** [0, 1). Injectable so jitter is deterministic in tests. */
  random(): number;
};

export const systemClock: Clock = {
  now: () => Date.now(),
  sleep: (ms) =>
    new Promise((resolve) => {
      setTimeout(resolve, ms);
    }),
  random: () => Math.random(),
};

export const BASE_BACKOFF_MS = 250;
export const MAX_BACKOFF_MS = 2_000;

/** Full jitter: a random point in [0, capped exponential backoff]. */
export function backoffDelay(attempt: number, random: number, retryAfterSeconds?: number): number {
  if (retryAfterSeconds !== undefined) {
    return Math.min(MAX_BACKOFF_MS, Math.max(0, retryAfterSeconds * 1000));
  }
  const ceiling = Math.min(MAX_BACKOFF_MS, BASE_BACKOFF_MS * 2 ** attempt);
  return Math.floor(random * ceiling);
}

export async function runModel(options: {
  adapter: ModelAdapter;
  capability: Capability;
  input: unknown;
  safetyIdentifier: string;
  requestID: string;
  clock?: Clock;
}): Promise<ModelResult> {
  const config = CAPABILITY_CONFIG[options.capability];
  const clock = options.clock ?? systemClock;
  let lastError: unknown;

  for (let attempt = 0; attempt <= config.maxRetries; attempt += 1) {
    const controller = new AbortController();
    const startedAt = clock.now();
    const timer = setTimeout(() => controller.abort(), config.timeoutMs);
    try {
      const result = await options.adapter.produce({
        capability: options.capability,
        model: modelFor(options.capability),
        promptVersion: config.promptVersion,
        input: options.input,
        safetyIdentifier: options.safetyIdentifier,
        requestID: options.requestID,
        signal: controller.signal,
      });
      return { ...result, latencyMs: clock.now() - startedAt };
    } catch (error) {
      lastError = error;

      // An error the API itself raised is already a decision. Don't retry it.
      if (error instanceof IntelligenceError) throw error;

      const failure =
        error instanceof ProviderError
          ? error
          : new ProviderError(controller.signal.aborted ? "timeout" : "network");

      if (!failure.isRetryable || attempt === config.maxRetries) {
        throw intelligenceErrorFor(failure);
      }

      await clock.sleep(
        backoffDelay(attempt, clock.random(), failure.retryAfterSeconds),
      );
    } finally {
      clearTimeout(timer);
    }
  }

  throw intelligenceErrorFor(
    lastError instanceof ProviderError ? lastError : new ProviderError("network"),
  );
}

/**
 * Provider failures become `model_unavailable` — the app's single, silent
 * fallback path. A malformed provider response is our contract being violated,
 * so it keeps the existing 502 policy.
 */
function intelligenceErrorFor(failure: ProviderError): IntelligenceError {
  if (failure.kind === "malformed") {
    return new IntelligenceError("invalid_model_output", "provider response was not usable JSON");
  }
  return new IntelligenceError("model_unavailable", failure.kind);
}
