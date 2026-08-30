import { manifest } from "./generated.ts";

/**
 * Every response records which prompt, schema, and model produced it. Without
 * this a behaviour change months from now is unattributable. The version comes
 * from the generated manifest so it cannot drift from the schemas it describes.
 */
export const SCHEMA_VERSION = manifest().schemaVersion;

export const CAPABILITIES = ["interpret", "gaps", "optimize"] as const;
export type Capability = (typeof CAPABILITIES)[number];

type CapabilityConfig = {
  /** Bumped whenever the prompt text changes, independent of the schema. */
  promptVersion: string;
  modelEnvVar: string;
  /** Per-identifier budget. Deliberately tight; intelligence is enhancement. */
  rateLimit: { requests: number; windowMs: number };
  timeoutMs: number;
  maxRetries: number;
};

export const CAPABILITY_CONFIG: Record<Capability, CapabilityConfig> = {
  interpret: {
    promptVersion: "interpret/1",
    modelEnvVar: "PACKWISE_MODEL_CONTEXT",
    rateLimit: { requests: 20, windowMs: 60_000 },
    timeoutMs: 8_000,
    maxRetries: 1,
  },
  gaps: {
    promptVersion: "gaps/1",
    modelEnvVar: "PACKWISE_MODEL_GAPS",
    rateLimit: { requests: 10, windowMs: 60_000 },
    timeoutMs: 12_000,
    maxRetries: 1,
  },
  optimize: {
    promptVersion: "optimize/1",
    modelEnvVar: "PACKWISE_MODEL_OPTIMIZE",
    rateLimit: { requests: 10, windowMs: 60_000 },
    timeoutMs: 12_000,
    maxRetries: 1,
  },
};

/**
 * Model IDs are configuration, never literals scattered through the code. The
 * fake adapter reports the configured name so logs stay comparable across the
 * M3A-2 swap.
 */
export function modelFor(capability: Capability): string {
  const config = CAPABILITY_CONFIG[capability];
  return process.env[config.modelEnvVar] ?? "fake";
}
