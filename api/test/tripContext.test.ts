import assert from "node:assert/strict";
import test from "node:test";

import { canonicalBagTypes, canonicalTripTypes } from "../src/canonical.ts";
import { gapsCapability } from "../src/capabilities/gaps.ts";
import { tripShape } from "../src/capabilities/common.ts";
import { interpretCapability } from "../src/capabilities/interpret.ts";
import { optimizeCapability } from "../src/capabilities/optimize.ts";
import { IntelligenceError } from "../src/errors.ts";
import { tripContextVocabulary } from "../src/generated.ts";
import { DevelopmentAppIntegrityProvider } from "../src/integrity/provider.ts";
import { createHandler } from "../src/pipeline.ts";
import type { CapabilityDefinition } from "../src/pipeline.ts";
import { InMemoryDurableStore } from "../src/store/memory.ts";
import type { ModelAdapter, ModelRequest } from "../src/model/adapter.ts";
import { FakeModelAdapter } from "../src/model/fake.ts";
import { validateRequest } from "../src/validation.ts";
import { SAFETY_IDENTIFIER, capture, post, tripContext } from "./helpers.ts";

/**
 * Product Experience V2, Task 15: trip context crosses the API boundary as
 * `tripTypes[]` (one or more) and `bagTypes[]` (zero or more physical bags).
 * The singular fields are gone from the current contract — not deprecated,
 * not a fallback — and unknown or retired values fail closed.
 *
 * Duplicate policy: arrays are sets, so a duplicate is rejected at the schema
 * (`uniqueItems`) rather than silently collapsed. Order is not significant on
 * the wire; the server canonicalizes it before anything downstream.
 */

function accepts(context: unknown): void {
  validateRequest("TripContextDTO", context);
}

function rejects(context: unknown, label: string): void {
  assert.throws(
    () => validateRequest("TripContextDTO", context),
    (error: unknown) => error instanceof IntelligenceError && error.code === "invalid_request",
    label,
  );
}

function without(key: string): Record<string, unknown> {
  const context: Record<string, unknown> = { ...tripContext() };
  delete context[key];
  return context;
}

// MARK: - tripTypes

test("a singleton tripTypes array is valid", () => {
  accepts(tripContext({ tripTypes: ["business"] }));
});

test("multiple tripTypes are valid", () => {
  accepts(tripContext({ tripTypes: ["vacation", "cityBreak"], bagTypes: ["carryOn", "checked"] }));
});

test("tripTypes must contain at least one value", () => {
  rejects(tripContext({ tripTypes: [] }), "empty tripTypes");
  rejects(without("tripTypes"), "missing tripTypes");
});

test("duplicate tripTypes are rejected, not collapsed", () => {
  rejects(tripContext({ tripTypes: ["beach", "beach"] }), "duplicate tripTypes");
});

test("an unknown trip type fails closed", () => {
  rejects(tripContext({ tripTypes: ["vacation", "spaceCruise"] }), "unknown trip type");
});

// MARK: - bagTypes

test("zero bags is valid and means unspecified luggage", () => {
  accepts(tripContext({ tripTypes: ["business"], bagTypes: [] }));
});

test("a singleton bag and multiple bags are valid", () => {
  accepts(tripContext({ bagTypes: ["backpack"] }));
  accepts(tripContext({ bagTypes: ["personalItem", "carryOn", "checked"] }));
});

test("bagTypes is required so absence is never ambiguous", () => {
  rejects(without("bagTypes"), "missing bagTypes");
});

test("retired and unknown bag values are rejected", () => {
  rejects(tripContext({ bagTypes: ["notSure"] }), "legacy notSure");
  rejects(tripContext({ bagTypes: ["roadTripLuggage"] }), "legacy roadTripLuggage");
  rejects(tripContext({ bagTypes: ["duffel"] }), "unknown bag");
  rejects(tripContext({ bagTypes: ["carryOn", "carryOn"] }), "duplicate bagTypes");
});

// MARK: - Legacy singular shape

test("the legacy singular request shape is rejected", () => {
  const legacy: Record<string, unknown> = { ...without("tripTypes"), tripType: "vacation", bagType: "carryOn" };
  delete legacy.bagTypes;
  rejects(legacy, "singular-only context");
});

test("singular fields are rejected even beside valid arrays, so they can never be read as a fallback", () => {
  rejects({ ...tripContext(), tripType: "vacation" }, "arrays plus tripType");
  rejects({ ...tripContext(), bagType: "carryOn" }, "arrays plus bagType");
});

// MARK: - Canonical order

test("the canonical vocabularies are the stable Swift orders", () => {
  assert.deepEqual(tripContextVocabulary().tripTypes, [
    "vacation",
    "cityBreak",
    "beach",
    "business",
    "outdoor",
    "roadTrip",
    "weddingEvent",
    "skiSnow",
    "festival",
    "visitingFamily",
    "other",
  ]);
  assert.deepEqual(tripContextVocabulary().bagTypes, ["personalItem", "carryOn", "checked", "backpack"]);
});

test("equivalent trip-type orderings canonicalize identically", () => {
  const expected = ["vacation", "cityBreak", "beach"];
  assert.deepEqual(canonicalTripTypes(["beach", "vacation", "cityBreak"]), expected);
  assert.deepEqual(canonicalTripTypes(["cityBreak", "beach", "vacation"]), expected);
});

test("equivalent bag orderings canonicalize identically", () => {
  const expected = ["personalItem", "carryOn", "checked"];
  assert.deepEqual(canonicalBagTypes(["checked", "personalItem", "carryOn"]), expected);
  assert.deepEqual(canonicalBagTypes(["carryOn", "checked", "personalItem"]), expected);
  assert.deepEqual(canonicalBagTypes([]), []);
});

test("canonicalization fails closed on anything schema validation should have stopped", () => {
  assert.throws(() => canonicalTripTypes(["spaceCruise"]), IntelligenceError);
  assert.throws(() => canonicalTripTypes([]), IntelligenceError);
  assert.throws(() => canonicalBagTypes(["roadTripLuggage"]), IntelligenceError);
  assert.throws(() => canonicalBagTypes(["notSure"]), IntelligenceError);
  assert.throws(() => canonicalTripTypes(["beach", "beach"]), IntelligenceError);
});

// MARK: - Model input

test("model input carries every selected value in canonical order and no singular field", () => {
  const shape = tripShape(
    tripContext({ tripTypes: ["beach", "cityBreak", "vacation"], bagTypes: ["checked", "personalItem", "carryOn"] }),
  );
  assert.deepEqual(shape.tripTypes, ["vacation", "cityBreak", "beach"]);
  assert.deepEqual(shape.bagTypes, ["personalItem", "carryOn", "checked"]);
  assert.ok(!Object.hasOwn(shape, "tripType"));
  assert.ok(!Object.hasOwn(shape, "bagType"));
});

test("zero bags reaches the model as an explicit empty selection, never an invented bag", () => {
  const shape = tripShape(tripContext({ tripTypes: ["business"], bagTypes: [] }));
  assert.deepEqual(shape.bagTypes, []);
  assert.deepEqual(shape.tripTypes, ["business"], "a trip type is never added or inferred");
});

// MARK: - Every endpoint parses the same contract

type Endpoint = {
  name: string;
  definition: CapabilityDefinition<{ safetyIdentifier: string }, unknown>;
  body(context: unknown): unknown;
};

const ENDPOINTS: Endpoint[] = [
  {
    name: "/v1/trip/interpret",
    definition: interpretCapability as unknown as Endpoint["definition"],
    body: (context) => ({ note: "Mostly beach days.", context, safetyIdentifier: SAFETY_IDENTIFIER }),
  },
  {
    name: "/v1/packing/gaps",
    definition: gapsCapability as unknown as Endpoint["definition"],
    body: (context) => ({ context, items: [], safetyIdentifier: SAFETY_IDENTIFIER }),
  },
  {
    name: "/v1/packing/optimize",
    definition: optimizeCapability as unknown as Endpoint["definition"],
    body: (context) => ({ context, items: [], safetyIdentifier: SAFETY_IDENTIFIER }),
  },
];

/** Records what the model was handed, then answers like the fake adapter. */
function spyAdapter(): { adapter: ModelAdapter; inputs: unknown[] } {
  const fake = new FakeModelAdapter();
  const inputs: unknown[] = [];
  return {
    inputs,
    adapter: {
      name: "spy",
      async produce(request: ModelRequest) {
        inputs.push(request.input);
        return fake.produce(request);
      },
    },
  };
}

for (const endpoint of ENDPOINTS) {
  test(`${endpoint.name} accepts multi-value context and hands the model canonical order`, async () => {
    const spy = spyAdapter();
    const { response, captured } = capture();
    const handler = createHandler(endpoint.definition, {
      adapter: spy.adapter,
      store: new InMemoryDurableStore(),
      integrity: new DevelopmentAppIntegrityProvider(),
    });
    await handler(
      post(endpoint.body(tripContext({ tripTypes: ["beach", "vacation"], bagTypes: ["checked", "carryOn"] }))),
      response,
    );

    assert.equal(captured.status, 200, JSON.stringify(captured.body));
    const trip = (spy.inputs[0] as { trip: { tripTypes: string[]; bagTypes: string[] } }).trip;
    assert.deepEqual(trip.tripTypes, ["vacation", "beach"]);
    assert.deepEqual(trip.bagTypes, ["carryOn", "checked"]);
  });

  test(`${endpoint.name} rejects the legacy singular context before the model runs`, async () => {
    const spy = spyAdapter();
    const { response, captured } = capture();
    const handler = createHandler(endpoint.definition, {
      adapter: spy.adapter,
      store: new InMemoryDurableStore(),
      integrity: new DevelopmentAppIntegrityProvider(),
    });
    const legacy: Record<string, unknown> = { ...tripContext(), tripType: "cityBreak", bagType: "carryOn" };
    delete legacy.tripTypes;
    delete legacy.bagTypes;
    await handler(post(endpoint.body(legacy)), response);

    assert.equal(captured.status, 400);
    assert.equal((captured.body as { error: string }).error, "invalid_request");
    assert.equal(spy.inputs.length, 0);
  });
}
