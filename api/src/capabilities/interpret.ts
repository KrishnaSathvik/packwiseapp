import { filterVocabulary } from "../canonical.ts";
import { runModel } from "../model/run.ts";
import { validateModelOutput } from "../validation.ts";
import type { CapabilityDefinition } from "../pipeline.ts";
import type { InterpretTripRequest, InterpretTripResponse, ModelTripInterpretation } from "../types.ts";
import { tripShape } from "./common.ts";

/**
 * Language understanding only. This capability returns context, never items:
 * the deterministic engine decides what a "fancy dinner" means for a packing
 * list. Everything it returns must already exist in the shared chip and
 * activity vocabularies.
 */
export const interpretCapability: CapabilityDefinition<InterpretTripRequest, InterpretTripResponse> = {
  capability: "interpret",
  requestSchema: "InterpretTripRequest",
  responseSchema: "InterpretTripResponse",

  async handle(request, context) {
    const result = await runModel({
      adapter: context.adapter,
      capability: "interpret",
      input: { note: request.note, trip: tripShape(request.context) },
      safetyIdentifier: context.safetyIdentifier,
      requestID: context.requestID,
      clock: context.clock,
    });

    context.observed(result);

    const output = validateModelOutput<ModelTripInterpretation>("interpret", result.output);
    const activities = filterVocabulary(output.inferredActivities, "activities");
    const chips = filterVocabulary(output.inferredChips, "chips");
    context.note([...activities.rejected, ...chips.rejected]);

    return {
      meta: context.meta,
      inferredActivities: activities.kept,
      inferredChips: chips.kept,
      ...(output.noteSummary ? { noteSummary: output.noteSummary } : {}),
    };
  },
};
