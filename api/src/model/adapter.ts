import type { Capability } from "../versions.ts";

export type ModelRequest = {
  capability: Capability;
  model: string;
  promptVersion: string;
  /** Already minimised: only what the capability needs, never the whole trip. */
  input: unknown;
  /**
   * Opaque and stable. The adapter derives the provider-facing
   * `safety_identifier` from it; the raw value never leaves the server.
   */
  safetyIdentifier: string;
  requestID: string;
  signal: AbortSignal;
};

/**
 * Server-side observability. Kept out of the client DTO — it exists so a weird
 * suggestion can be traced back to a model and prompt without logging the trip.
 */
export type ModelResult = {
  /** Unvalidated JSON. The caller validates against the generated schema. */
  output: unknown;
  providerResponseID?: string;
  inputTokens?: number;
  outputTokens?: number;
  latencyMs?: number;
};

/**
 * The seam. `FakeModelAdapter` keeps the whole pipeline provable without a key;
 * `OpenAIResponsesModelAdapter` is the same interface against the live API.
 */
export interface ModelAdapter {
  readonly name: string;
  produce(request: ModelRequest): Promise<ModelResult>;
}
