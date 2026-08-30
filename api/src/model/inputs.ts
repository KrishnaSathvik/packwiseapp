/**
 * What each capability actually sends to the model. Deliberately narrower than
 * the request the client sent: the model gets the packing-relevant shape of the
 * trip and nothing else.
 */

export type ModelTripShape = {
  destination: string;
  countryCode: string;
  tripType: string;
  durationDays: number;
  activities: string[];
  contextChips: string[];
  bagType: string;
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
