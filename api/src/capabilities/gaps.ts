import { filterCandidates, normalizeConfidence, toArgumentMap } from "../canonical.ts";
import { runModel } from "../model/run.ts";
import { validateModelOutput } from "../validation.ts";
import type { CapabilityDefinition } from "../pipeline.ts";
import type { ModelPackingGaps, PackingGapResponse, PackingGapsRequest, PackingSuggestionDTO } from "../types.ts";
import { presentItemIDs, tripShape } from "./common.ts";

/**
 * Candidates only. Nothing here reaches SwiftData: the Recommendation Resolver
 * and the user decide. Anything already on the list, substituted, or outside
 * the catalog is dropped before it leaves the server.
 */
export const gapsCapability: CapabilityDefinition<PackingGapsRequest, PackingGapResponse> = {
  capability: "gaps",
  requestSchema: "PackingGapsRequest",
  responseSchema: "PackingGapResponse",

  async handle(request, context) {
    const present = presentItemIDs(request.context, request.items);

    const result = await runModel({
      adapter: context.adapter,
      capability: "gaps",
      input: { trip: tripShape(request.context), presentItemIDs: present },
      safetyIdentifier: context.safetyIdentifier,
      requestID: context.requestID,
      clock: context.clock,
    });

    context.observed(result);

    const output = validateModelOutput<ModelPackingGaps>("gaps", result.output);
    const filtered = filterCandidates(output.suggestions, { presentItemIDs: present });
    context.note(filtered.rejected);

    const suggestions: PackingSuggestionDTO[] = filtered.kept.map((candidate) => {
      const confidence = normalizeConfidence(candidate.confidence);
      return {
        canonicalItemID: candidate.canonicalItemID,
        action: "recommend",
        reasonCode: candidate.reasonCode,
        reasonArguments: toArgumentMap(candidate.reasonArguments),
        signals: candidate.signals,
        ...(confidence === undefined ? {} : { confidence }),
        ...(candidate.reason ? { reason: candidate.reason } : {}),
      };
    });

    return { meta: context.meta, suggestions };
  },
};
