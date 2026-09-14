/**
 * What each capability actually sends to the model. Deliberately narrower than
 * the request the client sent: the model gets the packing-relevant shape of the
 * trip and nothing else.
 */

export type ModelTripShape = {
  destination: string;
  countryCode: string;
  /** Every selected trip type, canonical order. There is no primary type. */
  tripTypes: string[];
  durationDays: number;
  activities: string[];
  contextChips: string[];
  /** Every selected physical bag, canonical order. Empty means not specified. */
  bagTypes: string[];
  packingStyle: string;
  travelerCount: number;
  weatherSummary?: string;
};

export type InterpretInput = {
  note: string;
  trip: ModelTripShape;
};

export type GapsInput = {
  trip: ModelTripShape;
  presentItemIDs: string[];
};

export type OptimizeInput = {
  trip: ModelTripShape;
  items: { canonicalItemID: string; quantity: number }[];
};
