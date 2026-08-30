import { CAPABILITIES, CAPABILITY_CONFIG } from "./versions.ts";
import type { Capability } from "./versions.ts";

export type RuntimeMode = "development" | "production";
export type IntegrityMode = "development" | "appattest";
export type StoreMode = "memory" | "redis";

export type Config = {
  mode: RuntimeMode;
  integrityMode: IntegrityMode;
  storeMode: StoreMode;
  openAIKey?: string;
  openAIBaseURL: string;
  models: Record<Capability, string>;
  safetyIdentifierSecret?: string;
  redisURL?: string;
  /** Upstash REST endpoint and token. Preferred on serverless over TCP. */
  upstashURL?: string;
  upstashToken?: string;
  /** `<teamID>.<bundleID>`, the App Attest app identity. */
  appleAppID?: string;
  /**
   * Never inferred, never defaulted. Sandbox and production App Attest keys are
   * not interchangeable, and TestFlight and App Store builds always use the
   * production environment regardless of the entitlement set locally — so this
   * has to be stated by the deployment, not guessed from NODE_ENV or anything
   * else.
   */
  appAttestEnvironment?: "development" | "production";
  /** Apple App Attest Root CA, PEM. A synthetic root in tests. */
  appAttestRootPEM?: string;
};

export class ConfigError extends Error {
  readonly missing: string[];

  constructor(missing: string[]) {
    super(`missing required configuration: ${missing.join(", ")}`);
    this.name = "ConfigError";
    this.missing = missing;
  }
}

/** Some dashboards hand out values already wrapped in quotes. */
function unquote(value: string): string {
  return value.replace(/^["']|["']$/g, "");
}

function isProduction(env: NodeJS.ProcessEnv): boolean {
  return env.PACKWISE_ENV === "production" || env.VERCEL_ENV === "production";
}

/**
 * Production refuses to boot with incomplete configuration rather than
 * degrading quietly. A missing Redis URL must never fall back to process
 * memory for security state, and `appattest` must never fall back to
 * development trust — both would look like a working deployment.
 */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const mode: RuntimeMode = isProduction(env) ? "production" : "development";
  const integrityMode: IntegrityMode =
    env.PACKWISE_INTEGRITY_MODE === "appattest" ? "appattest" : "development";
  const hasRedis = Boolean(env.REDIS_URL) || Boolean(env.UPSTASH_REDIS_REST_URL);
  const storeMode: StoreMode = env.PACKWISE_STORE === "redis" || hasRedis ? "redis" : "memory";

  const models = Object.fromEntries(
    CAPABILITIES.map((capability) => [
      capability,
      env[CAPABILITY_CONFIG[capability].modelEnvVar] ?? "",
    ]),
  ) as Record<Capability, string>;

  const config: Config = {
    mode,
    integrityMode,
    storeMode,
    openAIKey: env.OPENAI_API_KEY,
    openAIBaseURL: env.OPENAI_BASE_URL ?? "https://api.openai.com/v1",
    models,
    safetyIdentifierSecret: env.PACKWISE_SAFETY_IDENTIFIER_SECRET,
    redisURL: env.REDIS_URL,
    ...(env.UPSTASH_REDIS_REST_URL ? { upstashURL: unquote(env.UPSTASH_REDIS_REST_URL) } : {}),
    ...(env.UPSTASH_REDIS_REST_TOKEN ? { upstashToken: unquote(env.UPSTASH_REDIS_REST_TOKEN) } : {}),
    appleAppID: env.PACKWISE_APP_ID,
    ...(env.PACKWISE_APP_ATTEST_ENVIRONMENT === "development" ||
    env.PACKWISE_APP_ATTEST_ENVIRONMENT === "production"
      ? { appAttestEnvironment: env.PACKWISE_APP_ATTEST_ENVIRONMENT }
      : {}),
    ...(env.PACKWISE_APP_ATTEST_ROOT_PEM
      ? { appAttestRootPEM: env.PACKWISE_APP_ATTEST_ROOT_PEM.replace(/\\n/g, "\n") }
      : {}),
  };

  const missing = missingRequirements(config);
  if (missing.length > 0) throw new ConfigError(missing);
  return config;
}

/** Which required settings are absent for the mode this config declares. */
export function missingRequirements(config: Config): string[] {
  const missing: string[] = [];

  if (config.mode === "production") {
    if (!config.openAIKey) missing.push("OPENAI_API_KEY");
    for (const capability of CAPABILITIES) {
      if (!config.models[capability]) missing.push(CAPABILITY_CONFIG[capability].modelEnvVar);
    }
    if (!config.safetyIdentifierSecret) missing.push("PACKWISE_SAFETY_IDENTIFIER_SECRET");
    if (config.storeMode !== "redis") missing.push("REDIS_URL");
    if (config.integrityMode !== "appattest") missing.push("PACKWISE_INTEGRITY_MODE=appattest");
  }

  // Independent of mode: these are what the chosen features need to work at all.
  if (config.storeMode === "redis" && !config.redisURL && !config.upstashURL) {
    missing.push("REDIS_URL or UPSTASH_REDIS_REST_URL");
  }
  if (config.upstashURL && !config.upstashToken) missing.push("UPSTASH_REDIS_REST_TOKEN");
  // A real provider call must never carry the raw install token. Without the
  // secret the pipeline has nothing to HMAC with, so a live key without one is
  // a configuration error rather than a quiet privacy regression.
  if (config.openAIKey && !config.safetyIdentifierSecret) {
    missing.push("PACKWISE_SAFETY_IDENTIFIER_SECRET");
  }
  if (config.integrityMode === "appattest") {
    if (!config.appleAppID) missing.push("PACKWISE_APP_ID");
    // Stated explicitly or not at all. An unset value must not quietly become
    // "production" — that would silently accept sandbox keys as real ones.
    if (!config.appAttestEnvironment) missing.push("PACKWISE_APP_ATTEST_ENVIRONMENT");
    if (!config.appAttestRootPEM) missing.push("PACKWISE_APP_ATTEST_ROOT_PEM");
  }

  return missing;
}

/** For health and startup checks: what is configured, without leaking secrets. */
export function configSummary(config: Config): Record<string, unknown> {
  return {
    mode: config.mode,
    integrityMode: config.integrityMode,
    storeMode: config.storeMode,
    storeTransport: config.upstashURL ? "upstash-rest" : config.redisURL ? "redis-tcp" : "memory",
    models: config.models,
    appAttestEnvironment: config.appAttestEnvironment ?? null,
    hasOpenAIKey: Boolean(config.openAIKey),
    hasSafetySecret: Boolean(config.safetyIdentifierSecret),
    hasAppID: Boolean(config.appleAppID),
    hasAppAttestRoot: Boolean(config.appAttestRootPEM),
  };
}
