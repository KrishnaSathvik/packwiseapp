import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

/**
 * Everything the functions load at runtime lives in `api/generated/`, produced
 * by `scripts/build_intelligence_schemas.py` from `shared/`. It is inside the
 * Vercel project root on purpose: deployment is a deterministic artifact, not
 * runtime knowledge of a path outside the root.
 */
const GENERATED_DIR = fileURLToPath(new URL("../generated/", import.meta.url));

function readJSON<T>(...segments: string[]): T {
  return JSON.parse(readFileSync(join(GENERATED_DIR, ...segments), "utf8")) as T;
}

export type Manifest = {
  schemaVersion: string;
  buildHash: string;
  capabilities: Record<string, { schema: string; definition: string }>;
};

let manifestCache: Manifest | undefined;

export function manifest(): Manifest {
  manifestCache ??= readJSON<Manifest>("manifest.json");
  return manifestCache;
}

export function apiSchema(): object {
  return readJSON<object>("schemas", "api.schema.json");
}

/** The exact schema handed to Structured Outputs for this capability. */
export function modelOutputSchema(capability: string): object {
  const entry = manifest().capabilities[capability];
  if (!entry) throw new Error(`no generated schema for capability ${capability}`);
  return readJSON<object>(...entry.schema.split("/"));
}

let catalogIDs: Set<string> | undefined;

/** Every canonical item ID the model is permitted to reference. */
export function canonicalItemIDs(): Set<string> {
  catalogIDs ??= new Set(readJSON<{ items: string[] }>("vocab", "canonical-items.json").items);
  return catalogIDs;
}

type ReasonCodeFile = { all: string[]; arguments: Record<string, string[]> };

let reasonCodeFile: ReasonCodeFile | undefined;

function reasonFile(): ReasonCodeFile {
  reasonCodeFile ??= readJSON<ReasonCodeFile>("vocab", "reason-codes.json");
  return reasonCodeFile;
}

let reasonCodeSet: Set<string> | undefined;

/** Reason codes are a closed set. Prose is never a durable identifier. */
export function reasonCodes(): Set<string> {
  reasonCodeSet ??= new Set(reasonFile().all);
  return reasonCodeSet;
}

/**
 * The placeholders this code's template needs to render. A reason missing one
 * of them would surface a literal `{otherItem}` to the customer.
 */
export function requiredReasonArguments(code: string): string[] {
  return reasonFile().arguments[code] ?? [];
}

let vocab: { chips: string[]; activities: string[] } | undefined;

export function vocabulary(): { chips: string[]; activities: string[] } {
  vocab ??= {
    chips: readJSON<{ chips: string[] }>("vocab", "context-chips.json").chips,
    activities: readJSON<{ activities: string[] }>("vocab", "activities.json").activities,
  };
  return vocab;
}
