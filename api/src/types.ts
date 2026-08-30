/**
 * Mirrors `api/generated/schemas/api.schema.json`. The schema validates;
 * these types describe. If they disagree the schema wins.
 */

export type DestinationDTO = {
  displayName: string;
  countryCode: string;
  latitude?: number;
  longitude?: number;
};

export type TripContextDTO = {
  destination: DestinationDTO;
  startDate: string;
  endDate: string;
  durationDays?: number;
  tripType: string;
  activities: string[];
  contextChips?: string[];
  bagType: string;
  packingStyle: string;
  transportation?: string;
  laundryAccess?: string;
  travelerCount?: number;
  userNotes?: string;
  weatherSummary?: string;
  currentItemIDs?: string[];
};

export type PackingItemDTO = {
  canonicalItemID?: string;
  displayName: string;
  quantity?: number;
  category?: string;
};

export type SuggestionAction = "recommend" | "remove_candidate" | "quantity_change";

export type PackingSuggestionDTO = {
  canonicalItemID: string;
  action: SuggestionAction;
  confidence?: number;
  signals?: string[];
  reason?: string;
  reasonCode: string;
  reasonArguments?: Record<string, string>;
};

export type PackingOptimizationDTO = {
  canonicalItemID: string;
  reason?: string;
  reasonCode: string;
  reasonArguments?: Record<string, string>;
  suggestedQuantity?: number;
  confidence?: number;
};

export type IntelligenceMeta = {
  requestID: string;
  generatedAt: string;
  model: string;
  promptVersion: string;
  schemaVersion: string;
  cached?: boolean;
};

export type InterpretTripRequest = {
  note: string;
  context: TripContextDTO;
  safetyIdentifier: string;
};

export type InterpretTripResponse = {
  meta: IntelligenceMeta;
  inferredActivities: string[];
  inferredChips: string[];
  noteSummary?: string;
};

export type PackingGapsRequest = {
  context: TripContextDTO;
  items: PackingItemDTO[];
  safetyIdentifier: string;
};

export type PackingGapResponse = {
  meta: IntelligenceMeta;
  suggestions: PackingSuggestionDTO[];
};

export type PackingOptimizeRequest = PackingGapsRequest;

export type PackingOptimizationResponse = {
  meta: IntelligenceMeta;
  optimizations: PackingOptimizationDTO[];
};

/** Model-side shapes, from `model-output.schema.json`. Arguments travel as
 *  name/value pairs because Structured Outputs cannot express a free-form map. */
export type ReasonArgumentPair = { name: string; value: string };

export type ModelTripInterpretation = {
  inferredActivities: string[];
  inferredChips: string[];
  noteSummary: string | null;
};

export type ModelGapSuggestion = {
  canonicalItemID: string;
  reasonCode: string;
  reasonArguments: ReasonArgumentPair[];
  reason: string | null;
  confidence: number;
  signals: string[];
};

export type ModelPackingGaps = { suggestions: ModelGapSuggestion[] };

export type ModelOptimization = {
  canonicalItemID: string;
  reasonCode: string;
  reasonArguments: ReasonArgumentPair[];
  reason: string | null;
  suggestedQuantity: number | null;
  confidence: number;
};

export type ModelPackingOptimizations = { optimizations: ModelOptimization[] };
