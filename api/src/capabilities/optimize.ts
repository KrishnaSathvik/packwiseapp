import { filterCandidates, normalizeConfidence, toArgumentMap } from "../canonical.ts";
import { runModel } from "../model/run.ts";
import { validateModelOutput } from "../validation.ts";
import type { CapabilityDefinition } from "../pipeline.ts";
import type {
  ModelPackingOptimizations,
  PackingOptimizationDTO,
  PackingOptimizationResponse,
  PackingOptimizeRequest,
} from "../types.ts";
import { presentItemIDs, tripShape } from "./common.ts";

/**
 * Backend-only in M3. The contract and the pipeline exist so Pack lighter can
 * be built in V1 without reopening the API; there is no M3 UI for this.
 */
export const optimizeCapability: CapabilityDefinition<
  PackingOptimizeRequest,
  PackingOptimizationResponse
> = {
  capability: "optimize",
  requestSchema: "PackingOptimizeRequest",
  responseSchema: "PackingOptimizationResponse",

  async handle(request, context) {
    const present = presentItemIDs(request.context, request.items);
    const items = request.items
      .filter((item) => item.canonicalItemID !== undefined)
      .map((item) => ({ canonicalItemID: item.canonicalItemID as string, quantity: item.quantity ?? 1 }));

    const result = await runModel({
      adapter: context.adapter,
      capability: "optimize",
      input: { trip: tripShape(request.context), items },
      safetyIdentifier: context.safetyIdentifier,
      requestID: context.requestID,
      clock: context.clock,
    });

    context.observed(result);

    const output = validateModelOutput<ModelPackingOptimizations>("optimize", result.output);
    // Optimizing something that is not on the list is meaningless, so the
    // membership test is inverted here.
    const filtered = filterCandidates(output.optimizations, {
      presentItemIDs: present,
      requirePresent: true,
    });
    context.note(filtered.rejected);

    const optimizations: PackingOptimizationDTO[] = filtered.kept.map((candidate) => {
      const confidence = normalizeConfidence(candidate.confidence);
      return {
        canonicalItemID: candidate.canonicalItemID,
        reasonCode: candidate.reasonCode,
        reasonArguments: toArgumentMap(candidate.reasonArguments),
        ...(candidate.suggestedQuantity === null ? {} : { suggestedQuantity: candidate.suggestedQuantity }),
        ...(confidence === undefined ? {} : { confidence }),
        ...(candidate.reason ? { reason: candidate.reason } : {}),
      };
    });

    return { meta: context.meta, optimizations };
  },
};
