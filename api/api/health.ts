import { configSummary, loadConfig, missingRequirements } from "../src/config.ts";
import { manifest } from "../src/generated.ts";
import { runtime } from "../src/runtime.ts";
import type { HttpRequest, HttpResponse } from "../src/pipeline.ts";

/**
 * Deployment check: what this instance is configured to do, what is missing,
 * and whether the durable store actually answers. Reports presence, never
 * values — no URLs, credentials, or identifiers.
 */
export default async function handler(
  _request: HttpRequest,
  response: HttpResponse,
): Promise<void> {
  let config;
  try {
    config = loadConfig();
  } catch (error) {
    response.status(503).json({
      status: "misconfigured",
      message: error instanceof Error ? error.message : "configuration error",
    });
    return;
  }

  // A configured store that cannot be reached is a failure, not a warning:
  // the alternative would be serving requests with no durable state.
  let store: { kind: string; reachable: boolean; error?: string };
  try {
    const { store: durable } = runtime();
    await durable.getKeyRecord("health-probe");
    store = { kind: durable.kind, reachable: true };
  } catch (error) {
    store = {
      kind: config.storeMode,
      reachable: false,
      error: error instanceof Error ? error.message : "store unreachable",
    };
  }

  const missing = missingRequirements(config);
  const healthy = missing.length === 0 && store.reachable;

  response.status(healthy ? 200 : 503).json({
    status: healthy ? "ok" : "degraded",
    build: manifest(),
    config: configSummary(config),
    store,
    missing,
  });
}
