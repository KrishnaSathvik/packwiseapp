import assert from "node:assert/strict";
import test from "node:test";

import { gapsCapability } from "../src/capabilities/gaps.ts";
import { interpretCapability } from "../src/capabilities/interpret.ts";
import { optimizeCapability } from "../src/capabilities/optimize.ts";
import { DevelopmentAppIntegrityProvider } from "../src/integrity/provider.ts";
import { createHandler } from "../src/pipeline.ts";
import type { CapabilityDefinition, PipelineOptions } from "../src/pipeline.ts";
import { InMemoryDurableStore } from "../src/store/memory.ts";
import type { ModelAdapter } from "../src/model/adapter.ts";
import { SAFETY_IDENTIFIER, capture, post, tripContext } from "./helpers.ts";

function call<Req extends { safetyIdentifier: string }, Res>(
  definition: CapabilityDefinition<Req, Res>,
  body: unknown,
  options: PipelineOptions = {},
) {
  const { response, captured } = capture();
  const handler = createHandler(definition, {
    store: new InMemoryDurableStore(),
    integrity: new DevelopmentAppIntegrityProvider(),
    ...options,
  });
  return handler(post(body), response).then(() => captured);
}

function adapterReturning(value: unknown): ModelAdapter {
  return {
    name: "scripted",
    async produce() {
      return { output: value };
    },
  };
}

test("interpret returns context, never packing items", async () => {
  const captured = await call(interpretCapability, {
    note: "Going to Tokyo, lots of walking, one fancy dinner, I'll probably work out twice and I get cold easily.",
    context: tripContext({ destination: { displayName: "Tokyo", countryCode: "JP" } }),
    safetyIdentifier: SAFETY_IDENTIFIER,
  });

  assert.equal(captured.status, 200);
  const body = captured.body as { inferredActivities: string[]; inferredChips: string[] };
  assert.ok(body.inferredActivities.includes("walking"));
  assert.ok(body.inferredActivities.includes("niceDinner"));
  assert.ok(body.inferredChips.includes("usuallyWorkOut"));
  assert.ok(body.inferredChips.includes("getColdEasily"));
  assert.ok(!Object.hasOwn(captured.body as object, "suggestions"));
});

test("invented vocabulary never reaches the client", async () => {
  // The model schema closes the chip and activity enums, so an invented value
  // is a broken model or a stale schema, not a suggestion to filter.
  const captured = await call(
    interpretCapability,
    {
      note: "anything",
      context: tripContext(),
      safetyIdentifier: SAFETY_IDENTIFIER,
    },
    {
      adapter: adapterReturning({
        inferredActivities: ["walking", "scubaDiving"],
        inferredChips: ["getColdEasily", "hatesMornings"],
        noteSummary: null,
      }),
    },
  );

  assert.equal(captured.status, 502);
  assert.equal((captured.body as { error: string }).error, "invalid_model_output");
});

test("gaps only ever recommends, and carries a resolvable reason code", async () => {
  const captured = await call(gapsCapability, {
    context: tripContext({ durationDays: 6, activities: ["walking", "sightseeing"] }),
    items: [{ canonicalItemID: "essentials.wallet", displayName: "Wallet" }],
    safetyIdentifier: SAFETY_IDENTIFIER,
  });

  assert.equal(captured.status, 200);
  const body = captured.body as { suggestions: { action: string; reasonCode: string }[] };
  assert.ok(body.suggestions.length > 0);
  for (const suggestion of body.suggestions) {
    assert.equal(suggestion.action, "recommend");
    assert.ok(suggestion.reasonCode.startsWith("context.gap_"));
  }
});

test("gaps drops an invented canonical item instead of creating one", async () => {
  // Item IDs stay free-form in the model schema, so this is the realistic
  // failure mode: one bad candidate is dropped, the response still succeeds.
  const captured = await call(
    gapsCapability,
    {
      context: tripContext(),
      items: [],
      safetyIdentifier: SAFETY_IDENTIFIER,
    },
    {
      adapter: adapterReturning({
        suggestions: [
          {
            canonicalItemID: "electronics.teleporter",
            reasonCode: "context.gap_generic",
            reasonArguments: [],
            reason: null,
            confidence: 0.9,
            signals: ["gptReasoning"],
          },
          {
            canonicalItemID: "electronics.power_bank",
            reasonCode: "context.gap_generic",
            reasonArguments: [],
            reason: null,
            confidence: 0.9,
            signals: ["gptReasoning"],
          },
        ],
      }),
    },
  );

  assert.equal(captured.status, 200);
  assert.deepEqual(
    (captured.body as { suggestions: { canonicalItemID: string }[] }).suggestions.map(
      (row) => row.canonicalItemID,
    ),
    ["electronics.power_bank"],
  );
});

test("an unknown reason code is a model failure, not a filtered candidate", async () => {
  const captured = await call(
    gapsCapability,
    { context: tripContext(), items: [], safetyIdentifier: SAFETY_IDENTIFIER },
    {
      adapter: adapterReturning({
        suggestions: [
          {
            canonicalItemID: "electronics.power_bank",
            reasonCode: "context.invented_code",
            reasonArguments: [],
            reason: null,
            confidence: 0.9,
            signals: ["gptReasoning"],
          },
        ],
      }),
    },
  );

  assert.equal(captured.status, 502);
});

test("gaps never re-proposes something already on the list", async () => {
  const captured = await call(
    gapsCapability,
    {
      context: tripContext({ currentItemIDs: ["electronics.power_bank"] }),
      items: [],
      safetyIdentifier: SAFETY_IDENTIFIER,
    },
    {
      adapter: adapterReturning({
        suggestions: [
          {
            canonicalItemID: "electronics.power_bank",
            reasonCode: "context.gap_generic",
            reasonArguments: [],
            reason: null,
            confidence: 0.9,
            signals: ["gptReasoning"],
          },
        ],
      }),
    },
  );

  assert.deepEqual((captured.body as { suggestions: unknown[] }).suggestions, []);
});

test("confidence survives as a number and is never turned into a label", async () => {
  const captured = await call(
    gapsCapability,
    { context: tripContext(), items: [], safetyIdentifier: SAFETY_IDENTIFIER },
    {
      adapter: adapterReturning({
        suggestions: [
          {
            canonicalItemID: "electronics.power_bank",
            reasonCode: "context.gap_generic",
            reasonArguments: [{ name: "activity", value: "walking" }],
            reason: null,
            confidence: 0.91,
            signals: ["activity"],
          },
        ],
      }),
    },
  );

  const [suggestion] = (
    captured.body as { suggestions: { confidence: number; reasonArguments: Record<string, string> }[] }
  ).suggestions;
  assert.equal(suggestion?.confidence, 0.91);
  assert.deepEqual(suggestion?.reasonArguments, { activity: "walking" });
});

test("out-of-range confidence is dropped rather than clamped into meaning", async () => {
  const captured = await call(
    gapsCapability,
    { context: tripContext(), items: [], safetyIdentifier: SAFETY_IDENTIFIER },
    {
      adapter: adapterReturning({
        suggestions: [
          {
            canonicalItemID: "electronics.power_bank",
            reasonCode: "context.gap_generic",
            reasonArguments: [],
            reason: null,
            confidence: 4.2,
            signals: [],
          },
        ],
      }),
    },
  );

  const [suggestion] = (captured.body as { suggestions: object[] }).suggestions;
  assert.ok(suggestion !== undefined);
  assert.ok(!Object.hasOwn(suggestion, "confidence"));
});

test("optimize ignores anything that is not on the list", async () => {
  const captured = await call(
    optimizeCapability,
    {
      context: tripContext({ packingStyle: "light" }),
      items: [{ canonicalItemID: "clothing.tshirt", displayName: "T-shirts", quantity: 9 }],
      safetyIdentifier: SAFETY_IDENTIFIER,
    },
    {
      adapter: adapterReturning({
        optimizations: [
          {
            canonicalItemID: "clothing.jeans",
            reasonCode: "context.optimize_generic",
            reasonArguments: [],
            reason: null,
            suggestedQuantity: null,
            confidence: 0.5,
          },
          {
            canonicalItemID: "clothing.tshirt",
            reasonCode: "context.optimize_quantity",
            reasonArguments: [
              { name: "quantity", value: "5" },
              { name: "tripDays", value: "5" },
            ],
            reason: null,
            suggestedQuantity: 5,
            confidence: 0.5,
          },
        ],
      }),
    },
  );

  const body = captured.body as { optimizations: { canonicalItemID: string }[] };
  assert.deepEqual(
    body.optimizations.map((row) => row.canonicalItemID),
    ["clothing.tshirt"],
  );
});

test("a reason whose template cannot render is dropped", async () => {
  // context.optimize_duplicate renders "{otherItem} can likely cover this as
  // well." Arguments that do not fill it would show literal braces.
  const captured = await call(
    optimizeCapability,
    {
      context: tripContext(),
      items: [{ canonicalItemID: "footwear.running_shoes", displayName: "Running shoes" }],
      safetyIdentifier: SAFETY_IDENTIFIER,
    },
    {
      adapter: adapterReturning({
        optimizations: [
          {
            canonicalItemID: "footwear.running_shoes",
            reasonCode: "context.optimize_duplicate",
            reasonArguments: [{ name: "tripDays", value: "6" }],
            reason: null,
            suggestedQuantity: null,
            confidence: 0.9,
          },
        ],
      }),
    },
  );

  assert.equal(captured.status, 200);
  assert.deepEqual((captured.body as { optimizations: unknown[] }).optimizations, []);
});

test("a code needing no arguments renders with none", async () => {
  const captured = await call(
    gapsCapability,
    { context: tripContext(), items: [], safetyIdentifier: SAFETY_IDENTIFIER },
    {
      adapter: adapterReturning({
        suggestions: [
          {
            canonicalItemID: "electronics.power_bank",
            reasonCode: "context.gap_generic",
            reasonArguments: [],
            reason: null,
            confidence: 0.5,
            signals: [],
          },
        ],
      }),
    },
  );

  assert.equal((captured.body as { suggestions: unknown[] }).suggestions.length, 1);
});
