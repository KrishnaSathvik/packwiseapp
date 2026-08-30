import { loadConfig } from "./config.ts";
import type { Config } from "./config.ts";
import { integrityProviderFor } from "./integrity/provider.ts";
import type { AppIntegrityProvider } from "./integrity/provider.ts";
import { FakeModelAdapter } from "./model/fake.ts";
import { OpenAIResponsesModelAdapter } from "./model/openai/adapter.ts";
import type { ModelAdapter } from "./model/adapter.ts";
import { InMemoryDurableStore } from "./store/memory.ts";
import { RealRedisClient } from "./store/realRedisClient.ts";
import { RedisDurableStore } from "./store/redis.ts";
import { UpstashRedisClient } from "./store/upstashRedisClient.ts";
import type { DurableStore } from "./store/durableStore.ts";
import type { RedisClient } from "./store/redisClient.ts";

/**
 * Composition root. Every selection here is explicit and fails loudly:
 * production never falls back to the in-memory store or the fake adapter,
 * because either would look like a working deployment.
 */
export type Runtime = {
  config: Config;
  store: DurableStore;
  adapter: ModelAdapter;
  integrity: AppIntegrityProvider;
};

export type RedisFactory = (config: Config) => RedisClient;

/**
 * REST is preferred when both are configured: on serverless a stateless HTTPS
 * call beats a TCP connection that has to be established per cold start.
 */
const defaultRedisFactory: RedisFactory = (config) => {
  if (config.upstashURL && config.upstashToken) {
    return new UpstashRedisClient(config.upstashURL, config.upstashToken);
  }
  if (config.redisURL) return new RealRedisClient(config.redisURL);
  throw new Error("no Redis transport configured");
};

/** Overridable so tests can inject `FakeRedisClient` without a server. */
let redisFactory: RedisFactory = defaultRedisFactory;

export function setRedisFactory(factory: RedisFactory | undefined): void {
  redisFactory = factory ?? defaultRedisFactory;
}

export function createStore(config: Config): DurableStore {
  if (config.storeMode !== "redis") {
    if (config.mode === "production") {
      throw new Error("production requires a durable store; set REDIS_URL");
    }
    return new InMemoryDurableStore();
  }
  if (!config.redisURL && !config.upstashURL) {
    throw new Error("REDIS_URL or UPSTASH_REDIS_REST_URL is required when the Redis store is selected");
  }
  return new RedisDurableStore(redisFactory(config));
}

export function createAdapter(config: Config): ModelAdapter {
  if (!config.openAIKey) {
    if (config.mode === "production") {
      throw new Error("production requires OPENAI_API_KEY");
    }
    return new FakeModelAdapter();
  }
  return new OpenAIResponsesModelAdapter({
    apiKey: config.openAIKey,
    baseURL: config.openAIBaseURL,
  });
}

let cached: Runtime | undefined;

export function runtime(): Runtime {
  if (cached) return cached;
  const config = loadConfig();
  const store = createStore(config);
  cached = {
    config,
    store,
    adapter: createAdapter(config),
    integrity: integrityProviderFor(config, store),
  };
  return cached;
}

export function resetRuntime(): void {
  cached = undefined;
}
