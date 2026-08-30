import { loadConfig } from "../src/config.ts";
import { gapsCapability } from "../src/capabilities/gaps.ts";
import { interpretCapability } from "../src/capabilities/interpret.ts";
import { optimizeCapability } from "../src/capabilities/optimize.ts";
import { DevelopmentAppIntegrityProvider } from "../src/integrity/provider.ts";
import { OpenAIResponsesModelAdapter } from "../src/model/openai/adapter.ts";
import { createHandler } from "../src/pipeline.ts";
import type { CapabilityDefinition, HttpResponse } from "../src/pipeline.ts";
import { InMemoryDurableStore } from "../src/store/memory.ts";
import {
  SAFETY_IDENTIFIER,
  contextFromFixture,
  tripContext,
  tripEvalFixtures,
} from "../test/helpers.ts";

/**
 * Step 1 of docs/m3a2-verification-runbook.md: one real call per capability
 * against the live provider, through the real pipeline so every validation
 * layer is exercised.
 *
 *   node --env-file=.env.local scripts/live-smoke.ts
 *   node --env-file=.env.local scripts/live-smoke.ts --evals
 *
 * With --base-url it runs the same cases against a deployed instance instead of
 * in-process, for the Vercel step:
 *
 *   node scripts/live-smoke.ts --base-url=https://<preview>.vercel.app
 *
 * Prints the evidence the runbook asks for. Never prints the API key, the HMAC
 * secret, or the derived safety identifier.
 */

const baseURLArgument = process.argv.find((argument) => argument.startsWith("--base-url="));
const BASE_URL = baseURLArgument?.slice("--base-url=".length);

const config = loadConfig();
if (!BASE_URL && !config.openAIKey) {
  console.error("OPENAI_API_KEY is not set. This script only makes live calls.");
  process.exit(1);
}
if (!BASE_URL && !config.safetyIdentifierSecret) {
  console.error("PACKWISE_SAFETY_IDENTIFIER_SECRET is required alongside a live key.");
  process.exit(1);
}

const adapter = BASE_URL
  ? undefined
  : new OpenAIResponsesModelAdapter({
      apiKey: config.openAIKey!,
      baseURL: config.openAIBaseURL,
    });

type LogEntry = {
  status: number;
  requestID?: string;
  model?: string;
  promptVersion?: string;
  schemaVersion?: string;
  providerResponseID?: string;
  providerLatencyMs?: number;
  inputTokens?: number;
  outputTokens?: number;
  dropped?: { reason: string; count: number }[];
  errorCode?: string;
};

function capture(): { response: HttpResponse; body: () => unknown; status: () => number } {
  let status = 0;
  let body: unknown;
  const response: HttpResponse = {
    status(code) {
      status = code;
      return response;
    },
    json(value) {
      body = value;
      return value;
    },
    setHeader(_name, value) {
      return value;
    },
  };
  return { response, body: () => body, status: () => status };
}

const REMOTE_PATHS: Record<string, string> = {
  interpret: "/v1/trip/interpret",
  gaps: "/v1/packing/gaps",
  optimize: "/v1/packing/optimize",
};

/**
 * Against a deployed instance the provider metadata lives in that server's
 * logs, not here — the response carries meta, which is what can be asserted
 * from outside.
 */
async function callRemote<Req, Res>(
  definition: CapabilityDefinition<Req, Res>,
  payload: unknown,
): Promise<{ status: number; body: unknown; log?: LogEntry }> {
  const response = await fetch(`${BASE_URL}${REMOTE_PATHS[definition.capability]}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  const body = (await response.json()) as { meta?: Record<string, string> };
  const meta = body.meta;
  return {
    status: response.status,
    body,
    ...(meta
      ? {
          log: {
            status: response.status,
            requestID: meta.requestID,
            model: meta.model,
            promptVersion: meta.promptVersion,
            schemaVersion: meta.schemaVersion,
          },
        }
      : {}),
  };
}

async function call<Req extends { safetyIdentifier: string }, Res>(
  definition: CapabilityDefinition<Req, Res>,
  payload: unknown,
): Promise<{ status: number; body: unknown; log?: LogEntry }> {
  if (BASE_URL) return callRemote(definition, payload);

  const handler = createHandler(definition, {
    config,
    adapter: adapter!,
    store: new InMemoryDurableStore(),
    integrity: new DevelopmentAppIntegrityProvider(),
  });

  const { response, body, status } = capture();
  const original = console.log;
  let log: LogEntry | undefined;
  console.log = (...args: unknown[]) => {
    const [first] = args;
    if (typeof first === "string" && first.includes("intelligence_request")) {
      log = JSON.parse(first) as LogEntry;
      return;
    }
    original(...args);
  };
  try {
    await handler({ method: "POST", headers: {}, body: payload }, response);
  } finally {
    console.log = original;
  }
  return { status: status(), body: body(), ...(log ? { log } : {}) };
}

function evidence(name: string, result: { status: number; body: unknown; log?: LogEntry }): void {
  const log = result.log;
  console.log(`\n── ${name} ${"─".repeat(Math.max(0, 46 - name.length))}`);
  console.log(`  status              ${result.status}`);
  console.log(`  model               ${log?.model ?? "?"}`);
  console.log(`  promptVersion       ${log?.promptVersion ?? "?"}`);
  console.log(`  schemaVersion       ${log?.schemaVersion ?? "?"}`);
  console.log(`  providerResponseID  ${log?.providerResponseID ?? "—"}`);
  console.log(`  providerLatencyMs   ${log?.providerLatencyMs ?? "—"}`);
  console.log(`  tokens in/out       ${log?.inputTokens ?? "—"} / ${log?.outputTokens ?? "—"}`);
  if (log?.dropped) console.log(`  dropped             ${JSON.stringify(log.dropped)}`);
  if (log?.errorCode) console.log(`  errorCode           ${log.errorCode}`);
  console.log(`  body                ${JSON.stringify(stripMeta(result.body))}`);
}

/** meta is already reported above; keep the body line about the actual output. */
function stripMeta(body: unknown): unknown {
  if (typeof body !== "object" || body === null) return body;
  const { meta: _meta, ...rest } = body as Record<string, unknown>;
  return rest;
}

const NOTE =
  "Going to Tokyo, lots of walking, one fancy dinner, I'll probably work out twice and I get cold easily.";

const TOKYO = tripContext({
  destination: { displayName: "Tokyo", countryCode: "JP" },
  durationDays: 6,
  activities: ["sightseeing", "walking"],
});

console.log(
  BASE_URL
    ? `PackWise live smoke — deployed instance ${new URL(BASE_URL).host}`
    : "PackWise live smoke — runbook step 1 (OpenAI live adapter)",
);
if (!BASE_URL) console.log(`models: ${JSON.stringify(config.models)}`);
console.log("safety_identifier: HMAC of the install token (not printed)");

evidence(
  "interpret",
  await call(interpretCapability, {
    note: NOTE,
    context: TOKYO,
    safetyIdentifier: SAFETY_IDENTIFIER,
  }),
);

evidence(
  "gaps",
  await call(gapsCapability, {
    context: TOKYO,
    items: [
      { canonicalItemID: "essentials.wallet", displayName: "Wallet", quantity: 1 },
      { canonicalItemID: "documents.passport", displayName: "Passport", quantity: 1 },
      { canonicalItemID: "footwear.walking_shoes", displayName: "Walking shoes", quantity: 1 },
    ],
    safetyIdentifier: SAFETY_IDENTIFIER,
  }),
);

evidence(
  "optimize",
  await call(optimizeCapability, {
    context: { ...TOKYO, packingStyle: "light" },
    items: [
      { canonicalItemID: "footwear.walking_shoes", displayName: "Walking shoes", quantity: 1 },
      { canonicalItemID: "footwear.running_shoes", displayName: "Running shoes", quantity: 1 },
      { canonicalItemID: "clothing.tshirt", displayName: "T-shirts", quantity: 9 },
    ],
    safetyIdentifier: SAFETY_IDENTIFIER,
  }),
);

if (!process.argv.includes("--evals")) {
  console.log("\nPass --evals to run the nine fixtures against the live model.");
  process.exit(0);
}

console.log("\n\nLive eval — baseline measurement, nine fixtures");
console.log("Everything fixed: model, prompt versions, schemas, reason validation.");
console.log("No prompt edits between fixtures. Differences are the measurement.\n");

type Bucket = "green" | "yellow" | "red";

const rows: {
  fixture: string;
  capability: string;
  bucket: Bucket;
  notes: string[];
  log?: LogEntry;
  accepted: number;
}[] = [];

function dropped(log?: LogEntry): string {
  if (!log?.dropped || log.dropped.length === 0) return "none";
  return log.dropped.map((row) => `${row.reason}×${row.count}`).join(" ");
}

function returnedCount(accepted: number, log?: LogEntry): number {
  return accepted + (log?.dropped ?? []).reduce((sum, row) => sum + row.count, 0);
}

function report(
  fixture: string,
  capability: string,
  result: { status: number; log?: LogEntry },
  accepted: number,
  bucket: Bucket,
  notes: string[],
): void {
  rows.push({ fixture, capability, bucket, notes, ...(result.log ? { log: result.log } : {}), accepted });
  const log = result.log;
  const mark = bucket === "green" ? "ok  " : bucket === "yellow" ? "warn" : "FAIL";
  console.log(`[${mark}] ${fixture} · ${capability}`);
  console.log(
    `        status ${result.status} · returned ${returnedCount(accepted, log)} · accepted ${accepted} · rejected ${dropped(log)}`,
  );
  console.log(
    `        ${log?.model ?? "?"} · ${log?.promptVersion ?? "?"} · schema ${log?.schemaVersion ?? "?"} · ${log?.providerLatencyMs ?? "?"}ms · tok ${log?.inputTokens ?? "?"}/${log?.outputTokens ?? "?"} · ${log?.requestID ?? "?"}`,
  );
  for (const note of notes) console.log(`        ${note}`);
}

for (const fixture of tripEvalFixtures()) {
  if (fixture.note === undefined) continue;
  const context = contextFromFixture(fixture);

  const interpreted = await call(interpretCapability, {
    note: fixture.note,
    context,
    safetyIdentifier: SAFETY_IDENTIFIER,
  });
  const body = interpreted.body as { inferredActivities?: string[]; inferredChips?: string[] };
  const inferred = [...(body.inferredActivities ?? []), ...(body.inferredChips ?? [])];
  const inferredSet = new Set(inferred);

  const missed = (fixture.mustInfer ?? []).filter((value) => !inferredSet.has(value));
  const overRead = (fixture.mustNotInfer ?? []).filter((value) => inferredSet.has(value));

  const interpretNotes = [`inferred ${inferred.join(", ") || "—"}`];
  if (missed.length > 0) interpretNotes.push(`MISSED mustInfer: ${missed.join(", ")}`);
  if (overRead.length > 0) interpretNotes.push(`VIOLATED mustNotInfer: ${overRead.join(", ")}`);

  report(
    fixture.id,
    "interpret",
    interpreted,
    inferred.length,
    interpreted.status !== 200 || missed.length > 0 || overRead.length > 0 ? "red" : "green",
    interpretNotes,
  );

  const gaps = await call(gapsCapability, {
    context,
    items: (fixture.mustInclude ?? []).map((id) => ({
      canonicalItemID: id,
      displayName: id,
      quantity: 1,
    })),
    safetyIdentifier: SAFETY_IDENTIFIER,
  });
  const allowed = new Set(fixture.allowedSuggestions ?? []);
  const suggestions =
    (gaps.body as { suggestions?: { canonicalItemID: string; reasonCode: string }[] }).suggestions ?? [];
  const outside = suggestions.filter((row) => !allowed.has(row.canonicalItemID));

  const gapNotes = [
    `suggested ${suggestions.map((row) => `${row.canonicalItemID}(${row.reasonCode})`).join(", ") || "—"}`,
  ];
  if (outside.length > 0) {
    gapNotes.push(`OUTSIDE allowedSuggestions: ${outside.map((row) => row.canonicalItemID).join(", ")}`);
  }
  // An empty result is valid: allowedSuggestions bounds what may be proposed,
  // it does not require anything to be.
  const unrenderable = (gaps.log?.dropped ?? []).find((row) => row.reason === "unrenderable_reason");
  if (unrenderable) gapNotes.push(`unrenderable_reason ×${unrenderable.count}`);

  report(
    fixture.id,
    "gaps",
    gaps,
    suggestions.length,
    gaps.status !== 200 || outside.length > 0 ? "red" : unrenderable ? "yellow" : "green",
    gapNotes,
  );
  console.log("");
}

const counts = { green: 0, yellow: 0, red: 0 };
for (const row of rows) counts[row.bucket] += 1;

const emptyGaps = rows.filter((row) => row.capability === "gaps" && row.accepted === 0).length;
const gapRows = rows.filter((row) => row.capability === "gaps").length;
const unrenderable = rows.reduce(
  (sum, row) => sum + ((row.log?.dropped ?? []).find((d) => d.reason === "unrenderable_reason")?.count ?? 0),
  0,
);
const totalTokens = rows.reduce(
  (sum, row) => sum + (row.log?.inputTokens ?? 0) + (row.log?.outputTokens ?? 0),
  0,
);

console.log("─".repeat(60));
console.log(`calls        ${rows.length}`);
console.log(`green        ${counts.green}`);
console.log(`yellow       ${counts.yellow}`);
console.log(`red          ${counts.red}`);
console.log(`empty gaps   ${emptyGaps}/${gapRows}  (valid unless it is nearly all of them)`);
console.log(`unrenderable ${unrenderable}  (rejections after the schema tightening)`);
console.log(`tokens       ${totalTokens}`);
console.log(
  `\nverdict      ${counts.red > 0 ? "RED — required assertions failed" : counts.yellow > 0 ? "YELLOW — structurally valid, review the warnings" : "GREEN"}`,
);
