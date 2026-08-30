import assert from "node:assert/strict";
import test from "node:test";

import {
  canRenderReason,
  filterCandidates,
  filterVocabulary,
  isKnownItem,
  isKnownReasonCode,
  normalizeConfidence,
  toArgumentMap,
} from "../src/canonical.ts";

/**
 * Domain validation is the second line. The model schema already closes most
 * of these doors, but the schema is generated and the model is remote, so the
 * checks are exercised directly here rather than only through the schema.
 */

test("catalog membership is the only source of valid item IDs", () => {
  assert.ok(isKnownItem("electronics.power_bank"));
  assert.ok(!isKnownItem("electronics.teleporter"));
  assert.ok(!isKnownItem("clothing.smart_casual_outfit"));
});

test("reason codes must resolve to a template", () => {
  assert.ok(isKnownReasonCode("context.gap_activity"));
  assert.ok(isKnownReasonCode("base.essential"));
  assert.ok(!isKnownReasonCode("context.sounds_plausible"));
});

test("candidates outside the catalog or the template set are dropped", () => {
  const result = filterCandidates([
    { canonicalItemID: "electronics.power_bank", reasonCode: "context.gap_generic" },
    { canonicalItemID: "electronics.teleporter", reasonCode: "context.gap_generic" },
    { canonicalItemID: "clothing.jeans", reasonCode: "context.sounds_plausible" },
  ]);

  assert.deepEqual(
    result.kept.map((row) => row.canonicalItemID),
    ["electronics.power_bank"],
  );
  assert.deepEqual(result.rejected, [
    { reason: "unknown_canonical_item", count: 1 },
    { reason: "unknown_reason_code", count: 1 },
  ]);
});

test("duplicates and items already on the list are dropped", () => {
  const result = filterCandidates(
    [
      { canonicalItemID: "electronics.power_bank", reasonCode: "context.gap_generic" },
      { canonicalItemID: "electronics.power_bank", reasonCode: "context.gap_generic" },
      { canonicalItemID: "clothing.jeans", reasonCode: "context.gap_generic" },
    ],
    { presentItemIDs: ["clothing.jeans"] },
  );

  assert.deepEqual(
    result.kept.map((row) => row.canonicalItemID),
    ["electronics.power_bank"],
  );
  assert.deepEqual(result.rejected.sort((a, b) => a.reason.localeCompare(b.reason)), [
    { reason: "already_on_list", count: 1 },
    { reason: "duplicate", count: 1 },
  ]);
});

test("requirePresent inverts membership for optimization candidates", () => {
  const result = filterCandidates(
    [
      { canonicalItemID: "clothing.jeans", reasonCode: "context.optimize_generic" },
      { canonicalItemID: "clothing.tshirt", reasonCode: "context.optimize_generic" },
    ],
    { presentItemIDs: ["clothing.jeans"], requirePresent: true },
  );

  assert.deepEqual(
    result.kept.map((row) => row.canonicalItemID),
    ["clothing.jeans"],
  );
  assert.deepEqual(result.rejected, [{ reason: "not_on_list", count: 1 }]);
});

test("vocabulary filtering is closed and de-duplicating", () => {
  assert.deepEqual(filterVocabulary(["walking", "walking", "scubaDiving"], "activities").kept, [
    "walking",
  ]);
  assert.deepEqual(filterVocabulary(["getColdEasily", "hatesMornings"], "chips").kept, [
    "getColdEasily",
  ]);
});

test("confidence outside 0...1 carries no meaning", () => {
  assert.equal(normalizeConfidence(0.91), 0.91);
  assert.equal(normalizeConfidence(0), 0);
  assert.equal(normalizeConfidence(1), 1);
  assert.equal(normalizeConfidence(1.4), undefined);
  assert.equal(normalizeConfidence(Number.NaN), undefined);
});

test("reason arguments convert from pairs to a map", () => {
  assert.deepEqual(
    toArgumentMap([
      { name: "activity", value: "hiking" },
      { name: "tripDays", value: "5" },
    ]),
    { activity: "hiking", tripDays: "5" },
  );
});

test("a template's placeholders must all be supplied", () => {
  assert.equal(
    canRenderReason({
      canonicalItemID: "footwear.walking_shoes",
      reasonCode: "context.optimize_duplicate",
      reasonArguments: [{ name: "otherItem", value: "footwear.running_shoes" }],
    }),
    true,
  );
  // The live model supplied "coveredBy" here, which the template cannot use.
  assert.equal(
    canRenderReason({
      canonicalItemID: "footwear.walking_shoes",
      reasonCode: "context.optimize_duplicate",
      reasonArguments: [{ name: "coveredBy", value: "footwear.running_shoes" }],
    }),
    false,
  );
  assert.equal(
    canRenderReason({
      canonicalItemID: "clothing.tshirt",
      reasonCode: "context.optimize_quantity",
      reasonArguments: [{ name: "quantity", value: "5" }],
    }),
    false,
  );
  assert.equal(
    canRenderReason({ canonicalItemID: "electronics.power_bank", reasonCode: "context.gap_generic" }),
    true,
  );
});
