import { randomUUID } from "node:crypto";

import { loadConfig } from "./config.ts";
import type { Config } from "./config.ts";
import { IntelligenceError, statusFor } from "./errors.ts";
import { integrityProviderFor } from "./integrity/provider.ts";
import type { AppIntegrityProvider } from "./integrity/provider.ts";
import { RateLimiter } from "./rateLimit.ts";
import { deriveSafetyIdentifier } from "./safetyIdentifier.ts";
import { InMemoryDurableStore } from "./store/memory.ts";
import type { DurableStore } from "./store/durableStore.ts";
import { assertSafetyIdentifier, validateRequest, validateResponse } from "./validation.ts";
import { CAPABILITY_CONFIG, SCHEMA_VERSION, modelFor } from "./versions.ts";
import type { Capability } from "./versions.ts";
import { FakeModelAdapter } from "./model/fake.ts";
import type { ModelAdapter, ModelResult } from "./model/adapter.ts";
import type { Clock } from "./model/run.ts";
import type { IntelligenceMeta } from "./types.ts";

export type HttpRequest = {
  method?: string;
  headers: Record<string, string | string[] | undefined>;
  body?: unknown;
};

export type HttpResponse = {
  status(code: number): HttpResponse;
  json(body: unknown): unknown;
  setHeader(name: string, value: string | number): unknown;
};

export type CapabilityContext = {
  requestID: string;
  clientID: string;
  /** Already HMAC'd. The raw install token never reaches the adapter. */
  safetyIdentifier: string;
  adapter: ModelAdapter;
  meta: IntelligenceMeta;
  clock?: Clock;
  /** Counts of dropped model output, for logging. Never contains trip content. */
  note(reasons: { reason: string; count: number }[]): void;
  /** Provider metadata, logged server-side only. */
  observed(result: ModelResult): void;
};

export type CapabilityDefinition<Req, Res> = {
  capability: Capability;
  requestSchema: string;
  responseSchema: string;
  handle(request: Req, context: CapabilityContext): Promise<Res>;
};

export type PipelineOptions = {
  adapter?: ModelAdapter;
  integrity?: AppIntegrityProvider;
  store?: DurableStore;
  config?: Config;
  clock?: Clock;
  now?: () => Date;
};

function headerValue(request: HttpRequest, name: string): string | undefined {
  const raw = request.headers[name] ?? request.headers[name.toLowerCase()];
  return Array.isArray(raw) ? raw[0] : raw;
}

function parseBody(request: HttpRequest): unknown {
  if (typeof request.body !== "string") return request.body;
  try {
    return JSON.parse(request.body);
  } catch {
    throw new IntelligenceError("invalid_request", "body is not valid JSON");
  }
}

/**
 * Route → request validation → integrity → rate limit → capability → model →
 * response validation → response. Every endpoint goes through this, so the
 * order of those steps is decided once.
 */
export function createHandler<Req extends { safetyIdentifier: string }, Res>(
  definition: CapabilityDefinition<Req, Res>,
  options: PipelineOptions = {},
) {
  const config = options.config ?? loadConfig();
  const adapter = options.adapter ?? new FakeModelAdapter();
  const store = options.store ?? new InMemoryDurableStore();
  const integrity = options.integrity ?? integrityProviderFor(config, store);
  const rateLimiter = new RateLimiter(store);
  const now = options.now ?? (() => new Date());

  return async function handler(request: HttpRequest, response: HttpResponse): Promise<void> {
    const requestID = headerValue(request, "x-request-id") ?? randomUUID();
    const startedAt = Date.now();
    const dropped: { reason: string; count: number }[] = [];
    let observed: ModelResult | undefined;

    response.setHeader("X-Request-ID", requestID);

    try {
      if (request.method !== "POST") {
        throw new IntelligenceError("method_not_allowed");
      }

      const body = validateRequest<Req>(definition.requestSchema, parseBody(request));
      assertSafetyIdentifier(body.safetyIdentifier);

      const identity = await integrity.verify({
        header: (name) => headerValue(request, name),
        body: request.body,
        requestID,
      });

      const retryAfter = await rateLimiter.check(definition.capability, identity.clientID);
      if (retryAfter !== null) {
        response.setHeader("Retry-After", retryAfter);
        throw new IntelligenceError("rate_limited");
      }

      const meta: IntelligenceMeta = {
        requestID,
        generatedAt: now().toISOString(),
        model: modelFor(definition.capability),
        promptVersion: CAPABILITY_CONFIG[definition.capability].promptVersion,
        schemaVersion: SCHEMA_VERSION,
      };

      const result = await definition.handle(body, {
        requestID,
        clientID: identity.clientID,
        // The provider sees an HMAC of the install token, never the token.
        safetyIdentifier: config.safetyIdentifierSecret
          ? deriveSafetyIdentifier(body.safetyIdentifier, config.safetyIdentifierSecret)
          : body.safetyIdentifier,
        adapter,
        meta,
        ...(options.clock ? { clock: options.clock } : {}),
        note: (reasons) => dropped.push(...reasons),
        observed: (value) => {
          observed = value;
        },
      });

      validateResponse(definition.responseSchema, result);
      log(definition.capability, requestID, 200, startedAt, identity.method, dropped, observed);
      response.status(200).json(result);
    } catch (error) {
      const failure =
        error instanceof IntelligenceError ? error : new IntelligenceError("internal_error");
      const status = statusFor(failure.code);
      log(
        definition.capability,
        requestID,
        status,
        startedAt,
        integrity.mode,
        dropped,
        observed,
        failure.code,
      );
      response.status(status).json({
        error: failure.code,
        message: failure.detail,
        requestID,
      });
    }
  };
}

/**
 * Trip notes, destinations, and item lists are never logged. Only the shape of
 * what happened, plus enough provider metadata to trace an odd suggestion back
 * to a model and prompt.
 */
function log(
  capability: Capability,
  requestID: string,
  status: number,
  startedAt: number,
  integrityMode: string,
  dropped: { reason: string; count: number }[],
  observed?: ModelResult,
  errorCode?: string,
): void {
  const entry = {
    event: "intelligence_request",
    capability,
    requestID,
    status,
    durationMs: Date.now() - startedAt,
    model: modelFor(capability),
    promptVersion: CAPABILITY_CONFIG[capability].promptVersion,
    schemaVersion: SCHEMA_VERSION,
    integrityMode,
    ...(observed?.providerResponseID ? { providerResponseID: observed.providerResponseID } : {}),
    ...(observed?.latencyMs === undefined ? {} : { providerLatencyMs: observed.latencyMs }),
    ...(observed?.inputTokens === undefined ? {} : { inputTokens: observed.inputTokens }),
    ...(observed?.outputTokens === undefined ? {} : { outputTokens: observed.outputTokens }),
    ...(dropped.length > 0 ? { dropped } : {}),
    ...(errorCode ? { errorCode } : {}),
  };
  console.log(JSON.stringify(entry));
}
