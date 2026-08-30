import assert from "node:assert/strict";
import test from "node:test";

import { gapsCapability } from "../src/capabilities/gaps.ts";
import { interpretCapability } from "../src/capabilities/interpret.ts";
import { DevelopmentAppIntegrityProvider } from "../src/integrity/provider.ts";
import { createHandler } from "../src/pipeline.ts";
import { InMemoryDurableStore } from "../src/store/memory.ts";
import { SAFETY_IDENTIFIER, capture, contextFromFixture, post, tripEvalFixtures } from "./helpers.ts";

/**
 * The evaluation harness. It runs the shared trip fixtures through the real
 * pipeline against FakeModelAdapter, which gives M3A-2 a green baseline: when
 * the OpenAI adapter lands, the same assertions measure whether a prompt or
 * model change actually improved PackWise.
 */

const fixtures = tripEvalFixtures();

test("the shared fixtures cover the agreed evaluation set", () => {
  const withNotes = fixtures.filter((fixture) => fixture.note !== undefined).map((f) => f.id);
  assert.deepEqual(withNotes.sort(), [
    "BusinessTrip3Day",
    "ChicagoCityRainy5Day",
    "DenverOutdoorCold",
    "FamilyToddlerThemePark",
    "LongHaulInternationalFlight",
    "MiamiBeachCarryOn",
    "ReykjavikPhotography",
    "TokyoInternationalWalking",
    "WeddingWeekend",
  ]);
});

for (const fixture of fixtures) {
  if (fixture.note === undefined) continue;

  test(`interpret: ${fixture.id}`, async () => {
    const { response, captured } = capture();
    const handler = createHandler(interpretCapability, {
      store: new InMemoryDurableStore(),
      integrity: new DevelopmentAppIntegrityProvider(),
    });
    await handler(
      post({
        note: fixture.note,
        context: contextFromFixture(fixture),
        safetyIdentifier: SAFETY_IDENTIFIER,
      }),
      response,
    );

    assert.equal(captured.status, 200, JSON.stringify(captured.body));
    const body = captured.body as { inferredActivities: string[]; inferredChips: string[] };
    const inferred = new Set([...body.inferredActivities, ...body.inferredChips]);

    for (const expected of fixture.mustInfer ?? []) {
      assert.ok(inferred.has(expected), `${fixture.id} did not infer ${expected}`);
    }
    for (const forbidden of fixture.mustNotInfer ?? []) {
      assert.ok(!inferred.has(forbidden), `${fixture.id} wrongly inferred ${forbidden}`);
    }
  });

  test(`gaps stay inside allowedSuggestions: ${fixture.id}`, async () => {
    const allowed = new Set(fixture.allowedSuggestions ?? []);
    const { response, captured } = capture();
    const handler = createHandler(gapsCapability, {
      store: new InMemoryDurableStore(),
      integrity: new DevelopmentAppIntegrityProvider(),
    });
    await handler(
      post({
        context: contextFromFixture(fixture),
        items: (fixture.mustInclude ?? []).map((id) => ({
          canonicalItemID: id,
          displayName: id,
          quantity: 1,
        })),
        safetyIdentifier: SAFETY_IDENTIFIER,
      }),
      response,
    );

    assert.equal(captured.status, 200, JSON.stringify(captured.body));
    const body = captured.body as { suggestions: { canonicalItemID: string }[] };
    for (const suggestion of body.suggestions) {
      assert.ok(
        allowed.has(suggestion.canonicalItemID),
        `${fixture.id} suggested ${suggestion.canonicalItemID}, which is outside allowedSuggestions`,
      );
    }
  });
}
